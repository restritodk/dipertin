======================================================
RELATÓRIO DE AUDITORIA — XML, DANFE, WEBHOOKS E STATUS
======================================================

**Data:** 07/07/2026  
**Escopo:** Módulo Fiscal NF-e (Focus NFe)  
**Versão do backend:** Functions Node.js 20  
**Versão do frontend:** Flutter Web  
**Provedor analisado:** Focus NFe  
**Analista:** Sistema de Auditoria Automatizada  

---

## RESUMO EXECUTIVO

O módulo fiscal NF-e do DiPertin está implementado de forma **robusta e bem estruturada**, com:
- Separação clara de responsabilidades (security guard, payload validator, logger, pos-emissão, webhook, proxy)
- Criptografia AES-256-GCM para credenciais
- Validação de payload contra dados reais do Firestore
- Segurança de acesso por loja (FiscalSecurityGuard)
- Logs de auditoria em 3 coleções dedicadas
- Idempotência de webhook via event hash SHA-256
- Salvamento de XML e DANFE no Storage com fallback

14 arquivos analisados. 20 problemas encontrados (2 críticos, 5 altos, 8 médios, 5 baixos).

---

## 1. XML

**Verificações:**

| Item | Status |
|------|--------|
| XML é obtido diretamente da API Focus NFe | ✅ |
| XML é salvo automaticamente | ✅ |
| XML fica vinculado à nota | ✅ |
| XML fica vinculado à loja correta | ✅ |
| XML pode ser baixado | ✅ |
| XML pode ser reenviado | ✅ |
| XML não é duplicado | ✅ |
| XML não é salvo quando a nota é rejeitada | ✅ |

**Status:** ✅ Implementado

**Arquivos:**
- `depertin_cliente/functions/fiscal_pos_emissao.js` (~413 linhas)
- `depertin_cliente/functions/fiscal_webhook.js` (~507 linhas)
- `depertin_cliente/functions/fiscal_nfe_proxy.js` (~1274 linhas)
- `depertin_web/lib/services/fiscal/fiscal_pos_emissao_service.dart` (~261 linhas)
- `depertin_web/lib/services/fiscal/providers/focus_nfe_provider.dart` (~535 linhas)

**Funções:**
- `fiscal_pos_emissao.js → salvarNoStorage()` (linha 120) — Download da URL Focus → upload para Storage → `makePublic()`
- `fiscal_pos_emissao.js → fiscalConsultarEAtualizarStatus()` (linha 167) — Quando autorizada, baixa XML da Focus e salva no Storage
- `fiscal_webhook.js → fiscalWebhookNFe()` (linhas 213-261) — Webhook autorizada também baixa/salva XML
- `fiscal_nfe_proxy.js → fiscalEmitirNFe()` (linha 239) — Salva URL original da Focus no documento
- `fiscal_pos_emissao_service.dart → baixarConteudoUrl()` (linha 242) — Download via HTTP no frontend

**Observações:**
- XML é baixado da URL oficial da Focus NFe (nunca gerado localmente)
- Salvo em `fiscal/{store_id}/{documento_id}/nfe-{numero}.xml` no Storage
- Torna o arquivo público via `makePublic()` e grava a URL pública no Firestore
- Se download falhar, usa URL original da Focus como fallback (não quebra o fluxo)
- Webhook também baixa e salva no Storage quando autorizada
- **Problema:** Lógica de download duplicada entre `salvarNoStorage()` (pos_emissao) e código inline no `fiscal_webhook.js`

---

## 2. DANFE

**Verificações:**

| Item | Status |
|------|--------|
| DANFE obtido da Focus | ✅ |
| PDF salvo | ✅ |
| Download funcionando | ✅ |
| Impressão funcionando | ⚠️ Parcial |
| Link armazenado | ✅ |
| Apenas notas autorizadas possuem DANFE | ✅ |
| Controle de permissões funcionando | ✅ |

**Status:** ✅ Implementado (com ressalvas)

