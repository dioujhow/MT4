//+------------------------------------------------------------------+
//|                                                SignalEA_Martingale.mq4 |
//|           EA de Trading baseado no PipFinite Breakout EDGE        |
//|           Apenas uma entrada principal com Martingale             |
//+------------------------------------------------------------------+
#property strict
#property version   "6.0"
#property description "EA de Trading com Martingale - Uma entrada por vez"

#define BUF_BUY_SIGNAL  0
#define BUF_SELL_SIGNAL 1

//--- Parâmetros de Entrada
input double Lots = 0.01;                  // Lote inicial
input int Slippage = 10;                   // Slippage permitido (pontos)
input int MagicNumber = 12345;             // Número mágico para ordens

input int FixedStopLossPoints = 500;       // Stop Loss fixo (pontos)
input int FixedTakeProfitPoints = 1000;    // Take Profit fixo (pontos)
input int TrailingStart = 100;             // Trailing Start (pontos)
input int TrailingStep = 50;               // Trailing Step (pontos)
input int TrailingStop = 50;               // Trailing Stop (pontos)

input string HorarioInicio = "09:00";      // Horário de início (HH:MM)
input string HorarioFim = "17:00";         // Horário de término (HH:MM)

input int SpreadMaximo = 30;               // Spread máximo permitido
input double LucroMaximoDiario = 500.0;    // Lucro diário máximo (USD)
input double PerdaMaximaDiaria = 300.0;    // Perda diária máxima (USD)

input bool EnableDebugLogs = true;         // Ativar logs detalhados?

//--- Martingale
input bool UsarMartingale = true;          // Ativar Martingale?
input double MultiplicadorMartingale = 2.0;// Multiplicador Martingale
input int MaxMartingale = 5;               // Máximo de níveis Martingale

//--- Variáveis Globais
double loteAtual = 0;
int nivelMartingale = 0;
double ultimoLucro = 0;
int ultimoTipoOrdemFechada = 0;
datetime ultimoFechamentoTime = 0;

double lucroDiarioAtual = 0;
datetime ultimoCalculoDiario = 0;
const datetime DATA_EXPIRACAO = D'2025.06.30 23:00';

color corTexto = clrWhite;
color corPositivo = clrLime;
color corNegativo = clrRed;
color corNeutro = clrGray;
color corAlerta = clrOrange;
int tamanhoFonte = 10;
string nomeFonte = "Arial";

//+------------------------------------------------------------------+
//| Função de inicialização do expert                               |
//+------------------------------------------------------------------+
int OnInit()
{
   ObjectsDeleteAll(0, "Panel_");
   CriarPainelDireito();
   ultimoCalculoDiario = iTime(Symbol(), PERIOD_D1, 0);
   CalcularEstatisticasDiarias();
   loteAtual = Lots;
   nivelMartingale = 0;
   if(EnableDebugLogs) 
   {
      Print("=========================================");
      Print("SignalEA_Martingale INICIALIZADO");
      Print("Lote inicial: ", Lots, " | Martingale: ", UsarMartingale ? "ON" : "OFF");
      Print("=========================================");
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Função de desinicialização do expert                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "Panel_");
   if(EnableDebugLogs) 
   {
      Print("EA Finalizado - Razão: ", reason);
      Print("=========================================");
   }
}


