//+------------------------------------------------------------------+
//|                                         CRT_Mother_Gold_v5_1.mq5 |
//|                               Copyright 2024, CRT Trading Expert |
//|                                      https://www.crt-trading.com |
//|              Modified by Gemini: Added 50% Body Penetration Rule |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, CRT Trading Expert"
#property link      "https://www.crt-trading.com"
#property version   "1.01" 
#property description "CRT - Vela Madre + Filtros + Sesiones + Filtro % Cuerpo"

#property indicator_chart_window
#property indicator_buffers 5 
#property indicator_plots   2

//--- PLOT 1: VENTA
#property indicator_label1  "BEARISH CRT"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDarkRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- PLOT 2: COMPRA
#property indicator_label2  "BULLISH CRT"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDarkGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//==================================================================
//                       INPUTS DEL USUARIO
//==================================================================

input group "1. CONFIGURACIÓN VISUAL CRT"
input color     InpBearColor    = clrRed;      // Color Venta
input color     InpBullColor    = clrLime;     // Color Compra
input int       InpArrowBear    = 218;         // Código Flecha Venta
input int       InpArrowBull    = 217;         // Código Flecha Compra
input int       InpArrowSize    = 2;           // Tamaño Flecha

input group "2. LÓGICA DEL PATRÓN CRT"
input int       InpMinBody      = 0;           // Mínimo puntos cuerpo (0=off)
input int       InpMinWick      = 0;           // Mínimo puntos mecha (0=off)
input bool      InpFilterWick   = false;       // Filtrar mecha lado apertura
input double    InpMaxPenetration = 50.0;      // % Max Penetración en Cuerpo Madre

input group "3. FILTRO TENDENCIA (EMA)"
input bool      UseEmaFilter    = false;       // Activar Filtro EMA
input int       InpFastEma      = 9;           // EMA Rápida
input int       InpSlowEma      = 21;          // EMA Lenta

input group "4. FILTRO MOMENTO (RSI)"
input bool      UseRsiFilter    = false;       // Activar Filtro RSI
input int       InpRsiPeriod    = 14;          // Periodo RSI
input double    InpRsiOs        = 30.0;        // Nivel Sobreventa (Buy > 30)
input double    InpRsiOb        = 70.0;        // Nivel Sobrecompra (Sell < 70)

input group "5. SESIONES (Formato HH:MM)"
input bool      ShowSessions    = true;        // Mostrar Cajas y Líneas
input bool      SessionsBg      = true;        // Fondo en sesiones
input string    AsiaStartStr    = "02:00";     // Inicio Asia
input string    AsiaEndStr      = "09:30";     // Fin Asia
input string    LonStartStr     = "10:00";     // Inicio Londres
input string    LonEndStr       = "14:30";     // Fin Londres
input string    NyStartStr      = "16:30";     // Inicio New York
input string    NyEndStr        = "21:00";     // Fin New York

//--- BUFFERS
double          BufBear[];
double          BufBull[];
double          BufFastMA[];
double          BufSlowMA[];
double          BufRSI[];

//--- HANDLES
int             hFastMA, hSlowMA, hRSI;

//--- GLOBALES
string          ShortName;
int             minBars;

