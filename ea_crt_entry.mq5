//+------------------------------------------------------------------+
//|                                   CRT_Mother_Bot_Final_v107_fix.mq5 |
//|                               Copyright 2024, CRT Trading Expert |
//|                                      https://www.crt-trading.com |
//|         Modified: usar símbolo del gráfico + min risk $1 + stops |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, CRT Trading Expert"
#property link      "https://www.crt-trading.com"
#property version   "1.08"

#include <Trade\Trade.mqh>

input group "1. GESTIÓN DE CAPITAL"
input bool      EnableTrading     = false;     // ACTIVAR COMERCIO
input double    InpLotSize        = 0.01;      // TU LOTAJE FIJO (Ej. 0.01)
input double    InpMaxRiskDollars = 4.0;       // RIESGO MÁXIMO EN $ (Ej. 4.00)
input int       MagicNumber       = 123456;    // Identificador del Bot

input group "2. LÓGICA DEL PATRÓN"
input int       InpMinBody        = 0;         // Mínimo puntos cuerpo madre
input int       InpMinWick        = 0;         // Mínimo puntos mecha madre
input bool      InpFilterWick     = false;     // Filtrar mecha lado apertura
input double    InpMaxPenetration = 50.0;      // % Max Penetración Gold en Cuerpo Madre

input group "3. FILTROS TÉCNICOS"
input bool      UseEmaFilter      = false;     // Activar Filtro EMA
input int       InpFastEma        = 9;         // EMA Rápida
input int       InpSlowEma        = 21;        // EMA Lenta
input bool      UseRsiFilter      = false;     // Activar Filtro RSI
input int       InpRsiPeriod      = 14;        // Periodo RSI
input double    InpRsiOs          = 30.0;      // RSI Sobreventa (Buy)
input double    InpRsiOb          = 70.0;      // RSI Sobrecompra (Sell)

input group "4. FILTRO HORARIO"
input bool      UseTimeFilter     = true;      // Operar solo en horario definido
input string    AsiaStartStr      = "02:00";
input string    AsiaEndStr        = "09:30";
input string    LonStartStr       = "10:00";
input string    LonEndStr         = "14:30";
input string    NyStartStr        = "16:30";
input string    NyEndStr          = "21:00";

CTrade trade;
int    hFastMA = INVALID_HANDLE, hSlowMA = INVALID_HANDLE, hRSI = INVALID_HANDLE;
datetime lastBarTime = 0;
string TradeSymbol = ""; // símbolo del gráfico donde está el EA