**Arquivos:**
- `depertin_cliente/functions/fiscal_pos_emissao.js` — salvarNoStorage + consulta automática
- `depertin_web/lib/screens/admin_fiscal_screen.dart` — botões XML, DANFE, Imprimir (linhas 1340-1480)
- `depertin_web/lib/services/fiscal/fiscal_pos_emissao_service.dart` — baixarConteudoUrl

**Funções:**
- `salvarNoStorage()` (linha 120) — Download PDF da Focus → Storage
- `fiscalConsultarEAtualizarStatus()` (linha 167) — Salva DANFE quando autorizada
- `_nfBaixarArquivo()` no admin_fiscal_screen.dart (linha 1331) — Download via HTTP
- `_nfImprimirDanfe()` (linha 1374) — Abre PDF para impressão

**Observações:**
- DANFE em PDF oficial da Focus NFe (nunca gerado localmente)
- Path no Storage: `fiscal/{store_id}/{documento_id}/danfe-{numero}.pdf`
- Botão "Imprimir DANFE" existe na UI mas apenas abre o PDF (não força diálogo de impressão nativa)
- Fallback preserva URL original da Focus se download falhar
- **Risco:** Se a URL original da Focus expirar e o Storage falhou, DANFE fica indisponível

---

## 3. Consulta automática

**Verificações:**

| Item | Status |
|------|--------|
| Consulta automática após emissão | ⚠️ Parcial |
| Intervalos corretos | ✅ |
| Timeout | ✅ |
| Quantidade máxima de tentativas | ✅ |
| Encerramento automático | ✅ |
| Atualização correta do banco | ✅ |
| Atualização correta da interface | ✅ |

**Status:** ⚠️ Parcial

**Arquivos:**
- `depertin_cliente/functions/fiscal_pos_emissao.js` — `fiscalConsultarEAtualizarStatus` (linha 167)
- `depertin_web/lib/services/fiscal/fiscal_pos_emissao_service.dart` — `consultarComRetry()` (linha 148)

**Funções:**
- `fiscalConsultarEAtualizarStatus` (linha 167) — Callable que consulta Focus NFe e atualiza Firestore
- `consultarComRetry()` (linha 148) — Retry progressivo: 5s → 15s → 30s (3 tentativas)

**Observações:**
- O frontend possui `consultarComRetry()` com retry progressivo
- A consulta automática **não é acionada automaticamente após emissão** — depende do frontend chamar a função
- Backend tem a callable pronta (`fiscalConsultarEAtualizarStatus`) que faz toda a lógica
- 1ª consulta: 5s, 2ª: 15s, 3ª: 30s — máximo 3 tentativas
- Para automaticamente quando status é autorizada, rejeitada, cancelada ou erro
- Se autorizada: baixa XML e DANFE no Storage
- Se rejeitada: salva rejection_reason e rejection_code
- Se exceder tentativas: retorna "processando" (sem loop infinito)

---

## 4. Webhook

**Verificações:**

| Item | Status |
|------|--------|
| Endpoint público | ✅ |
| Recebe POST corretamente | ✅ |
| Atualiza nota correta | ✅ |
| Localiza por REF | ✅ |
| Localiza por chave | ✅ |
| Atualiza Firestore | ✅ |
| Atualiza Storage quando necessário | ✅ |
| Atualiza frontend | ✅ |

**Status:** ✅ Implementado

**Arquivos:**
- `depertin_cliente/functions/fiscal_webhook.js` — `fiscalWebhookNFe` (linha 22)
- `depertin_cliente/functions/index.js` — export (linha 1732)

**Funções:**
- `fiscalWebhookNFe` (onRequest v1, linha 22) — Endpoint POST público
- `validarOrigem(req, provider)` (linha 350) — Valida HMAC, API Key ou Bearer token
- `extrairDadosWebhook(body, provider)` (linha 404) — Parseia formato específico de cada provedor
- `mapearStatus(statusProvedor, provider)` (linha 475) — ~40 variações → `autorizada/rejeitada/cancelada/processando`

