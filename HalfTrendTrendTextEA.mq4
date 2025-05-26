//+------------------------------------------------------------------+
//|                                       SignalEA_Martingale_v3.mq4 |
//|                    EA de Trading baseado no PipFinite Breakout EDGE |
//|                       Apenas uma entrada principal com Martingale |
//+------------------------------------------------------------------+
#property strict
#property version   "8.0" // Versão incrementada
#property description "EA com Martingale, Filtro MA, Dias Semana, Botão TS, e Salva Último Sinal"

#define BUF_BUY_SIGNAL  0
#define BUF_SELL_SIGNAL 1

//--- Parâmetros de Entrada
input group "Configurações Gerais"
input double Lots = 0.01;               // Lote inicial
input int Slippage = 10;                // Slippage permitido (pontos)
input int MagicNumber = 12345;          // Número mágico para ordens

input group "Stop Loss e Take Profit"
input int FixedStopLossPoints = 500;    // Stop Loss fixo (pontos)
input int FixedTakeProfitPoints = 1000; // Take Profit fixo (pontos)

input group "Trailing Stop"
input bool UsarTrailingStop = true;     // Ativar Trailing Stop?
input int TrailingStart = 100;          // Trailing Start (pontos)
input int TrailingStep = 50;            // Trailing Step (pontos)
input int TrailingStop = 50;            // Trailing Stop (pontos)

input group "Horário de Operação"
input string HorarioInicio = "09:00";   // Horário de início (HH:MM)
input string HorarioFim = "17:00";      // Horário de término (HH:MM)

input group "Filtros de Entrada"
input int SpreadMaximo = 30;            // Spread máximo permitido
input int PeriodoMediaMovel = 200;      // Período da Média Móvel para filtro de tendência

input group "Gerenciamento de Risco Diário"
input double LucroMaximoDiario = 500.0; // Lucro diário máximo (USD)
input double PerdaMaximaDiaria = 300.0; // Perda diária máxima (USD)

input group "Martingale"
input bool UsarMartingale = true;       // Ativar Martingale?
input double MultiplicadorMartingale = 2.0; // Multiplicador Martingale
input int MaxMartingale = 5;            // Máximo de níveis Martingale

input group "Dias da Semana para Operar"
input bool OperarDomingo = false;
input bool OperarSegunda = true;
input bool OperarTerca = true;
input bool OperarQuarta = true;
input bool OperarQuinta = true;
input bool OperarSexta = true;
input bool OperarSabado = false;

input group "Outros"
input bool EnableDebugLogs = true;      // Ativar logs detalhados?
const datetime DATA_EXPIRACAO = D'2025.12.31 23:00';

//--- Variáveis Globais
double loteAtual = 0;
int nivelMartingale = 0;
datetime ultimoCalculoDiario = 0;
double lucroDiarioAtual = 0;

int ultimoSinalValidoSalvo = 0; // NOVO: 0 = Nenhum, 1 = Compra, -1 = Venda

