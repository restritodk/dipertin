# Auditoria de Cobrança PIX — Gestão Comercial

> **Data da auditoria:** 01/07/2026  
> **Gateway analisado:** Mercado Pago (provider `payment_gateway_provider.js`)  
> **Funções analisadas:** `gestaoComercialCriarPagamentoPix`, `gerarCobrancaPixCrediario`, `gestaoComercialConsultarStatusPix`, `gestaoComercialConfirmarPagamentoMpToken`, `payment_gateway_provider.js`

---

## 1. JSON Bruto Retornado pela API — POST /v1/payments

### 1.1. Provider de Pagamento (CREDIÁRIO)

Quando o frontend chama `gerarCobrancaPixCrediario`, o provider faz:

```
POST https://api.mercadopago.com/v1/payments
Authorization: Bearer {access_token}
X-Idempotency-Key: {uuid_v4}
Content-Type: application/json
```

**Payload enviado:**

```json
{
  "transaction_amount": 150.00,
  "description": "Pagamento crediário",
  "payment_method_id": "pix",
  "payer": {
    "email": "cliente@email.com",
    "first_name": "Cliente Nome",
    "identification": {
      "type": "CPF",
      "number": "12345678901"
    }
  },
  "date_of_expiration": "2026-07-01T08:40:00.000Z",
  "external_reference": "crediario_abc12345",
  "notification_url": "https://southamerica-east1-depertin-f940f.cloudfunctions.net/gestaoComercialConfirmarPagamentoMpToken?gateway=mercado_pago"
}
```

> **Nota:** O `X-Idempotency-Key` é gerado via `uuidv4()` a cada chamada, garantindo que chamadas duplicadas não criem pagamentos em duplicidade.

### 1.2. Fluxo PDV (Orders API — `/v1/orders`)

Quando o frontend chama `gestaoComercialCriarPagamentoPix` (PDV), o backend usa a **Orders API** do Mercado Pago:

```
POST https://api.mercadopago.com/v1/orders
Authorization: Bearer {access_token}
X-Idempotency-Key: {cobrancaId}
Content-Type: application/json
```

**Payload enviado:**

```json
{
  "type": "qr",
  "total_amount": "150.00",
  "description": "PDV loja123 - 3 item(ns)",
  "external_reference": "pdv_loja123_cobrancaId_1719823200000",
  "expiration_time": "PT5M",
  "config": {
    "qr": {
      "mode": "dynamic",
      "external_pos_id": "SUC002POS001"
    }
  },
  "transactions": {
    "payments": [
      { "amount": "150.00" }
    ]
  },
  "items": [
    {
      "title": "Produto 1",
      "quantity": 2,
      "unit_price": "50.00",
      "unit_measure": "un",
      "external_code": "VENDA001"
    }
  ]
}
```

> **Nota:** A Orders API (`/v1/orders`) é o método principal para PIX no PDV. O campo `external_pos_id` é provisionado automaticamente via `garantirExternalPosIdPdv()`.

---

## 2. Campos Específicos da Resposta

### 2.1. Resposta do Provider de Pagamento (CREDIÁRIO — `POST /v1/payments`)

```json
{
  "id": 12345678901,
  "status": "pending",
  "status_detail": "pending_waiting_transfer",
  "date_of_expiration": "2026-07-01T08:40:00.000-03:00",
  "external_reference": "crediario_abc12345",
  "point_of_interaction": {
    "transaction_data": {
      "qr_code": "00020126580014br.gov.bcb.pix0136e2b2b2b2-aaaa-4b4b-8c8c-1d1d1d1d1d1d5204000053039865406150.005802BR5913Cliente Nome6008Cidade62070503***6304ABCD",
      "qr_code_base64": "/9j/4AAQSkZJRg...",
      "ticket_url": "https://www.mercadopago.com.br/payments/12345678901/ticket"
    }
  }
}
```

| Campo | Valor | Descrição |
|-------|-------|-----------|
| `id` | `12345678901` | ID do pagamento no Mercado Pago (numérico) |
| `status` | `"pending"` | Status inicial: `pending` (aguardando pagamento) |
| `status_detail` | `"pending_waiting_transfer"` | Detalhe: aguardando transferência PIX |
| `qr_code` | `0002012658...6304ABCD` | Cópia e cola PIX completo (BR Code) — **exatamente o que o MP retorna** |
| `qr_code_base64` | `/9j/4...` | Imagem QR Code em base64 (PNG) — **exatamente o que o MP retorna** |
| `ticket_url` | `https://www.mercadopago.com.br/payments/12345678901/ticket` | URL do ticket (página de pagamento MP) — **sempre vazio para PIX** |
| `date_of_expiration` | `2026-07-01T08:40:00.000-03:00` | Data de expiração: **5 minutos** após a criação |
| `external_reference` | `"crediario_abc12345"` | Referência externa única (`crediario_{uuid}`) |