//--- VARIABLES INTERNAS PARA TIEMPO
int AsiaStartMin, AsiaEndMin;
int LonStartMin, LonEndMin;
int NyStartMin, NyEndMin;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   ShortName = "CRT_Gold_v5.1";
   
   SetIndexBuffer(0, BufBear, INDICATOR_DATA);
   SetIndexBuffer(1, BufBull, INDICATOR_DATA);
   SetIndexBuffer(2, BufFastMA, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufSlowMA, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufRSI, INDICATOR_CALCULATIONS);
   
   PlotIndexSetInteger(0, PLOT_ARROW, InpArrowBear);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBearColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpArrowSize);
   PlotIndexSetInteger(1, PLOT_ARROW, InpArrowBull);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpBullColor);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpArrowSize);
   
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Parsear Horarios "HH:MM" a minutos del día (0-1439)
   AsiaStartMin = TimeStringToMinutes(AsiaStartStr);
   AsiaEndMin   = TimeStringToMinutes(AsiaEndStr);
   LonStartMin  = TimeStringToMinutes(LonStartStr);
   LonEndMin    = TimeStringToMinutes(LonEndStr);
   NyStartMin   = TimeStringToMinutes(NyStartStr);
   NyEndMin     = TimeStringToMinutes(NyEndStr);

   minBars = 2;
   if(UseEmaFilter) {
      hFastMA = iMA(_Symbol, _Period, InpFastEma, 0, MODE_EMA, PRICE_CLOSE);
      hSlowMA = iMA(_Symbol, _Period, InpSlowEma, 0, MODE_EMA, PRICE_CLOSE);
      if(hFastMA == INVALID_HANDLE) return(INIT_FAILED);
      minBars = MathMax(minBars, InpSlowEma);
   }
   if(UseRsiFilter) {
      hRSI = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
      if(hRSI == INVALID_HANDLE) return(INIT_FAILED);
      minBars = MathMax(minBars, InpRsiPeriod);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < minBars) return(0);
   int start = (prev_calculated == 0) ? 1 : prev_calculated - 1;
   
   if(UseEmaFilter) {
      if(CopyBuffer(hFastMA, 0, 0, rates_total, BufFastMA) < 0) return(0);
      if(CopyBuffer(hSlowMA, 0, 0, rates_total, BufSlowMA) < 0) return(0);
   }
   if(UseRsiFilter) {
      if(CopyBuffer(hRSI, 0, 0, rates_total, BufRSI) < 0) return(0);
   }

   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      BufBear[i] = EMPTY_VALUE;
      BufBull[i] = EMPTY_VALUE;
      bool isClosed = (i < rates_total - 1) || (TimeCurrent() >= time[i] + PeriodSeconds());
      
      if(isClosed)
      {
         bool signalBuy = true, signalSell = true;
         
         if(UseEmaFilter) {
            if(!(BufFastMA[i] > BufSlowMA[i] && close[i] > BufSlowMA[i])) signalBuy = false;
            if(!(BufFastMA[i] < BufSlowMA[i] && close[i] < BufSlowMA[i])) signalSell = false;
         }
         if(UseRsiFilter) {
            if(BufRSI[i] <= InpRsiOs) signalBuy = false;
            if(BufRSI[i] >= InpRsiOb) signalSell = false;
         }
         
         double offset = (high[i] - low[i]) * 0.15;
         if(signalSell && CheckBearish(i, open, high, low, close)) BufBear[i] = high[i] + offset;
         if(signalBuy && CheckBullish(i, open, high, low, close)) BufBull[i] = low[i] - offset;
      }
   }
   
   // DIBUJO DE SESIONES
   if(ShowSessions && prev_calculated > 0) {
      DrawSessions(time, high, low, rates_total);
   }
   
   return(rates_total);
}

//==================================================================
//                      LÓGICA DE SESIONES (BOXES & LINES)
//==================================================================
void DrawSessions(const datetime &time[], const double &high[], const double &low[], int total)
{
   // Colores (Verde, Azul, Gris)
   color colAsia = clrDarkSeaGreen;
   color colLon  = clrDodgerBlue;
   color colNY   = clrDarkGray;
   
   ProcessSession("Asia", AsiaStartMin, AsiaEndMin, colAsia, time, high, low, total);
   ProcessSession("London", LonStartMin, LonEndMin, colLon, time, high, low, total);
   ProcessSession("NY", NyStartMin, NyEndMin, colNY, time, high, low, total);
}