//+------------------------------------------------------------------+
//| Cria o painel informativo no canto superior direito              |
//+------------------------------------------------------------------+
void CriarPainelDireito()
{
   int x_pos = 300;
   int y_pos = 20;
   int linhaAltura = 18;
   
   CriarTexto("Panel_Title", "SignalEA Martingale", x_pos, y_pos, corTexto, tamanhoFonte+2, true);
   y_pos += linhaAltura + 5;
   
   CriarTexto("Panel_Symbol", StringFormat("%s | %s", Symbol(), TimeframeToString(Period())), x_pos, y_pos, corTexto, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Status", "Status: INICIANDO", x_pos, y_pos, corNeutro, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Signal", "Sinal: NENHUM", x_pos, y_pos, corNeutro, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Order", "Ordem: NENHUMA", x_pos, y_pos, corNeutro, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Spread", "Spread: " + IntegerToString(MarketInfo(Symbol(), MODE_SPREAD)), x_pos, y_pos, corTexto, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Time", "Horário: " + HorarioInicio + " - " + HorarioFim, x_pos, y_pos, corTexto, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Lucro", "Lucro Hoje: $0.00", x_pos, y_pos, corTexto, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Martingale", "Martingale: " + (UsarMartingale ? "ON" : "OFF"), x_pos, y_pos, UsarMartingale ? corPositivo : corNegativo, tamanhoFonte);
   y_pos += linhaAltura;
   CriarTexto("Panel_Nivel", "Nível Martingale: 0", x_pos, y_pos, corTexto, tamanhoFonte);
}

//+------------------------------------------------------------------+
//| Atualiza o painel informativo                                   |
//+------------------------------------------------------------------+
void AtualizarPainel()
{
   color corStatus = (EAExpirado() ? corNegativo : corPositivo);
   AtualizarTextoPainel("Panel_Status", "Status: " + (EAExpirado() ? "EXPIRADO" : "ATIVO"), corStatus);

   int sinalAtual = GetPipFiniteSignal();
   color corSignal = (sinalAtual == 1) ? corPositivo : (sinalAtual == -1) ? corNegativo : corNeutro;
   AtualizarTextoPainel("Panel_Signal", "Sinal: " + (sinalAtual == 1 ? "COMPRA" : sinalAtual == -1 ? "VENDA" : "NENHUM"), corSignal);

   int ordemAberta = CurrentOpenOrderType();
   color corOrder = (ordemAberta == 1) ? corPositivo : (ordemAberta == -1) ? corNegativo : corNeutro;
   AtualizarTextoPainel("Panel_Order", "Ordem: " + (ordemAberta == 1 ? "COMPRA" : ordemAberta == -1 ? "VENDA" : "NENHUMA"), corOrder);

   int spreadAtual = MarketInfo(Symbol(), MODE_SPREAD);
   color corSpread = (spreadAtual <= SpreadMaximo) ? corPositivo : corNegativo;
   AtualizarTextoPainel("Panel_Spread", "Spread: " + IntegerToString(spreadAtual), corSpread);

   color corLucro = (lucroDiarioAtual >= 0) ? corPositivo : corNegativo;
   if(lucroDiarioAtual >= LucroMaximoDiario) corLucro = corAlerta;
   if(lucroDiarioAtual <= -PerdaMaximaDiaria) corLucro = corAlerta;
   AtualizarTextoPainel("Panel_Lucro", "Lucro Hoje: $" + DoubleToString(lucroDiarioAtual, 2), corLucro);

   AtualizarTextoPainel("Panel_Martingale", "Martingale: " + (UsarMartingale ? "ON" : "OFF"), UsarMartingale ? corPositivo : corNegativo);
   AtualizarTextoPainel("Panel_Nivel", "Nível Martingale: " + IntegerToString(nivelMartingale), corTexto);
}

//+------------------------------------------------------------------+
//| Cria um objeto de texto no painel                               |
//+------------------------------------------------------------------+
void CriarTexto(string nome, string texto, int x, int y, color cor, int tamanho, bool negrito = false)
{
   ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nome, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanho);
   ObjectSetString(0, nome, OBJPROP_FONT, nomeFonte);
   if(negrito) ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanho+1);
}



//+------------------------------------------------------------------+
//| Atualiza um texto no painel                                     |
//+------------------------------------------------------------------+
void AtualizarTextoPainel(string nome, string texto, color cor = clrWhite)
{
   if(ObjectFind(0, nome) >= 0)
   {
      ObjectSetString(0, nome, OBJPROP_TEXT, texto);
      ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   }
}