//--- Variáveis Globais para Botões e Painel
color corTexto = clrWhite;
color corPositivo = clrLime;
color corNegativo = clrRed;
color corNeutro = clrGray;
color corAlerta = clrOrange;
int tamanhoFonte = 10;
string nomeFonte = "Arial";
bool g_UsarTrailingStop_GUI;

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
    g_UsarTrailingStop_GUI = UsarTrailingStop;
    ultimoSinalValidoSalvo = 0; // Inicializa o último sinal salvo

    if(EnableDebugLogs)
    {
        Print("=========================================");
        Print("SignalEA_Martingale_v3 INICIALIZADO");
        Print("Lote inicial: ", Lots, " | Martingale: ", UsarMartingale ? "ON" : "OFF");
        Print("Filtro MA(", PeriodoMediaMovel, ")");
        Print("Trailing Stop: ", g_UsarTrailingStop_GUI ? "ON" : "OFF");
        Print("Último Sinal Salvo: Nenhum (Inicial)");
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
//| Cria o painel informativo no canto superior direito             |
//+------------------------------------------------------------------+
void CriarPainelDireito()
{
    int x_pos = 300;
    int y_pos = 20;
    int linhaAltura = 18;
    int larguraBotao = 80;
    int alturaBotao = 20;

    // Fixed: Explicitly passed 'true' for 'negrito' (7 arguments)
    CriarTexto("Panel_Title", "SignalEA Martingale v3", x_pos, y_pos, corTexto, (int)(tamanhoFonte+2), true);
    y_pos += linhaAltura + 5;

    // Fixed: Explicitly passed 'false' for 'negrito' (7 arguments)
    CriarTexto("Panel_Symbol", StringFormat("%s | %s", Symbol(), TimeframeToString(Period())), x_pos, y_pos, corTexto, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_Status", "Status: INICIANDO", x_pos, y_pos, corNeutro, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_SignalPipFinite", "Sinal PipFinite: NENHUM", x_pos, y_pos, corNeutro, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_SignalMA", "Sinal MA(" + IntegerToString(PeriodoMediaMovel) + "): AGUARDANDO", x_pos, y_pos, corNeutro, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_UltimoSinal", "Último Sinal Salvo: NENHUM", x_pos, y_pos, corNeutro, (int)tamanhoFonte, false); // NOVO
    y_pos += linhaAltura;
    CriarTexto("Panel_Order", "Ordem: NENHUMA", x_pos, y_pos, corNeutro, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_Spread", "Spread: " + IntegerToString((int)MarketInfo(Symbol(), MODE_SPREAD)), x_pos, y_pos, corTexto, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_Time", "Horário: " + HorarioInicio + " - " + HorarioFim, x_pos, y_pos, corTexto, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_DiasOperacao", "Dias: " + DiasOperacaoToString(), x_pos, y_pos, corTexto, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_Lucro", "Lucro Hoje: $0.00", x_pos, y_pos, corTexto, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_Martingale", "Martingale: " + (UsarMartingale ? "ON" : "OFF"), UsarMartingale ? corPositivo : corNegativo, (int)tamanhoFonte, false);
    y_pos += linhaAltura;
    CriarTexto("Panel_Nivel", "Nível Martingale: 0", x_pos, y_pos, corTexto, (int)tamanhoFonte, false);
    y_pos += linhaAltura;

    CriarBotao("Panel_TrailingStop_Btn", x_pos - larguraBotao - 5, y_pos, larguraBotao, alturaBotao, g_UsarTrailingStop_GUI ? "TS: ON" : "TS: OFF");
    ObjectSetInteger(0, "Panel_TrailingStop_Btn", OBJPROP_BGCOLOR, g_UsarTrailingStop_GUI ? corPositivo : corNegativo);
    CriarTexto("Panel_TrailingStop_Label", "Trailing Stop:", x_pos, y_pos + 3, corTexto, (int)tamanhoFonte, false); // Fixed: Explicitly pass 'false'
}

//+------------------------------------------------------------------+
//| Atualiza o painel informativo                                   |
//+------------------------------------------------------------------+
void AtualizarPainel()
{
    color corStatus = (EAExpirado() ? corNegativo : corPositivo);
    AtualizarTextoPainel("Panel_Status", "Status: " + (EAExpirado() ? "EXPIRADO" : "ATIVO"), corStatus);

    int sinalPipFinite = GetPipFiniteSignal(); // Pega sinal atual para painel
    color corSignalPipFinite = (sinalPipFinite == 1) ? corPositivo : (sinalPipFinite == -1) ? corNegativo : corNeutro;
    AtualizarTextoPainel("Panel_SignalPipFinite", "Sinal PipFinite: " + (sinalPipFinite == 1 ? "COMPRA" : sinalPipFinite == -1 ? "VENDA" : "NENHUM"), corSignalPipFinite);

    int sinalMA = SinalMediaMovel(); // Pega sinal MA atual para painel
    color corSignalMA = (sinalMA == 1) ? corPositivo : (sinalMA == -1) ? corNegativo : corNeutro;
    AtualizarTextoPainel("Panel_SignalMA", "Sinal MA(" + IntegerToString(PeriodoMediaMovel) + "): " + (sinalMA == 1 ? "COMPRA" : sinalMA == -1 ? "VENDA" : "NEUTRO"), corSignalMA);

    // Atualiza Último Sinal Salvo no Painel
    string strUltimoSinal = "NENHUM";
    color corUltimoSinal = corNeutro;
    if(ultimoSinalValidoSalvo == 1) { strUltimoSinal = "COMPRA SALVA"; corUltimoSinal = corPositivo; }
    else if(ultimoSinalValidoSalvo == -1) { strUltimoSinal = "VENDA SALVA"; corUltimoSinal = corNegativo; }
    AtualizarTextoPainel("Panel_UltimoSinal", "Último Sinal Salvo: " + strUltimoSinal, corUltimoSinal);

    int ordemAberta = CurrentOpenOrderType();
    color corOrder = (ordemAberta == 1) ? corPositivo : (ordemAberta == -1) ? corNegativo : corNeutro;
    AtualizarTextoPainel("Panel_Order", "Ordem: " + (ordemAberta == 1 ? "COMPRA" : ordemAberta == -1 ? "VENDA" : "NENHUMA"), corOrder);

    int spreadAtual = (int)MarketInfo(Symbol(), MODE_SPREAD);
    color corSpread = (spreadAtual <= SpreadMaximo && SpreadMaximo > 0) ? corPositivo : corNegativo;
    AtualizarTextoPainel("Panel_Spread", "Spread: " + IntegerToString(spreadAtual), corSpread);

    color corLucro = (lucroDiarioAtual >= 0) ? corPositivo : corNegativo;
    if(lucroDiarioAtual >= LucroMaximoDiario && LucroMaximoDiario > 0) corLucro = corAlerta;
    if(lucroDiarioAtual <= -PerdaMaximaDiaria && PerdaMaximaDiaria > 0) corLucro = corAlerta;
    AtualizarTextoPainel("Panel_Lucro", "Lucro Hoje: $" + DoubleToString(lucroDiarioAtual, 2), corLucro);

    AtualizarTextoPainel("Panel_Martingale", "Martingale: " + (UsarMartingale ? "ON" : "OFF"), UsarMartingale ? corPositivo : corNegativo);
    AtualizarTextoPainel("Panel_Nivel", "Nível Martingale: " + IntegerToString(nivelMartingale), corTexto);

    // Fixed: Ensure ObjectSetText receives int for font_size
    ObjectSetText("Panel_TrailingStop_Btn", g_UsarTrailingStop_GUI ? "TS: ON" : "TS: OFF", (int)tamanhoFonte, nomeFonte, corTexto);
    ObjectSetInteger(0, "Panel_TrailingStop_Btn", OBJPROP_BGCOLOR, g_UsarTrailingStop_GUI ? corPositivo : corNegativo);
    AtualizarTextoPainel("Panel_DiasOperacao", "Dias: " + DiasOperacaoToString(), corTexto);
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
    // Fixed: Ensure OBJPROP_FONTSIZE receives a long.
    ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, (long)tamanho);
    ObjectSetString(0, nome, OBJPROP_FONT, nomeFonte);
    if(negrito) ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, (long)(tamanho + 1)); // Explicitly cast result to long
}