//+------------------------------------------------------------------+
//| Inicialización                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Aseguramos que sólo en M1 como antes
   if(_Period != PERIOD_M1) {
      Alert("¡ERROR CRÍTICO! Este Bot solo funciona en M1.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);

   // Inicializamos handles para el símbolo actual del gráfico
   TradeSymbol = ChartSymbol(0);
   if(StringLen(TradeSymbol) == 0) {
      Print("No se pudo obtener símbolo del gráfico.");
      return(INIT_FAILED);
   }
   if(!CreateIndicatorHandles()) return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ReleaseIndicatorHandles();
}

// Create / Release helpers
bool CreateIndicatorHandles()
{
   ReleaseIndicatorHandles();
   if(UseEmaFilter) {
      hFastMA = iMA(TradeSymbol, PERIOD_M1, InpFastEma, 0, MODE_EMA, PRICE_CLOSE);
      hSlowMA = iMA(TradeSymbol, PERIOD_M1, InpSlowEma, 0, MODE_EMA, PRICE_CLOSE);
      if(hFastMA == INVALID_HANDLE || hSlowMA == INVALID_HANDLE) {
         Print("Error creando handles EMA para ", TradeSymbol);
         return false;
      }
   }
   if(UseRsiFilter) {
      hRSI = iRSI(TradeSymbol, PERIOD_M1, InpRsiPeriod, PRICE_CLOSE);
      if(hRSI == INVALID_HANDLE) {
         Print("Error creando handle RSI para ", TradeSymbol);
         return false;
      }
   }
   return true;
}

void ReleaseIndicatorHandles()
{
   if(hFastMA != INVALID_HANDLE) { IndicatorRelease(hFastMA); hFastMA = INVALID_HANDLE; }
   if(hSlowMA != INVALID_HANDLE) { IndicatorRelease(hSlowMA); hSlowMA = INVALID_HANDLE; }
   if(hRSI    != INVALID_HANDLE) { IndicatorRelease(hRSI);    hRSI    = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Loop Principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!EnableTrading) return;
   if(_Period != PERIOD_M1) return; 
   if(PositionsTotal() > 0) return; 

   // Si el usuario cambió de símbolo en el gráfico, actualizamos handles
   string currentChartSym = ChartSymbol(0);
   if(currentChartSym != TradeSymbol) {
      TradeSymbol = currentChartSym;
      if(!CreateIndicatorHandles()) {
         Print("Fallo re-creando indicadores para ", TradeSymbol);
         return;
      }
      Print("EA: símbolo del gráfico cambiado a ", TradeSymbol);
   }

   // DETECCIÓN DE NUEVA VELA (Momento exacto del cierre anterior)
   datetime currentTime = iTime(TradeSymbol, PERIOD_M1, 0);
   if(currentTime == lastBarTime) return;
   lastBarTime = currentTime;

   // Filtro Horario
   if(UseTimeFilter && !IsSessionTime()) return;

   // Datos Velas (1=Gold recién cerrada, 2=Madre)
   double O1 = iOpen(TradeSymbol, PERIOD_M1, 1);
   double H1 = iHigh(TradeSymbol, PERIOD_M1, 1);
   double L1 = iLow(TradeSymbol, PERIOD_M1, 1);
   double C1 = iClose(TradeSymbol, PERIOD_M1, 1);
   
   double O2 = iOpen(TradeSymbol, PERIOD_M1, 2);
   double H2 = iHigh(TradeSymbol, PERIOD_M1, 2);
   double L2 = iLow(TradeSymbol, PERIOD_M1, 2);
   double C2 = iClose(TradeSymbol, PERIOD_M1, 2);

   // Calculamos TP como la punta de la mecha del lado de la apertura de la vela madre
   double tp_mother_wick = O2; // fallback
   if(C2 > O2) tp_mother_wick = L2;     // madre alcista -> apertura bajo -> mecha inferior
   else if(C2 < O2) tp_mother_wick = H2; // madre bajista -> apertura alto -> mecha superior

   // Filtros Técnicos
   bool filterBuy = true;
   bool filterSell = true;

   if(UseEmaFilter) {
      double fMA[], sMA[];
      if(CopyBuffer(hFastMA, 0, 1, 1, fMA) > 0 && CopyBuffer(hSlowMA, 0, 1, 1, sMA) > 0) {
         if(!(fMA[0] > sMA[0] && C1 > sMA[0])) filterBuy = false;
         if(!(fMA[0] < sMA[0] && C1 < sMA[0])) filterSell = false;
      } else return;
   }
   if(UseRsiFilter) {
      double rsiVal[];
      if(CopyBuffer(hRSI, 0, 1, 1, rsiVal) > 0) {
         if(rsiVal[0] <= InpRsiOs) filterBuy = false;
         if(rsiVal[0] >= InpRsiOb) filterSell = false;
      } else return;
   }

   // --- EJECUCIÓN ---
   // A. VENTA
   if(filterSell && CheckBearish(O1, H1, L1, C1, O2, H2, L2, C2)) 
   {
      double entry = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
      double sl    = H1; // SL en High Gold
      double tp    = tp_mother_wick;

      // Ajustamos sl/tp y verificamos condiciones monetarias y stops
      if(CheckTradeConditionsAndAdjust(TradeSymbol, entry, sl, tp)) 
      {
         // Normalizamos precios según dígitos
         int digits = (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS);
         double price = NormalizeDouble(entry, digits);
         double stopl = NormalizeDouble(sl, digits);
         double takep = NormalizeDouble(tp, digits);
         trade.Sell(InpLotSize, TradeSymbol, price, stopl, takep, "CRT Sell");
      }
   }

   // B. COMPRA
   if(filterBuy && CheckBullish(O1, H1, L1, C1, O2, H2, L2, C2)) 
   {
      double entry = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
      double sl    = L1; // SL en Low Gold
      double tp    = tp_mother_wick;

      if(CheckTradeConditionsAndAdjust(TradeSymbol, entry, sl, tp)) 
      {
         int digits = (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS);
         double price = NormalizeDouble(entry, digits);
         double stopl = NormalizeDouble(sl, digits);
         double takep = NormalizeDouble(tp, digits);
         trade.Buy(InpLotSize, TradeSymbol, price, stopl, takep, "CRT Buy");
      }
   }
}

//==================================================================
//            VALIDACIÓN FINANCIERA Y ADAPTACIÓN DE STOPS
//==================================================================
// Esta función ajusta SL si riesgo < 1$ y aplica stopLevel mínimo.
// Devuelve true si la operación sigue siendo válida (1:1 o más), false si se debe descartar.
bool CheckTradeConditionsAndAdjust(string sym, double &entry, double &sl, double &tp)
{
   double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double stopLevelPoints = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL); // en puntos
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   if(tickSize == 0 || tickValue == 0) {
      Print("Error: No se puede calcular el valor del tick para ", sym);
      return false;
   }

   if(stopLevelPoints < 0) stopLevelPoints = 0;
   double stopLevelPrice = stopLevelPoints * point;

   // Distancias iniciales
   double riskDist = MathAbs(entry - sl);   // precio a precio
   double rewardDist = MathAbs(entry - tp);

   // 1) Asegurar mínimo stop level (distancia mínima permitida por broker)
   if(riskDist < stopLevelPrice) {
      // ampliamos riskDist al mínimo permitido
      riskDist = stopLevelPrice;
      // reasignamos sl en función de la dirección
      if(tp < entry) {
         // sell: SL debe quedar arriba del entry
         sl = entry + riskDist;
      } else {
         // buy: SL debe quedar abajo del entry
         sl = entry - riskDist;
      }
      // normalizamos
      sl = NormalizeDouble(sl, digits);
      Print("CRT Info: SL ampliado por stopLevel. Nueva distancia: ", DoubleToString(riskDist/point,0), " puntos");
   }

   // 2) Asegurar riesgo mínimo en $ (1 USD)
   double riskMoney = (riskDist / tickSize) * tickValue * InpLotSize;
   double minRiskMoney = 1.0; // tal como pediste

   if(riskMoney < minRiskMoney) {
      // calculamos la distancia necesaria para que riskMoney == minRiskMoney
      double neededDist = (minRiskMoney / (tickValue * InpLotSize)) * tickSize; // en precio
      // si neededDist < stopLevelPrice, respetamos stopLevelPrice (ya cubierto antes)
      if(neededDist < stopLevelPrice) neededDist = stopLevelPrice;
      // reasignamos sl para conseguir neededDist
      if(tp < entry) {
         // sell: sl arriba
         sl = entry + neededDist;
      } else {
         // buy: sl abajo
         sl = entry - neededDist;
      }
      sl = NormalizeDouble(sl, digits);
      riskDist = MathAbs(entry - sl);
      riskMoney = (riskDist / tickSize) * tickValue * InpLotSize;
      PrintFormat("CRT Info: SL ampliado para riesgo mínimo $%.2f -> nueva distancia = %.5f (precio), riesgo=$%.2f", minRiskMoney, riskDist, riskMoney);
   }

   // Recalculamos rewardDist (TP no lo tocamos salvo que sea necesario)
   rewardDist = MathAbs(entry - tp);

   // 3) Comprobación ratio 1:1 (rewardDist >= riskDist)
   if(rewardDist < riskDist) {
      Print("CRT Info: Operación cancelada por Ratio < 1:1 después de ajustes.");
      return false;
   }

   // 4) Verificar que SL/TP estén en sentido correcto respecto al tipo de orden
   // Para Buy: SL < entry < TP
   // Para Sell: TP < entry < SL
   if(entry <= 0) {
      Print("CRT Error: entry inválido.");
      return false;
   }

   if(tp == sl) {
      Print("CRT Error: TP igual a SL, operación ignorada.");
      return false;
   }

   // Para BUY
   if(tp > entry) {
      if(!(sl < entry)) {
         Print("CRT Error: SL no está por debajo del precio de compra. SL=", DoubleToString(sl, digits), " entry=", DoubleToString(entry, digits));
         return false;
      }
      // También chequear que TP esté por encima del nivel mínimo de distancia (stopLevel)
      if((tp - entry) < stopLevelPrice) {
         Print("CRT Error: TP demasiado cercano al precio para BUY. Distancia TP=", DoubleToString((tp-entry)/point,0), " puntos");
         return false;
      }
   }
   // Para SELL
   else {
      if(!(sl > entry)) {
         Print("CRT Error: SL no está por encima del precio de venta. SL=", DoubleToString(sl, digits), " entry=", DoubleToString(entry, digits));
         return false;
      }
      if((entry - tp) < stopLevelPrice) {
         Print("CRT Error: TP demasiado cercano al precio para SELL. Distancia TP=", DoubleToString((entry-tp)/point,0), " puntos");
         return false;
      }
   }

   // 5) Verificación final de riesgo máximo en $
   if(riskMoney > InpMaxRiskDollars) {
      Print("CRT ALERTA: Operación cancelada por riesgo excesivo tras ajustes.");
      Print("   -> Riesgo Calculado: $", DoubleToString(riskMoney, 2));
      Print("   -> Riesgo Máximo Configurado: $", DoubleToString(InpMaxRiskDollars, 2));
      return false;
   }

   // Todo OK
   PrintFormat("CRT: Operación Aprobada. %s entry=%.5f SL=%.5f TP=%.5f Riesgo=$%.2f",
               (tp>entry) ? "BUY" : "SELL",
               entry, sl, tp, riskMoney);
   return true;
}