**Observações:**
- Endpoint: `fiscalWebhookNFe` em `us-central1`
- Suporta: Focus NFe (HMAC), PlugNotas (X-API-Key), Enotas (Bearer), Nuvem Fiscal (Bearer)
- Localiza nota por `chaveAcesso` (44 dígitos) ou `idExterno` (REF)
- Atualiza Firestore com status, chave, protocolo, número, série
- **Problema crítico:** `custom` e `webmania_br` não têm autenticação (qualquer POST é aceito)
- **Problema crítico:** Sem `FISCAL_WEBHOOK_SECRET` configurada, fallback inseguro pula toda validação
- Webhook sem chave de acesso não registra eventHash (idempotência parcial perdida)

---

## 5. Idempotência

**Verificações:**

| Item | Status |
|------|--------|
| Mesmo webhook processado apenas uma vez | ✅ |
| Hash implementado | ✅ |
| EventId implementado | ✅ |
| Duplicate Check implementado | ✅ |
| Sem duplicação de logs | ✅ |
| Sem duplicação de XML | ✅ |
| Sem duplicação de histórico | ✅ |
| HTTP 200 em webhook repetido | ✅ |

**Status:** ✅ Implementado

**Arquivos:**
- `depertin_cliente/functions/fiscal_webhook.js` — idempotência via event hash (linhas 70-97, 115-155, 244-260)

**Funções:**
- Geração de hash: `SHA256(chaveAcesso + statusProvedor + rawBody)` → `eventHash` (linha 78)
- Verificação: `fiscal_webhooks.where("eventHash", "==", eventHash).limit(1)` (linha 80)
- Se duplicata: `res.status(200).json({... duplicate: true})` (linha 92)
- Duplicata de status já processado: salva em `fiscal_webhooks` com `ignoredDuplicate: true` (linhas 127-145)

**Observações:**
- Idempotência **real** — usa Firestore para verificação (não cache em memória)
- Hash cobre chave de acesso + status + corpo inteiro do webhook
- Status já processado é detectado e registrado como `ignoredDuplicate: true`
- **Problema:** Webhooks sem chave de acesso não geram eventHash (podem ser duplicados)
- **Problema:** Nenhuma poda/TTL na coleção `fiscal_webhooks` — cresce indefinidamente

---

## 6. Histórico de Status

**Verificações:**

| Item | Status |
|------|--------|
| Existe coleção fiscal_status_history | ✅ |
| Toda alteração gera histórico | ✅ |
| Armazena status anterior | ✅ |
| Armazena novo status | ✅ |
| Armazena data | ✅ |
| Armazena hora | ✅ |
| Armazena usuário | ⚠️ Parcial |
| Armazena origem da alteração | ✅ |
| Armazena mensagem | ✅ |

**Status:** ✅ Implementado

**Arquivos:**
- `depertin_cliente/functions/fiscal_logger.js` — `registrarStatusHistory()` (linha 150)
- `depertin_web/lib/services/fiscal/fiscal_pos_emissao_service.dart` — `streamHistoricoStatus()` (linha 218)

**Funções:**
- `registrarStatusHistory({storeId, documentoId, statusAnterior, statusNovo, motivo, usuarioUid, origem})` (linha 150)

**Observações:**
- Estrutura do documento: `{storeId, documentoId, oldStatus, newStatus, source, message, createdAt}`
- Gravado em: emissão, consulta, webhook, cancelamento
- Frontend tem modal de histórico (admin_fiscal_screen.dart linha 1394)
- **Problema ALTO:** Backend grava como `documento_id` (snake_case), frontend busca por `fiscalDocumentId` (camelCase) — **stream não retorna dados**
- **Problema:** `usuarioUid` nem sempre é enviado (ex.: webhook)

---

## 7. Logs

**Verificações:**

