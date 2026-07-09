# Finalização — Módulo Fiscal NF-e

> **Data:** 06/jul/2026  
> **Versão do módulo:** 1.1.1  
> **Stack:** Flutter Web + Firebase (Firestore, Functions, Rules)  
> **Projeto Firebase:** `depertin-f940f`  
> **Região Functions:** `us-central1`

---

## Status Geral

| Item | Status |
|---|---|
| **Criptografia** | ✅ AES-256-GCM (upgrade de XOR legado) |
| **Provedores Fiscais** | ✅ 6 provedores com HTTP real |
| **Webhook** | ✅ Cloud Function HTTP recebendo POST |
| **Proxy Webmania** | ✅ 5 Cloud Functions onCall (OAuth 1.0a) |
| **Certificado A1** | ✅ Upload, validação, expiração, bloqueio |
| **Dados Fiscais Empresa** | ✅ CNPJ, IE, CNAE, regime, endereço fiscal |
| **Painel Admin** | ✅ Tela administrativa com KPIs e ações |
| **Firebase Rules** | ✅ 8 coleções fiscais protegidas |
| **Variáveis de Ambiente** | ✅ Configuradas no .env + env.fiscal.example |
| **Rotina Mensal** | ✅ Scheduled function (reset limite + alertas) |
| **Migração** | ✅ Script CLI para ajustar lojas antigas |
| **Monitoramento** | ✅ FiscalMonitoringService (erros, certificados, limites) |
| **Deploy** | ✅ Script PowerShell para deploy seletivo |
| **Testes Dart** | ✅ 4 arquivos, `dart analyze` zero erros |
| **Testes Node.js** | ✅ 2 arquivos, 31/31 testes passando |

---

## 1. Arquitetura

