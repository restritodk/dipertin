# Módulo Fiscal — NF-e (Nota Fiscal Eletrônica)

> **Data:** julho/2026 (v1.1.0 — integração real com API externa)  
> **Stack:** Flutter Web + Firebase (Firestore, Functions)  
> **Painel:** `depertin_web/` — Módulo do Lojista

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Arquitetura do Módulo](#2-arquitetura-do-módulo)
3. [Modelos de Dados](#3-modelos-de-dados)
4. [Camada de Provedores Fiscais](#4-camada-de-provedores-fiscais)
5. [Validação Fiscal](#5-validação-fiscal)
6. [Geração de XML](#6-geração-de-xml)
7. [Serviço de Emissão](#7-serviço-de-emissão)
8. [Cancelamento de NF-e](#8-cancelamento-de-nf-e)
9. [Carta de Correção Eletrônica (CC-e)](#9-carta-de-correção-eletrônica-cc-e)
10. [Inutilização de Numeração](#10-inutilização-de-numeração)
11. [Contingência](#11-contingência)
12. [Controle de Séries e Numeração](#12-controle-de-séries-e-numeração)
13. [Envio de E-mail Transacional](#13-envio-de-e-mail-transacional)
14. [Download de XML e DANFE](#14-download-de-xml-e-danfe)
15. [Tradução de Erros (SEFAZ/API)](#15-tradução-de-erros-sefazapi)
16. [Criptografia de Dados Sensíveis](#16-criptografia-de-dados-sensíveis)
17. [Auditoria e Segurança](#17-auditoria-e-segurança)
18. [Painel Fiscal do Lojista (Tela)](#18-painel-fiscal-do-lojista-tela)
19. [Modal de Emissão com Animação](#19-modal-de-emissão-com-animação)
20. [Integração com Assinaturas](#20-integração-com-assinaturas)
21. [Estrutura de Arquivos](#21-estrutura-de-arquivos)
22. [Fluxo Completo de Emissão](#22-fluxo-completo-de-emissão)
23. [Camada HTTP Padronizada](#23-camada-http-padronizada)
24. [Certificado Digital A1](#24-certificado-digital-a1)
25. [Dados Fiscais da Empresa](#25-dados-fiscais-da-empresa)
26. [Cloud Functions (Webhook + Proxy)](#26-cloud-functions-webhook--proxy)
27. [Painel Admin Fiscal](#27-painel-admin-fiscal)
28. [Dependências](#28-dependências)

---

## 1. Visão Geral

O **Módulo Fiscal** permite que lojistas emitam NF-e (e futuramente NFC-e/NFS-e) diretamente pelo painel web DiPertin, sem sair da plataforma. O módulo foi projetado com os seguintes princípios:

- **Segurança em camadas**: certificados, tokens e senhas são criptografados com AES-256-GCM; o lojista nunca vê dados sensíveis
- **Provider-agnostic**: suporte a múltiplos provedores fiscais (Focus NFe, Enotas, PlugNotas, Nuvem Fiscal, WebmaniaBR, API Customizada) com **chamadas HTTP reais**
- **Validação completa antes da emissão**: CFOP, NCM, CST/CSOSN, CEST, CNPJ, IE, regime tributário, valores
- **Limite mensal por lojista**: controle de quantas notas podem ser emitidas por mês
- **Ambiente de homologação/produção**: suporte a sandbox para testes
- **Auditoria total**: todas as operações são registradas em `audit_logs`
- **UX Premium**: modais com animação, feedback em tempo real, mensagens de erro amigáveis
- **Webhook funcional**: atualização automática de status via Cloud Function
- **Certificado Digital A1**: upload seguro, validação e bloqueio de emissão se vencido

---

## 2. Arquitetura do Módulo

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     Painel Web (Flutter)                                        │
│                                                                                 │
│  ┌─────────────────┐  ┌────────────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │ LojistaModulo    │  │ FiscalEmissaoModal │  │ AdminFiscal  │  │ Modais    │  │
│  │ FiscalScreen     │  │ (Pré-vis + Emissão)│  │ Screen       │  │ Ação     │  │
│  │ (Dashboard +     │  └────────┬───────────┘  │ (Admin/Staff)│  │(Cancel/   │  │
│  │  Tabela Notas)   │           │              └──────┬───────┘  │ CCe/      │  │
│  └────────┬─────────┘           │                      │          │ Inutiliz) │  │
│           │                     │                      │          └─────┬─────┘  │
│  ┌────────▼─────────────────────▼──────────────────────▼──────────────▼──────┐ │
│  │                   FiscalEmissaoService (Orquestrador)                       │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐  │ │
│  │  │Validator │ │XmlBuilder│ │Provider  │ │CryptoUtil│ │ProviderHttp    │  │ │
│  │  │(valida   │ │(gera XML)│ │Service   │ │AES-256-  │ │(HTTP real c/   │  │ │
│  │  │ payload) │ │          │ │(resolve  │ │GCM       │ │ timeout/retry) │  │ │
│  │  └──────────┘ └──────────┘ │ provider)│ └──────────┘ └────────────────┘  │ │
│  │                            └──────────┘                                    │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│           │                                                                    │
│  ┌────────▼──────────────────────────────────────────────────────────────────┐ │
│  │                    Firestore (Coleções)                                    │ │
│  │  fiscal_documents / store_fiscal_settings /                               │ │
│  │  fiscal_integrations / fiscal_series / audit_logs /                       │ │
│  │  lojista_integracao / fiscal_audit_logs                                   │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
                          │                           │
          ┌───────────────▼───────┐     ┌─────────────▼──────────────┐
          │  API Externa          │     │  Cloud Functions           │
          │  (Focus / Enotas /    │     │  ┌─────────────────────┐  │
          │   PlugNotas / Nuvem   │     │  │ fiscal_webhook.js   │  │
          │   Fiscal / Webmania / │     │  │ → Recebe POST       │  │
          │   Custom)             │     │  │ → Valida origem     │  │
          │                       │     │  │ → Atualiza status   │  │
          │   → SEFAZ             │     │  └─────────────────────┘  │
          └───────────────────────┘     │  ┌─────────────────────┐  │
                                        │  │ fiscal_proxy.js     │  │
                                        │  │ → Proxy OAuth 1.0a │  │
                                        │  │ → WebmaniaBR        │  │
                                        │  └─────────────────────┘  │
                                        └───────────────────────────┘
```

### Fluxo de dados (visão macro)

1. **Usuário** → interage com `LojistaModuloFiscalScreen` (painel do lojista) ou `AdminFiscalScreen` (painel admin)
2. **Painel** → chama `FiscalEmissaoService.emitirNotaCompleta()`
3. **Service** → valida → busca config → resolve provider → verifica limite → reserva numeração → gera XML → descriptografa credenciais → envia ao provider via HTTP real
4. **Provider** → chama API externa via `FiscalProviderHttp` → retorna `FiscalProviderResult`
5. **Service** → persiste documento → atualiza contagem → registra auditoria
6. **Painel** → exibe resultado com animação
7. **Webhook** → API externa notifica `fiscal_webhook.js` → atualiza status automaticamente

---

## 3. Modelos de Dados

### 3.1 `FiscalDocumentModel`

Arquivo: `lib/models/fiscal_document_model.dart`

Representa um documento fiscal emitido (NF-e, NFC-e, NFS-e).

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `String` | ID do documento no Firestore |
| `storeId` | `String` | ID da loja |
| `saleId` | `String?` | ID da venda associada |
| `customerId` | `String?` | ID do cliente |
| `documentType` | `String` | Tipo: `nfe`, `nfce`, `nfse` |
| `provider` | `String` | ID do provedor usado |
| `status` | `String` | Status atual (ver `StatusFiscal`) |
| `accessKey` | `String?` | Chave de acesso (44 dígitos) |
| `protocol` | `String?` | Protocolo de autorização |
| `number` | `String?` | Número da NF-e |
| `series` | `String?` | Série fiscal |
| `xmlUrl` | `String?` | URL do XML autorizado |
| `pdfUrl` | `String?` | URL do DANFE PDF |
| `xmlCancelamentoUrl` | `String?` | URL do XML de cancelamento |
| `pdfCancelamentoUrl` | `String?` | URL do PDF de cancelamento |
| `rejectionReason` | `String?` | Motivo da rejeição |
| `rejectionCode` | `String?` | Código de rejeição SEFAZ |
| `providerResponse` | `String?` | Resposta completa do provedor |
| `justificativaCancelamento` | `String?` | Justificativa do cancelamento |
| `justificativaInutilizacao` | `String?` | Justificativa da inutilização |
| `cartasCorrecao` | `List<CartaCorrecaoEvento>` | Histórico de CC-e |
| `emContingencia` | `bool` | Se foi emitida em contingência |
| `motivoContingencia` | `String?` | Motivo da contingência |
| `resolvidoContingenciaEm` | `Timestamp?` | Quando a contingência foi resolvida |
| `issuedAt` | `Timestamp?` | Data de emissão |
| `cancelledAt` | `Timestamp?` | Data de cancelamento |
| `createdAt` | `Timestamp?` | Data de criação |
| `updatedAt` | `Timestamp?` | Data da última atualização |

**Getters:**
- `isAutorizada`, `isRejeitada`, `isCancelada`, `isProcessando`, `isContingencia`
- `podeCancelar` → autorizada E não cancelada
- `podeCorrigir` → autorizada E não cancelada E `< 20 CC-e`
- `totalCartasCorrecao` → quantidade de CC-e emitidas

### 3.2 `StatusFiscal` (constantes)

```dart
class StatusFiscal {
  static const String processando = 'processando';
  static const String autorizada = 'autorizada';
  static const String rejeitada = 'rejeitada';
  static const String cancelada = 'cancelada';
  static const String cancelamentoHomologado = 'cancelamento_homologado';
  static const String contingencia = 'contingencia';
  static const String contingenciaResolvida = 'contingencia_resolvida';
  static const String ccEnviada = 'cc_e_enviada';
  static const String numeracaoInutilizada = 'numeracao_inutilizada';
}
```

### 3.3 `CartaCorrecaoEvento`

| Campo | Tipo | Descrição |
|---|---|---|
| `sequencia` | `int` | Número sequencial da CC-e |
| `textoCorrecao` | `String` | Texto da correção |
| `protocolo` | `String?` | Protocolo SEFAZ |
| `xmlUrl` | `String?` | URL do XML da CC-e |
| `chaveAcesso` | `String?` | Chave de acesso |
| `enviadaEm` | `Timestamp?` | Data de envio |

### 3.4 `StoreFiscalSettingsModel`

Arquivo: `lib/models/store_fiscal_settings_model.dart`

Configuração fiscal da loja no Firestore (`store_fiscal_settings`).

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `String` | ID do documento |
| `storeId` | `String` | ID da loja |
| `integrationId` | `String` | ID da integração (provedor) |
| `enableNfe` | `bool` | NF-e ativada |
| `enableNfce` | `bool` | NFC-e ativada |
| `enableNfse` | `bool` | NFS-e ativada |
| `companyTaxData` | `Map<String, dynamic>?` | Dados fiscais da empresa (CNPJ, IE, CRT, endereço) |
| `certificateDataEncrypted` | `String?` | Certificado A1 criptografado (AES-256-GCM) |
| `certificatePasswordEncrypted` | `String?` | Senha do certificado criptografada |
| `certificateExpiresAt` | `Timestamp?` | Data de validade do certificado |
| `certificateInfo` | `Map<String, dynamic>?` | Metadados do certificado (emissor, CNPJ, etc.) |
| `nfeSettings` | `Map<String, dynamic>?` | Configurações NF-e (série, ambiente) |
| `nfceSettings` | `Map<String, dynamic>?` | Configurações NFC-e |
| `nfseSettings` | `Map<String, dynamic>?` | Configurações NFS-e |
| `webhookUrl` | `String?` | URL de webhook para atualizações |
| `status` | `String` | `active`, `inactive`, `pending` |
| `createdAt` | `Timestamp?` | Data de criação |
| `updatedAt` | `Timestamp?` | Data da última atualização |

### 3.5 `FiscalIntegrationModel`

Arquivo: `lib/models/fiscal_integration_model.dart`

Configuração do provedor fiscal (`fiscal_integrations`). Contém as credenciais criptografadas do provedor (API key, token, etc.).

### 3.6 `LojistaIntegracaoModel`

Arquivo: `lib/models/lojista_integracao_model.dart`

Controle de integração e limite mensal por lojista (`lojista_integracao`).

| Campo | Tipo | Descrição |
|---|---|---|
| `storeId` | `String` | ID da loja |
| `limiteMensal` | `int` | Limite máximo de emissões por mês |
| `notasEmitidas` | `int` | Notas emitidas no mês atual |
| `notasRestantes` | `int` | Notas restantes (getter: `limiteMensal - notasEmitidas`) |
| `mesReferencia` | `String` | Mês de referência no formato `YYYY-MM` |
| `ativa` | `bool` | Se a integração está ativa |

---

## 4. Camada de Provedores Fiscais

### 4.1 `FiscalProviderResult`

Arquivo: `lib/services/fiscal/fiscal_provider.dart`

Classe base de retorno de todos os provedores.

| Campo | Tipo | Descrição |
|---|---|---|
| `sucesso` | `bool` | Se a operação foi bem-sucedida |
| `chaveAcesso` | `String?` | Chave de acesso da NF-e |
| `protocolo` | `String?` | Protocolo de autorização |
| `numero` | `String?` | Número da NF-e |
| `serie` | `String?` | Série fiscal |
| `xmlUrl` | `String?` | URL do XML |
| `pdfUrl` | `String?` | URL do DANFE |
| `erro` | `String?` | Mensagem de erro |
| `mensagem` | `String?` | Mensagem de sucesso |
| `statusEnvio` | `String?` | Status do envio |
| `providerResponse` | `String?` | Resposta completa do provedor |
| `codigoRejeicao` | `String?` | Código de rejeição SEFAZ |

### 4.2 `FiscalProviderService`

Arquivo: `lib/services/fiscal/fiscal_provider_service.dart`

Responsável por resolver e instanciar o provedor correto com base nos dados da integração.

**Métodos públicos:**
- `resolverDeIntegracao(Map<String, dynamic> integrationDoc)` → retorna instância do provedor
- `extrairConfig(Map<String, dynamic> integrationDoc)` → extrai configuração do documento

### 4.3 Provedores Suportados

| Provedor | Classe | `providerId` | Arquivo |
|---|---|---|---|
| **Focus NFe** | `FocusNfeProvider` | `focus_nfe` | `providers/focus_nfe_provider.dart` |
| **Enotas** | `EnotasProvider` | `enotas` | `providers/enotas_provider.dart` |
| **PlugNotas** | `PlugNotasProvider` | `plug_notas` | `providers/plug_notas_provider.dart` |
| **Nuvem Fiscal** | `NuvemFiscalProvider` | `nuvem_fiscal` | `providers/nuvem_fiscal_provider.dart` |
| **WebmaniaBR** | `WebmaniaProvider` | `webmaniabr` | `providers/webmania_provider.dart` |
| **Custom / Genérico** | `CustomFiscalProvider` | `custom` | `providers/custom_fiscal_provider.dart` |

Cada provider implementa a interface `FiscalProvider`:

```dart
abstract class FiscalProvider {
  Future<FiscalProviderResult> emitirNota(FiscalPayload payload, Map<String, dynamic> config);
  Future<FiscalProviderResult> cancelarNota({
    required String chaveAcesso, required String protocolo, required String justificativa,
    Map<String, dynamic>? config,
  });
  Future<FiscalProviderResult> enviarCartaCorrecao({
    required String chaveAcesso, required String textoCorrecao, required int sequencia,
    Map<String, dynamic>? config,
  });
  Future<FiscalProviderResult> inutilizarNumeracao({
    required String cnpj, required String uf, required String serie,
    required int numeroInicial, required int numeroFinal, required String justificativa,
    Map<String, dynamic>? config,
  });
  Future<FiscalProviderResult> testarConexao(Map<String, dynamic> config);
  String get providerId;
}
```

### 4.4 Integração HTTP Real por Provedor

Todos os provedores agora fazem **chamadas HTTP reais** via `FiscalProviderHttp` (exceto WebmaniaBR, que usa Cloud Function proxy para OAuth 1.0a).

| Provedor | Autenticação | Endpoints Implementados |
|---|---|---|
| **Focus NFe** | Bearer Token (HTTP Header) | `POST /v2/nfe` (emissão), `POST /v2/nfe/{chave}/cancelamento`, `PUT /v2/nfe/{chave}/carta-correcao`, `POST /v2/nfe/inutilizacao`, `GET /v2/nfe/{chave}` (status) |
| **Enotas** | API Key (HTTP Header) | `POST /v1/empresas/{empresaId}/nf-e` (emissão), `DELETE /v1/empresas/{empresaId}/nf-e/{nfeId}` (cancelamento). CC-e e inutilização não suportados publicamente |
| **PlugNotas** | API Key (HTTP Header) | `POST /nfe` (emissão), `POST /nfe/{id}/cancelar`, `POST /nfe/{id}/carta-correcao`, `POST /nfe/inutilizar`, `GET /nfe/{id}` |
| **Nuvem Fiscal** | OAuth 2.0 Client Credentials (token caching) | `POST /oauth/token` (token), `POST /nfe` (emissão), `POST /nfe/{id}/cancelamento`, `POST /nfe/{id}/carta-correcao`, `GET /nfe/{id}` |
| **WebmaniaBR** | OAuth 1.0a (via Cloud Function) | Proxy via `fiscal_proxy.js`: emissão, cancelamento, CC-e, inutilização, testar conexão |
| **Custom** | Bearer, Basic, API Key, OAuth2, None | Endpoints configuráveis via `store_fiscal_settings`. Emissão, cancelamento, CC-e e inutilização quando endpoints são fornecidos |

---

## 5. Validação Fiscal

### 5.1 `FiscalValidator`

Arquivo: `lib/services/fiscal/fiscal_validator.dart`

Valida todos os dados fiscais antes da emissão.

**Método principal:**
```dart
static ValidationResult validarParaEmissao(FiscalPayload payload);
```

**Validações realizadas:**

| Categoria | Campos validados | Regras |
|---|---|---|
| **Emitente** | CNPJ, IE, razão social, endereço | CNPJ obrigatório e válido (dígitos verificadores), IE obrigatória, endereço completo |
| **Destinatário** | Nome, CPF/CNPJ | Nome obrigatório, CPF/CNPJ válido |
| **Itens** | NCM, CFOP, CST, quantidade, valor | NCM deve ter 8 dígitos, CFOP deve ser numérico, CST obrigatório, quantidade > 0, valor > 0 |
| **Totais** | Base de cálculo ICMS, valor total | Base ICMS não negativa, valor total > 0 |
| **Pagamento** | Forma de pagamento, valor | Forma de pagamento obrigatória, valor pago >= 0 |
| **Natureza operação** | Descrição | Não pode ser vazia |
| **Regime tributário** | CRT do emitente | Deve ser válido (1=Simples Nacional, 2=Simples Excesso, 3=Regime Normal) |

**Retorno:**
```dart
class ValidationResult {
  final bool valido;
  final List<ValidationError> erros;
  final List<ValidationWarning> avisos;
}

class ValidationError {
  final String campo;    // ex: "itens[0].ncm"
  final String mensagem; // ex: "NCM deve ter 8 dígitos"
  final String? codigo;  // código do erro
}

class ValidationWarning {
  final String campo;
  final String mensagem;
}
```

---

## 6. Geração de XML

### 6.1 `FiscalXmlBuilder`

Arquivo: `lib/services/fiscal/fiscal_xml_builder.dart`

Responsável por gerar o XML completo da NF-e no padrão da SEFAZ (Schema XSD).

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `gerarXmlNFeApenas({required FiscalPayload payload, required bool homologacao, required bool emitirNfce}) → String` | Gera o XML completo da NF-e/NFC-e |
| `gerarXmlCancelamento({required String chaveAcesso, required String justificativa, required String protocolo}) → String` | Gera o XML de cancelamento (pedido) |
| `gerarXmlCartaCorrecao({required String chaveAcesso, required String textoCorrecao, required int sequencia}) → String` | Gera o XML da CC-e |
| `gerarXmlInutilizacao({required String cnpj, required String uf, required String serie, required int numeroInicial, required int numeroFinal, required String justificativa}) → String` | Gera o XML de inutilização |

**Estrutura do XML NF-e gerado:**
- Tag raiz `<nfeProc>` ou `<NFe>` com `xmlns="http://www.portalfiscal.inf.br/nfe"`
- InfNFe com:
  - `ide`: dados da NF-e (UF, CNPJ, natOp, modelo, série, nNF, dEmi, tpAmb, tpNF, tpEmis, cNF, cDV, tpImp, tpAmb, finNFe, procEmi, verProc)
  - `emit`: dados do emitente (CNPJ, xNome, xFant, IE, CRT, EnderEmit)
  - `dest`: dados do destinatário (CNPJ/CPF, xNome, EnderDest)
  - `det`: produtos (nItem, prod, imposto)
  - `total`: totais (ICMSTot, prod, frete, desconto, total NF)
  - `pag`: pagamento (detPagamentos)
  - `infAdic`: informações adicionais
- Assinatura digital (`<Signature>`)

---

## 7. Serviço de Emissão

### 7.1 `FiscalEmissaoService`

Arquivo: `lib/services/fiscal/fiscal_emissao_service.dart`

Singleton que orquestra todo o fluxo de emissão.

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `emitirNotaCompleta({lojaId, payload, homologacao, emitirNfce})` | Fluxo completo: valida → config → provider → limite → numeração → XML → emissão → persistência → auditoria |
| `emitirNotaAssinatura({cliente, tipoDocumento, valorPersonalizado})` | Emite NF-e para cobrança de assinatura recorrente |
| `cancelarNota({storeId, fiscalDocumentId, accessKey, protocol, justificativa})` | Cancela NF-e autorizada |
| `enviarCartaCorrecao({storeId, fiscalDocumentId, textoCorrecao})` | Envia CC-e |
| `inutilizarNumeracao({storeId, serie, numeroInicial, numeroFinal, justificativa})` | Inutiliza faixa de numeração |
| `validarDados(FiscalPayload) → ValidationResult` | Valida payload (delega ao FiscalValidator) |

**Fluxo de `emitirNotaCompleta`:**

```
1. Validar payload (FiscalValidator.validarParaEmissao)
   ↓ se inválido → retorna erro com lista de erros
2. Obter configuração da loja (store_fiscal_settings)
   ↓ se não encontrada → retorna erro
3. Buscar integração (fiscal_integrations)
   ↓ se não encontrada → retorna erro
4. Resolver provedor (FiscalProviderService)
   ↓ se não resolvido → retorna erro
5. Verificar limite mensal (LojistaIntegracaoService)
   ↓ se esgotado → retorna erro
6. Verificar certificado digital (se necessário) → FiscalCertificadoService
   ↓ se vencido → retorna erro
7. Verificar contingência (FiscalContingenciaService)
8. Reservar numeração (FiscalSeriesService) - se não em contingência
9. Gerar XML (FiscalXmlBuilder.gerarXmlNFeApenas)
10. Descriptografar credenciais (FiscalCryptoUtil)
11. Emitir no provedor via HTTP real (provider.emitirNota → FiscalProviderHttp)
    ↓
12. Se sucesso:
    - Confirmar numeração
    - Criar FiscalDocumentModel
    - Persistir (FiscalIntegrationsService.registrarDocumento)
    - Atualizar contagem mensal
    - Registrar auditoria
13. Se falha:
    - Criar FiscalDocumentModel com status rejeitada
    - Registrar erro
    - Registrar auditoria
14. Retornar FiscalEmissaoResult
```

### 7.2 `FiscalEmissaoResult`

| Campo | Tipo | Descrição |
|---|---|---|
| `sucesso` | `bool` | Se a emissão foi bem-sucedida |
| `chaveAcesso` | `String?` | Chave de acesso |
| `protocolo` | `String?` | Protocolo |
| `numero` | `String?` | Número da NF-e |
| `serie` | `String?` | Série |
| `xmlGerado` | `String?` | XML gerado |
| `xmlUrl` | `String?` | URL do XML autorizado |
| `pdfUrl` | `String?` | URL do DANFE |
| `statusFinal` | `String?` | Status final |
| `mensagem` | `String?` | Mensagem amigável |
| `erro` | `String?` | Mensagem de erro |
| `errosValidacao` | `List<ValidationError>` | Erros de validação |
| `avisosValidacao` | `List<ValidationWarning>` | Avisos de validação |
| `documentoId` | `String?` | ID do documento no Firestore |
| `providerResponse` | `String?` | Resposta completa do provedor |
| `codigoRejeicao` | `String?` | Código de rejeição |

---

## 8. Cancelamento de NF-e

### 8.1 `FiscalCancelamentoService`

Arquivo: `lib/services/fiscal/fiscal_cancelamento_service.dart`

**Constantes:**
- `prazoMaximoHoras = 24` (prazo legal para cancelamento)

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `cancelarNota({storeId, fiscalDocumentId, justificativa, accessKey, protocol})` | Executa cancelamento no provedor via HTTP real |
| `mensagemErroAmigavel(FiscalProviderResult result)` | Retorna mensagem traduzida |

**Regras:**
- Só pode cancelar dentro de **24 horas** após a autorização SEFAZ
- Justificativa é obrigatória e deve ter no mínimo 10 caracteres
- Ao cancelar, gera XML de cancelamento e DANFE de cancelamento
- Atualiza status para `cancelada` (ou `cancelamento_homologado`)
- Registra auditoria

### 8.2 Modal de Cancelamento (`_CancelamentoDialog`)

Widget premium com:
- Ícone de bloqueio vermelho
- Informação sobre o prazo legal de 24h
- Campo de justificativa (max 500 caracteres)
- Validação de mínimo 10 caracteres
- Botão "Confirmar Cancelamento" com loading
- Feedback de erro/sucesso via `FiscalErroTranslator`

---

## 9. Carta de Correção Eletrônica (CC-e)

### 9.1 `FiscalCartaCorrecaoService`

Arquivo: `lib/services/fiscal/fiscal_carta_correcao_service.dart`

**Constantes:**
- `maxCartasPorNfe = 20` (limite legal de CC-e por NF-e)
- `maxTextoCorrecao = 1000` (limite de caracteres)

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `enviarCartaCorrecao({storeId, fiscalDocumentId, textoCorrecao})` | Envia CC-e ao provedor via HTTP real |
| `gerarTextoPadrao(campoCorrigido, valorAntigo, valorNovo)` | Gera texto padronizado para correção |
| `campoPodeSerCorrigido(String campo)` | Verifica se campo pode ser corrigido |
| `campoProibido(String campo)` | Verifica se campo é proibido |

### 9.2 Modal de CC-e (`_CartaCorrecaoDialog`)

Widget premium com:
- Contador de caracteres (max 1000)
- Informação do limite de 20 CC-e por NF-e
- Campo de texto da correção
- Botão "Enviar CC-e" com loading

---

## 10. Inutilização de Numeração

### 10.1 `FiscalInutilizacaoService`

Arquivo: `lib/services/fiscal/fiscal_inutilizacao_service.dart`

**Constantes:**
- `maxFaixaPorVez = 999` (máximo de números por inutilização)

**Método público:**
```dart
static Future<FiscalProviderResult> inutilizar({
  required String storeId,
  required String serie,
  required int numeroInicial,
  required int numeroFinal,
  required String justificativa,
});
```

### 10.2 Modal de Inutilização (`_InutilizacaoDialog`)

Widget premium com:
- Campo de número inicial e final
- Validação: número final >= número inicial
- Validação: faixa <= 999 números
- Campo de justificativa
- Botão "Inutilizar Numeração" com loading

---

## 11. Contingência

### 11.1 `FiscalContingenciaService`

Arquivo: `lib/services/fiscal/fiscal_contingencia_service.dart`

Gerencia o estado de contingência (quando a SEFAZ ou API está indisponível).

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `estaEmContingencia(String storeId) → Future<bool>` | Verifica se a loja está em contingência |
| `ativarContingencia(String storeId, {String? motivo})` | Ativa contingência |
| `resolverContingencia(String storeId)` | Resolve contingência (volta ao normal) |
| `streamEstado(String storeId) → Stream<EstadoContingencia>` | Stream de atualizações do estado |

**Estado de contingência:**
- `EstadoContingencia.emContingencia` (bool)
- `EstadoContingencia.motivo` (String?)
- `EstadoContingencia.ativadaEm` (Timestamp?)
- `EstadoContingencia.resolvidaEm` (Timestamp?)

**Comportamento:**
- Notas emitidas em contingência recebem status `contingencia`
- Quando a contingência é resolvida, as notas podem ser reenviadas
- Badge "Contingência" aparece no painel do lojista
- O modal de contingência exibe motivo e instruções

---

## 12. Controle de Séries e Numeração

### 12.1 `FiscalSeriesService`

Arquivo: `lib/services/fiscal/fiscal_series_service.dart`

Gerencia a numeração sequencial das NF-e por loja/série.

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `reservarProximoNumero({storeId, documentType, serie, ambiente}) → Future<FiscalSerie>` | Reserva o próximo número disponível (atômico no Firestore) |
| `confirmarNumeracao({storeId, numero, documentType, serie})` | Confirma o número após emissão bem-sucedida |
| `liberarNumeracao({storeId, numero, documentType, serie})` | Libera o número se a emissão falhou |
| `streamSerie({storeId}) → Stream<FiscalSerie?>` | Stream da série ativa |

### 12.2 `FiscalSerie`

Arquivo: `lib/services/fiscal/fiscal_serie_model.dart`

| Campo | Tipo | Descrição |
|---|---|---|
| `serie` | `String` | Número da série |
| `proximoNumero` | `int` | Próximo número disponível |
| `documentType` | `String` | Tipo de documento (`nfe`, `nfce`) |
| `ambiente` | `String` | `production` ou `sandbox` |

**Regras:**
- A numeração é separada por loja (nunca se mistura entre lojistas)
- Separada por tipo de documento (NF-e vs NFC-e)
- Separada por ambiente (produção vs homologação)
- A série pode ser configurada por loja/CNPJ

---

## 13. Envio de E-mail Transacional

### 13.1 `FiscalEmailService`

Arquivo: `lib/services/fiscal/fiscal_email_service.dart`

Responsável por enviar DANFE/XML por e-mail ao cliente.

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `enviarNotaPorEmail({storeId, fiscalDocumentId, destinatarios})` | Envia NF-e (DANFE + XML) para o(s) destinatário(s) |
| `enviarNotaPorEmailComCopia({storeId, fiscalDocumentId, destinatarios, copias})` | Envia com cópia para múltiplos endereços |
| `verificarConfiguracaoEmail({storeId}) → Future<bool>` | Verifica se o e-mail transacional está configurado |

**Template de e-mail:**
- **Assunto:** `NF-e {numero} — {razaoSocial} — Série {serie}`
- **Corpo:** Template premium com identidade DiPertin (roxo/laranja) contendo:
  - Logotipo DiPertin
  - Resumo da nota (número, série, chave de acesso, valor total)
  - Cliente e emitente
  - Link para download do DANFE
  - Link para download do XML
  - Protocolo de autorização
  - Código de verificação

---

## 14. Download de XML e DANFE

Implementado diretamente em `lojista_modulo_fiscal_screen.dart`.

**Fluxo de download:**

1. **XML:** Se `xmlUrl` existe → abre URL externa via `url_launcher`
2. **DANFE:** Se `pdfUrl` existe → abre URL externa via `url_launcher`
3. **Fallback:** Se URL falha → exibe diálogo com o link manual (`_mostrarDownloadManual`)
4. **Conteúdo inline:** Se `xml_conteudo` está presente no documento → baixa como arquivo via BLOB (`_baixarConteudoComoArquivo`)

**Segurança:** URLs são abertas em navegador externo (`LaunchMode.externalApplication`), nunca dentro do iframe do painel.

---

## 15. Tradução de Erros (SEFAZ/API)

### 15.1 `FiscalErroTranslator`

Arquivo: `lib/services/fiscal/fiscal_erro_translator.dart`

Traduz códigos de rejeição da SEFAZ e erros de API em mensagens amigáveis para o lojista.

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `traduzir(codigo, {mensagemOriginal}) → ({String titulo, String descricao})` | Traduz código de erro em mensagem amigável |
| `extrairCodigoRejeicao(String? erro) → String?` | Extrai código de rejeição de uma mensagem de erro |
| `isIndisponibilidadeSefaz(String? erro) → bool` | Verifica se o erro indica indisponibilidade da SEFAZ |
| `isErroConfiguracao(String? erro) → bool` | Verifica se o erro é de configuração |

**Exemplos de tradução (~42 erros mapeados):**

| Código | Título | Descrição amigável |
|---|---|---|
| `110` | CFOP Inválido | O CFOP informado não é válido para a operação |
| `220` | NCM Incorreto | O NCM do produto não corresponde à descrição |
| `230` | CST Incorreto | O CST informado é incompatível com o produto |
| `301` | IE do Destinatário | IE do destinatário inválida ou não informada |
| `330` | CNPJ do Emitente | CNPJ do emitente inválido ou não cadastrado |
| `334` | IE do Emitente | IE do emitente inválida ou não informada |
| `340` | CNPJ do Destinatário | CNPJ/CPF do destinatário inválido |
| `345` | IE do Destinatário | IE do destinatário é obrigatória |
| `400` | XML Mal Formado | O XML da NF-e está mal formado |
| `500` | Erro no Servidor | Erro interno no servidor da SEFAZ. Tente novamente |
| `600` | Serviço Paralisado | SEFAZ está com serviço paralisado. Ative a contingência |

---

## 16. Criptografia de Dados Sensíveis

### 16.1 `FiscalCryptoUtil`

Arquivo: `lib/services/fiscal/fiscal_crypto_util.dart`

Utilitário de criptografia para proteger dados sensíveis (API keys, tokens, certificados, senhas).

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `encrypt(String plaintext) → String` | Criptografa texto com AES-256-GCM |
| `decrypt(String ciphertext) → String` | Descriptografa texto (inclui fallback legado XOR) |
| `pareceCriptografado(String valor) → bool` | Verifica se o valor já está criptografado |
| `validarIntegridade(String encryptedText) → bool` | Valida integridade do dado criptografado |
| `ofuscar(String value) → String` | Ofusca valor para logs seguros (ex: "sk_l...yz") |
| `gerarChaveEfemera() → String` | Gera chave aleatória de 32 bytes |
| `sanitizarParaLog(Map config) → Map` | Remove dados sensíveis de mapas de config |
| `definirChaveMestra(String chave)` | Define chave mestra obtida do backend (cache 5 min) |

**Algoritmo:** AES-256-GCM (dados em repouso no Firestore ficam criptografados).

**Detalhes da implementação:**

| Componente | Detalhe |
|---|---|
| **Algoritmo** | AES-256-GCM (Galois/Counter Mode) |
| **Derivação de chave** | SHA-256 a partir da chave mestra → 32 bytes |
| **IV** | 12 bytes aleatórios (Random.secure) por operação |
| **Formato** | `DIP_AES256_v2:{iv_base64url}.{ciphertext_base64url}` |
| **Tag GCM** | Inclusa no ciphertext (pacote `encrypt`) |
| **Fallback legado** | `DIP_ENC_v1:` → XOR (para dados migrados) |
| **Pacotes** | `encrypt: ^5.0.3`, `pointycastle: ^3.9.1` |

**Regras de segurança:**
- O frontend **nunca** exibe dados sensíveis (API keys, tokens, certificados)
- Os dados são descriptografados apenas em memória durante a emissão
- O lojista configura uma vez e nunca mais vê as credenciais
- Certificado A1 (arquivo .pfx) é armazenado criptografado no Firestore
- Logs têm dados sensíveis ofuscados automaticamente

---

## 17. Auditoria e Segurança

### 17.1 `FiscalAuditService`

Arquivo: `lib/services/fiscal/fiscal_audit_service.dart`

Registra todas as operações fiscais para auditoria.

**Constantes:**
- `acaoEmissao = 'emissao'`
- `acaoCancelamento = 'cancelamento'`
- `acaoCartaCorrecao = 'carta_correcao'`
- `acaoInutilizacao = 'inutilizacao'`
- `acaoContingenciaAtivada = 'contingencia_ativada'`
- `acaoContingenciaResolvida = 'contingencia_resolvida'`
- `acaoEmail = 'email_enviado'`
- `acaoDownload = 'download'`
- `acaoConsulta = 'consulta_sefaz'`

**Método principal:**
```dart
static Future<void> registrar({
  required String lojaId,
  required String acao,
  required String descricao,
  String? documentoId,
  String? chaveAcesso,
  String? provedor,
  String? ipAddress,
  String? userAgent,
});
```

**Eventos registrados:**

| Evento | Descrição |
|---|---|
| `emissao` | NF-e emitida (com chave de acesso e número) |
| `emissao_rejeitada` | NF-e rejeitada (com código e motivo) |
| `cancelamento` | NF-e cancelada |
| `carta_correcao` | CC-e enviada |
| `inutilizacao` | Numeração inutilizada |
| `contingencia_ativada` | Contingência ativada (com motivo) |
| `contingencia_resolvida` | Contingência resolvida |
| `email_enviado` | NF-e enviada por e-mail ao cliente |
| `download` | Download de XML ou DANFE |
| `consulta_sefaz` | Consulta de status na SEFAZ |

---

## 18. Painel Fiscal do Lojista (Tela)

### 18.1 `LojistaModuloFiscalScreen`

Arquivo: `lib/screens/lojista_modulo_fiscal_screen.dart` (~7143 linhas)

A tela principal do módulo fiscal, acessível na rota `/modulo_fiscal` do painel.

#### 18.1.1 Dashboard (topo)

Indicadores em tempo real:
- **Notas emitidas** (mês atual)
- **Notas pendentes** (aguardando emissão)
- **Notas rejeitadas** (que precisam de correção)
- **Valor total faturado** (soma das notas emitidas no mês)
- **Limite mensal** (utilizado / total)
- Badge de contingência quando ativa

#### 18.1.2 Abas

| Aba | Filtro | Ações disponíveis |
|---|---|---|
| **Todas** | Todas as notas | Emitir, Download XML/PDF, Reenviar e-mail, Cancelar, CC-e, Consultar SEFAZ |
| **Clientes** | Lista de clientes do comercial | Ver notas do cliente |
| **Notas Emitidas** | Status = autorizada | Download, Reenviar e-mail, Cancelar, CC-e, Consultar SEFAZ |
| **Pendentes** | Status = aguardando_emissão | Emitir nota |
| **Rejeitadas** | Status = rejeitada | Ver motivo, Reemitir |
| **Canceladas** | Status = cancelada | Ver justificativa, Download |
| **Contingência** | Status = contingencia | Ver motivo, Resolver, Reenviar |
| **Histórico** | Todas (ordenado por data) | Visualizar |

#### 18.1.3 Menu de Ações (três pontos)

Para cada nota na tabela:

| Ação | Disponível para | Descrição |
|---|---|---|
| **Download XML** | Autorizada, Cancelada, Contingência | Abre URL do XML ou baixa inline |
| **Download DANFE** | Autorizada, Cancelada | Abre URL do DANFE ou baixa inline |
| **Reenviar por E-mail** | Autorizada | Abre modal de envio de e-mail |
| **Cancelar NF-e** | Autorizada (≤ 24h) | Abre modal de cancelamento |
| **Carta de Correção** | Autorizada (< 20 CC-e) | Abre modal de CC-e |
| **Inutilizar Numeração** | Aguardando emissão | Abre modal de inutilização |
| **Consultar SEFAZ** | Autorizada, Cancelada | Exibe status detalhado |
| **Detalhes da Contingência** | Contingência | Exibe motivo da contingência |

#### 18.1.4 Modais

| Modal | Classe | Função |
|---|---|---|
| Emissão | `_EmitirNotaModal` | Emite nota com animação de progresso |
| Envio por e-mail | `_EnviarNotaModal` | Envia DANFE/XML ao cliente |
| Cancelamento | `_CancelamentoDialog` | Cancela NF-e com justificativa |
| CC-e | `_CartaCorrecaoDialog` | Envia carta de correção |
| Inutilização | `_InutilizacaoDialog` | Inutiliza faixa de numeração |

---

## 19. Modal de Emissão com Animação

### 19.1 `FiscalEmissaoModal`

Arquivo: `lib/widgets/fiscal/fiscal_emissao_modal.dart` (~910 linhas)

Modal premium de emissão de NF-e com 4 estados animados.

#### Estados:

| Estado | Tela | Descrição |
|---|---|---|
| `preview` | Pré-visualização | Mostra resumo (emitente, destinatário, itens, totais), validação, XML collapsible |
| `validando` | Validação | Animação de pulso com ícone de checklist, barra de progresso |
| `emitindo` | Transmissão | Animação de pulso com gradiente roxo/laranja, barra de progresso com percentual |
| `resultado` | Resultado | Sucesso (verde) ou erro (vermelho) com detalhes |

#### Funcionalidades:
- **Pré-visualização:** cards de resumo, validação inline (verde/vermelho), XML collapsível com contagem de caracteres
- **Validação antes da emissão:** só permite emitir se `podeEmitir == true`
- **Animação de transmissão:** ícone pulsante com gradiente + progresso simulado
- **Resultado:** exibe chave de acesso, protocolo, número, série; XML gerado collapsível
- **Erros:** exibe erros de validação com campo e mensagem

#### Preview Modal (`mostrarPreview`)

Versão simplificada apenas para consulta (sem emissão), usada pelo módulo de assinaturas.

---

## 20. Integração com Assinaturas

### 20.1 `emitirNotaAssinatura` no `FiscalEmissaoService`

Permite emitir NF-e para cobranças recorrentes de assinatura.

**Fluxo:**
1. Recebe `ClienteAssinaturaModel` com dados do cliente e plano
2. Busca dados fiscais da loja em `store_fiscal_settings`
3. Monta `FiscalPayload` com:
   - **Emitente:** dados fiscais da loja (CNPJ, IE, endereço)
   - **Destinatário:** nome, CPF/CNPJ, endereço do assinante
   - **Item:** descrição "Assinatura {plano}", valor mensal, NCM genérico
   - **Totais:** valor total = valor da assinatura
4. Chama `emitirNotaCompleta` com os dados montados

---

## 21. Estrutura de Arquivos

```
depertin_web/lib/
│
├── models/
│   ├── fiscal_document_model.dart          # FiscalDocumentModel, StatusFiscal, CartaCorrecaoEvento
│   ├── store_fiscal_settings_model.dart    # StoreFiscalSettingsModel
│   ├── fiscal_integration_model.dart       # FiscalIntegrationModel
│   └── lojista_integracao_model.dart       # LojistaIntegracaoModel (limite mensal)
│
├── services/
│   ├── fiscal/
│   │   ├── fiscal.dart                     # Re-export barrel
│   │   ├── fiscal_payload.dart             # FiscalPayload, tipos de documento, emitente, destinatário
│   │   ├── fiscal_provider.dart            # FiscalProvider, FiscalProviderResult
│   │   ├── fiscal_provider_service.dart    # FiscalProviderService (resolve provedores)
│   │   ├── fiscal_provider_http.dart       # ⬅ NOVO: Camada HTTP padronizada (postJson, get, tratamento de erro)
│   │   ├── fiscal_validator.dart           # FiscalValidator, ValidationResult
│   │   ├── fiscal_xml_builder.dart         # FiscalXmlBuilder (geração de XML)
│   │   ├── fiscal_emissao_service.dart     # FiscalEmissaoService (orquestrador principal)
│   │   ├── fiscal_cancelamento_service.dart # Cancelamento de NF-e
│   │   ├── fiscal_carta_correcao_service.dart # CC-e
│   │   ├── fiscal_inutilizacao_service.dart # Inutilização de numeração
│   │   ├── fiscal_contingencia_service.dart # Contingência SEFAZ
│   │   ├── fiscal_series_service.dart      # Controle de séries e numeração
│   │   ├── fiscal_serie_model.dart         # FiscalSerie
│   │   ├── fiscal_email_service.dart       # Envio de e-mail transacional
│   │   ├── fiscal_erro_translator.dart     # Tradução de erros SEFAZ
│   │   ├── fiscal_crypto_util.dart         # ⬅ UPGRADE: AES-256-GCM (antes XOR)
│   │   ├── fiscal_audit_service.dart       # Auditoria de operações
│   │   ├── fiscal_certificado_service.dart  # ⬅ NOVO: Upload/validação certificado A1
│   │   ├── fiscal_admin_service.dart        # ⬅ NOVO: Serviço administrativo (streams, suspender, reativar)
│   │   └── providers/
│   │       ├── focus_nfe_provider.dart     # ⬅ REFAT: HTTP real (POST /v2/nfe, cancelamento, CC-e)
│   │       ├── enotas_provider.dart        # ⬅ REFAT: HTTP real (POST /v1/empresas/{id}/nf-e)
│   │       ├── plug_notas_provider.dart    # ⬅ REFAT: HTTP real (POST /nfe, cancelamento, CC-e)
│   │       ├── nuvem_fiscal_provider.dart  # ⬅ REFAT: HTTP real + OAuth2 (token caching)
│   │       ├── webmania_provider.dart      # ⬅ REFAT: via Cloud Function proxy (OAuth 1.0a)
│   │       └── custom_fiscal_provider.dart # ⬅ REFAT: HTTP real (multi-auth, endpoints config)
│   ├── fiscal_integrations_service.dart     # FiscalIntegrationsService (CRUD Firestore)
│   ├── lojista_integracao_service.dart      # LojistaIntegracaoService (limite mensal)
│   └── fiscal_service.dart                 # FiscalService (auxiliar)
│
├── screens/
│   ├── lojista_modulo_fiscal_screen.dart   # Tela principal do módulo (~7143 linhas)
│   ├── assinaturas_fiscal_screen.dart      # Tela fiscal para assinaturas (~1708 linhas)
│   └── admin_fiscal_screen.dart            # ⬅ NOVO: Painel admin fiscal (KPIs, tabela, ações)
│
└── widgets/
    └── fiscal/
        ├── fiscal_emissao_modal.dart       # Modal premium de emissão (~910 linhas)
        ├── fiscal_certificado_modal.dart    # ⬅ NOVO: Upload certificado A1 (.pfx/.p12)
        └── fiscal_dados_empresa_modal.dart  # ⬅ NOVO: Formulário dados fiscais empresa

depertin_cliente/functions/
│
├── fiscal_webhook.js                       # ⬅ NOVO: HTTP endpoint p/ webhooks de provedores fiscais
├── fiscal_proxy.js                         # ⬅ NOVO: Proxy p/ provedores com auth complexa (WebmaniaBR)
└── index.js                                # ⬅ ADD: exports das novas functions
```

**Total: 32 arquivos** (25 existentes + 7 novos)

---

## 22. Fluxo Completo de Emissão

### 22.1 Fluxo Normal (com HTTP real)

```
Usuário                      Painel                         Service                   Provedor (HTTP)
   │                            │                              │                         │
   │  Clique "Emitir NF-e"       │                              │                         │
   ├───────────────────────────►│                              │                         │
   │                            │  Abre FiscalEmissaoModal      │                         │
   │                            ├─── preview (valida)          │                         │
   │                            │     │                        │                         │
   │  Revê dados + confirma      │     │                        │                         │
   ├───────────────────────────►│     │                        │                         │
   │                            │  Chama emitirNotaCompleta()   │                         │
   │                            ├─────────────────────────────►│                         │
   │                            │                              │  FiscalValidator         │
   │                            │                              │  ├── valida payload      │
   │                            │                              │  ├── valida CFOP/NCM/CST │
   │                            │                              │  ├── valida CNPJ/IE      │
   │                            │                              │  └── valida valores      │
   │                            │                              │                         │
   │                            │                              │  StoreFiscalSettings     │
   │                            │                              │  ├── busca config loja   │
   │                            │                              │  └── busca integração    │
   │                            │                              │                         │
   │                            │                              │  FiscalProviderService   │
   │                            │                              │  └── resolve provider    │
   │                            │                              │                         │
   │                            │                              │  LojistaIntegracao       │
   │                            │                              │  └── verifica limite     │
   │                            │                              │                         │
   │                            │                              │  FiscalCertificadoService │
   │                            │                              │  └── valida certificado  │
   │                            │                              │                         │
   │                            │                              │  FiscalSeriesService     │
   │                            │                              │  └── reserva número      │
   │                            │                              │                         │
   │                            │                              │  FiscalXmlBuilder        │
   │                            │                              │  └── gera XML NF-e       │
   │                            │                              │                         │
   │                            │                              │  FiscalCryptoUtil        │
   │                            │                              │  └── descriptografa      │
   │                            │                              │      credenciais         │
   │                            │                              │                         │
   │                            │                              │  FiscalProviderHttp      │
   │                            │                              │  └── POST real ──────────►
   │                            │                              │                         │
   │                            │                              │    ◄── JSON resposta ────┤
   │                            │                              │                         │
   │                            │                              │  Persiste documento      │
   │                            │                              │  FiscalAuditService      │
   │                            │                              │  └── registra auditoria  │
   │                            │                              │                         │
   │                            │  ◄── FiscalEmissaoResult ────│                         │
   │                            │                              │                         │
   │  Animação de sucesso/erro  │                              │                         │
   │  ◄─────────────────────────┤                              │                         │
   │                            │                              │                         │
```

### 22.2 Fluxo de Cancelamento (via HTTP real)

```
Usuário → Clica "Cancelar NF-e"
  → Verifica prazo (≤ 24h da autorização)
  → Abre _CancelamentoDialog
  → Preenche justificativa (min 10 char)
  → Confirma
  → FiscalCancelamentoService.cancelarNota()
    → Gera XML de cancelamento
    → Descriptografa credenciais
    → Envia ao provedor via HTTP real (POST /cancelamento)
    → Provedor → SEFAZ
    → Se sucesso:
        → Atualiza status para "cancelada"
        → Salva XML/PDF de cancelamento
        → Cancela numeração (se aplicável)
        → Registra auditoria
    → Se falha:
        → Exibe erro traduzido (FiscalErroTranslator)
```

### 22.3 Fluxo de CC-e (via HTTP real)

```
Usuário → Clica "Carta de Correção"
  → Verifica limite (< 20 CC-e)
  → Abre _CartaCorrecaoDialog
  → Digita texto de correção (max 1000 char)
  → Confirma
  → FiscalCartaCorrecaoService.enviarCartaCorrecao()
    → Gera XML da CC-e
    → Descriptografa credenciais
    → Envia ao provedor via HTTP real (POST /carta-correcao)
    → Provedor → SEFAZ
    → Se sucesso:
        → Adiciona ao histórico de CC-e da nota
        → Registra auditoria
    → Se falha:
        → Exibe erro traduzido
```

### 22.4 Fluxo de Inutilização (via HTTP real)

```
Usuário → Clica "Inutilizar Numeração"
  → Abre _InutilizacaoDialog
  → Define faixa (inicial → final, max 999)
  → Preenche justificativa
  → Confirma
  → FiscalInutilizacaoService.inutilizar()
    → Gera XML de inutilização
    → Descriptografa credenciais
    → Envia ao provedor via HTTP real (POST /inutilizacao)
    → Provedor → SEFAZ
    → Se sucesso:
        → Atualiza numeração para pular faixa
        → Registra auditoria
    → Se falha:
        → Exibe erro traduzido
```

---

## 23. Camada HTTP Padronizada

### 23.1 `FiscalProviderHttp`

Arquivo: `lib/services/fiscal/fiscal_provider_http.dart` (NOVO)

Utilitário abstrato que fornece métodos HTTP padronizados para todos os provedores fiscais.

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `postJson(String url, Map body, {Map? headers, int timeoutSegundos}) → Future<FiscalProviderResult>` | POST com body JSON |
| `get(String url, {Map? headers, int timeoutSegundos}) → Future<FiscalProviderResult>` | GET |
| `putJson(String url, Map body, {Map? headers, int timeoutSegundos}) → Future<FiscalProviderResult>` | PUT com body JSON |
| `delete(String url, {Map? headers, int timeoutSegundos}) → Future<FiscalProviderResult>` | DELETE |
| `parseSucesso(Map responseJson, {String? chaveAcessoPath, String? protocoloPath, String? numeroPath, String? seriePath, String? xmlUrlPath, String? pdfUrlPath, String? statusPath}) → FiscalProviderResult` | Parse padronizado de resposta de sucesso |
| `parseErro(dynamic error, {int? statusCode}) → FiscalProviderResult` | Parse padronizado de erro |

**Comportamento:**
- Timeout padrão de 30 segundos (configurável por chamada)
- Headers padrão: `Content-Type: application/json`, `Accept: application/json`
- Retorna `FiscalProviderResult` com `sucesso=false` e mensagem amigável em caso de:
  - Timeout (`SocketException`, `TimeoutException`)
  - Erro de rede (`HttpException`)
  - Status HTTP 4xx/5xx (com corpo do erro)
  - Exceções não tratadas

**Tratamento de erros:**

| Situação | Mensagem amigável |
|---|---|
| Timeout | "O servidor não respondeu dentro do prazo. Verifique sua conexão e tente novamente." |
| Rede | "Erro de conexão com o servidor fiscal. Verifique sua internet." |
| HTTP 401/403 | "Credenciais inválidas. Verifique a configuração do provedor." |
| HTTP 4xx genérico | "Requisição inválida (código {status})." |
| HTTP 5xx | "Erro no servidor do provedor fiscal. Tente novamente mais tarde." |

---

## 24. Certificado Digital A1

### 24.1 `FiscalCertificadoService`

Arquivo: `lib/services/fiscal/fiscal_certificado_service.dart` (NOVO)

Gerencia o upload, armazenamento e validação de certificados digitais A1 (.pfx/.p12).

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `selecionarArquivo() → Future<PlatformFile?>` | Abre seletor de arquivos (filtro .pfx, .p12) |
| `salvarCertificado({storeId, fileBytes, fileName, password})` | Criptografa dados e salva no Firestore |
| `validarCertificado({storeId}) → Future<bool>` | Verifica se certificado existe e não está vencido |
| `obterInfoCertificado({storeId}) → Future<Map?>` | Retorna metadados do certificado |
| `removerCertificado({storeId})` | Remove certificado do Firestore |

**Fluxo de salvamento:**
1. Usuário seleciona arquivo `.pfx` ou `.p12` via `FilePicker`
2. Lê bytes do arquivo
3. Criptografa bytes com `FiscalCryptoUtil.encrypt` (AES-256-GCM)
4. Criptografa senha do certificado separadamente
5. Salva em `store_fiscal_settings/{lojaId}.certificateDataEncrypted` + `.certificatePasswordEncrypted`
6. Extrai e salva metadados: data de validade, emissor, CNPJ (quando suportado)
7. Marca `status = active`

**Validação antes da emissão:**
- Certificado existe? → bloqueia se não
- Certificado está vencido? → bloqueia com mensagem "Certificado vencido em {data}"

### 24.2 `FiscalCertificadoModal`

Arquivo: `lib/widgets/fiscal/fiscal_certificado_modal.dart` (NOVO)

Modal premium para upload e gerenciamento do certificado digital A1.

**Funcionalidades:**
- Upload de arquivo `.pfx`/`.p12` com preview do nome e tamanho
- Campo de senha do certificado (obscureText)
- Validação de extensão e tamanho
- Exibição do status atual: "Configurado", "Não configurado", "Venceu em dd/mm/aaaa"
- Badge verde/vermelho conforme validade
- Botão "Remover certificado" com confirmação
- Tema DiPertin (roxo/laranja)

---

## 25. Dados Fiscais da Empresa

### 25.1 `FiscalDadosEmpresaModal`

Arquivo: `lib/widgets/fiscal/fiscal_dados_empresa_modal.dart` (NOVO)

Modal premium para cadastro completo dos dados fiscais da loja.

**Campos do formulário:**

| Seção | Campo | Tipo | Validação |
|---|---|---|---|
| **Identificação** | Razão Social | Texto | Obrigatório |
| | Nome Fantasia | Texto | Opcional |
| | CNPJ | CNPJ (14 dígitos) | Obrigatório + dígitos verificadores |
| | Inscrição Estadual | Texto | Obrigatório |
| | Inscrição Municipal | Texto | Opcional |
| | Regime Tributário | Dropdown | Obrigatório (Simples Nacional, MEI, Regime Normal) |
| | CRT | Dropdown | Obrigatório (1, 2, 3) |
| | CNAE | Texto (7 dígitos) | Opcional |
| **Endereço Fiscal** | CEP | CEP (8 dígitos) | Obrigatório |
| | Logradouro | Texto | Obrigatório |
| | Número | Texto | Obrigatório |
| | Complemento | Texto | Opcional |
| | Bairro | Texto | Obrigatório |
| | Cidade | Texto | Obrigatório |
| | UF | Dropdown (2 letras) | Obrigatório |
| **Contato** | Telefone | Telefone | Opcional |
| | E-mail Fiscal | Email | Opcional |

**Funcionalidades:**
- Input formatters para CNPJ (`XX.XXX.XXX/XXXX-XX`), CEP (`XXXXX-XXX`) e telefone
- Validação de CNPJ com dígitos verificadores (`_validarCnpjDigitos`)
- Dropdown de UF com lista completa
- Dropdown de regime tributário com descrições
- Consistência visual com gradiente roxo no cabeçalho

**Modelo de dados:**
```dart
class DadosEmpresaFiscal {
  final String razaoSocial;
  final String? nomeFantasia;
  final String cnpj;
  final String ie;
  final String? im;
  final String regimeTributario;
  final String crt;
  final String? cnae;
  final String cep;
  final String logradouro;
  final String numero;
  final String? complemento;
  final String bairro;
  final String cidade;
  final String uf;
  final String? telefone;
  final String? emailFiscal;

  Map<String, dynamic> toMap();
  bool validar();
}
```

---

## 26. Cloud Functions (Webhook + Proxy)

### 26.1 `fiscal_webhook.js`

Arquivo: `depertin_cliente/functions/fiscal_webhook.js` (NOVO)

Cloud Function HTTP que recebe webhooks de provedores fiscais para atualização automática de status.

**Características:**
- **Região:** `us-central1` (compartilhada com as demais functions do marketplace)
- **Timeout:** 60 segundos
- **Memória:** 256 MB

**Validação de origem:**

| Provedor | Método | Detalhe |
|---|---|---|
| Focus NFe | HMAC-SHA256 | Lê `x-focus-signature` e valida com `webhook_secret` |
| PlugNotas | Bearer Token | Lê `Authorization: Bearer {token}` e compara com config |
| Nuvem Fiscal | API Key | Lê `x-api-key` e compara com config |
| Enotas | IP allowlist | Valida IP de origem |
| WebmaniaBR | HMAC-SHA256 | Lê `x-webmania-signature` |
| Genérico | Token | Lê campo `token` no body e compara com config |

**Atualizações no Firestore:**
```javascript
// Coleção: fiscal_documents/{docId}
// Campos atualizados:
{
  status: 'autorizada' | 'rejeitada' | 'cancelada',
  accessKey: '352406...',
  protocol: '123456789...',
  xmlUrl: 'https://...nfe.xml',
  pdfUrl: 'https://...danfe.pdf',
  rejectionReason: '...',
  rejectionCode: '220',
  updatedAt: firestore.FieldValue.serverTimestamp(),
}
```

**Mapeamento de status dos provedores:**

| Provedor | Status do provedor → Status interno |
|---|---|
| Focus NFe | `autorizado` → `autorizada`, `rejeitado` → `rejeitada`, `cancelado` → `cancelada` |
| PlugNotas | `autorizado` → `autorizada`, `rejeitado` → `rejeitada`, `cancelado` → `cancelada` |
| Nuvem Fiscal | `autorizado` → `autorizada`, `rejeitado` → `rejeitada` |
| Enotas | `Autorizado` → `autorizada`, `Rejeitado` → `rejeitada` |
| WebmaniaBR | `aprovado` → `autorizada`, `reprovado` → `rejeitada`, `cancelado` → `cancelada` |

**Saída:**
```json
{ "recebido": true, "documentoId": "abc123" }
```

### 26.2 `fiscal_proxy.js`

Arquivo: `depertin_cliente/functions/fiscal_proxy.js` (NOVO)

Cloud Function `onCall` que atua como proxy para provedores fiscais com autenticação complexa (WebmaniaBR com OAuth 1.0a).

**Funções exportadas:**

| Nome | Tipo | Descrição |
|---|---|---|
| `fiscalProxyEmitir` | `onCall` | Proxy para emissão |
| `fiscalProxyCancelar` | `onCall` | Proxy para cancelamento |
| `fiscalProxyCartaCorrecao` | `onCall` | Proxy para CC-e |
| `fiscalProxyInutilizar` | `onCall` | Proxy para inutilização |
| `fiscalProxyTestarConexao` | `onCall` | Proxy para teste de conexão |

**Fluxo:**
1. Frontend envia payload + credenciais criptografadas
2. Function descriptografa credenciais com AES-256-GCM
3. Monta requisição HTTP com OAuth 1.0a (consumer key/secret + access token/secret)
4. Executa HTTP request para a API WebmaniaBR
5. Retorna resultado para o frontend

**Segurança:**
- `enforceAppCheck: false` (compatível com painel web)
- Credenciais são descriptografadas apenas em memória, nunca logadas
- Valida se o caller está autenticado

---

## 27. Painel Admin Fiscal

### 27.1 `AdminFiscalScreen`

Arquivo: `lib/screens/admin_fiscal_screen.dart` (NOVO)

Tela administrativa para staff/master gerenciar todas as integrações fiscais dos lojistas.

**Acessível em:** rota `/admin_fiscal` (índice 53 do shell)
**Visível para:** perfis staff/admin ("chefe" na sidebar)

#### KPIs (topo)

| Indicador | Descrição |
|---|---|
| **Integrações Ativas** | Total de lojas com `store_fiscal_settings.status == active` |
| **Total de Lojas** | Total de lojas que possuem configuração fiscal |
| **Com Erro** | Lojas com certificado vencido ou falha recente |

#### Tabela de Lojas

| Coluna | Descrição |
|---|---|
| Loja | Nome da loja |
| Provedor | Nome do provedor fiscal configurado |
| Status do Certificado | Ícone verde (válido) / vermelho (vencido) / cinza (não configurado) |
| Status da Integração | Active / Inactive / Pending |

#### Ações (PopupMenuButton)

| Ação | Descrição |
|---|---|
| Reativar | Reativa integração suspensa |
| Suspender | Suspende integração ativa |
| Remover | Remove integração e dados fiscais |
| Ver logs | Abre modal com `fiscal_audit_logs` da loja |

#### Filtros

- **Busca por nome da loja** (client-side)
- **Apenas ativos** (toggle para filtrar só integrações ativas)

### 27.2 `FiscalAdminService`

Arquivo: `lib/services/fiscal/fiscal_admin_service.dart` (NOVO)

Serviço com métodos administrativos.

**Métodos públicos:**

| Método | Descrição |
|---|---|
| `streamTodasConfiguracoes()` | Stream de todas as `store_fiscal_settings` |
| `streamDocumentosMes(String storeId, {DateTime? referencia})` | Stream de documentos do mês |
| `suspenderIntegracao(String storeId)` | Suspende integração |
| `reativarIntegracao(String storeId)` | Reativa integração |
| `removerIntegracao(String storeId)` | Remove integração e dados |
| `reenviarNota(String fiscalDocumentId)` | Marca nota para reenvio |
| `streamAuditLogs(String storeId)` | Stream de logs de auditoria |
| `totalNotasMes(String storeId, {DateTime? referencia})` | Total de notas emitidas no mês |

---

## 28. Dependências

### 28.1 pubspec.yaml

Dependências adicionadas ao projeto web para suportar o módulo fiscal:

```yaml
dependencies:
  encrypt: ^5.0.3           # AES-256-GCM para criptografia de dados sensíveis
  asn1lib: ^1.5.8           # Parse de certificados ASN.1
  pointycastle: ^3.9.1      # Algoritmos criptográficos (SHA-256)
```

### 28.2 Cloud Functions

Dependências em `depertin_cliente/functions/package.json` (já existentes):

```json
{
  "dependencies": {
    "firebase-admin": "^11.x",
    "firebase-functions": "^5.x",
    "@google-cloud/firestore": "^7.x"
  }
}
```

---

## Histórico de Versões

| Data | Versão | Descrição |
|---|---|---|
| jul/2026 | 1.1.1 | **Checklist final de produção**: Firestore Rules expandidas (fiscal_audit_logs, fiscal_series), env.fiscal.example, deploy_fiscal_functions.ps1, fiscal_monthly_reset.js (reset mensal + alertas certificado), FiscalMonitoringService, scripts/migrar_dados_fiscais.js, 31 testes automatizados (webhook 24 + proxy 7 + Dart) |
| jul/2026 | 1.1.0 | **Integração real com API externa**: HTTP real em todos os provedores, AES-256-GCM, certificado digital A1, webhook funcional, Cloud Function proxy, painel admin fiscal, dados da empresa, validação com `dart analyze` zero erros |
| jul/2026 | 1.0.0 | Implementação inicial do módulo fiscal completo |

---

*Documentação gerada em julho/2026 — Módulo Fiscal DiPertin v1.1.0*
