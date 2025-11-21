//+------------------------------------------------------------------+
//|                                   CRT_Mother_Bot_Final_v107.mq5  |
//|                               Copyright 2024, CRT Trading Expert |
//|                                      https://www.crt-trading.com |
//|         Modified by Gemini: Universal Risk Calc + Debug Prints   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, CRT Trading Expert"
#property link      "https://www.crt-trading.com"
#property version   "1.07"

#include <Trade\Trade.mqh>

//==================================================================
//                       INPUTS (CONFIGURACIÓN)
//==================================================================

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
int    hFastMA, hSlowMA, hRSI;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Inicialización                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_Period != PERIOD_M1) {
      Alert("¡ERROR CRÍTICO! Este Bot solo funciona en M1.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   
   if(UseEmaFilter) {
      hFastMA = iMA(_Symbol, _Period, InpFastEma, 0, MODE_EMA, PRICE_CLOSE);
      hSlowMA = iMA(_Symbol, _Period, InpSlowEma, 0, MODE_EMA, PRICE_CLOSE);
      if(hFastMA == INVALID_HANDLE || hSlowMA == INVALID_HANDLE) return(INIT_FAILED);
   }
   if(UseRsiFilter) {
      hRSI = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
      if(hRSI == INVALID_HANDLE) return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(hFastMA != INVALID_HANDLE) IndicatorRelease(hFastMA);
   if(hSlowMA != INVALID_HANDLE) IndicatorRelease(hSlowMA);
   if(hRSI    != INVALID_HANDLE) IndicatorRelease(hRSI);
}

//+------------------------------------------------------------------+
//| Loop Principal                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!EnableTrading) return;
   if(_Period != PERIOD_M1) return; 
   if(PositionsTotal() > 0) return; 

   // DETECCIÓN DE NUEVA VELA (Momento exacto del cierre anterior)
   datetime currentTime = iTime(_Symbol, _Period, 0);
   if(currentTime == lastBarTime) return;
   lastBarTime = currentTime;

   // Filtro Horario
   if(UseTimeFilter && !IsSessionTime()) return;

   // Datos Velas (1=Gold recién cerrada, 2=Madre)
   double O1 = iOpen(_Symbol, _Period, 1);
   double H1 = iHigh(_Symbol, _Period, 1);
   double L1 = iLow(_Symbol, _Period, 1);
   double C1 = iClose(_Symbol, _Period, 1);
   
   double O2 = iOpen(_Symbol, _Period, 2);
   double H2 = iHigh(_Symbol, _Period, 2);
   double L2 = iLow(_Symbol, _Period, 2);
   double C2 = iClose(_Symbol, _Period, 2);

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
      // El precio actual (Bid) es el precio de entrada "Market" al inicio de la vela
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl    = H1; // SL en High Gold
      double tp    = O2; // TP en Open Madre
      
      // VERIFICACIÓN DE DINERO Y RATIO
      if(CheckTradeConditions(entry, sl, tp)) 
      {
         trade.Sell(InpLotSize, _Symbol, entry, sl, tp, "CRT Sell");
      }
   }

   // B. COMPRA
   if(filterBuy && CheckBullish(O1, H1, L1, C1, O2, H2, L2, C2)) 
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = L1; // SL en Low Gold
      double tp    = O2; // TP en Open Madre
      
      if(CheckTradeConditions(entry, sl, tp)) 
      {
         trade.Buy(InpLotSize, _Symbol, entry, sl, tp, "CRT Buy");
      }
   }
}

//==================================================================
//               VALIDACIÓN FINANCIERA (CRUCIAL)
//==================================================================

bool CheckTradeConditions(double entry, double sl, double tp)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tickSize == 0 || tickValue == 0) {
      Print("Error: No se puede calcular el valor del tick para este par.");
      return false;
   }

   double riskDist = MathAbs(entry - sl);
   double rewardDist = MathAbs(entry - tp);
   
   // 1. FILTRO RATIO 1:1
   if(rewardDist < riskDist) {
      // Opcional: Descomentar para ver por qué no entra
      // Print("CRT Info: Operación ignorada por Ratio < 1:1.");
      return false; 
   }
   
   // 2. CÁLCULO DEL RIESGO EN DÓLARES
   // Fórmula universal: (Distancia / TamañoTick) * ValorDeUnTick * Lotes
   double riskMoney = (riskDist / tickSize) * tickValue * InpLotSize;
   
   // Verificación de seguridad
   if(riskMoney > InpMaxRiskDollars) {
      Print("CRT ALERTA: Operación cancelada por riesgo excesivo.");
      Print("   -> Riesgo Calculado: $", DoubleToString(riskMoney, 2));
      Print("   -> Riesgo Máximo Configurado: $", DoubleToString(InpMaxRiskDollars, 2));
      Print("   -> Lotaje usado: ", DoubleToString(InpLotSize, 2));
      return false;
   }
   
   // Si pasa, imprimimos luz verde en el log
   Print("CRT: Operación Aprobada. Riesgo estimado: $", DoubleToString(riskMoney, 2));
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
//                      LÓGICA DE PATRONES
//==================================================================

bool CheckBearish(double o1, double h1, double l1, double c1, double o2, double h2, double l2, double c2) 
{
   if(c2 <= o2) return false; // Madre Alcista
   
   double motherBody = c2 - o2;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(InpMinBody > 0 && motherBody < InpMinBody*point) return false;
   if(InpFilterWick && InpMinWick > 0 && (o2-l2) < InpMinWick*point) return false;
   
   if(h1 <= h2) return false; 
   if(c1 >= h2) return false; 
   if(c1 >= o1) return false; 
   if(l1 <= o2) return false; 
   
   // 50% Penetración
   double limitPrice = c2 - (motherBody * (InpMaxPenetration / 100.0));
   if(c1 < limitPrice) return false; 
   
   return true;
}

bool CheckBullish(double o1, double h1, double l1, double c1, double o2, double h2, double l2, double c2) 
{
   if(c2 >= o2) return false; // Madre Bajista
   
   double motherBody = o2 - c2;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(InpMinBody > 0 && motherBody < InpMinBody*point) return false;
   if(InpFilterWick && InpMinWick > 0 && (h2-o2) < InpMinWick*point) return false;
   
   if(l1 >= l2) return false; 
   if(c1 <= l2) return false; 
   if(c1 <= o1) return false; 
   if(h1 >= o2) return false; 
   
   // 50% Penetración
   double limitPrice = c2 + (motherBody * (InpMaxPenetration / 100.0));
   if(c1 > limitPrice) return false; 
   
   return true;
}
//+------------------------------------------------------------------+