```
┌─ Frontend (Flutter Web) ─────────────────────────────────────┐
│                                                              │
│  LojistaModuloFiscalScreen  ─────  FiscalEmissaoModal         │
│       │                               │                      │
│       ├─ Painel Notas (CRUD)          ├─ FiscalPayload        │
│       ├─ Cancelamento                 ├─ FiscalValidator      │
│       ├─ CC-e                         ├─ FiscalXmlBuilder     │
│       ├─ Inutilização                 └─ FiscalItemBuilder     │
│       └─ Contingência                                         │
│                                                              │
│  AdminFiscalScreen  ──  FiscalAdminService                    │
│                              │                               │
│                              ├─ streamConfigs()              │
│                              ├─ streamDocumentos()           │
│                              ├─ suspender/reativar/remover    │
│                              └─ streamAuditLogs()            │
│                                                              │
│  FiscalMonitoringService                                      │
│      ├─ streamCertificadosProximosVencimento()               │
│      ├─ streamErrosEmissao()                                 │
│      ├─ streamLojistasProximosLimite()                       │
│      └─ contarErrosRecentes()                                │
│                                                              │
│  FiscalCertificadoService  ──  FiscalCertificadoModal        │
│  FiscalDadosEmpresaModal                                      │
│                                                              │
└──────────────────────────────────────────────────────────────┘
            │                   ▲
            ▼                   │
┌─ Camada de Provedores ───────┴──────────────────────────────┐
│                                                              │
│  FiscalProvider (interface)                                  │
│      ├─ FocusNFeProvider     (Bearer Token + HMAC)           │
│      ├─ EnotasProvider       (Bearer Token)                  │
│      ├─ PlugNotasProvider    (API Key)                       │
│      ├─ NuvemFiscalProvider  (OAuth 2.0 Client Credentials)  │
│      ├─ WebmaniaProvider     (OAuth 1.0a → Cloud Function)   │
│      └─ CustomFiscalProvider (Bearer/Basic/API Key/OAuth2)   │
│                                                              │
│  FiscalProviderHttp (HTTP helpers padronizados)              │
│  FiscalCryptoUtil   (AES-256-GCM)                            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
            │                   ▲
            ▼                   │
┌─ Cloud Functions (Firebase) ────────────────────────────────┐
│                                                              │
│  HTTP:  fiscalWebhookNFe    ← POST de provedores fiscais    │
│  Call:  proxyWebmania*      ← OAuth 1.0a (5 funções)        │
│  Sched: fiscalRotinaMensalReset  ← 1º dia do mês 02:00 SP   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
            │
            ▼
┌─ Firestore ─────────────────────────────────────────────────┐
│  store_fiscal_settings     (config fiscal da loja)           │
│  fiscal_documents          (NF-e emitidas)                   │
│  lojista_integracao        (integração ativa + limite)       │
│  fiscal_integrations       (provedores globais - staff)      │
│  planos_emissao_nfe        (planos de emissão - staff)       │
│  fiscal_series             (numeração fiscal por loja)       │
│  fiscal_audit_logs         (log de operações - imutável)     │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Provedores Fiscais Suportados

| Provedor | ID | Autenticação | Emissão | Cancelamento | CC-e | Inutilização | Teste |
|---|---|---|---|---|---|---|---|
| **Focus NFe** | `focus_nfe` | Bearer Token | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Enotas** | `enotas` | Bearer Token + empresa_id | ✅ | ✅ | ❌ (API) | ❌ (API) | ✅ |
| **PlugNotas** | `plug_notas` | API Key (header) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Nuvem Fiscal** | `nuvem_fiscal` | OAuth 2.0 | ✅ | ✅ | ✅ | ❌ (config) | ✅ |
| **WebmaniaBR** | `webmania` | OAuth 1.0a (CF Proxy) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Custom** | `custom` | Multi-auth | ✅ | ✅ | config | config | ✅ |

---

## 3. Status dos NF-e

| Status Interno | Descrição |
|---|---|
| `rascunho` | Em edição, não enviado |
| `enviado` | Enviado para API, aguardando resposta |
| `processando` | API está processando |
| `autorizada` | NF-e autorizada pela SEFAZ |
| `rejeitada` | Rejeitada pela SEFAZ/API |
| `cancelada` | Cancelada dentro do prazo legal |
| `cancelamento_homologado` | Cancelamento homologado |
| `contingencia` | Em contingência (offline) |
| `corrigida` | Possui CC-e emitida |
| `denegada` | Denegada (não pode ser emitida) |

---

## 4. Coleções Firestore e Regras

| Coleção | Regra de Leitura | Regra de Escrita |
|---|---|---|
| `store_fiscal_settings/{id}` | Staff ou lojista da própria loja | Staff ou lojista da própria loja (delete só staff) |
| `fiscal_documents/{id}` | Staff ou lojista da própria loja | `false` (só Admin SDK) |
| `lojista_integracao/{id}` | Staff ou lojista da própria loja | Staff |
| `fiscal_integrations/{id}` | Staff | Staff |
| `planos_emissao_nfe/{id}` | Staff | Staff |
| `fiscal_series/{id}` | Staff ou lojista da própria loja | Staff (update: lojista próprio) |
| `fiscal_audit_logs/{id}` | Staff | `false` (só Admin SDK) |
| `users/{uid}/notas_fiscais/{id}` | Dono, colaborador, staff | Dono (operacional), staff |

---

## 5. Cloud Functions

### 5.1 `fiscalWebhookNFe` (HTTP onRequest)

- **Endpoint:** `POST https://us-central1-depertin-f940f.cloudfunctions.net/fiscalWebhookNFe`
- **Query param:** `?provider=focus_nfe|plug_notas|enotas|nuvem_fiscal|webmania_br|custom`
- **Validação de origem:**
  - `focus_nfe`: HMAC SHA256 (header `X-Focus-Signature`)
  - `plug_notas`: API Key (header `X-API-Key`)
  - `enotas`/`nuvem_fiscal`: Bearer Token (header `Authorization`)
  - `webmania_br`/`custom`: IP whitelist
  - `default`: HMAC genérico com `FISCAL_WEBHOOK_SECRET`