//+------------------------------------------------------------------+
//| Cria um botão no painel                                         |
//+------------------------------------------------------------------+
void CriarBotao(string nome, int x, int y, int largura, int altura, string texto)
{
    ObjectCreate(0, nome, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, nome, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, nome, OBJPROP_XSIZE, largura);
    ObjectSetInteger(0, nome, OBJPROP_YSIZE, altura);
    ObjectSetString(0, nome, OBJPROP_TEXT, texto);
    ObjectSetInteger(0, nome, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, nome, OBJPROP_BGCOLOR, clrGray);
    ObjectSetInteger(0, nome, OBJPROP_BORDER_COLOR, clrBlack);
    // Fixed: Ensure OBJPROP_FONTSIZE receives a long.
    ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, (long)tamanhoFonte);
    ObjectSetString(0, nome, OBJPROP_FONT, nomeFonte);
    ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, nome, OBJPROP_STATE, false);
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
//| Converte timeframe para string legível                           |
//+------------------------------------------------------------------+
string TimeframeToString(int tf)
{
    switch(tf)
    {
        case PERIOD_M1: return "M1"; case PERIOD_M5: return "M5"; case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30"; case PERIOD_H1: return "H1"; case PERIOD_H4: return "H4";
        case PERIOD_D1: return "D1"; case PERIOD_W1: return "W1"; case PERIOD_MN1: return "MN1";
        default: return IntegerToString(tf);
    }
}