void ProcessSession(string name, int startMin, int endMin, color clr, const datetime &time[], const double &high[], const double &low[], int total)
{
   int startIdx = -1;
   int endIdx = -1;
   
   // Buscar hacia atrás la última sesión válida
   for(int i = total - 1; i >= 0; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      int currentMin = dt.hour * 60 + dt.min;
      
      bool inSession = false;
      
      if(startMin < endMin) {
         // Rango normal (ej: 09:00 a 17:00)
         if(currentMin >= startMin && currentMin < endMin) inSession = true;
      } else {
         // Cruza medianoche (ej: 22:00 a 08:00)
         if(currentMin >= startMin || currentMin < endMin) inSession = true;
      }
      
      if(inSession) {
         if(endIdx == -1) endIdx = i; 
         startIdx = i; 
      } else {
         if(endIdx != -1) break; // Salimos de la sesión
      }
      
      if(total - i > 3000) break; // Límite de seguridad
   }
   
   if(startIdx != -1 && endIdx != -1)
   {
      double highest = -DBL_MAX;
      double lowest  = DBL_MAX;
      
      // Calcular rango de precio de esa sesión
      for(int k = startIdx; k <= endIdx; k++) {
         if(high[k] > highest) highest = high[k];
         if(low[k] < lowest)   lowest = low[k];
      }
      
      // 1. DIBUJAR CAJA (BOX)
      string boxName = "CRT_" + name + "_Box";
      if(ObjectFind(0, boxName) < 0) {
         ObjectCreate(0, boxName, OBJ_RECTANGLE, 0, time[startIdx], highest, time[endIdx], lowest);
         ObjectSetInteger(0, boxName, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, boxName, OBJPROP_FILL, SessionsBg); // Relleno
         ObjectSetInteger(0, boxName, OBJPROP_BACK, true); // DETRÁS de las velas (Efecto transparencia)
         ObjectSetInteger(0, boxName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, boxName, OBJPROP_STYLE, STYLE_DOT);
      } else {
         ObjectMove(0, boxName, 0, time[startIdx], highest);
         ObjectMove(0, boxName, 1, time[endIdx], lowest);
      }

      // 2. DIBUJAR LINEAS (RAY RIGHT)
      string lineHi = "CRT_" + name + "_Hi";
      string lineLo = "CRT_" + name + "_Lo";
      
      // Nota: Usamos time[endIdx] como punto de anclaje para la linea
      UpdateLine(lineHi, time[endIdx], highest, clr);
      UpdateLine(lineLo, time[endIdx], lowest, clr);
   }
}

void UpdateLine(string name, datetime t1, double price, color clr)
{
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t1 + PeriodSeconds()*10, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   } else {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t1 + PeriodSeconds()*10, price);
   }
}

// Helper para convertir "HH:MM" a minutos totales
int TimeStringToMinutes(string timeStr)
{
   string items[];
   if(StringSplit(timeStr, ':', items) == 2) {
      long h = StringToInteger(items[0]);
      long m = StringToInteger(items[1]);
      return (int)(h * 60 + m);
   }
   return 0;
}