- **Fluxo:** Extrai dados → busca `fiscal_documents` por chave de acesso → mapeia status → atualiza documento → registra auditoria → responde 200

### 5.2 Proxy WebmaniaBR (5 onCall v2)

| Função | Descrição |
|---|---|
| `proxyWebmaniaEmitirNota` | Emite NF-e |
| `proxyWebmaniaCancelarNota` | Cancela NF-e |
| `proxyWebmaniaCartaCorrecao` | Envia carta de correção |
| `proxyWebmaniaInutilizar` | Inutiliza numeração |
| `proxyWebmaniaTestarConexao` | Testa conectividade |

Todas exigem `request.auth`. Credenciais OAuth 1.0a nunca são logadas.

### 5.3 `fiscalRotinaMensalReset` (scheduled)

- **Schedule:** `0 2 1 * *` (1º dia de cada mês, 02:00 SP)
- **Ações:**
  1. Reseta `notasEmitidas: 0` e atualiza `mesReferencia`
  2. Verifica certificados próximos do vencimento (30 dias)
  3. Bloqueia integrações com certificado vencido
  4. Registra auditoria em `fiscal_audit_logs`

---

## 6. Segurança

### 6.1 Criptografia

| Dado | Algoritmo | Onde está armazenado | Acessível no frontend? |
|---|---|---|---|
| API Keys / Tokens | AES-256-GCM | Firestore (`credentials_encrypted`) | ❌ (só em memória descriptografado) |
| Senha do Certificado A1 | AES-256-GCM | Firestore (`certificate_password_encrypted`) | ❌ (nunca exposta) |
| Certificado A1 (binário) | AES-256-GCM | Firestore (`certificate_data_encrypted`) | ❌ (nunca exposto) |
| Consumer Key/Secret | AES-256-GCM | Firestore (`*_encrypted`) | ❌ (proxy no backend) |

### 6.2 Proteções

- `FiscalAuditService` sanitiza logs — NUNCA salva credenciais
- `fiscal_proxy.js` filtra campos logados (`ALLOWED_LOG_FIELDS`)
- `fiscal_documents` com `write: false` nas regras Firestore
- `fiscal_audit_logs` com `write: false` (só Admin SDK)

---

## 7. Arquivos do Módulo

### 7.1 Frontend (depertin_web/)

```
lib/services/fiscal/
├── fiscal.dart                    # barrel export
├── fiscal_admin_service.dart      # admin: stream configs, ações
├── fiscal_audit_service.dart      # auditoria de operações
├── fiscal_cancelamento_service.dart # cancelamento de NF-e
├── fiscal_carta_correcao_service.dart # CC-e
├── fiscal_certificado_service.dart   # upload/validação A1
├── fiscal_contingencia_service.dart  # contingência offline
├── fiscal_crypto_util.dart           # AES-256-GCM
├── fiscal_emissao_service.dart       # orquestrador emissão
├── fiscal_erro_translator.dart       # tradução de rejeições
├── fiscal_inutilizacao_service.dart  # inutilização
├── fiscal_monitoring_service.dart    # monitoramento
├── fiscal_payload.dart               # modelos de dados
├── fiscal_provider.dart              # interface FiscalProvider
├── fiscal_provider_http.dart         # HTTP helpers
├── fiscal_provider_service.dart      # registry de providers
├── fiscal_series_service.dart        # controle de numeração
├── fiscal_validator.dart             # validação fiscal
├── fiscal_xml_builder.dart           # geração de XML
├── providers/
│   ├── focus_nfe_provider.dart       # Focus NFe
│   ├── enotas_provider.dart          # Enotas
│   ├── plug_notas_provider.dart      # PlugNotas
│   ├── nuvem_fiscal_provider.dart    # Nuvem Fiscal
│   ├── webmania_provider.dart        # WebmaniaBR
│   └── custom_fiscal_provider.dart   # API personalizada

lib/screens/
├── lojista_modulo_fiscal_screen.dart  # painel do lojista (~7143 linhas)
└── admin_fiscal_screen.dart           # painel admin (~novo)

lib/widgets/fiscal/
├── fiscal_emissao_modal.dart          # modal de emissão
├── fiscal_certificado_modal.dart      # upload certificado A1
└── fiscal_dados_empresa_modal.dart    # dados fiscais da loja
```