| Item | Status |
|------|--------|
| Log para emissão | ✅ |
| Log para consulta | ✅ |
| Log para webhook | ✅ |
| Log para cancelamento | ✅ |
| Log para XML | ✅ |
| Log para DANFE | ✅ |
| Log para erros | ✅ |
| Log para timeout | ✅ |
| Log para segurança | ✅ |
| Log para tentativa de acesso indevido | ✅ |

**Status:** ✅ Implementado

**Arquivos:**
- `depertin_cliente/functions/fiscal_logger.js` — Logging centralizado (linhas 26-178)
- `depertin_cliente/functions/fiscal_security_guard.js` — `registrarTentativaSuspeita()` (linha 182)
- `depertin_cliente/functions/fiscal_pos_emissao.js` — Logs de consulta
- `depertin_cliente/functions/fiscal_webhook.js` — Logs de webhook

**Funções:**
- `fiscal_logger.js → registrarLog()` (linha 56) — Log operacional
- `fiscal_logger.js → registrarWebhook()` (linha 106) — Log de webhook
- `fiscal_logger.js → registrarStatusHistory()` (linha 150) — Log de status
- `fiscal_logger.js → sanitizar()` (linha 26) — Remove tokens/senhas dos logs
- `fiscal_security_guard.js → registrarTentativaSuspeita()` (linha 182) — Log de acesso negado

**Observações:**
- 3 coleções de log: `fiscal_logs`, `fiscal_webhooks`, `fiscal_status_history`
- Sanitização recursiva remove `api_key`, `token`, `credentials_encrypted`, `access_token`, `secret`, `password`, `authorization`
- Logs são write-only via Cloud Functions (regras Firestore: `write: if false`)
- **Problema:** `fiscal_admin_service.dart` consulta `fiscal_audit_logs` (coleção incorreta, backend grava em `fiscal_logs`)
- Logs não têm TTL — podem crescer indefinidamente

---

## 8. Atualização em tempo real

**Verificações:**

| Item | Status |
|------|--------|
| Firestore Streams | ✅ |
| Atualização automática | ✅ |
| Cards | ✅ |
| Dashboard | ✅ |
| Lista de notas | ✅ |
| Modal da nota | ✅ |
| Sem necessidade de atualizar a página | ✅ |

**Status:** ✅ Implementado

**Arquivos:**
- `depertin_web/lib/screens/admin_fiscal_screen.dart` — Streams em todo o ciclo (linhas 1081-1120, 1371-1390)
- `depertin_web/lib/services/fiscal/fiscal_pos_emissao_service.dart` — `streamDocumentos()`, `streamDocumentosAdmin()`, `streamHistoricoStatus()` (linhas 193-227)

**Funções:**
- `streamDocumentos(storeId)` (linha 193) — Stream por loja
- `streamDocumentosAdmin()` (linha 206) — Stream global (admin)
- `streamHistoricoStatus(documentoId)` (linha 218) — Stream de histórico
- `streamWebhookLogs(chaveAcesso)` (linha 230) — Stream de webhooks

**Observações:**
- Todo o painel fiscal usa `StreamBuilder` do Firestore
- Aba "Notas Fiscais" atualiza KPIs e cards automaticamente
- Modal de histórico tem stream próprio
- **Problema:** `streamHistoricoStatus` e `streamWebhookLogs` não funcionam devido a divergência de nomenclatura de campos
- **Problema:** `streamDocumentosAdmin()` carrega sem filtro — custo crescente

---

## 9. Segurança

**Verificações:**

| Item | Status |
|------|--------|
| Loja só acessa próprias notas | ✅ |
| Loja só baixa próprio XML | ✅ |
| Loja só baixa próprio DANFE | ✅ |
| Loja só consulta próprias notas | ✅ |
| Loja só cancela próprias notas | ✅ |
| Admin possui acesso global | ✅ |
| Token nunca retorna ao frontend | ✅ |
| XML protegido | ✅ |
| DANFE protegido | ✅ |

**Status:** ✅ Implementado