//+------------------------------------------------------------------+
//| Verifica se o EA expirou                                        |
//+------------------------------------------------------------------+
bool EAExpirado()
{
    if(TimeCurrent() >= DATA_EXPIRACAO)
    {
        if(EnableDebugLogs) Print("EA EXPIRADO em ", TimeToString(DATA_EXPIRACAO), ". Fechando todas as ordens.");
        CloseAllOrders(true); // Passa true para indicar que é um fechamento por expiração
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Retorna string com os dias permitidos para operar               |
//+------------------------------------------------------------------+
string DiasOperacaoToString()
{
    string dias = "";
    if(OperarDomingo) dias += "Dom,"; if(OperarSegunda) dias += "Seg,"; if(OperarTerca) dias += "Ter,";
    if(OperarQuarta) dias += "Qua,"; if(OperarQuinta) dias += "Qui,"; if(OperarSexta) dias += "Sex,";
    if(OperarSabado) dias += "Sab,";
    if(StringLen(dias) > 0) dias = StringSubstr(dias, 0, StringLen(dias) - 1); else dias = "Nenhum";
    return dias;
}

//+------------------------------------------------------------------+
//| Verifica se o dia atual é permitido para operar                 |
//+------------------------------------------------------------------+
bool DiaPermitidoParaOperar()
{
    int diaDaSemana = DayOfWeek();
    switch(diaDaSemana)
    {
        case 0: return OperarDomingo; case 1: return OperarSegunda; case 2: return OperarTerca;
        case 3: return OperarQuarta; case 4: return OperarQuinta; case 5: return OperarSexta;
        case 6: return OperarSabado; default: return false;
    }
}

//+------------------------------------------------------------------+
//| Verifica todas as condições para trading                         |
//+------------------------------------------------------------------+
bool VerificarCondicoesTrading()
{
    if(EAExpirado()) return false; // EAExpirado já loga e fecha ordens

    if(!DentroDoHorario()) {
        if(EnableDebugLogs) Print("Condição Falhou: Fora do horário de trading.");
        return false;
    }
    if(!DiaPermitidoParaOperar()) {
        if(EnableDebugLogs) Print("Condição Falhou: Dia da semana não permitido (", EnumToString((ENUM_DAY_OF_WEEK)DayOfWeek()), ").");
        return false;
    }
    int spreadAtual = (int)MarketInfo(Symbol(), MODE_SPREAD);
    if(spreadAtual > SpreadMaximo && SpreadMaximo > 0) {
        if(EnableDebugLogs) Print("Condição Falhou: Spread (", spreadAtual, ") > Máximo (", SpreadMaximo, ").");
        return false;
    }
    if(lucroDiarioAtual >= LucroMaximoDiario && LucroMaximoDiario > 0) {
        if(EnableDebugLogs) Print("Condição Falhou: Lucro diário (", lucroDiarioAtual, ") >= Máximo (", LucroMaximoDiario, ").");
        return false;
    }
    if(lucroDiarioAtual <= -PerdaMaximaDiaria && PerdaMaximaDiaria > 0) {
        if(EnableDebugLogs) Print("Condição Falhou: Perda diária (", lucroDiarioAtual, ") <= Máxima (-", PerdaMaximaDiaria, ").");
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
    int agora_HHMM = TimeHour(agora) * 100 + TimeMinute(agora);
    int inicio_HHMM = StringToInteger(StringSubstr(HorarioInicio,0,2)) * 100 + StringToInteger(StringSubstr(HorarioInicio,3,2));
    int fim_HHMM = StringToInteger(StringSubstr(HorarioFim,0,2)) * 100 + StringToInteger(StringSubstr(HorarioFim,3,2));

    if(fim_HHMM < inicio_HHMM) return (agora_HHMM >= inicio_HHMM || agora_HHMM <= fim_HHMM);
    else return (agora_HHMM >= inicio_HHMM && agora_HHMM <= fim_HHMM);
}

//+------------------------------------------------------------------+
//| Calcula estatísticas diárias de lucro/prejuízo                   |
//+------------------------------------------------------------------+
void CalcularEstatisticasDiarias()
{
    lucroDiarioAtual = 0;
    datetime inicioDia = iTime(Symbol(), PERIOD_D1, 0);
    for(int i = OrdersHistoryTotal()-1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) {
            if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderCloseTime() >= inicioDia) {
                lucroDiarioAtual += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    if(EnableDebugLogs) Print("Estatísticas diárias. Lucro/Perda Hoje: ", DoubleToString(lucroDiarioAtual,2));
}

//+------------------------------------------------------------------+
//| Obtém sinal do indicador PipFinite                               |
//+------------------------------------------------------------------+
int GetPipFiniteSignal()
{
    double buy = iCustom(Symbol(), Period(), "PipFinite Breakout EDGE_fix", BUF_BUY_SIGNAL, 1);
    double sell = iCustom(Symbol(), Period(), "PipFinite Breakout EDGE_fix", BUF_SELL_SIGNAL, 1);
    if(buy != 0.0 && buy != EMPTY_VALUE) return 1;
    if(sell != 0.0 && sell != EMPTY_VALUE) return -1;
    return 0;
}

//+------------------------------------------------------------------+
//| Obtém sinal da Média Móvel                                      |
//+------------------------------------------------------------------+
int SinalMediaMovel()
{
    if(PeriodoMediaMovel <= 0) return 0; // Filtro desativado
    double maValue = iMA(Symbol(), Period(), PeriodoMediaMovel, 0, MODE_SMA, PRICE_CLOSE, 1);
    if(maValue == 0 || maValue == EMPTY_VALUE) return 0;
    if(Ask > maValue) return 1;  // Tendência de alta (preço acima da MA)
    if(Bid < maValue) return -1; // Tendência de baixa (preço abaixo da MA)
    return 0; // Preço sobre a MA ou indefinido
}

//+------------------------------------------------------------------+
//| Verifica se há ordem aberta do EA                               |
//+------------------------------------------------------------------+
int CurrentOpenOrderType()
{
    for(int i = OrdersTotal()-1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber) {
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
bool CloseAllOrders(bool expiracao = false) // Adicionado parâmetro opcional
{
    bool result = true;
    double lucroTotalFechamento = 0;
    int ordensFechadas = 0;

    for(int i = OrdersTotal()-1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber) {
                double price = (OrderType() == OP_BUY) ? Bid : Ask;
                double lucroOrdem = OrderProfit() + OrderSwap() + OrderCommission(); // Calcula antes de fechar
                if(!OrderClose(OrderTicket(), OrderLots(), price, Slippage, clrNONE)) {
                    Print("Erro ao fechar ordem #", OrderTicket(), " | Erro: ", GetLastError());
                    result = false;
                } else {
                    lucroTotalFechamento += lucroOrdem;
                    ordensFechadas++;
                    if(EnableDebugLogs) Print("Ordem #", OrderTicket(), " fechada via CloseAllOrders. Lucro da ordem: ", lucroOrdem);
                }
            }
        }
    }
    if (ordensFechadas > 0 && !expiracao) { // Só atualiza Martingale se não for por expiração
        // A lógica de Martingale agora é centralizada no OnTick pela verificação do histórico
        // Mas podemos registrar o resultado consolidado deste fechamento em massa se necessário
        if(EnableDebugLogs) Print("CloseAllOrders: ", ordensFechadas, " ordens fechadas. Lucro total do fechamento: ", lucroTotalFechamento);
    }
    return result;
}


//+------------------------------------------------------------------+
//| FUNÇÃO NOVA: Fecha ordens se o sinal mudar                      |
//+------------------------------------------------------------------+
void CloseOrdersOnSignalChange()
{
    int sinalPipFiniteAtual = GetPipFiniteSignal();
    int sinalMAAtual = SinalMediaMovel();
    int ordemAberta = CurrentOpenOrderType();

    // Determina o sinal "válido" atual para comparação (mesma lógica que a de salvar)
    int currentValidSignal = 0;
    if (sinalPipFiniteAtual == 1 && sinalMAAtual == 1) {
        currentValidSignal = 1; // Compra
    } else if (sinalPipFiniteAtual == -1 && sinalMAAtual == -1) {
        currentValidSignal = -1; // Venda
    }

    // Se há uma ordem aberta E o sinal válido atual é diferente do sinal salvo
    // E o sinal válido atual NÃO é neutro (0)
    if (ordemAberta != 0 && ultimoSinalValidoSalvo != 0 && currentValidSignal != 0 && currentValidSignal != ultimoSinalValidoSalvo)
    {
        if (EnableDebugLogs) {
            Print("Sinal mudou! Fechando ordens. Último Sinal Salvo: ", ultimoSinalValidoSalvo == 1 ? "COMPRA" : "VENDA",
                  " | Novo Sinal Válido: ", currentValidSignal == 1 ? "COMPRA" : "VENDA");
        }
        CloseAllOrders(); // Fecha todas as ordens existentes
        ultimoSinalValidoSalvo = currentValidSignal; // Atualiza o sinal salvo após o fechamento
    }
    // Se não há ordem aberta e o sinal válido atual é diferente do último sinal salvo, atualiza o último sinal salvo
    else if (ordemAberta == 0 && currentValidSignal != 0 && currentValidSignal != ultimoSinalValidoSalvo)
    {
        if (EnableDebugLogs) {
            Print("Último Sinal Salvo atualizado sem ordem aberta. Anterior: ", ultimoSinalValidoSalvo == 1 ? "COMPRA" : (ultimoSinalValidoSalvo == -1 ? "VENDA" : "NENHUM"),
                  " | Novo Sinal Válido: ", currentValidSignal == 1 ? "COMPRA" : "VENDA");
        }
        ultimoSinalValidoSalvo = currentValidSignal;
    }
}


//+------------------------------------------------------------------+
//| Gerenciamento de Trailing Stop                                  |
//+------------------------------------------------------------------+
void GerenciarTrailingStop()
{
    if(!g_UsarTrailingStop_GUI) return;
    for(int i = OrdersTotal()-1; i >= 0; i--) {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
            int tipo = OrderType();
            if(tipo != OP_BUY && tipo != OP_SELL) continue;

            double profitPoints = (tipo == OP_BUY) ? (Bid - OrderOpenPrice()) / _Point : (OrderOpenPrice() - Ask) / _Point;
            if(profitPoints >= TrailingStart) {
                double novoSL = (tipo == OP_BUY) ? NormalizeDouble(Bid - TrailingStop * _Point, _Digits) : NormalizeDouble(Ask + TrailingStop * _Point, _Digits);
                bool condModSL = (tipo == OP_BUY && (OrderStopLoss() < novoSL || OrderStopLoss() == 0.0) && novoSL > OrderOpenPrice()) ||
                                 (tipo == OP_SELL && (OrderStopLoss() > novoSL || OrderStopLoss() == 0.0) && novoSL < OrderOpenPrice() && novoSL != 0.0);
                if(condModSL) {
                    if(!OrderModify(OrderTicket(), OrderOpenPrice(), novoSL, OrderTakeProfit(), 0, clrNONE)) {
                        Print("Erro Trailing Stop #", OrderTicket(), ": ", GetLastError(), " SL Atual: ", OrderStopLoss(), " Novo: ", novoSL);
                    } else if(EnableDebugLogs) {
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
    RefreshRates();
    double sl = FixedStopLossPoints > 0 ? NormalizeDouble(Ask - FixedStopLossPoints * _Point, _Digits) : 0;
    double tp = FixedTakeProfitPoints > 0 ? NormalizeDouble(Ask + FixedTakeProfitPoints * _Point, _Digits) : 0;
    int ticket = OrderSend(Symbol(), OP_BUY, loteAtual, Ask, Slippage, sl, tp, "COMPRA SignalEA v3", MagicNumber, 0, clrGreen);
    if(ticket < 0) {
        Print("Erro COMPRA: ", GetLastError(), " Lote:", loteAtual, " Ask:", Ask, " SL:", sl, " TP:", tp);
        return false;
    }
    if(EnableDebugLogs) Print("COMPRA Aberta: #", ticket, " Preço:", Ask, " Lote:", loteAtual, " Nível Mart.:", nivelMartingale);
    return true;
}

//+------------------------------------------------------------------+
//| Abre ordem de venda                                             |
//+------------------------------------------------------------------+
bool AbrirOrdemVenda()
{
    RefreshRates();
    double sl = FixedStopLossPoints > 0 ? NormalizeDouble(Bid + FixedStopLossPoints * _Point, _Digits) : 0;
    double tp = FixedTakeProfitPoints > 0 ? NormalizeDouble(Bid - FixedTakeProfitPoints * _Point, _Digits) : 0;
    int ticket = OrderSend(Symbol(), OP_SELL, loteAtual, Bid, Slippage, sl, tp, "VENDA SignalEA v3", MagicNumber, 0, clrRed);
    if(ticket < 0) {
        Print("Erro VENDA: ", GetLastError(), " Lote:", loteAtual, " Bid:", Bid, " SL:", sl, " TP:", tp);
        return false;
    }
    if(EnableDebugLogs) Print("VENDA Aberta: #", ticket, " Preço:", Bid, " Lote:", loteAtual, " Nível Mart.:", nivelMartingale);
    return true;
}

//+------------------------------------------------------------------+
//| Função principal de execução                                    |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime lastBarTime = 0;
    datetime currentTimeForBarCheck = iTime(Symbol(), Period(), 0);

    // --- Atualizações a cada Tick ---
    if(iTime(Symbol(), PERIOD_D1, 0) != ultimoCalculoDiario) {
        CalcularEstatisticasDiarias();
        ultimoCalculoDiario = iTime(Symbol(), PERIOD_D1, 0);
    }
    GerenciarTrailingStop(); // Gerencia TS a cada tick
    AtualizarPainel();       // Atualiza painel a cada tick

    // --- Lógica de Martingale (Verifica fechamentos a cada tick) ---
    static int prevOrdersTotal = -1;
    static int prevHistoryTotal = -1;
    if(prevOrdersTotal == -1) prevOrdersTotal = OrdersTotal(); // Inicializa na primeira vez
    if(prevHistoryTotal == -1) prevHistoryTotal = OrdersHistoryTotal();

    int currentOrders = OrdersTotal();
    int currentHistory = OrdersHistoryTotal();

    if(currentOrders < prevOrdersTotal && currentHistory > prevHistoryTotal) { // Ordem foi fechada
        if(OrderSelect(OrdersHistoryTotal()-1, SELECT_BY_POS, MODE_HISTORY)) {
            if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol()) {
                double lucroFechamento = OrderProfit() + OrderSwap() + OrderCommission();
                if(EnableDebugLogs) Print("Ordem Fechada (Histórico): #",OrderTicket(), " Lucro: ",lucroFechamento, " Tipo: ",OrderType());

                if(UsarMartingale && lucroFechamento < 0) {
                    nivelMartingale++;
                    if(nivelMartingale > MaxMartingale) nivelMartingale = MaxMartingale;
                    if(EnableDebugLogs) Print("Martingale Nível: ", nivelMartingale, " Próximo Lote: ", NormalizeDouble(Lots * MathPow(MultiplicadorMartingale, nivelMartingale),2));
                } else if(lucroFechamento >= 0) {
                    if(nivelMartingale > 0 && EnableDebugLogs) Print("Martingale Resetado.");
                    nivelMartingale = 0;
                }
            }
        }
    }
    prevOrdersTotal = currentOrders;
    prevHistoryTotal = currentHistory;

    // --- Lógica Principal (Nova Barra) ---
    if(currentTimeForBarCheck != lastBarTime || IsTesting())
    {
        lastBarTime = currentTimeForBarCheck;
        if(EnableDebugLogs && !IsTesting()) Print("--- Nova Barra ", TimeToString(lastBarTime), " ---");

        // NEW: Call the function to close orders on signal change
        CloseOrdersOnSignalChange();

        // 1. Detectar e Salvar Sinal Válido (logic partially moved to CloseOrdersOnSignalChange for clarity)
        int sinalPipFiniteAtual = GetPipFiniteSignal();
        int sinalMAAtual = SinalMediaMovel();

        // The primary logic to update ultimoSinalValidoSalvo when a *new* confirmed signal arrives
        // This ensures that if the signal changes and orders are closed, the 'ultimoSinalValidoSalvo'
        // is immediately updated. If no order is open, it also updates.
        if(sinalPipFiniteAtual == 1 && sinalMAAtual == 1) {
            if(ultimoSinalValidoSalvo != 1) { // Only log if it's genuinely new
                if(EnableDebugLogs) Print("Sinal de COMPRA CONFIRMADO (PipFinite:",sinalPipFiniteAtual,", MA:",sinalMAAtual,")");
                ultimoSinalValidoSalvo = 1;
            }
        } else if(sinalPipFiniteAtual == -1 && sinalMAAtual == -1) {
            if(ultimoSinalValidoSalvo != -1) { // Only log if it's genuinely new
                if(EnableDebugLogs) Print("Sinal de VENDA CONFIRMADO (PipFinite:",sinalPipFiniteAtual,", MA:",sinalMAAtual,")");
                ultimoSinalValidoSalvo = -1;
            }
        } else {
            // If signals diverge or are neutral, do NOT change ultimoSinalValidoSalvo
            // It maintains the last confirmed trend. This is crucial if we only want to trade
            // with confirmed signals and not open new trades on weak/divergent signals.
            if(EnableDebugLogs && (sinalPipFiniteAtual !=0 || sinalMAAtual !=0) ) {
                Print("Sinais não conclusivos ou divergentes nesta barra. PipFinite:",sinalPipFiniteAtual,", MA:",sinalMAAtual,". Último sinal salvo mantido: ", ultimoSinalValidoSalvo);
            }
        }

        // 2. Verificar Condições de Trading
        if(!VerificarCondicoesTrading()) {
             if(EnableDebugLogs) Print("Condições de trading NÃO PERMITIDAS na barra atual. Nenhuma ordem será aberta.");
            return; // Sai da lógica de nova barra se condições não permitirem
        }

        // 3. Lógica de Abertura de Ordem (Baseada no Sinal Salvo)
        int ordemAberta = CurrentOpenOrderType();
        if(ordemAberta == 0 && ultimoSinalValidoSalvo != 0) // Se nenhuma ordem aberta E existe um sinal salvo
        {
            if(EnableDebugLogs) Print("Sem ordens abertas. Tentando abrir a favor do último sinal salvo: ", (ultimoSinalValidoSalvo == 1 ? "COMPRA" : "VENDA"));

            if(UsarMartingale && nivelMartingale > 0)
                loteAtual = NormalizeDouble(Lots * MathPow(MultiplicadorMartingale, nivelMartingale), 2);
            else
                loteAtual = Lots;

            if(nivelMartingale > MaxMartingale) { // Segurança extra
                nivelMartingale = MaxMartingale;
                loteAtual = NormalizeDouble(Lots * MathPow(MultiplicadorMartingale, MaxMartingale),2);
                 if(EnableDebugLogs) Print("Martingale no nível máximo (", MaxMartingale, ") para esta entrada.");
            }
            // Adicionar verificações de lote mínimo/máximo do broker aqui se necessário

            bool opened = false;
            if(ultimoSinalValidoSalvo == 1) {
                opened = AbrirOrdemCompra();
            } else if(ultimoSinalValidoSalvo == -1) {
                opened = AbrirOrdemVenda();
            }
            // Se opened, logs já estão nas funções AbrirOrdemCompra/Venda
        } else if (ordemAberta != 0 && EnableDebugLogs) {
            Print("Já existe uma ordem aberta. Nenhuma nova ordem será aberta.");
        } else if (ultimoSinalValidoSalvo == 0 && EnableDebugLogs) {
            Print("Nenhum sinal válido salvo. Nenhuma nova ordem será aberta.");
        }
    } // Fim da lógica de Nova Barra
}

//+------------------------------------------------------------------+
//| Função para eventos do gráfico (cliques em objetos)             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == "Panel_TrailingStop_Btn") {
            g_UsarTrailingStop_GUI = !g_UsarTrailingStop_GUI;
            if(EnableDebugLogs) Print("Botão Trailing Stop clicado. Novo estado: ", g_UsarTrailingStop_GUI ? "ON" : "OFF");
            AtualizarPainel(); // Atualiza o texto e cor do botão
            ChartRedraw();
        }
    }
}
//+------------------------------------------------------------------+