//+------------------------------------------------------------------+
//| Converte timeframe para string legível                          |
//+------------------------------------------------------------------+
string TimeframeToString(int tf)
{
   switch(tf)
   {
      case 1: return "M1";
      case 5: return "M5";
      case 15: return "M15";
      case 30: return "M30";
      case 60: return "H1";
      case 240: return "H4";
      case 1440: return "D1";
      case 10080: return "W1";
      case 43200: return "MN";
      default: return IntegerToString(tf) + "M";
   }
}

//+------------------------------------------------------------------+
//| Verifica se o EA expirou                                        |
//+------------------------------------------------------------------+
bool EAExpirado()
{
   if(TimeCurrent() >= DATA_EXPIRACAO)
   {
      CloseAllOrders();
      if(EnableDebugLogs) 
      {
         Print("EA EXPIRADO em ", TimeToString(DATA_EXPIRACAO));
         Print("Todas as ordens foram fechadas");
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Verifica todas as condições para trading                         |
//+------------------------------------------------------------------+
bool VerificarCondicoesTrading()
{
   if(EAExpirado()) 
   {
      if(EnableDebugLogs) Print("EA expirado - trading bloqueado");
      return false;
   }
   
   if(!DentroDoHorario()) 
   {
      if(EnableDebugLogs) Print("Fora do horário de trading permitido");
      return false;
   }
   
   int spreadAtual = MarketInfo(Symbol(), MODE_SPREAD);
   if(spreadAtual > SpreadMaximo) 
   {
      if(EnableDebugLogs) Print("Spread atual ", spreadAtual, " acima do máximo permitido ", SpreadMaximo);
      return false;
   }
   
   if(lucroDiarioAtual >= LucroMaximoDiario) 
   {
      if(EnableDebugLogs) Print("Lucro diário ", lucroDiarioAtual, " atingiu o máximo ", LucroMaximoDiario);
      return false;
   }
   
   if(lucroDiarioAtual <= -PerdaMaximaDiaria) 
   {
      if(EnableDebugLogs) Print("Perda diária ", lucroDiarioAtual, " atingiu o máximo ", PerdaMaximaDiaria);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Verifica se está dentro do horário de trading                   |
//+------------------------------------------------------------------+
bool DentroDoHorario()
{
   datetime agora = TimeCurrent();
   datetime hoje = agora - (agora % 86400);

   int horaInicio = (int)StringToInteger(StringSubstr(HorarioInicio, 0, 2));
   int minutoInicio = (int)StringToInteger(StringSubstr(HorarioInicio, 3, 2));
   datetime inicio = hoje + (horaInicio * 3600) + (minutoInicio * 60);

   int horaFim = (int)StringToInteger(StringSubstr(HorarioFim, 0, 2));
   int minutoFim = (int)StringToInteger(StringSubstr(HorarioFim, 3, 2));
   datetime fim = hoje + (horaFim * 3600) + (minutoFim * 60);

   // Suporte para horários que cruzam a meia-noite
   if(fim < inicio)
   {
      if(agora >= inicio || agora <= fim)
         return true;
      else
         return false;
   }
   else
   {
      if(agora >= inicio && agora <= fim)
         return true;
      else
         return false;
   }
}

//+------------------------------------------------------------------+
//| Calcula estatísticas diárias de lucro/prejuízo                  |
//+------------------------------------------------------------------+
void CalcularEstatisticasDiarias()
{
   lucroDiarioAtual = 0;
   datetime inicioDia = iTime(Symbol(), PERIOD_D1, 0);
   
   for(int i = OrdersHistoryTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderCloseTime() >= inicioDia)
         {
            lucroDiarioAtual += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }
   
   if(EnableDebugLogs) Print("Estatísticas diárias calculadas. Lucro: ", lucroDiarioAtual);
}

//+------------------------------------------------------------------+
//| Obtém sinal do indicador PipFinite                              |
//+------------------------------------------------------------------+
int GetPipFiniteSignal()
{
   double buy = iCustom(Symbol(), Period(), "PipFinite Breakout EDGE_fix", BUF_BUY_SIGNAL, 1);
   double sell = iCustom(Symbol(), Period(), "PipFinite Breakout EDGE_fix", BUF_SELL_SIGNAL, 1);

   if(buy != 0.0 && buy != EMPTY_VALUE)
      return 1;
   if(sell != 0.0 && sell != EMPTY_VALUE)
      return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Verifica se há ordem aberta do EA                               |
//+------------------------------------------------------------------+
int CurrentOpenOrderType()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            if(OrderType() == OP_BUY) return 1;
            if(OrderType() == OP_SELL) return -1;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Fecha todas as ordens do EA                                     |
//+------------------------------------------------------------------+
bool CloseAllOrders()
{
   bool result = true;
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            double price = (OrderType() == OP_BUY) ? Bid : Ask;
            if(!OrderClose(OrderTicket(), OrderLots(), price, Slippage, clrNONE))
            {
               Print("Erro ao fechar ordem #", OrderTicket(), " | Erro: ", GetLastError());
               result = false;
            }
            else
            {
               ultimoTipoOrdemFechada = OrderType();
               ultimoFechamentoTime = TimeCurrent();
               ultimoLucro = OrderProfit() + OrderSwap() + OrderCommission();
               if(EnableDebugLogs) Print("Ordem #", OrderTicket(), " fechada. Lucro: ", ultimoLucro);
            }
         }
      }
   }
   return result;
}

//+------------------------------------------------------------------+
//| Gerenciamento de Trailing Stop                                  |
//+------------------------------------------------------------------+
void GerenciarTrailingStop()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
         int tipo = OrderType();
         if(tipo != OP_BUY && tipo != OP_SELL) continue;

         double profitPoints = (tipo == OP_BUY) ? (Bid - OrderOpenPrice())/Point : (OrderOpenPrice() - Ask)/Point;
         if(profitPoints >= TrailingStart)
         {
            double novoSL = (tipo == OP_BUY)
                           ? NormalizeDouble(Bid - TrailingStop * Point, Digits)
                           : NormalizeDouble(Ask + TrailingStop * Point, Digits);

            if((tipo == OP_BUY && (OrderStopLoss() < novoSL || OrderStopLoss() == 0) && novoSL > OrderOpenPrice()) ||
               (tipo == OP_SELL && (OrderStopLoss() > novoSL || OrderStopLoss() == 0) && novoSL < OrderOpenPrice()))
            {
               if(!OrderModify(OrderTicket(), OrderOpenPrice(), novoSL, OrderTakeProfit(), 0, clrNONE))
               {
                  Print("Erro ao atualizar Trailing Stop. Erro: ", GetLastError());
               }
               else if(EnableDebugLogs)
               {
                  Print("Trailing Stop atualizado para ", novoSL, " na ordem #", OrderTicket());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Abre ordem de compra                                            |
//+------------------------------------------------------------------+
bool AbrirOrdemCompra()
{
   double sl = FixedStopLossPoints > 0 ? NormalizeDouble(Ask - FixedStopLossPoints * Point, Digits) : 0;
   double tp = FixedTakeProfitPoints > 0 ? NormalizeDouble(Ask + FixedTakeProfitPoints * Point, Digits) : 0;
   int ticket = OrderSend(Symbol(), OP_BUY, loteAtual, Ask, Slippage, sl, tp, "COMPRA SignalEA", MagicNumber, 0, clrGreen);

   if(ticket < 0) 
   {
      Print("Erro ao abrir ordem de COMPRA | Erro: ", GetLastError());
      return false;
   }
   if(EnableDebugLogs) 
   {
      Print("Ordem de COMPRA aberta:");
      Print(" - Ticket: ", ticket);
      Print(" - Preço: ", Ask);
      Print(" - SL: ", sl);
      Print(" - TP: ", tp);
      Print(" - Lote: ", loteAtual);
   }
   return true;
}

//+------------------------------------------------------------------+
//| Abre ordem de venda                                             |
//+------------------------------------------------------------------+
bool AbrirOrdemVenda()
{
   double sl = FixedStopLossPoints > 0 ? NormalizeDouble(Bid + FixedStopLossPoints * Point, Digits) : 0;
   double tp = FixedTakeProfitPoints > 0 ? NormalizeDouble(Bid - FixedTakeProfitPoints * Point, Digits) : 0;
   int ticket = OrderSend(Symbol(), OP_SELL, loteAtual, Bid, Slippage, sl, tp, "VENDA SignalEA", MagicNumber, 0, clrRed);

   if(ticket < 0) 
   {
      Print("Erro ao abrir ordem de VENDA | Erro: ", GetLastError());
      return false;
   }
   if(EnableDebugLogs) 
   {
      Print("Ordem de VENDA aberta:");
      Print(" - Ticket: ", ticket);
      Print(" - Preço: ", Bid);
      Print(" - SL: ", sl);
      Print(" - TP: ", tp);
      Print(" - Lote: ", loteAtual);
   }
   return true;
}

//+------------------------------------------------------------------+
//| Função principal de execução                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(Symbol(), Period(), 0);

   // Atualiza estatísticas diárias ao virar o dia
   if(TimeCurrent() - ultimoCalculoDiario >= 86400)
   {
      CalcularEstatisticasDiarias();
      ultimoCalculoDiario = iTime(Symbol(), PERIOD_D1, 0);
   }

   GerenciarTrailingStop();
   AtualizarPainel();

   // Só executa lógica principal em novo candle
   if(lastBarTime == currentBarTime)
      return;
   lastBarTime = currentBarTime;

   if(!VerificarCondicoesTrading())
      return;

   int sinalAtual = GetPipFiniteSignal();
   int ordemAberta = CurrentOpenOrderType();

   // Se não há ordem aberta e há sinal, abre ordem
   if(ordemAberta == 0 && sinalAtual != 0)
   {
      // Define lote conforme Martingale
      if(UsarMartingale && nivelMartingale > 0)
         loteAtual = Lots * MathPow(MultiplicadorMartingale, nivelMartingale);
      else
         loteAtual = Lots;

      // Limita o nível de martingale
      if(nivelMartingale > MaxMartingale)
         loteAtual = Lots;

      bool opened = false;
      if(sinalAtual == 1)
         opened = AbrirOrdemCompra();
      else if(sinalAtual == -1)
         opened = AbrirOrdemVenda();

      if(opened && EnableDebugLogs)
         Print("Ordem aberta com lote: ", loteAtual, " | Nível Martingale: ", nivelMartingale);
   }

   // Se ordem foi fechada, atualiza Martingale
   if(ordemAberta == 0 && ultimoFechamentoTime != 0)
   {
      // Se último lucro foi negativo, sobe martingale
      if(UsarMartingale && ultimoLucro < 0)
      {
         nivelMartingale++;
         if(nivelMartingale > MaxMartingale)
            nivelMartingale = MaxMartingale;
         if(EnableDebugLogs)
            Print("Martingale ativado. Novo nível: ", nivelMartingale, " | Novo lote: ", Lots * MathPow(MultiplicadorMartingale, nivelMartingale));
      }
      // Se último lucro foi positivo, reseta martingale
      else if(ultimoLucro >= 0)
      {
         nivelMartingale = 0;
         if(EnableDebugLogs)
            Print("Martingale resetado após lucro.");
      }
      ultimoFechamentoTime = 0; // Evita repetir ajuste
   }
}






//+------------------------------------------------------------------+
//| Função de finalização (opcional)                                |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