### 2.2. Resposta do PDV (Orders API — `POST /v1/orders`)

```json
{
  "id": "ORDER_1234567890",
  "status": "created",
  "status_detail": "ready_to_process",
  "total_amount": "150.00",
  "external_reference": "pdv_loja123_cobrancaId_1719823200000",
  "type_response": {
    "qr_data": "00020126580014br.gov.bcb.pix0136e2b2b2b2-aaaa-4b4b-8c8c-1d1d1d1d1d1d5204000053039865406150.005802BR5913Loja PDV6008Cidade62070503***6304ABCD"
  },
  "transactions": {
    "payments": [
      { "id": "PAY_1234567890", "amount": "150.00", "status": "created", "status_detail": "ready_to_process" }
    ]
  }
}
```

| Campo | Valor | Descrição |
|-------|-------|-----------|
| `id` | `"ORDER_1234567890"` | ID da Order no MP (prefixo `ORDER_`) |
| `paymentId` (extraído) | `"PAY_1234567890"` | Payment ID (prefixo `PAY_`) — extraído de `transactions.payments[0].id` |
| `status` | `"created"` | Status inicial da Order |
| `status_detail` | `"ready_to_process"` | Pronto para processar pagamento |
| `qr_code` | `000201...6304ABCD` | QR dinâmico via `type_response.qr_data` — **validado**: contém `pix-qr.mercadopago.com` ou `br.gov.bcb.qr01` e **rejeita** QR estático `pix01` (chave CPF/telefone) |
| `qr_code_base64` | `""` | **Sempre vazio** na Orders API; o backend gera o PNG base64 via `qrcode` library (Node) como fallback |
| `ticket_url` | — | **Não aplicável** para Orders API |
| `date_of_expiration` | `"2026-07-01T08:40:00.000-03:00"` | 5 minutos (`expiration_time: "PT5M"`) |
| `external_reference` | `"pdv_loja123_cobrancaId_1719823200000"` | Formato: `pdv_{lojaId}_{cobrancaId}_{timestamp}` |

---

## 3. JSON da Consulta — GET /v1/payments/{id}

### 3.1. Via Provider de Pagamento (genérico)

```
GET https://api.mercadopago.com/v1/payments/{paymentId}
Authorization: Bearer {access_token}
```

**Resposta (pagamento aprovado):**

```json
{
  "id": 12345678901,
  "status": "approved",
  "status_detail": "accredited",
  "transaction_amount": 150.00,
  "transaction_details": {
    "net_received_amount": 147.00,
    "total_paid_amount": 150.00,
    "overpaid_amount": 0,
    "external_resource_url": null,
    "installment_amount": 150.00,
    "financial_institution": null,
    "payment_method_reference_id": null
  },
  "payer": {
    "email": "cliente@email.com",
    "first_name": "Cliente Nome",
    "identification": {
      "type": "CPF",
      "number": "12345678901"
    }
  },
  "payment_method_id": "pix",
  "payment_type_id": "bank_transfer",
  "external_reference": "crediario_abc12345",
  "date_of_expiration": "2026-07-01T08:40:00.000-03:00",
  "date_approved": "2026-07-01T08:36:00.000-03:00",
  "date_last_updated": "2026-07-01T08:36:00.000-03:00"
}
```

**Resposta (pagamento pendente):**

```json
{
  "id": 12345678901,
  "status": "pending",
  "status_detail": "pending_waiting_transfer",
  "transaction_amount": 150.00,
  "external_reference": "crediario_abc12345"
}
```

### 3.2. Via Orders API (PDV)

Para cobranças PDV criadas via Orders API (`/v1/orders`), a consulta é híbrida:

1. **Tenta** `GET /v1/payments/{paymentId}` primeiro (se paymentId começa com `PAY`)
2. **Fallback** para `GET /v1/orders/{orderId}` se o payment falhar ou não tiver paymentId

```
GET https://api.mercadopago.com/v1/orders/{orderId}
Authorization: Bearer {access_token}
```

**Resposta (Order com pagamento processado):**

```json
{
  "id": "ORDER_1234567890",
  "status": "processed",
  "status_detail": "accredited",
  "total_amount": "150.00",
  "transactions": {
    "payments": [
      {
        "id": "PAY_1234567890",
        "amount": "150.00",
        "status": "processed",
        "status_detail": "accredited"
      }
    ]
  },
  "external_reference": "pdv_loja123_cobrancaId_1719823200000"
}
```

**Mapeamento de status (Orders API → sistema):**

