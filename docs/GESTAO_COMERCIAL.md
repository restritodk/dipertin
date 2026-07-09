# Módulo Gestão Comercial — DiPertin

> Documentação completa do módulo de gestão financeira e PDV para lojistas.
> Versão: junho/2026 | Região Cloud Functions: `southamerica-east1`

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Menu e Navegação](#2-menu-e-navegação)
3. [Telas do Módulo](#3-telas-do-módulo)
4. [Widgets Compartilhados](#4-widgets-compartilhados)
5. [Services (Dart)](#5-services-dart)
6. [Cloud Functions](#6-cloud-functions)
7. [Firestore Collections](#7-firestore-collections)
8. [Fluxo PIX (PDV)](#8-fluxo-pix-pdv)
9. [Configurações e API Keys](#9-configurações-e-api-keys)
10. [Arquitetura de Chamadas](#10-arquitetura-de-chamadas)
11. [Glossário](#11-glossário)
12. [E-mail Transacional](#12-e-mail-transacional)
13. [Checklist produção](#13-checklist-produção)

---

## 1. Visão Geral

O **Gestão Comercial** é um módulo SaaS completo para lojistas gerenciarem suas operações financeiras e vendas no balcão. Ele inclui:

- **PDV** (Ponto de Venda) com suporte a PIX via Mercado Pago, dinheiro, cartão e crédito próprio
- **Crediário** com controle de parcelas, juros, multas e limite de crédito por cliente
- **Controle de Caixa** com abertura/fechamento diário e consolidação automática
- **Pendências Financeiras** com agrupamento por cliente, cálculo de juros/multa
- **Histórico e Relatórios** com gráficos, exportação PDF e métricas
- **Configurações** com integração Mercado Pago (cada loja com token próprio)

### Público-alvo

Apenas **lojistas** (perfil lojista). Admin/master não tem acesso ao módulo.

### Stack

| Camada | Tecnologia |
|--------|------------|
| Frontend | Flutter Web (painel admin) |
| Backend | Firebase Cloud Functions (Node.js 20, Gen2) |
| Região Functions | `southamerica-east1` (Brasil) |
| Banco | Firestore (Firebase) |
| Gateway | Mercado Pago (PIX) |

---

## 2. Menu e Navegação

### 2.1 Sidebar

O item **"Gestão Comercial"** é um accordion expansível no sidebar (`sidebar_menu.dart`), disponível **apenas para perfil lojista**.

```
┌─ Gestão Comercial (accordion) ─────────────────────────┐
│  📊  Dashboard Comercial        → /comercial_dashboard  │
│  🏪  PDV                        → /pdv                 │
│  👥  Cadastro de Clientes       → /comercial_clientes  │
│  ⚙️  Configurações Comerciais   → /comercial_configuracoes │
│                                                         │
│  ┌─ 💰 Financeiro (sub-accordion) ──────────────────┐  │
│  │  💳  Crédito de Cliente    → /comercial_credito  │  │
│  │  ⚠️  Pendência Financeira  → /comercial_pendencias│  │
│  │  💸  Recebimentos          → /comercial_recebimentos│ │
│  │  📋  Histórico de Vendas   → /comercial_historico │  │
│  │  📈  Relatório Comercial   → /comercial_relatorios│  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Rotas

9 rotas registradas no shell (`painel_routes.dart`):

| Índice | Rota | Widget | Descrição |
|--------|------|--------|-----------|
| 27 | `/pdv` | `LojistaPdvScreen` | Ponto de venda completo |
| 36 | `/comercial_dashboard` | `LojistaComercialDashboardScreen` | Dashboard com KPIs |
| 37 | `/comercial_clientes` | `LojistaComercialClientesScreen` | CRUD de clientes |
| 38 | `/comercial_credito` | `LojistaComercialCreditoScreen` | Crediário e parcelas |
| 39 | `/comercial_pendencias` | `ComercialPendenciasScreen` | Pendências financeiras |
| 40 | `/comercial_recebimentos` | `ComercialRecebimentosScreen` | Histórico de recebimentos |
| 41 | `/comercial_historico` | `ComercialHistoricoVendasScreen` | Histórico de vendas |
| 42 | `/comercial_relatorios` | `ComercialRelatorioScreen` | Relatórios financeiros |
| 43 | `/comercial_configuracoes` | `ComercialConfiguracoesScreen` | Configurações (API keys, juros, etc.) |

**Helpers:**

```dart
PainelRoutes.comercialFinanceiroRotas
// → ['/comercial_credito', '/comercial_pendencias', '/comercial_recebimentos',
//     '/comercial_historico', '/comercial_relatorios']

PainelRoutes.ehRotaComercialFinanceiro(rota)
// → true se a rota pertence ao subgrupo financeiro
```

---

## 3. Telas do Módulo

### 3.1 Dashboard Comercial (`LojistaComercialDashboardScreen`)

**Arquivo:** `lojista_comercial_dashboard_screen.dart` (~1649 linhas)

Dashboard premium com visão geral do negócio:

- **Seletor de período:** 7 dias, 30 dias, 90 dias, Este ano
- **Grid de KPIs (6 cards):** Vendas Hoje, Vendas Ontem, Ticket Médio, Crédito Utilizado, Pendências, Clientes Ativos
- **Gráficos:** evolução de vendas, distribuição por forma de pagamento, inadimplência
- **Seções:**
  - Vendas e Crédito
  - Clientes e Pendências
  - Pagamentos, Produtos e Insights
  - Ações Rápidas

**Coleções:** `gestao_comercial_vendas`, `gestao_comercial_recebimentos`, `clientes_comercial`, `parcelas_cliente`

**Chamadas de Functions:** Nenhuma (dados via `ComercialDashboardService` com queries Firestore diretas)

---

### 3.2 PDV — Ponto de Venda (`LojistaPdvScreen`)

**Arquivo:** `lojista_pdv_screen.dart` (~5202 linhas) — a maior tela do módulo

PDV profissional completo com todas as funcionalidades de venda no balcão.

#### Funcionalidades

| Funcionalidade | Descrição |
|----------------|-----------|
| **Carrinho** | Lista local de itens (`PdvItem`), soma automática, desconto por valor ou % |
| **Busca de produtos** | Por nome com categorias |
| **Seleção de cliente** | Modal de busca, cadastro rápido |
| **Formas de pagamento** | Dinheiro, PIX (QR Code), Cartão, Crédito Cliente, Fiado |
| **Caixa** | Abertura/fechamento diário com saldo inicial |
| **Calculadora** | Calculadora embutida para troco |
| **Recibo** | Impressão de recido/PDF |
| **PIX** | Geração de QR Code via Mercado Pago, polling de status |

#### Fluxo PIX

```
1. Operador seleciona PIX como forma de pagamento
2. Chama gestaoComercialCriarPagamentoPix (southamerica-east1)
3. Exibe QR Code + chave PIX copia-e-cola no modal
4. Inicia listener Firestore em gestao_comercial_cobrancas/{cobrancaId}
5. Timer de 5 minutos para expiração
6. Botão "Verificar pagamento" → chama gestaoComercialConsultarStatusPix
7. Webhook do MP → atualiza Firestore → listener detecta "pago"
8. Modal de sucesso premium com detalhes do pagamento
```

**Coleções:** `gestao_comercial_vendas`, `gestao_comercial_cobrancas`, `gestao_comercial_caixas`, `gestao_comercial_recebimentos`, `clientes_comercial`, `parcelas_cliente`

**Cloud Functions chamadas:**
- `gestaoComercialCriarPagamentoPix`
- `gestaoComercialConsultarStatusPix`
- `gestaoComercialReceberPagamento`
- `gestaoComercialAbrirCaixa`
- `gestaoComercialFecharCaixa`

---

### 3.3 Cadastro de Clientes (`LojistaComercialClientesScreen`)

**Arquivo:** `lojista_comercial_clientes_screen.dart` (~1437 linhas)

CRUD completo de clientes comerciais da loja:

- **Filtros:** Status (Ativo/Com pendência/Bloqueado), crédito (Sim/Não), pendência (Sim/Não)
- **Ordenação:** Mais recentes, Nome A-Z, Maior total comprado
- **Ações por cliente:**
  - Editar dados
  - Ver perfil completo (com histórico)
  - Receber pagamento
  - Conceder/ajustar limite de crédito
  - Bloquear cliente
- **Modal de cadastro** com campos: nome, telefone, WhatsApp, CPF, RG, e-mail, endereço completo, dia de vencimento do crédito, observações

**Coleção:** `users/{lojaId}/clientes_comercial` (subcoleção)

**Modais integrados:**
- `ComercialClienteFormModal` — cadastro/edição
- `ComercialClientePerfilModal` — perfil completo
- `ComercialClienteRecebimentoModal` — receber pagamento
- `ComercialBuscaClienteModal` — busca rápida

---

### 3.4 Crédito de Cliente (`LojistaComercialCreditoScreen`)

**Arquivo:** `lojista_comercial_credito_screen.dart` (~1855 linhas)

Crediário completo com 3 abas em tempo real:

| Aba | Conteúdo |
|-----|----------|
| **Clientes** | Lista com limite, utilizado, disponível, status |
| **Parcelas** | Parcelas em aberto com vencimento, valor, dias em atraso |
| **Recebimentos** | Histórico de recebimentos do crediário |

- **Filtros:** status crédito, faixa de valor, ordenação, status parcela
- **Ações:** conceder crédito, receber pagamento, ver extrato do cliente
- **Streams em tempo real** via `ComercialCreditoService`

---

### 3.5 Pendências Financeiras (`ComercialPendenciasScreen`)

**Arquivo:** `comercial_pendencias_screen.dart` (~527 linhas) — enxuta, foco em usabilidade

Pendências financeiras **agrupadas por cliente**:

- **Filtros:**
  - Status: Vencido / Vence hoje / Vence em breve / Em dia
  - Vencimento: Vencidos / Vence hoje / Próximos 7 dias / Próximos 30 dias
- **Cards de resumo (5 cards):**
  1. Vencidas (valor total)
  2. Vence hoje
  3. Próximos 7 dias
  4. Total em aberto
  5. Recebido no mês
- **Gráfico donut:** distribuição das pendências (vencidas, vence hoje, 7 dias, outros)
- **Top 5 devedores:** ranking com nome, valor, badge de posição
- **Ações por pendência:** Receber, Enviar cobrança, Ver extrato, Negociar, Bloquear crédito, Excluir

**Coleções:** `parcelas_cliente`, `clientes_comercial`, `recebimentos_cliente`

---

### 3.6 Recebimentos (`ComercialRecebimentosScreen`)

**Arquivo:** `comercial_recebimentos_screen.dart` (~1768 linhas)

Lista em tempo real de todos os recebimentos da loja:

- **Stream** de `gestao_comercial_recebimentos` com filtros:
  - Período (início/fim)
  - Forma de pagamento
  - Recebido por (operador)
  - Busca textual
- **Cards de resumo:** Recebido hoje, Recebido no mês, Variação %, Ticket médio, Parcelas recebidas, Clientes pagantes
- **Tabela** com: cliente, valor, forma de pagamento, data, recebido por
- **Ações:** Estornar recebimento (reabre parcela vinculada via transação Firestore)

---

### 3.7 Histórico de Vendas (`ComercialHistoricoVendasScreen`)

**Arquivo:** `comercial_historico_vendas_screen.dart` (~1959 linhas)

Histórico completo de vendas:

- **Filtros:** período (início/fim), status, forma de pagamento
- **Busca:** por nome do cliente, documento, código da venda
- **Resumo:** total de vendas, total recebido, ticket médio no período
- **Exportação:** PDF com detalhes das vendas
- **Paginação** para grandes volumes

---

### 3.8 Relatório Comercial (`ComercialRelatorioScreen`)

**Arquivo:** `comercial_relatorio_screen.dart` (~2370 linhas)

Relatório financeiro completo com análise avançada:

- **KPIs:** Faturamento do mês, Total recebido, Em aberto, Ticket médio, Qtd. vendas, Clientes ativos
- **Comparação** com mês anterior (variação %)
- **Gráfico de evolução** de vendas (fl_chart)
- **Rankings:**
  - Produtos mais vendidos
  - Clientes que mais compram
- **Distribuição** por forma de pagamento (pizza)
- **Tabela de vendas** por dia
- **Gráfico de inadimplência**

---

### 3.9 Configurações Comerciais (`ComercialConfiguracoesScreen`)

**Arquivo:** `comercial_configuracoes_screen.dart` (~3768 linhas)

Tela de configurações com 4 seções principais. **(Documentação detalhada na seção [9. Configurações e API Keys](#9-configurações-e-api-keys).)**

---

## 4. Widgets Compartilhados

Pasta `depertin_web/lib/widgets/comercial/`.

### 4.1 ComercialDashboardAcoes (`comercial_dashboard_acoes.dart`)

Ações rápidas exibidas no dashboard. 8 botões com ícone + label:

| Ação | Rota/Comando |
|------|-------------|
| Nova Venda | → `/pdv` |
| Novo Cliente | Abre modal de cadastro |
| Conceder Crédito | Abre modal de crédito |
| Ver Pendências | → `/comercial_pendencias` |
| Receber Pagamento | Abre modal de recebimento |
| Relatórios | → `/comercial_relatorios` |
| Histórico Vendas | → `/comercial_historico` |
| Exportar Relatório | Gera PDF |

### 4.2 FinancialSummaryCard (`comercial_financial_summary_card.dart`)

Card de resumo financeiro com:
- Ícone (customizável por cor de fundo)
- Título do indicador
- Valor em R$ (formatado)
- Rodapé com texto adicional
- Variação percentual (up/down)

### 4.3 FinancialTable (`comercial_financial_table.dart`)

Tabela genérica de pendências (~502 linhas) com:
- Colunas: checkbox seleção, cliente, código, vencimento, valor, ações
- Paginação (itens por página)
- Suporte a ações por linha (via callback)
- Ordenação por coluna

### 4.4 FinancialFilters (`comercial_financial_filters.dart`)

Barra de filtros (~188 linhas) com:
- Campo de busca textual
- Dropdowns: status, plano, vencimento
- Botão "Limpar filtros"

### 4.5 FinancialStatusBadge (`comercial_financial_status_badge.dart`)

Chip colorido de status:

| Status | Cor |
|--------|-----|
| Vencido | Vermelho (`#DC2626`) |
| Vence hoje | Laranja (`#FF8F00`) |
| Vence em breve | Amarelo (`#CA8A04`) |
| Em dia | Verde (`#16A34A`) |

### 4.6 FinancialActionMenu (`comercial_financial_action_menu.dart`)

PopupMenuButton com 6 ações: Receber, Enviar cobrança, Ver extrato, Negociar, Bloquear crédito, Excluir.

### 4.7 DebtChartCard (`comercial_debt_chart_card.dart`)

Gráfico donut personalizado (CustomPaint) com segmentos coloridos:
- Vencidas
- Vence hoje
- Vence em 7 dias
- Outros (em dia)

### 4.8 TopDebtorsCard (`comercial_top_debtors_card.dart`)

Top 5 maiores devedores com:
- Nome do cliente
- Valor total da dívida
- Badge de posição (1º, 2º, 3º...)
- Cores: 1º roxo, 2º laranja, 3º roxo 50%

### 4.9 QuickActionsCard (`comercial_quick_actions_card.dart`)

Ações rápidas em formato de botões: Enviar lembretes, Gerar cobranças, Exportar relatório.

### 4.10 ComercialPendenciasModal (`comercial_pendencias_modal.dart`)

Modal que lista clientes com pendências e permite receber pagamento diretamente.

### 4.11 ComercialClienteRecebimentoModal (`comercial_cliente_recebimento_modal.dart`)

**Modal principal de recebimento** (~916 linhas). Funcionalidades:

- Lista parcelas em aberto do cliente
- Seleção múltipla de parcelas para receber
- Cálculo automático de juros e multa (baseado na config da loja)
- Formas de pagamento: Dinheiro, PIX, Cartão débito/crédito, Transferência, Carteira DiPertin
- Opção de desconto
- Comprovante após confirmação

### Outros Modais

| Widget | Arquivo | Função |
|--------|---------|--------|
| `ComercialClienteFormModal` | `comercial_cliente_form_modal.dart` | Cadastro/edição de cliente |
| `ComercialBuscaClienteModal` | `comercial_busca_cliente_modal.dart` | Busca rápida |
| `ComercialConcederCreditoModal` | `comercial_conceder_credito_modal.dart` | Conceder/ajustar limite |
| `ComercialHistoricoVendasModal` | `comercial_historico_vendas_modal.dart` | Histórico resumido |
| `ComercialExportarModal` | `comercial_exportar_modal.dart` | Exportação |
| `ComercialModalShell` | `comercial_modal_ui.dart` | Shell base para modais |

---

## 5. Services (Dart)

### 5.1 ComercialCreditoService

**Arquivo:** `comercial_credito_service.dart` (~647 linhas)

Operações de crediário:

```dart
// Streams em tempo real (limit 3000 parcelas, 2000 recebimentos)
Stream<List<Map>> streamParcelasCliente(String lojaId, String clienteId);
Stream<List<Map>> streamParcelasLoja(String lojaId);
Stream<List<Map>> streamRecebimentosLoja(String lojaId);

// Operações
Future<void> criarVendaCredito({lojaId, clienteId, valor, parcelas, ...});
Future<void> registrarPagamentoParcela({parcelaId, valor, formaPagamento, ...});
Future<void> concederLimiteAdicional({clienteId, novoLimite, ...});

// Auditoria (via Cloud Function)
callFirebaseFunctionSafe('registrarEventoAuditoriaApp', region: 'us-central1', ...);
```

**Coleções:** `users/{lojaId}/vendas_credito`, `parcelas_cliente`, `recebimentos_cliente`, `clientes_comercial`, `gestao_comercial_recebimentos`

---

### 5.2 ComercialConfigService

**Arquivo:** `comercial_config_service.dart` (~66 linhas)

Configurações de juros e multa:

```dart
Future<Map> carregarJurosMultaConfig(String lojaId);
Stream<Map> streamJurosMultaConfig(String lojaId); // tempo real
```

**Coleção:** `gestao_comercial_configuracoes/{lojaId}`

---

### 5.3 ComercialPendenciasService

**Arquivo:** `comercial_pendencias_service.dart` (~259 linhas)

Agregação local de pendências (não altera Firestore):

```dart
Future<ResumoPendencias> carregarResumo(String lojaId);
Stream<ResumoPendencias> streamResumo(String lojaId); // reage a mudanças

// Estrutura do ResumoPendencias
class ResumoPendencias {
  double totalVencidas, totalVenceHoje, totalProximos7Dias, totalEmAberto;
  int qtdVencidas, qtdVenceHoje, qtdProximos7Dias, qtdEmAberto;
  double recebidoMes;
  List<Map> topDevedores;
  Map<String, int> distribuicaoStatus;
}
```

**Coleções:** `parcelas_cliente`, `clientes_comercial`, `recebimentos_cliente`

---

### 5.4 ComercialRecebimentosService

**Arquivo:** `comercial_recebimentos_service.dart` (~551 linhas)

CRUD completo de recebimentos:

```dart
Stream<List<Map>> streamRecebimentos({lojaId, periodo, forma, recebidoPor, busca});
Future<void> criar({...});           // Cria recebimento
Future<void> estornar({id, motivo}); // Estorna (transação: reabre parcela)
ResumoRecebimentos calcularResumo(List recebimentos);

// Migração de dados legados
Future<void> migrarLegados(String lojaId);
```

**Coleção:** `gestao_comercial_recebimentos`

---

### 5.5 VendasHistoricoService

**Arquivo:** `vendas_historico_service.dart` (~129 linhas)

Carga de vendas com filtros:

```dart
Future<List<Map>> carregarVendas({lojaId, dataInicio, dataFim});
List<Map> aplicarFiltros(vendas, {status, formaPagamento, buscaTexto});
```

**Coleção:** `gestao_comercial_vendas`

---

## 6. Cloud Functions

Todas as funções do Gestão Comercial estão na região **`southamerica-east1`** (Gen2).

### 6.1 Configuração Padrão

```javascript
const CONFIG_PADRAO = {
    region: "southamerica-east1",
    cpu: 1,
    memory: "512MiB",
    maxInstances: 10,
    timeoutSeconds: 60,
};

const CONFIG_PESADO = {  // Para consultas mais pesadas
    region: "southamerica-east1",
    cpu: 1,
    memory: "1GiB",
    maxInstances: 5,
    timeoutSeconds: 120,
};
```

### 6.2 Lista Completa

| # | Nome da Função | Config | Tipo | Descrição |
|---|---------------|--------|------|-----------|
| 1 | `gestaoComercialCriarPagamentoPix` | Padrão | onCall | Cria pagamento PIX no Mercado Pago |
| 2 | `gestaoComercialConsultarStatusPix` | Padrão | onCall | Consulta status PIX diretamente no MP |
| 3 | `gestaoComercialTestarConexaoMercadoPago` | Padrão | onCall | Testa validade do Access Token |
| 4 | `gestaoComercialWebhookMercadoPago` | Padrão | onRequest | Webhook HTTP para notificações MP |
| 5 | `gestaoComercialAbrirCaixa` | Padrão | onCall | Abre caixa diário |
| 6 | `gestaoComercialFecharCaixa` | Padrão | onCall | Fecha caixa com consolidação |
| 7 | `gestaoComercialReceberPagamento` | Padrão | onCall | Registra recebimento manual |
| 8 | `gestaoComercialConcederCredito` | Padrão | onCall | Ajusta limite de crédito |
| 9 | `gestaoComercialConsultarPendencias` | Pesado | onCall | Resumo de pendências financeiras |
| 10 | `gestaoComercialHistoricoVendas` | Pesado | onCall | Histórico de vendas com filtros |
| 11 | `gestaoComercialRelatorio` | Pesado | onCall | Relatório financeiro consolidado |
| 12 | `gestaoComercialFinanceiroCliente` | Padrão | onCall | Situação financeira detalhada do cliente |
| 13 | `gestaoComercialConsultarParcelas` | Padrão | onCall | Consulta parcelas de venda |

### 6.3 Detalhamento das Funções

#### 1. `gestaoComercialCriarPagamentoPix`

**Propósito:** Cria um pagamento PIX no Mercado Pago para uma venda PDV. Usa as credenciais do lojista (nunca expõe o token ao frontend). Gera cobrança com QR Code e cria documento de venda com status `aguardando_pagamento`.

**Parâmetros de entrada:**
```json
{
  "lojaId": "string (obrigatório)",
  "vendaId": "string (obrigatório)",
  "valor": "number >0 (obrigatório)",
  "itens": "[{id, nome, preco, quantidade}] (opcional)",
  "clienteId": "string? (opcional)",
  "clienteNome": "string? (opcional)",
  "operadorId": "string? (opcional)"
}
```

**Retorno:**
```json
{
  "cobrancaId": "string",
  "paymentId": "string",
  "qrCodeBase64": "string (base64 do QR Code)",
  "pixCopiaECola": "string (chave PIX copia-e-cola)",
  "expiresAt": "string (ISO, 5 minutos)",
  "status": "aguardando_pagamento"
}
```

**Coleções acessadas:** `gestao_comercial_configuracoes`, `gestao_comercial_integracoes_pagamento`, `gestao_comercial_cobrancas`, `gestao_comercial_vendas`

**Expiração:** 5 minutos (`Date.now() + 5 * 60 * 1000`)

---

#### 2. `gestaoComercialConsultarStatusPix`

**Propósito:** Consulta o status de uma cobrança PIX. Se estiver aguardando, consulta a API do Mercado Pago diretamente. Se aprovado, atualiza cobrança e finaliza venda. Se expirado (5 min), marca como `expirado`. **Nunca** marca como cancelado/recusado durante o prazo.

**Parâmetros:**
```json
{ "cobrancaId": "string (obrigatório)" }
```

**Retorno:**
```json
{
  "status": "aguardando_pagamento | pago | expirado | cancelado",
  "pago": false,
  "expirado": false,
  "cancelado": false,
  "valorRecebido": 0,
  "vendaId": "string",
  "pagamento": { /* detalhes se pago */ }
}
```

**Coleções:** `gestao_comercial_cobrancas`, `gestao_comercial_vendas`, `gestao_comercial_recebimentos`, `gestao_comercial_configuracoes`

---

#### 3. `gestaoComercialTestarConexaoMercadoPago`

**Propósito:** Testa se um Access Token do Mercado Pago é válido fazendo `GET /v1/payments/search?limit=1`. Evita CORS ao chamar a API MP diretamente do navegador.

**Parâmetros:**
```json
{ "accessToken": "string (obrigatório)" }
```

**Retorno:**
```json
{ "valido": true, "mensagem": "Access Token valido!" }
```

**Coleções:** Nenhuma (chama API externa MP)

---

#### 4. `gestaoComercialWebhookMercadoPago`

**Propósito:** Endpoint HTTP público para receber notificações de pagamento do Mercado Pago. URL: `https://southamerica-east1-depertin-f940f.cloudfunctions.net/gestaoComercialWebhookMercadoPago`

- GET → health check (retorna "ok")
- POST → processa notificação

**Idempotência:** Usa flag `processed: true` na cobrança para evitar duplicidade.

---

#### 5. `gestaoComercialAbrirCaixa`

**Propósito:** Abre o caixa diário de uma loja. Detecta se já existe caixa aberto para a data atual. Se já existir, retorna o existente.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "operadorId": "string?",
  "saldoInicial": "number (default 0)"
}
```

**Retorno:** `{ caixaId, status: "aberto", abertoEm, saldoInicial }`

**Coleção:** `gestao_comercial_caixas`

---

#### 6. `gestaoComercialFecharCaixa`

**Propósito:** Fecha o caixa diário. Consolida automaticamente todas as vendas do dia (total por forma de pagamento) e calcula totais.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "caixaId": "string? (se omitido, busca pelo mais recente aberto)",
  "saldoFinal": "number?",
  "observacao": "string?"
}
```

**Retorno:** `{ caixaId, status: "fechado", resumo: { totalVendas, quantidadeVendas, totalPix, totalDinheiro, ... } }`

**Coleções:** `gestao_comercial_caixas`, `gestao_comercial_vendas`

---

#### 7. `gestaoComercialReceberPagamento`

**Propósito:** Registra recebimento de pagamento manual (dinheiro, cartão, etc.). Inclui idempotência por venda + forma de pagamento.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "vendaId": "string (obrigatório)",
  "valor": "number >0 (obrigatório)",
  "formaPagamento": "string (obrigatório)",
  "clienteId": "string?",
  "clienteNome": "string?",
  "observacao": "string?"
}
```

**Retorno:** `{ recebimentoId, status: "confirmado" }`

**Coleções:** `gestao_comercial_vendas`, `gestao_comercial_recebimentos`

---

#### 8. `gestaoComercialConcederCredito`

**Propósito:** Concede ou ajusta o limite de crédito de um cliente comercial. Atualiza o campo `credito_disponivel` automaticamente.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "clienteId": "string (obrigatório)",
  "limite": "number >=0 (obrigatório)",
  "observacao": "string?"
}
```

**Retorno:** `{ clienteId, limite, limiteAnterior, status: "concedido" }`

**Coleção:** `clientes_comercial`

---

#### 9. `gestaoComercialConsultarPendencias`

**Propósito:** Retorna resumo completo de pendências financeiras de uma loja. Agrupa por cliente e calcula totais vencidos.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "clienteId": "string? (filtro opcional)"
}
```

**Retorno:** `{ totalPendente, totalVencido, totalParcelas, topDevedores: [...], clientes: [...] }`

**Coleção:** `parcelas_cliente`

---

#### 10. `gestaoComercialHistoricoVendas`

**Propósito:** Retorna histórico de vendas com filtros opcionais de data, status e limite.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "dataInicio": "string ISO?",
  "dataFim": "string ISO?",
  "status": "string?",
  "limite": "number (max 500, default 100)"
}
```

**Retorno:** `{ vendas: [{vendaId, codigo, clienteNome, valorTotal, status, ...}], total }`

**Coleção:** `gestao_comercial_vendas`

---

#### 11. `gestaoComercialRelatorio`

**Propósito:** Gera relatório financeiro consolidado para um período com vendas, recebimentos e indicadores.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "periodoInicio": "string ISO? (default: 30 dias atrás)",
  "periodoFim": "string ISO? (default: agora)"
}
```

**Retorno:** `{ periodo, resumo: {totalVendas, totalPago, totalRecebido, qtdPago, ticketMedio, ...}, porFormaPagamento: {}, recebimentos: [...] }`

**Coleções:** `gestao_comercial_vendas`, `gestao_comercial_recebimentos`

---

#### 12. `gestaoComercialFinanceiroCliente`

**Propósito:** Retorna situação financeira detalhada de um cliente: dados cadastrais, limite de crédito, parcelas pendentes ordenadas por vencimento.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "clienteId": "string (obrigatório)"
}
```

**Retorno:** `{ cliente, credito: {limite, utilizado, disponivel}, parcelas: [...], totalPendente, totalVencido }`

**Coleções:** `clientes_comercial`, `parcelas_cliente`

---

#### 13. `gestaoComercialConsultarParcelas`

**Propósito:** Retorna parcelas de uma venda específica ou de todas as vendas pendentes de um cliente.

**Parâmetros:**
```json
{
  "lojaId": "string (obrigatório)",
  "vendaId": "string?",
  "clienteId": "string?"
}
```

**Retorno:** `{ parcelas: [{parcelaId, numero, valor, dataVencimento, status, vencido}], totalPendente }`

**Coleção:** `parcelas_cliente`

---

### 6.4 Funções Legadas (ainda em `us-central1`)

**Arquivo:** `mercado_pago_gestao_comercial.js`

Estas funções continuam existindo em `us-central1` para compatibilidade, mas não são mais chamadas pelo frontend:

| Função | Tipo | Observação |
|--------|------|------------|
| `webhookMercadoPagoGestaoComercial` | v1 onRequest | Webhook legado (us-central1). Ainda pode receber notificações se configurado no MP |
| `createPdvPixPayment` | v2 onCall | Substituída por `gestaoComercialCriarPagamentoPix` |
| `checkPdvPixPaymentStatus` | v2 onCall | Substituída por `gestaoComercialConsultarStatusPix` |
| `testarConexaoMercadoPago` | v2 onCall | Substituída por `gestaoComercialTestarConexaoMercadoPago` |

> **Atenção:** O webhook legado `webhookMercadoPagoGestaoComercial` deve ser mantido até que o Mercado Pago seja reconfigurado para apontar para o novo endpoint `gestaoComercialWebhookMercadoPago` em `southamerica-east1`.

---

## 7. Firestore Collections

### 7.1 Coleções Top-Level

#### `gestao_comercial_vendas`

Vendas realizadas no PDV e na gestão comercial.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `loja_id` | string | ID da loja |
| `venda_id` | string | ID único da venda |
| `cobranca_id` | string | ID da cobrança PIX (se aplicável) |
| `codigo_venda` | string | Código amigável (ex: `A1B2C3D4`) |
| `cliente_id` | string | ID do cliente ou `"venda_balcao"` |
| `cliente_nome` | string | Nome do cliente |
| `itens` | array | `[{id, nome, preco, quantidade}]` |
| `quantidade_itens` | number | Total de itens |
| `forma_pagamento` | string | `PIX`, `Dinheiro`, `Cartão`, `Crédito`, `Fiado` |
| `valor_total` | number | Valor total da venda |
| `valor_pago` | number | Valor já pago |
| `valor_pendente` | number | Valor pendente |
| `desconto_total` | number | Desconto aplicado |
| `status` | string | `aguardando_pagamento`, `pago`, `pendente`, `cancelado`, `quitado`, `finalizada` |
| `operador_id` | string | ID do operador |
| `operador_nome` | string | Nome do operador |
| `data_venda` | Timestamp | Data da venda |
| `pagoEm` | Timestamp | Data do pagamento |
| `mpPaymentId` | string | ID do pagamento no Mercado Pago |
| `createdAt` | Timestamp | Data de criação |
| `updatedAt` | Timestamp | Data da última atualização |

#### `gestao_comercial_recebimentos`

Recebimentos consolidados da loja.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `loja_id` | string | ID da loja |
| `venda_id` | string | ID da venda |
| `cliente_id` | string | ID do cliente |
| `cliente_nome` | string | Nome do cliente |
| `parcela_id` | string | ID da parcela (se aplicável) |
| `valor_original` | number | Valor original |
| `valor_recebido` | number | Valor efetivamente recebido |
| `valor_multa` | number | Multa cobrada |
| `valor_juros` | number | Juros cobrados |
| `valor_desconto` | number | Desconto concedido |
| `forma_pagamento` | string | `PIX`, `Dinheiro`, `Cartão`, `Crédito`, `Fiado`, `Transferência`, `Carteira DiPertin` |
| `gateway` | string | `mercado_pago` (se PIX) |
| `payment_id` | string | ID do pagamento no gateway |
| `cobranca_id` | string | ID da cobrança (PDV PIX) |
| `recebido_por_id` | string | ID do operador |
| `recebido_por_nome` | string | Nome do operador |
| `data_recebimento` | Timestamp | Data do recebimento |
| `status` | string | `confirmado`, `estornado` |
| `origem` | string | `pdv_pix`, `pdv_manual`, `recebimento_parcela` |
| `comprovante_url` | string | URL do comprovante |
| `created_at` | Timestamp | Data de criação |

#### `gestao_comercial_cobrancas`

Cobranças PIX em andamento.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `lojaId` | string | ID da loja |
| `vendaId` | string | ID da venda |
| `clienteId` | string | ID do cliente |
| `clienteNome` | string | Nome do cliente |
| `operadorId` | string | ID do operador |
| `gateway` | string | `mercado_pago` |
| `paymentId` | string | ID do pagamento no MP |
| `externalReference` | string | Referência externa |
| `valor` | number | Valor da cobrança |
| `status` | string | `aguardando_pagamento`, `pago`, `expirado`, `cancelado`, `recusado`, `estornado` |
| `qrCodeBase64` | string | QR Code em base64 |
| `pixCopiaECola` | string | Chave PIX copia-e-cola |
| `expiresAt` | Timestamp | Data de expiração (5 min) |
| `processed` | boolean | Flag de idempotência |
| `origem` | string | `pdv` |
| `createdAt` | Timestamp | Data de criação |
| `updatedAt` | Timestamp | Última atualização |
| `pagoEm` | Timestamp | Data do pagamento (se pago) |
| `mpStatus` | string | Status retornado pelo MP |
| `mpPaymentMethod` | string | Método de pagamento MP |

#### `gestao_comercial_caixas`

Controle de abertura/fechamento de caixa.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `loja_id` | string | ID da loja |
| `data_key` | string | Data no formato `YYYY-MM-DD` |
| `status` | string | `aberto`, `fechado` |
| `saldo_inicial` | number | Saldo no início do dia |
| `saldo_atual` | number | Saldo atual |
| `saldo_final` | number | Saldo informado no fechamento |
| `total_entradas` | number | Total de entradas |
| `total_saidas` | number | Total de saídas |
| `total_vendas` | number | Total de vendas (consolidado) |
| `quantidade_vendas` | number | Quantidade de vendas |
| `total_pix` | number | Total recebido em PIX |
| `total_dinheiro` | number | Total recebido em dinheiro |
| `total_cartao` | number | Total recebido em cartão |
| `total_fiado` | number | Total em fiado |
| `operador_id_abertura` | string | Operador que abriu |
| `operador_id_fechamento` | string | Operador que fechou |
| `aberto_em` | Timestamp | Data de abertura |
| `fechado_em` | Timestamp | Data de fechamento |
| `atualizado_em` | Timestamp | Última atualização |

#### `gestao_comercial_configuracoes`

Configurações da loja para o módulo. Documentado em detalhes na seção [9. Configurações](#9-configurações-e-api-keys).

---

### 7.2 Subcoleções (em `users/{lojaId}/...`)

#### `clientes_comercial`

Clientes cadastrados no módulo.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `nome` | string | Nome do cliente |
| `telefone` | string | Telefone |
| `whatsapp` | string | WhatsApp |
| `cpf` | string | CPF |
| `rg` | string | RG |
| `email` | string | E-mail |
| `endereco` | map | `{logradouro, numero, bairro, cidade, uf, cep}` |
| `creditoHabilitado` | boolean | Crédito habilitado |
| `limiteCredito` | number | Limite de crédito |
| `creditoUtilizado` | number | Crédito já utilizado |
| `creditoDisponivel` | number | Crédito disponível |
| `diaVencimentoCredito` | int | Dia de vencimento padrão |
| `status` | string | `ativo`, `bloqueado`, `inativo` |
| `observacoes` | string | Observações |
| `vip` | boolean | Cliente VIP |
| `cashback` | number | Cashback acumulado |
| `totalComprado` | number | Total comprado (histórico) |
| `ultimaCompra` | Timestamp | Data da última compra |

#### `vendas_credito`

Vendas financiadas (crediário).

| Campo | Descrição |
|-------|-----------|
| `loja_id` | ID da loja |
| `cliente_id` | ID do cliente |
| `venda_id` | ID da venda |
| `codigo_venda` | Código da venda |
| `valor_total` | Valor total |
| `quantidade_parcelas` | Número de parcelas |
| `valor_entrada` | Valor de entrada |
| `valor_financiado` | Valor financiado |
| `status` | `ativo`, `quitado` |
| `data_compra` | Data da compra |

#### `parcelas_cliente`

Parcelas do crediário.

| Campo | Descrição |
|-------|-----------|
| `loja_id` | ID da loja |
| `cliente_id` | ID do cliente |
| `venda_credito_id` | ID da venda crédito |
| `venda_id` | ID da venda |
| `codigo_venda` | Código da venda |
| `numero_parcela` | Número da parcela |
| `total_parcelas` | Total de parcelas |
| `valor_parcela` | Valor da parcela |
| `valor_pago` | Valor pago |
| `valor_em_aberto` | Valor em aberto |
| `data_compra` | Data da compra |
| `data_vencimento` | Data de vencimento |
| `data_pagamento` | Data do pagamento |
| `status` | `em_aberto`, `pago`, `parcialmente_pago`, `vencido`, `cancelado` |

#### `recebimentos_cliente` (LEGADO)

Recebimentos antigos (sendo migrados para `gestao_comercial_recebimentos`).

---

## 8. Fluxo PIX (PDV)

### 8.1 Diagrama de Sequência

```
┌──────────────┐          ┌──────────────────┐          ┌──────────────┐
│  Painel Web  │          │  Cloud Functions  │          │ Mercado Pago │
│   (PDV)      │          │ southamerica-east1│          │              │
└──────┬───────┘          └────────┬─────────┘          └──────┬───────┘
       │                          │                           │
       │  1. Criar Cobrança PIX   │                           │
       │ ────────────────────────►│                           │
       │  gestaoComercialCriar    │                           │
       │  PagamentoPix            │                           │
       │                          │  2. POST /v1/payments    │
       │                          │ ────────────────────────►│
       │                          │                           │
       │                          │ ◄──── {id, qr_code} ─────│
       │                          │                           │
       │ ◄── {cobrancaId, QR,     │                           │
       │       pixCopiaECola,     │                           │
       │       expiresAt}         │                           │
       │                          │                           │
       │  ┌──────────────────────┐│                           │
       │  │ Exibe QR Code        ││                           │
       │  │ Inicia timer 5min    ││                           │
       │  │ Firestore listener   ││                           │
       │  └──────────────────────┘│                           │
       │                          │                           │
       │    (cliente paga PIX)    │                           │
       │                          │                           │
       │                          │  3. Webhook POST          │
       │                          │ ◄────────────────────────│
       │                          │  gestaoComercialWebhook   │
       │                          │  MercadoPago              │
       │                          │                           │
       │                          │  4. GET /v1/payments     │
       │                          │ ────────────────────────►│
       │                          │ ◄── {status:"approved"}──│
       │                          │                           │
       │                          │  5. Atualiza Firestore    │
       │                          │  cobranca → "pago"        │
       │                          │  venda → finalizada       │
       │                          │  cria recebimento         │
       │                          │                           │
       │  6. Listener detecta     │                           │
       │  status="pago"           │                           │
       │ ◄──── (tempo real) ──────│                           │
       │                          │                           │
       │  ┌──────────────────────┐│                           │
       │  │ Modal de sucesso     ││                           │
       │  │ Exibe comprovante    ││                           │
       │  └──────────────────────┘│                           │
       │                          │                           │
       │  7. (Opcional)           │                           │
       │  Verificar Pagamento     │                           │
       │ ────────────────────────►│                           │
       │  gestaoComercialConsultar│                           │
       │  StatusPix               │                           │
       │                          │  8. GET /v1/payments     │
       │                          │ ────────────────────────►│
       │                          │ ◄── status ──────────────│
       │ ◄── {status, pago,       │                           │
       │       pagamento}         │                           │
```

### 8.2 Regras de Negócio

1. **Expiração de 5 minutos:** O QR Code PIX expira em exatamente 5 minutos. A expiração é definida no backend (`Date.now() + 5 * 60 * 1000`) e enviada ao Mercado Pago como `date_of_expiration`.

2. **QR Code fixo:** O QR Code é gerado uma única vez e armazenado no Firestore. O frontend o exibe sem regeneração ou pulsação.

3. **Confirmação pelo backend:** O pagamento SÓ é confirmado pelo backend. O frontend NUNCA confirma pagamento localmente — ele apenas reage às mudanças no Firestore via listener.

4. **Idempotência:** Tanto o webhook quanto a finalização da venda usam flags `processed` e verificações de status para garantir que uma notificação duplicada não crie múltiplos recebimentos.

5. **Botão "Verificar pagamento":** Apenas consulta o status atual e NUNCA cancela a cobrança.

6. **Cancelamento manual:** Apenas o operador pode cancelar uma cobrança (via botão "Cancelar cobrança" com confirmação). O cancelamento atualiza o Firestore para `cancelado`.

### 8.3 Status da Cobrança

| Status | Quando ocorre | Ação do frontend |
|--------|---------------|------------------|
| `aguardando_pagamento` | Cobrança criada | Exibe QR Code e timer |
| `pago` | MP confirma approved/authorized | Modal de sucesso premium |
| `expirado` | 5 minutos sem pagamento | Permite gerar nova cobrança |
| `cancelado` | Operador cancela manualmente | Fecha modal sem finalizar |
| `recusado` | MP rejeita (após expirado) | Apenas informativo |
| `estornado` | MP estorna (após pago) | Apenas informativo |

---

## 9. Configurações e API Keys

### 9.1 Acessando as Configurações

No sidebar: **Gestão Comercial > Configurações Comerciais** → rota `/comercial_configuracoes`

### 9.2 Seções de Configuração

#### Seção 1: Juros e Multas

Campos para configurar regras de cobrança de atraso:

| Campo | Tipo | Default | Descrição |
|-------|------|---------|-----------|
| Cobrar multa | boolean | false | Aplica multa em atraso |
| Percentual multa | number | 2.0 | % sobre o valor da parcela |
| Cobrar juros | boolean | false | Aplica juros ao dia |
| Percentual juros ao dia | number | 0.033 | % ao dia sobre o valor |
| Dias de tolerância | number | 0 | Dias sem cobrança após vencimento |
| Aplicar multa única | boolean | true | Multa cobrada apenas uma vez |
| Aplicar juros ao dia | boolean | true | Juros calculados por dia corrido |

**Estrutura no Firestore** (`gestao_comercial_configuracoes/{lojaId}`):
```javascript
{
  "jurosMultas": {
    "cobrarMulta": false,
    "percentualMulta": 2.0,
    "cobrarJuros": false,
    "percentualJurosDia": 0.033,
    "diasTolerancia": 0,
    "aplicarMultaUnica": true,
    "aplicarJurosAoDia": true
  }
}
```

#### Seção 2: Integrações de Pagamento (Mercado Pago)

Configuração do gateway de pagamento **Mercado Pago** para recebimento via PIX.

> ⚠️ **Segurança:** As credenciais são enviadas diretamente do frontend para a Cloud Function (`gestaoComercialTestarConexaoMercadoPago`) e NUNCA são expostas ao cliente. O Access Token é armazenado no Firestore com regras de segurança staff/lojista.

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| **Nome** | Sim | Nome amigável (ex: "Mercado Pago") |
| **Provedor** | Sim | `mercado_pago` |
| **Tipo** | Sim | `PIX` |
| **Ambiente** | Sim | `producao` ou `sandbox` |
| **Access Token** | **Sim** | Token de acesso do Mercado Pago (começa com `APP_USR-` em produção) |
| **Public Key** | Não | Chave pública do Mercado Pago |
| **Chave PIX** | Não | Chave PIX para identificação |
| **Ativo** | Sim | Marca se o gateway está ativo |

**Onde obter as chaves:**
1. Acesse [Mercado Pago Developers](https://developers.mercadopago.com.br)
2. Crie ou acesse sua aplicação
3. Em **Credentials**, copie:
   - **Access Token** → campo "Access Token" na configuração
   - **Public Key** → campo "Public Key" na configuração (opcional)

**Teste de Conexão:**
O botão **"Testar conexão"** chama a função `gestaoComercialTestarConexaoMercadoPago` que faz uma requisição `GET /v1/payments/search?limit=1` com o token informado. Retorna:
- ✅ **Verde:** "Access Token válido! Conexão realizada com sucesso."
- ❌ **Vermelho:** Mensagem específica do erro (token inválido, sem permissão, etc.)

**Estrutura no Firestore:**
```javascript
{
  "pagamentos": {
    "mercado_pago": {
      "nome": "Mercado Pago",
      "provedor": "mercado_pago",
      "tipo": "PIX",
      "ambiente": "producao",         // "producao" | "sandbox"
      "chavePix": "seu-email@ou-chave",
      "clientId": "APP_USR-xxxxx",    // Public Key
      "token": "APP_USR-xxxxx",       // Access Token
      "webhookUrl": "",
      "ativo": true
    }
  }
}
```

**Fallback legado para credenciais:**
O backend também busca credenciais em:
```
gestao_comercial_integracoes_pagamento/{lojaId}/gateways/mercado_pago
└── accessToken: string
└── publicKey: string
└── ambiente: string ("producao" | "sandbox")
└── ativo: boolean
```

#### Seção 3: Canais de Cobrança

| Canal | Campos |
|-------|--------|
| **WhatsApp** | Tipo (whatsapp), API URL, Token, Remetente, Template de mensagem, Ativo |
| **E-mail** | Modal **E-mail Transacional** (3 abas: Configuração SMTP/API, Templates, Histórico). Campos legados `apiUrl`/`token`/`templateMensagem` mantidos para compatibilidade. Ver [§12](#12-e-mail-transacional). |
| **SMS** | Tipo (sms), API URL, Token, Remetente, Template de mensagem, Ativo |

#### Seção 4: Regras Automáticas

| Campo | Tipo | Default | Descrição |
|-------|------|---------|-----------|
| Limite crédito padrão | number | 0 | Limite automático para novos clientes |
| Dia vencimento padrão | number | 15 | Dia do mês para vencimento das parcelas |
| Bloquear automaticamente | boolean | false | Bloqueia cliente ao atingir limite |
| Notificar vencimento | boolean | false | Envia notificação de vencimento |
| Dias para notificar | number | 3 | Dias antes do vencimento para notificar |

### 9.3 Estrutura Completa no Firestore

```javascript
// Coleção: gestao_comercial_configuracoes
// Documento: {lojaId}

{
  "loja_id": "abc123",
  "jurosMultas": {
    "cobrarMulta": false,
    "percentualMulta": 2.0,
    "cobrarJuros": false,
    "percentualJurosDia": 0.033,
    "diasTolerancia": 0,
    "aplicarMultaUnica": true,
    "aplicarJurosAoDia": true
  },
  "pagamentos": {
    "mercado_pago": {
      "nome": "Mercado Pago",
      "provedor": "mercado_pago",
      "tipo": "PIX",
      "ambiente": "producao",
      "chavePix": "cliente@email.com",
      "apiUrl": "",
      "clientId": "APP_USR-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "clientSecret": "",
      "token": "APP_USR-xxxxxxxxxxxxxxxxxxxxxxxx-xxxxxxxx",
      "webhookUrl": "",
      "ativo": true
    }
  },
  "cobranca": {
    "whatsapp": {
      "nome": "WhatsApp",
      "tipo": "whatsapp",
      "apiUrl": "",
      "token": "",
      "remetente": "",
      "templateMensagem": "Olá {{cliente}}, sua parcela de R$ {{valor}} vence em {{vencimento}}.",
      "ativo": false
    },
    "email": {
      "nome": "E-mail",
      "tipo": "email",
      "apiUrl": "",
      "token": "",
      "remetente": "",
      "emailRemetente": "",
      "templateMensagem": "",
      "ativo": false
    },
    "sms": {
      "nome": "SMS",
      "tipo": "sms",
      "apiUrl": "",
      "token": "",
      "remetente": "",
      "templateMensagem": "",
      "ativo": false
    }
  },
  "regrasAutomaticas": {
    "limiteCreditoPadrao": 0,
    "diaVencimentoPadrao": 15,
    "bloquearAutomaticamente": false,
    "notificarVencimento": false,
    "diasParaNotificar": 3
  },
  "updatedAt": Timestamp("2026-06-27T12:00:00Z")
}
```

---

## 10. Arquitetura de Chamadas

### 10.1 Mecanismo de Chamada

O painel web (Flutter) chama as Cloud Functions através da função `callFirebaseFunctionSafe` em `firebase_functions_config.dart`.

**Mobile/Desktop:**
```dart
final functions = region == 'southamerica-east1'
  ? appFirebaseFunctionsSouth   // instância southamerica-east1
  : appFirebaseFunctions;        // instância us-central1
final callable = functions.httpsCallable(functionName);
return await callable.call(parameters);
```

**Web:**
```dart
final uri = Uri.parse('https://$region-depertin-f940f.cloudfunctions.net/$functionName');
final headers = {
  'Content-Type': 'application/json',
  'Authorization': 'Bearer ${user.getIdToken()}' // se logado
};
final response = await http.post(uri, headers: headers, body: jsonEncode({'data': parameters}));
```

### 10.2 Regiões

| Módulo | Região | Instância |
|--------|--------|-----------|
| Marketplace/Delivery (funções antigas) | `us-central1` | `appFirebaseFunctions` |
| **Gestão Comercial** | **`southamerica-east1`** | **`appFirebaseFunctionsSouth`** |

### 10.3 Parâmetro `region` no frontend

```dart
// Chamando função do Gestão Comercial (southamerica-east1):
await callFirebaseFunctionSafe(
  'gestaoComercialCriarPagamentoPix',
  region: 'southamerica-east1',       // ← obrigatório para GC
  parameters: { ... }
);

// Chamando função do marketplace (us-central1) — region é opcional (default):
await callFirebaseFunctionSafe(
  'validarCupom',
  parameters: { ... }
  // region: 'us-central1'  ← implícito
);
```

### 10.4 Mapeamento de Chamadas (Frontend → Functions)

| Tela | Função Chamada | Região |
|------|---------------|--------|
| PDV (criar PIX) | `gestaoComercialCriarPagamentoPix` | southamerica-east1 |
| PDV (verificar status) | `gestaoComercialConsultarStatusPix` | southamerica-east1 |
| Configurações (testar MP) | `gestaoComercialTestarConexaoMercadoPago` | southamerica-east1 |
| PDV (abrir caixa) | `gestaoComercialAbrirCaixa` | southamerica-east1 |
| PDV (fechar caixa) | `gestaoComercialFecharCaixa` | southamerica-east1 |
| PDV (receber manual) | `gestaoComercialReceberPagamento` | southamerica-east1 |
| Crédito (conceder) | `gestaoComercialConcederCredito` | southamerica-east1 |
| Pendências (consultar) | `gestaoComercialConsultarPendencias` | southamerica-east1 |
| Histórico (vendas) | `gestaoComercialHistoricoVendas` | southamerica-east1 |
| Relatório | `gestaoComercialRelatorio` | southamerica-east1 |
| Financeiro cliente | `gestaoComercialFinanceiroCliente` | southamerica-east1 |
| Parcelas (consultar) | `gestaoComercialConsultarParcelas` | southamerica-east1 |
| E-mail (salvar config) | `gestaoComercialEmailSalvarConfig` | southamerica-east1 |
| E-mail (testar SMTP) | `gestaoComercialEmailTestarSmtp` | southamerica-east1 |
| E-mail (testar API) | `gestaoComercialEmailTestarApi` | southamerica-east1 |
| E-mail (enviar teste) | `gestaoComercialEmailEnviarTeste` | southamerica-east1 |
| E-mail (salvar template) | `gestaoComercialEmailSalvarTemplate` | southamerica-east1 |
| E-mail (teste template) | `gestaoComercialEmailEnviarTemplateTeste` | southamerica-east1 |
| E-mail (histórico) | `gestaoComercialEmailListarHistorico` | southamerica-east1 |
| Webhook MP | `gestaoComercialWebhookMercadoPago` | southamerica-east1 |

---

## 11. Glossário

| Termo | Definição |
|-------|-----------|
| **PDV** | Ponto de Venda — sistema de vendas no balcão |
| **PIX** | Meio de pagamento instantâneo brasileiro, processado via Mercado Pago |
| **QR Code** | Código bidimensional para pagamento PIX |
| **Copia-e-cola** | Chave PIX em texto para copiar e pagar no app do banco |
| **Access Token** | Token de autenticação da API do Mercado Pago |
| **Public Key** | Chave pública do Mercado Pago (identificação da aplicação) |
| **Crediário** | Sistema de venda parcelada com crédito próprio da loja |
| **Caixa** | Controle de abertura e fechamento diário do PDV |
| **Pendência** | Parcela ou valor em atraso |
| **Recebimento** | Confirmação de pagamento recebido |
| **Idempotência** | Garantia de que uma operação só produz efeito uma vez, mesmo se chamada múltiplas vezes |
| **Webhook** | Callback HTTP enviado pelo Mercado Pago quando há mudança no status do pagamento |
| **Gen2** | Geração 2 das Cloud Functions (baseadas em Cloud Run) |
| **southamerica-east1** | Região da Google Cloud em São Paulo, Brasil |
| **E-mail transacional** | Módulo por loja: SMTP/API, templates em blocos, histórico de envios |
| **GC_EMAIL_CONFIG_SECRET** | Chave server-side para criptografar senhas SMTP e API Keys (obrigatória em produção) |

---

## 12. E-mail Transacional

Modal em **Configurações Comerciais → Envio de Cobrança → E-mail → Configurar**.

| Aba | Conteúdo |
|-----|----------|
| **Configuração** | SMTP vs API, teste de conexão, e-mail de teste, avançado, status |
| **Templates** | 16 templates, editor por blocos, preview, automação D±30 |
| **Histórico** | Envios por loja com status e detalhes técnicos |

**Backend:** `depertin_cliente/functions/gestao_comercial_email.js`

**Firestore:**

- Config estendida: `gestao_comercial_configuracoes/{lojaId}.cobranca.email.emailTransacional`
- Templates: `gestao_comercial_email_templates/{lojaId}/templates/{slug}`
- Histórico: `gestao_comercial_email_historico/{lojaId}/envios/{id}` (write só Admin SDK)

**Segurança:** senhas e API Keys **nunca** em texto puro — criptografia AES-256-GCM com `GC_EMAIL_CONFIG_SECRET`.

**Arquivo de exemplo:** `depertin_cliente/functions/env.gestao_comercial_email.example`

---

## 13. Checklist produção

Antes de publicar o painel ou go-live do módulo, seguir:

**[docs/GESTAO_COMERCIAL_CHECKLIST_PRODUCAO.md](./GESTAO_COMERCIAL_CHECKLIST_PRODUCAO.md)**

Resumo mínimo (e-mail):

1. Gerar e definir `GC_EMAIL_CONFIG_SECRET` em `functions/.env`
2. Redeploy das 8 callables `gestaoComercialEmail*`
3. Smoke test: testar conexão + e-mail de teste + histórico
4. Deploy do painel web (`build_sistema.ps1`)

---

> **Documento gerado em:** 27 de junho de 2026
>
> **Arquivos de referência:**
> - `depertin_cliente/functions/gestao_comercial_email.js`
> - `depertin_cliente/functions/env.gestao_comercial_email.example`
> - `docs/GESTAO_COMERCIAL_CHECKLIST_PRODUCAO.md`
> - `depertin_cliente/functions/mercado_pago_gestao_comercial.js`
> - `depertin_web/lib/services/firebase_functions_config.dart`
> - `depertin_web/lib/screens/` (telas do módulo)
> - `depertin_web/lib/widgets/comercial/` (widgets compartilhados)
> - `depertin_web/lib/services/` (services Dart)
> - `depertin_web/lib/navigation/painel_routes.dart`
> - `depertin_web/lib/widgets/sidebar_menu.dart`