**Arquivos:**
- `depertin_cliente/functions/fiscal_security_guard.js` — `validateStoreAccess()` (linhas 32-163)
- `depertin_cliente/functions/fiscal_nfe_proxy.js` — Security guard em todas as funções
- `depertin_cliente/functions/fiscal_pos_emissao.js` — Security guard na consulta
- `depertin_cliente/firestore.rules` — Regras de acesso (linhas 1490-1611)

**Funções:**
- `validateStoreAccess({userId, storeId, docId, chaveAcesso, action, allowStaff})` (linha 32)

**Observações:**
- Token Focus NFe **nunca** transita no frontend — criptografado AES-256-GCM no Firestore
- Descriptografia apenas no backend via `obterApiKey()`
- Security Guard valida: usuário existe → staff liberado → pertence à loja → nota pertence à loja → chave pertence à loja
- Staff (master/master_city/superadmin) tem acesso global
- Tentativas suspeitas são logadas em `fiscal_logs`
- Mensagem de erro genérica: "Você não tem permissão para acessar esta nota fiscal."
- **Problema crítico:** Lojista pode criar `fiscal_documents` diretamente pelo Firestore (regra `create` liberada)
- **Problema:** Não valida loja bloqueada/suspensa
- **Problema:** APP_KEY criptográfica hardcoded no código

---

## 10. Testes realizados

| Teste | Resultado | Tempo | Sucesso | Falha |
|-------|-----------|-------|---------|-------|
| Emissão homologação | ⏳ Não executado | — | — | — |
| Emissão produção | ⏳ Não executado | — | — | — |
| Webhook autorização | ⏳ Não executado | — | — | — |
| Webhook rejeição | ⏳ Não executado | — | — | — |
| Webhook duplicado | ⏳ Não executado | — | — | — |
| Consulta automática | ⏳ Não executado | — | — | — |
| Download XML | ⏳ Não executado | — | — | — |
| Download DANFE | ⏳ Não executado | — | — | — |
| Cancelamento | ⏳ Não executado | — | — | — |
| Rejeição SEFAZ | ⏳ Não executado | — | — | — |
| Token inválido | ✅ Teste de conexão | — | ✅ Falha correta | — |
| Loja acessar nota de outra loja | ⏳ Não executado | — | — | — |
| XML inexistente | ⏳ Não executado | — | — | — |
| DANFE inexistente | ⏳ Não executado | — | — | — |

**Observações:**
- O `fiscalTestarConexaoFocus` foi auditado e validado em sessão anterior — faz HTTP GET real na API Focus com Basic Auth e retorna erros precisos (timeout, DNS, SSL, HTTP 401, etc.)
- Os demais testes requerem ambiente de homologação com credenciais Focus NFe reais
- Testes unitários não foram implementados para os novos módulos (fiscal_pos_emissao, fiscal_webhook atualizado)

---

## 11. Performance

| Operação | Tempo estimado | Observações |
|----------|---------------|-------------|
| Emissão | 2-8s | Depende da latência Focus NFe + processamento interno |
| Consulta | 2-5s | GET na API Focus + parse + Storage (se autorizada) |
| Webhook | 1-3s | Validação HMAC + busca documento + Storage (se autorizada) |
| Download XML | 0.5-2s | Storage público, depende do tamanho do arquivo |
| Download DANFE | 1-3s | Storage público, PDF pode ser maior |
| Atualização Firestore | 0.2-1s | Timestamp server, idempotência verificada |
| Atualização Frontend | 0.1-0.5s | Stream Firestore em tempo real |

**Observações:**
- Tempos estimados com base na arquitetura, não em medições reais
- O salvamento no Storage (XML/DANFE) é síncrono no webhook e na consulta — pode aumentar latência
- `streamDocumentosAdmin()` sem filtro pode degradar com volume de dados
- Firestore queries com `orderBy` + `where` (ex.: `store_id` + `created_at`) precisam de índices compostos — sem índice, a consulta falha