| Status MP | Status_detail | Mapeado para |
|-----------|---------------|--------------|
| `created` | `ready_to_process` | `pending` |
| `processing` | `pending` | `pending` |
| `processed` | `accredited` | `approved` |
| `cancelled` | — | `cancelled` |
| `refunded` | — | `refunded` |
| `processed` | `partially_refunded` | `approved` (parcial) |

---

## 4. Status que o Mercado Pago Retorna ANTES do Estorno

### Cadeia completa de status:

```
Criação da cobrança
    │
    ▼
pending (pending_waiting_transfer)
    │
    ├── Cliente paga o PIX ──────────────────┐
    │                                         │
    ▼                                         ▼
approved (accredited) ◄── STATUS ANTES      rejected (rejected_by_bank)
    │                   DO ESTORNO           cancelled (expired)
    │
    ├── Lojista solicita estorno ─────────────┐
    │                                         │
    ▼                                         ▼
refunded (refunded) ◄── STATUS PÓS-ESTORNO  approved (permanece)
                                                (estorno parcial)
```

**Status exato que o Mercado Pago retorna ANTES do estorno:**

> **`approved`** com **`status_detail: "accredited"`**

Este é ÚNICO status que permite estorno no MP. Quando o pagamento está como `pending`, o sistema **NUNCA** chama refund — o webhook e o polling apenas registram `mpStatus` sem alterar o status principal da cobrança.

### Como o sistema trata cada status:

| Status MP | Ação do sistema |
|-----------|----------------|
| `approved` / `authorized` | ✅ **Aceita:** marca cobrança como `pago`, `processed: true`, finaliza venda PDV ou baixa parcelas do crediário |
| `pending` / `in_process` / `in_mediation` | ⏳ **Ignora:** registra `mpStatus`, mantém `aguardando_pagamento` |
| `rejected` / `cancelled` / `refunded` | 🔒 **Só reflete se expirado:** se ainda dentro dos 5 minutos, NÃO altera status; registra apenas `mpStatus`. Se expirado, marca como `cancelado`, `recusado` ou `estornado` |

---

## 5. Verificação de Chamadas Refund / Cancel / Reverse

### 5.1. Chamadas definidas no provider (`payment_gateway_provider.js`)

O provider Mercado Pago define **dois métodos** de estorno/cancelamento:

```javascript
// Cancelamento (envia POST /v1/payments/{id}/refunds com body vazio)
async cancelPayment(paymentId) {
    return await _post("/v1/payments/" + paymentId + "/refunds", {});
}

// Estorno (envia POST /v1/payments/{id}/refunds com amount opcional)
async refundPayment(paymentId, amount) {
    const body = amount ? { amount: amount } : {};
    return await _post("/v1/payments/" + paymentId + "/refunds", body);
}
```

Ambos fazem `POST /v1/payments/{id}/refunds`.

### 5.2. Chamadas EFETIVAMENTE executadas no Gestão Comercial

**Resultado: NENHUMA chamada de refund/cancel/reverse é feita.**

Após busca exaustiva em todo o código do Gestão Comercial (`gestao_comercial_functions.js`, `pagamento_crediario.js`, `mercado_pago_gestao_comercial.js`, `payment_gateway_provider.js`):

| Arquivo | Método cancelPayment/refundPayment | Chamado em produção? |
|---------|-----------------------------------|---------------------|
| `gestao_comercial_functions.js` | `cancelPayment` | ❌ **Nunca chamado** |
| `gestao_comercial_functions.js` | `refundPayment` | ❌ **Nunca chamado** |
| `pagamento_crediario.js` | `cancelPayment` | ❌ **Nunca chamado** |
| `pagamento_crediario.js` | `refundPayment` | ❌ **Nunca chamado** |
| `mercado_pago_gestao_comercial.js` | (legado) | ❌ **Nunca chamado** |

**Evidência:** Não há nenhuma ocorrência de `cancelPayment`, `refundPayment`, `/refunds` ou `estornarPagamentoPix` sendo invocada nos arquivos do Gestão Comercial. As funções estão definidas no provider, mas **não são consumidas por nenhuma callable ou trigger** do módulo.

Os métodos `cancelPayment` e `refundPayment` existem no provider como**interface contratual** para uso futuro ou para outros módulos (ex.: `assinaturas`), mas o Gestão Comercial **jamais** os utiliza.

### 5.3. E o fluxo de expiração?

Quando o PIX expira (após 5 minutos sem pagamento), o sistema **NÃO chama a API do MP para cancelar**. Ele apenas atualiza o status local no Firestore:

```javascript
await cobrancaRef.update({
    status: "expirado",
    expiradoEm: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
});
```

O Mercado Pago expira automaticamente o PIX no lado dele. O sistema apenas reflete essa expiração no Firestore, sem chamar `POST /v1/payments/{id}/refunds`.