//==================================================================
//                      LÓGICA PATRONES
//==================================================================
bool CheckBearish(int i, const double &o[], const double &h[], const double &l[], const double &c[]) {
   int m = i - 1; // Índice Madre
   
   // 1. Madre debe ser Alcista
   if(c[m] <= o[m]) return false;
   
   // 2. Filtro tamaño mínimo cuerpo madre
   double motherBody = c[m] - o[m];
   if(InpMinBody > 0 && motherBody < InpMinBody*_Point) return false;
   
   // 3. Filtro mecha inferior madre
   if(InpFilterWick && InpMinWick > 0 && (o[m]-l[m]) < InpMinWick*_Point) return false;
   
   // 4. Condiciones Inside Bar básicas
   if(h[i] <= h[m]) return false; // Corrección lógica original: h[i] debe ser menor a h[m] para ser inside. 
                                  // TU CODIGO ORIGINAL DECIA: if(h[i] <= h[m]) return false; 
                                  // Esto significa que si h[i] es MENOR, se cancela? 
                                  // Normalmente Inside bar es High[i] < High[m]. 
                                  // ASUMO que tu lógica original busca un FALSO QUIEBRE (Fakeout) o similar
                                  // dado que CheckBearish suele ser para venta. 
                                  // MANTENGO TU LÓGICA ORIGINAL DE ESTRUCTURA, SOLO AGREGO EL FILTRO DE 50%.
   
   // NOTA EXPERTO: En tu código original tenías:
   // if(h[i] <= h[m]) return false; -> Esto exige que la vela Gold ROMPA el alto de la madre.
   // if(c[i] >= h[m]) return false; -> Pero que cierre DENTRO (debajo del alto).
   // Esto es un patrón de "Toma de liquidez" o "Fakeout" por arriba.
   
   if(h[i] <= h[m]) return false; 
   if(c[i] >= h[m]) return false; 
   if(c[i] >= o[i]) return false; // Gold debe ser bajista (Open > Close)
   if(l[i] <= o[m]) return false; // Gold Low no debe romper el Open de la madre (mantenerse arriba)
   
   // --- NUEVO FILTRO: CIERRE NO MAYOR AL 50% DEL CUERPO MADRE ---
   // En Venta: Madre es Verde. Cuerpo va de Open a Close.
   // Queremos que la vela Roja (Gold) baje, pero NO baje más del 50% del cuerpo de la Madre.
   // El nivel del 50% es: CloseMadre - (CuerpoMadre * 0.50)
   double limitPrice = c[m] - (motherBody * (InpMaxPenetration / 100.0));
   
   // Si el precio de cierre es MENOR al límite, significa que penetró más del 50% hacia abajo.
   if(c[i] < limitPrice) return false; 
   
   return true;
}

bool CheckBullish(int i, const double &o[], const double &h[], const double &l[], const double &c[]) {
   int m = i - 1;
   
   // 1. Madre debe ser Bajista
   if(c[m] >= o[m]) return false;
   
   // 2. Filtro tamaño mínimo cuerpo madre
   double motherBody = o[m] - c[m];
   if(InpMinBody > 0 && motherBody < InpMinBody*_Point) return false;
   
   // 3. Filtro mecha superior madre
   if(InpFilterWick && InpMinWick > 0 && (h[m]-o[m]) < InpMinWick*_Point) return false;
   
   // 4. Condiciones Patrón (Fakeout por abajo)
   if(l[i] >= l[m]) return false; // Exige que Low Gold rompa el Low Madre
   if(c[i] <= l[m]) return false; // Pero que cierre DENTRO (encima del low)
   if(c[i] <= o[i]) return false; // Gold debe ser alcista (Close > Open)
   if(h[i] >= o[m]) return false; // High Gold no debe romper el Open Madre
   
   // --- NUEVO FILTRO: CIERRE NO MAYOR AL 50% DEL CUERPO MADRE ---
   // En Compra: Madre es Roja. Cuerpo va de Close a Open.
   // Queremos que la vela Verde (Gold) suba, pero NO suba más del 50% del cuerpo de la Madre.
   // El nivel del 50% es: CloseMadre + (CuerpoMadre * 0.50)
   double limitPrice = c[m] + (motherBody * (InpMaxPenetration / 100.0));
   
   // Si el precio de cierre es MAYOR al límite, significa que penetró más del 50% hacia arriba.
   if(c[i] > limitPrice) return false; 
   
   return true;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "CRT_Asia_");
   ObjectsDeleteAll(0, "CRT_London_");
   ObjectsDeleteAll(0, "CRT_NY_");
   
   if(hFastMA != INVALID_HANDLE) IndicatorRelease(hFastMA);
   if(hSlowMA != INVALID_HANDLE) IndicatorRelease(hSlowMA);
   if(hRSI    != INVALID_HANDLE) IndicatorRelease(hRSI);
}
//+------------------------------------------------------------------+