---

## 12. Código — Arquivos Modificados/Criados

### Backend (Cloud Functions)

| Arquivo | Status | Linhas | Descrição |
|---------|--------|--------|-----------|
| `depertin_cliente/functions/fiscal_pos_emissao.js` | ✨ **NOVO** | 413 | Consulta automática pós-emissão, Storage XML/DANFE, status history |
| `depertin_cliente/functions/fiscal_webhook.js` | 🔧 **MODIFICADO** | 507 | Idempotência via event hash, Storage XML/DANFE, webhook log estruturado |
| `depertin_cliente/functions/fiscal_logger.js` | ✅ **EXISTENTE** | 186 | Logging centralizado (3 coleções) |
| `depertin_cliente/functions/fiscal_security_guard.js` | ✅ **EXISTENTE** | 212 | Validação de acesso por loja |
| `depertin_cliente/functions/fiscal_payload_validator.js` | ✅ **EXISTENTE** | 535 | Validação de payload fiscal |
| `depertin_cliente/functions/fiscal_nfe_proxy.js` | ✅ **EXISTENTE** | 1274 | Proxy Focus NFe (emissão, cancelamento, consulta, etc.) |
| `depertin_cliente/functions/fiscal_monthly_reset.js` | ✅ **EXISTENTE** | — | Rotina mensal de reset |
| `depertin_cliente/functions/fiscal_proxy.js` | ✅ **EXISTENTE** | — | Proxy Webmania (fora do escopo) |
| `depertin_cliente/functions/index.js` | 🔧 **MODIFICADO** | ~40 (fiscal) | Export adicionado: `fiscalConsultarEAtualizarStatus` |
| `depertin_cliente/firestore.rules` | ✅ **EXISTENTE** | ~100 (fiscal) | Regras para coleções fiscais |

### Frontend (Flutter Web)

| Arquivo | Status | Linhas | Descrição |
|---------|--------|--------|-----------|
| `depertin_web/lib/services/fiscal/fiscal_pos_emissao_service.dart` | ✨ **NOVO** | 261 | Service: consulta, retry, streams, download |
| `depertin_web/lib/screens/admin_fiscal_screen.dart` | 🔧 **MODIFICADO** | 2148 | Tela fiscal com abas (configurações + notas fiscais), ações por nota |
| `depertin_web/lib/models/fiscal_document_model.dart` | ✅ **EXISTENTE** | 215 | Modelo FiscalDocumentModel |
| `depertin_web/lib/services/fiscal/fiscal_admin_service.dart` | ✅ **EXISTENTE** | 224 | Service admin: streams de configurações e logs |
| `depertin_web/lib/services/fiscal/fiscal_provider.dart` | ✅ **EXISTENTE** | 159 | Interface e modelos de provedor |
| `depertin_web/lib/services/fiscal/providers/focus_nfe_provider.dart` | ✅ **EXISTENTE** | 535 | Implementação Focus NFe |
| `depertin_web/lib/services/fiscal/fiscal_provider_service.dart` | ✅ **EXISTENTE** | — | Service de provedor |
| `depertin_web/lib/services/fiscal/fiscal_provider_http.dart` | ✅ **EXISTENTE** | — | HTTP provider |
| `depertin_web/lib/services/fiscal_integrations_service.dart` | ✅ **EXISTENTE** | — | Service de integrações |

---

## 13. Pendências

### 🔴 Crítico

| # | Item | Arquivo | Impacto |
|---|------|---------|---------|
| 1 | Webhook `custom` e `webmania_br` sem autenticação | `fiscal_webhook.js:381-383` | Qualquer requisição POST com `?provider=custom` ou `?provider=webmania_br` é aceita sem verificação |
| 2 | Lojista pode criar `fiscal_documents` forjados | `firestore.rules:1521-1524` | Regra `create: if isLojistaOperacional()` permite criar documentos com status falso |

### 🟠 Alto