//==================================================================
//                      FUNCIONES AUXILIARES
//==================================================================

bool IsSessionTime()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int currentMin = dt.hour * 60 + dt.min;
   
   if(CheckTimeRange(currentMin, AsiaStartStr, AsiaEndStr)) return true;
   if(CheckTimeRange(currentMin, LonStartStr, LonEndStr)) return true;
   if(CheckTimeRange(currentMin, NyStartStr, NyEndStr)) return true;
   return false;
}

bool CheckTimeRange(int current, string startStr, string endStr)
{
   int tStart = TimeStringToMinutes(startStr);
   int tEnd   = TimeStringToMinutes(endStr);
   if(tStart < tEnd) return (current >= tStart && current < tEnd);
   else return (current >= tStart || current < tEnd);
}

int TimeStringToMinutes(string timeStr) {
   string items[]; 
   if(StringSplit(timeStr, ':', items) == 2) 
      return (int)(StringToInteger(items[0]) * 60 + StringToInteger(items[1]));
   return 0;
}

//==================================================================
//                      LÓGICA DE PATRONES (sin cambios)
//==================================================================

bool CheckBearish(double o1, double h1, double l1, double c1, double o2, double h2, double l2, double c2) 
{
   if(c2 <= o2) return false; // Madre Alcista
   
   double motherBody = c2 - o2;
   double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
   
   if(InpMinBody > 0 && motherBody < InpMinBody*point) return false;
   if(InpFilterWick && InpMinWick > 0 && (o2-l2) < InpMinWick*point) return false;
   
   if(h1 <= h2) return false; 
   if(c1 >= h2) return false; 
   if(c1 >= o1) return false; 
   if(l1 <= o2) return false; 
   
   // Penetración
   double limitPrice = c2 - (motherBody * (InpMaxPenetration / 100.0));
   if(c1 < limitPrice) return false; 
   
   return true;
}

bool CheckBullish(double o1, double h1, double l1, double c1, double o2, double h2, double l2, double c2) 
{
   if(c2 >= o2) return false; // Madre Bajista
   
   double motherBody = o2 - c2;
   double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
   
   if(InpMinBody > 0 && motherBody < InpMinBody*point) return false;
   if(InpFilterWick && InpMinWick > 0 && (h2-o2) < InpMinWick*point) return false;
   
   if(l1 >= l2) return false; 
   if(c1 <= l2) return false; 
   if(c1 <= o1) return false; 
   if(h1 >= o2) return false; 
   
   double limitPrice = c2 + (motherBody * (InpMaxPenetration / 100.0));
   if(c1 > limitPrice) return false; 
   
   return true;
}
//+------------------------------------------------------------------+