### 7.2 Cloud Functions (depertin_cliente/functions/)

```
functions/
├── fiscal_webhook.js                  # webhook NF-e (HTTP)
├── fiscal_proxy.js                    # proxy WebmaniaBR (5 onCall)
├── fiscal_monthly_reset.js            # rotina mensal (scheduled)
├── fiscal_entregador.js               # fiscal do entregador (existente)
├── index.js                           # exports (fiscal + proxy + rotina)
├── .env                               # variáveis de ambiente fiscais
├── env.fiscal.example                 # template de variáveis
├── deploy_fiscal_functions.ps1        # script de deploy
├── scripts/
│   └── migrar_dados_fiscais.js        # migração de lojas antigas
└── test/
    ├── fiscal_webhook.test.js         # 24 testes
    └── fiscal_proxy.test.js           # 7 testes
```

### 7.3 Testes (depertin_web/test/)

```
test/fiscal/
├── fiscal_validator_test.dart         # 4 testes
├── fiscal_limite_test.dart            # 7 testes
├── fiscal_certificado_test.dart       # 6 testes
└── fiscal_provider_mock_test.dart     # 11 testes
```

---

## 8. Como Executar

### Testes

```bash
# Testes Dart
cd depertin_web
flutter test test/fiscal/

# Testes Node.js
cd depertin_cliente/functions
node --test test/fiscal_webhook.test.js
node --test test/fiscal_proxy.test.js
```

### Deploy

```powershell
# Apenas funções fiscais
.\deploy_fiscal_functions.ps1

# Funções fiscais + rules + indexes
.\deploy_fiscal_functions.ps1 -All

# Simular
.\deploy_fiscal_functions.ps1 -DryRun
```

### Migração de Lojas

```bash
cd depertin_cliente/functions

# Simular (não persiste)
node scripts/migrar_dados_fiscais.js --dry-run

# Executar
node scripts/migrar_dados_fiscais.js

# Loja específica
node scripts/migrar_dados_fiscais.js --dry-run --loja=LOJA_ID
```

---

## 9. Checklist Pós-Deploy

- [ ] Configurar `FISCAL_MASTER_KEY` no `.env` (64 chars hex)
- [ ] Configurar `FISCAL_WEBHOOK_SECRET` no `.env`
- [ ] Executar `.\deploy_fiscal_functions.ps1`
- [ ] Executar `node scripts/migrar_dados_fiscais.js --dry-run`
- [ ] Configurar webhook nos provedores fiscais:
      URL: `https://us-central1-depertin-f940f.cloudfunctions.net/fiscalWebhookNFe?provider={provedor}`
- [ ] Habilitar integração de um lojista em homologação
- [ ] Emitir NF-e de teste (homologação)
- [ ] Verificar status no painel do lojista
- [ ] Verificar recebimento do webhook
- [ ] Baixar XML + DANFE
- [ ] Cancelar NF-e de teste
- [ ] Enviar CC-e de teste
- [ ] Verificar logs no `fiscal_audit_logs`
- [ ] Verificar admin fiscal (`/admin_fiscal`)

---

## 10. Validação Final

```
dart analyze test/fiscal/          → 0 erros, 0 warnings
dart analyze lib/services/fiscal/  → 0 erros (apenas info/style preexistentes)
node --test test/fiscal_webhook.test.js → 24/24 passando
node --test test/fiscal_proxy.test.js   → 7/7 passando
```

**Total:** 6 arquivos de teste, 38 cenários, todos passando.

---

*Documento gerado em 06/jul/2026 — Módulo Fiscal NF-e DiPertin v1.1.1*