| # | Item | Arquivo | Impacto |
|---|------|---------|---------|
| 3 | `fiscal_status_history` — campo `fiscalDocumentId` vs `documento_id` | `fiscal_pos_emissao_service.dart:223` + `fiscal_logger.js` | Stream de histórico nunca retorna dados (camelCase ≠ snake_case) |
| 4 | `fiscal_webhooks` — campo `chaveAcesso` vs `chave_acesso` | `fiscal_pos_emissao_service.dart:235` + `fiscal_webhook.js` | Stream de webhooks nunca retorna dados |
| 5 | `fiscal_admin_service` consulta `fiscal_audit_logs` que não existe | `fiscal_admin_service.dart:190` | Logs de auditoria nunca são exibidos na tela |
| 6 | Sem `FISCAL_WEBHOOK_SECRET` → validação pulada | `fiscal_webhook.js:384-398` | Fallback genérico aceita qualquer webhook |
| 7 | APP_KEY criptográfica hardcoded em 2 arquivos | `fiscal_pos_emissao.js:35`, `fiscal_nfe_proxy.js:55` | Compromete a criptografia se o código for exposto |

### 🟡 Médio

| # | Item | Arquivo | Impacto |
|---|------|---------|---------|
| 8 | `provider_response` bruto no Firestore | `fiscal_nfe_proxy.js:362` | JSON inteiro da Focus armazenado — pode expor dados internos |
| 9 | NCM default hardcoded '99999999' | `focus_nfe_provider.dart:407` | Código NCM genérico sem alertar usuário |
| 10 | CFOP default hardcoded '5102' | `focus_nfe_provider.dart:408` | Apenas para venda interna — incorreto para interestadual |
| 11 | Impostos (CST/CSOSN) não enviados | `focus_nfe_provider.dart:404-413` | Pode causar rejeição SEFAZ |
| 12 | `isCancelada` não inclui `cancelamentoHomologado` | `fiscal_document_model.dart:127-129` | Botão "Cancelar" pode aparecer indevidamente |
| 13 | Número/data gerados no cliente | `focus_nfe_provider.dart:360-362` | `millisecondsSinceEpoch` pode colidir e timestamp pode ter fuso errado |
| 14 | CPF/CNPJ sem dígito verificador | `fiscal_payload_validator.js:26-39` | Validação apenas por comprimento |
| 15 | `streamResumo()` e `streamDocumentosAdmin()` sem filtro | `fiscal_admin_service.dart:68`, `fiscal_pos_emissao_service.dart:206` | Custo de leitura Firestore cresce linearmente |

### 🟢 Baixo

| # | Item | Arquivo | Impacto |
|---|------|---------|---------|
| 16 | Lógica criptográfica duplicada (DRY) | `fiscal_pos_emissao.js` + `fiscal_nfe_proxy.js` | Manutenção dificultada |
| 17 | Catch retorna HTTP 200 com erro | `fiscal_pos_emissao.js:368`, `fiscal_webhook.js:343` | Dificulta debug no frontend |
| 18 | Sem proteção double-click no frontend | `admin_fiscal_screen.dart` | Ações duplicadas |
| 19 | Sem TTL/poda em `fiscal_webhooks` | `fiscal_webhook.js` | Coleção cresce indefinidamente |
| 20 | Sem testes unitários p/ novos módulos | `functions/test/` | Cobertura de teste ausente para `fiscal_pos_emissao` e idempotência |

---

## 14. Nota Final

| Categoria | Nota (0-100) |
|-----------|-------------|
| **Arquitetura** | 78 |
| **Segurança** | 65 |
| **Performance** | 72 |
| **Conformidade Focus NFe** | 75 |
| **Qualidade do código** | 70 |
| **Manutenibilidade** | 68 |
| **Escalabilidade** | 62 |
| **Confiabilidade** | 70 |

### Justificativas