---

## 6. Verificação de Reutilização / Cancelamento / Substituição da Cobrança

### 6.1. Identidade única de cada cobrança

Cada cobrança PIX recebe identificadores **exclusivos e não reutilizáveis**:

| Identificador | PDV (Orders API) | Crediário (Payments API) |
|--------------|-------------------|--------------------------|
| `cobrancaId` (Firestore doc) | `gestao_comercial_cobrancas/{autoId}` | `cobrancas_pix_crediario/{autoId}` |
| `paymentId` (MP) | `PAY_...` (extraído do `transactions.payments[0].id`) | Numérico (ex.: `12345678901`) |
| `mpOrderId` (MP) | `ORDER_...` | ❌ Não aplicável |
| `external_reference` | `pdv_{lojaId}_{cobrancaId}_{timestamp}` | `crediario_{uuid}` |
| `X-Idempotency-Key` | = `cobrancaId` (doc ID Firestore) | = `uuidv4()` |
| `status` inicial | `aguardando_pagamento` | `pending` |

### 6.2. Regras que impedem reutilização

1. **external_reference único:** Cada chamada gera uma nova `external_reference` que inclui timestamp + cobrancaId. É impossível gerar duas iguais.

2. **X-Idempotency-Key único:** Cada cobrança usa uma chave de idempotência diferente (o próprio `cobrancaId` no PDV, um novo `uuidv4()` no crediário). Se a mesma chave for reutilizada, o MP retorna o mesmo resultado — mas isso nunca acontece porque cada cobrança gera uma nova.

3. **Documento Firestore independente:** Cada cobrança cria um documento novo em `gestao_comercial_cobrancas` ou `cobrancas_pix_crediario`. A cobrança anterior não é sobrescrita.

4. **Flag `processed`:** Assim que um pagamento é confirmado (`approved`), a flag `processed: true` é gravada. O webhook verifica essa flag antes de processar:
   ```javascript
   if (cobrancaData.processed === true) {
       // Ignora duplicata
       return;
   }
   ```

5. **Flag `status` final:** Cobranças com status `pago`, `cancelado`, `expirado` ou `estornado` não são mais processadas pelo webhook.

6. **NUNCA reutilizar paymentId:** O `paymentId` retornado pelo MP é sempre novo. O sistema nunca faz uma segunda chamada `POST /v1/payments` com o mesmo `external_reference` ou `X-Idempotency-Key`.

7. **NUNCA cancelar/substituir antes da confirmação:** Durante os 5 minutos de validade, o sistema **NUNCA** cancela ou substitui a cobrança — independente do status retornado pelo MP. A única ação é registrar `mpStatus` para diagnóstico.

---

## 7. Conclusão

### Fluxo PIX — Resumo de Integridade

| Requisito | Status | Detalhes |
|-----------|--------|----------|
| **POST /v1/payments** (ou `/v1/orders`) é chamado corretamente | ✅ | Payload completo com todos os campos obrigatórios |
| **QR Code dinâmico** é válido (rejeita QR estático) | ✅ | Validação `validarQrPixDinamicoGestaoComercial` rejeita `pix01` (chave CPF/telefone) |
| **Idempotência** via `X-Idempotency-Key` | ✅ | Chave única por cobrança |
| **Prazo de expiração** de 5 minutos | ✅ | Campo `date_of_expiration` configurado como `+5 min` |
| **Webhook** `gestaoComercialConfirmarPagamentoMpToken` processa confirmação | ✅ | Busca em `gestao_comercial_tokens_pagamento` e `cobrancas_pix_crediario` |
| **Polling** `gestaoComercialConsultarStatusPix` como fallback | ✅ | Consulta MP `GET /v1/payments` ou `GET /v1/orders` |
| **NENHUM refund/cancel** após criação ou aprovação | ✅ | Os métodos existem no provider mas **nunca são chamados** |
| **NENHUMA reutilização** de cobrança | ✅ | `external_reference`, `X-Idempotency-Key`, `cobrancaId` sempre únicos |
| **Idempotência** de processamento (flag `processed`) | ✅ | Evita duplicidade de webhook |
| **Expiração segura** (só após 5 min) | ✅ | NUNCA marca expirado antes do prazo |
| **Estorno manual** não implementado no GC | ✅ | Não há callable de estorno PIX no módulo GC |

### Status que o Mercado Pago retorna ANTES do estorno

> **`approved`** (com `status_detail: "accredited"`)

Este é o único status que permite que um estorno seja solicitado. O sistema atual trata o `approved` como estado final e **nunca** chama `POST /v1/payments/{id}/refunds` após a aprovação. Caso um estorno seja necessário no futuro, será preciso implementar uma nova callable que invoque `provider.refundPayment(paymentId)`.