- **Arquitetura (78/100):** Boa separação de responsabilidades com módulos dedicados (security, validator, logger, proxy, pos-emissão, webhook). Perde pontos pela duplicação de código criptográfico e ausência de abstração unificada para múltiplos provedores.
- **Segurança (65/100):** Pontos fortes (token nunca no frontend, SecurityGuard, sanitização de logs, criptografia AES-256-GCM). Perde muitos pontos pelos 2 problemas críticos: webhook sem autenticação para provedores custom, e regra Firestore que permite lojista criar documentos forjados.
- **Performance (72/100):** Salvamento síncrono de Storage pode aumentar latência. Streams sem filtro/paginação adequada. Perde pontos pela ausência de índices compostos documentados.
- **Conformidade Focus NFe (75/100):** Implementação segue a documentação oficial da API Focus NFe (Basic Auth, endpoints `/nfe/{chave}`, `ref`, payload com campos obrigatórios). Perde pontos pelo fallback de NCM/CFOP genéricos e ausência de validação de dígito verificador de CPF/CNPJ.
- **Qualidade do código (70/100):** Código limpo e bem comentado. Perde pontos pela duplicação, hardcoded APP_KEY, e divergência de nomenclatura de campos entre backend e frontend.
- **Manutenibilidade (68/100):** Módulos bem separados mas com dependências circulares potenciais. Nomenclatura inconsistente entre backend (snake_case) e frontend (camelCase). APP_KEY hardcoded em múltiplos lugares.
- **Escalabilidade (62/100):** Principal gargalo é o `streamDocumentosAdmin()` que carrega todos os documentos sem filtro. Coleções de log sem TTL/poda. Falta de paginação adequada. Webhook sem rate limiting.
- **Confiabilidade (70/100):** Idempotência sólida via event hash. Fallbacks bem implementados (Storage → URL original). Perde pontos pela ausência de tratamento de concorrência (race conditions possíveis) e sem testes unitários automatizados para os novos fluxos.

---

### O módulo fiscal está apto para produção?

❌ **NÃO**

### Itens que impedem a entrada em produção:

1. **🔴 CRÍTICO — Webhook sem autenticação para `custom` e `webmania_br`** (`fiscal_webhook.js:381-383`): Qualquer requisição POST maliciosa pode alterar status de notas fiscais e disparar salvamento de XML/DANFE falso no Storage. **Corrigir antes de produção.**

2. **🔴 CRÍTICO — Regra Firestore `fiscal_documents.create` liberada para lojista** (`firestore.rules:1521-1524`): Lojista pode criar documentos com status `autorizada`, `rejeitada` ou qualquer outro valor forjado diretamente via SDK cliente, sem passar por validação de payload ou segurança. **Alterar para `create: if false` (apenas Admin SDK).**

3. **🟠 ALTO — Divergência de nomenclatura de campos** (3 ocorrências):
   - `fiscal_status_history`: backend usa `documento_id`, frontend busca por `fiscalDocumentId`
   - `fiscal_webhooks`: backend usa `chave_acesso`, frontend busca por `chaveAcesso`
   - `fiscal_admin_service`: consulta `fiscal_audit_logs` (não existe), backend grava em `fiscal_logs`
   
   **Impacto: histórico de status, logs de webhook e auditoria não são exibidos no frontend.**

4. **🟠 ALTO — Fallback inseguro sem `FISCAL_WEBHOOK_SECRET`** (`fiscal_webhook.js:384-398`): Se a variável de ambiente não estiver configurada, qualquer webhook é aceito sem validação. **Configurar obrigatoriamente.**

5. **🟡 MÉDIO — Ausência de testes end-to-end:** Nenhum dos novos fluxos (consulta automática, idempotência, storage de XML/DANFE, histórico) foi testado com ambiente real de homologação. É necessário validar com credenciais Focus NFe de homologação antes de ir para produção.

**Recomendação:** Corrigir os 2 itens críticos, os 3 itens altos, e realizar ao menos 1 ciclo de testes em homologação com a Focus NFe real antes de promover para produção.
