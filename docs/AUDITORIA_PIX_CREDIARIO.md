# Auditoria do Fluxo PIX — Pagamento Crediário (Renegociação de Dívida)

> **Data:** 30/jun/2026
> **Módulo:** Gestão Comercial → Crediário → Renegociação de Dívida → Efetuar Pagamento → PIX
> **Arquivos auditados:** `pagamento_crediario.js`, `comercial_renegociar_divida_modal.dart`, `gestao_comercial_functions.js`
> **Gateway:** Mercado Pago (configurado por loja em `gestao_comercial_configuracoes/{lojaId}.pagamentos.mercado_pago`)

---

## 1. Endpoint da API para criar cobrança PIX

**Endpoint oficial Mercado Pago:**

```
POST https://api.mercadopago.com/v1/payments
```

**Headers:**
```
Authorization: Bearer {access_token_da_loja}
Content-Type: application/json
X-Idempotency-Key: {uuid_v4}
```

---

## 2. Código do backend que faz a requisição

**Arquivo:** `depertin_cliente/functions/pagamento_crediario.js`
**Função:** `exports.gerarCobrancaPixCrediario` (linha 368)

```javascript
const paymentPayload = {
    transaction_amount: Math.round(valor * 100) / 100,
    description: descricao || "Pagamento crediário",
    payment_method_id: "pix",
    payer: {
        email: emailPayer,
        first_name: (clienteNome || "Cliente")
            .replace(/[^a-zA-ZÀ-ÿ\s]/g, "")
            .substring(0, 40)
            .trim() || "Cliente",
        identification: {
            type: "CPF",
            number: cpfLimpo,
        },
    },
    date_of_expiration: new Date(
        Date.now() + 5 * 60 * 1000
    ).toISOString(),
    external_reference: cobrancaId,
    notification_url:
        "https://southamerica-east1-depertin-f940f.cloudfunctions.net/gestaoComercialConfirmarPagamentoMpToken",
};

const mpResponse = await fetch(MP_API + "/v1/payments", {
    method: "POST",
    headers: {
        Authorization: "Bearer " + mpCreds.accessToken,
        "Content-Type": "application/json",
        "X-Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify(paymentPayload),
});
```

O `access_token` vem do gateway configurado pelo lojista em **Banco e Pagamento** → integração Mercado Pago (`gestao_comercial_configuracoes/{lojaId}.pagamentos.mercado_pago.token`). Fallback para o gateway global do marketplace (`gateways_pagamento/mercado_pago.access_token`).

---

## 3. Resposta JSON completa da API

A resposta oficial do Mercado Pago `POST /v1/payments` é recebida em `mpData` (linha 459). O backend **salva integralmente** no Firestore e retorna **apenas os campos relevantes** ao frontend.

### O que é salvo em `cobrancas_pix_crediario/{cobrancaId}`:

```javascript
// Firestore document — TODOS os campos extraídos da resposta MP:
{
    loja_id: "string",
    cliente_id: "string",
    cliente_nome: "string",
    cliente_cpf: "12345678909",         // CPF limpo
    valor: 6.58,                         // number
    mp_payment_id: 123456789,            // number — ID do pagamento no MP
    mp_status: "pending",                // string — status atual no MP
    mp_status_detail: "pending_waiting_transfer", // string — detalhe do status
    qr_code: "00020126580014br.gov.bcb.pix0136...", // string — EMV completo (copia e cola)
    qr_code_base64: "iVBORw0KGgoAAAANSUhEUg...",   // string — imagem QR em base64
    ticket_url: "https://www.mercadopago.com/...",   // string — URL do ticket (opcional)
    copia_cola: "00020126580014br.gov.bcb.pix0136...", // string — mesmo conteúdo do qr_code
    criado_em: Timestamp,                // timestamp — momento da criação
    status: "pending",                   // string — status interno (pending/approved/expired)
    idempotency_key: "uuid-v4-string",   // string — chave de idempotência
    email_payer: "crediario_abc123@pg.dipertin.com.br", // string — email fictício do pagador
}
```

### O que é retornado ao frontend (`gerarCobrancaPixCrediario` response):

```json
{
    "id": "crediario_a1b2c3d4",
    "mp_payment_id": 123456789,
    "status": "pending",
    "copia_cola": "00020126580014br.gov.bcb.pix0136...",  // EMV completo retornado pela API
    "qr_code": "iVBORw0KGgoAAAANSUhEUg...",              // base64 retornado pela API
    "ticket_url": "https://www.mercadopago.com/...",
    "valor": 6.58,
    "criado_em": { "_seconds": 1770321000, "_nanoseconds": 0 }
}
```

---

## 4. QR Code: direto da API ou gerado localmente?

**O QR Code exibido na tela vem DIRETAMENTE da API do Mercado Pago.**

O campo `qr_code_base64` (`point_of_interaction.transaction_data.qr_code_base64`) é extraído da **resposta oficial da API do Mercado Pago** (linha 473):

```javascript
qr_code_base64: mpData.point_of_interaction?.transaction_data?.qr_code_base64 || "",
```

O frontend recebe como `data['qr_code']` (linha 488 do backend, linha 4183 do frontend) e exibe com:

```dart
// comercial_renegociar_divida_modal.dart:3725-3731
child: _pixQrCodeBase64.isNotEmpty
    ? Image.memory(
        base64Decode(_pixQrCodeBase64),  // ← decodifica o base64 da API
        fit: BoxFit.contain,
        width: 220,
        height: 220,
        gaplessPlayback: true,
      )
```

**Conclusão:** O sistema NÃO gera QR Code localmente. Ele exibe exatamente a imagem (`qr_code_base64`) retornada pela API do Mercado Pago. A única validação é se a string não está vazia.

---

## 5. Código "Pix Copia e Cola": da API ou montado pelo sistema?

**O código "Pix Copia e Cola" é exatamente o campo retornado pela API do Mercado Pago.**

O campo `qr_code` (`point_of_interaction.transaction_data.qr_code`) — que é o EMV/BR Code completo — vem da API (linha 472):

```javascript
qr_code: mpData.point_of_interaction?.transaction_data?.qr_code || "",
copia_cola: mpData.point_of_interaction?.transaction_data?.qr_code || "",
```

O frontend recebe como `data['copia_cola']` (linha 4182) e exibe o valor **exatamente como retornado**, sem truncar, modificar ou reconstruir.

**Conclusão:** O sistema NÃO monta o código Pix manualmente. Exibe exatamente o EMV/BR Code retornado pela API do Mercado Pago (`point_of_interaction.transaction_data.qr_code`).

---

## 6. ID da transação (payment_id)

O ID da transação é o `mpData.id` retornado pela API do Mercado Pago (um número inteiro, ex.: `123456789`).

**Salvo em Firestore como:** `cobrancas_pix_crediario/{cobrancaId}.mp_payment_id`
**Retornado ao frontend como:** `data['mp_payment_id']`

**Estrutura:**
- No backend (linha 469): `mp_payment_id: mpData.id`
- No frontend (linha 4184): `_pixTransacaoId = data['mp_payment_id']?.toString() ?? data['id'] ?? ''`
- Na consulta de status (`consultarCobrancaPixCrediario`, linha 559): `GET /v1/payments/{mp_payment_id}`

---

## 7. Como o backend confirma o pagamento PIX?

Existem **dois mecanismos** de confirmação:

### 7.1. Webhook (Mercado Pago → Cloud Function)

- **URL registrada no payload PIX:** `https://southamerica-east1-depertin-f940f.cloudfunctions.net/gestaoComercialConfirmarPagamentoMpToken`
- **Função:** `exports.gestaoComercialConfirmarPagamentoMpToken` em `gestao_comercial_functions.js` (linha 4353)
- **Funcionamento:** MP envia POST com `{ action, data: { id } }` → função consulta `GET /v1/payments/{id}` → se `approved`, baixa parcelas

### ⚠️ INCOMPATIBILIDADE IDENTIFICADA:

O webhook `gestaoComercialConfirmarPagamentoMpToken` usa `_processarConfirmacaoPagamentoToken` que busca a cobrança na coleção **`gestao_comercial_tokens_pagamento`**.

Já o fluxo de crediário (`gerarCobrancaPixCrediario`) salva a cobrança em **`cobrancas_pix_crediario`**.

**Isso significa que o webhook NÃO consegue encontrar a cobrança do crediário automaticamente.** Embora a `notification_url` seja enviada ao MP, o processamento do webhook falha em localizar o documento correto.

### 7.2. Polling ativo (Frontend → Backend → MP)

O **mecanismo realmente funcional** é o polling no frontend:

```
A cada 5 segundos:
  Frontend → consultarCobrancaPixCrediario (callable)
    → Backend → GET https://api.mercadopago.com/v1/payments/{mp_payment_id}
    → Backend analisa status: "approved" → "aprovado"
    → Frontend detecta "aprovado" → chama efetuarPagamentoCrediario
```

Fluxo completo (`comercial_renegociar_divida_modal.dart`, linha 4229):

```dart
// Polling de 5s
_pixPollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
    // Chama consultarCobrancaPixCrediario
    // Se status == 'aprovado':
    //   1. Cancela timers
    //   2. Chama _confirmarPagamentoComDados()
    //   3. Que chama efetuarPagamentoCrediario (callable)
    //   4. Mostra comprovante
    // Se passou 5 minutos sem aprovação:
    //   Marca como expirado e permite gerar nova cobrança
});
```

---

## 8. Após confirmação, como as parcelas são baixadas?

**Função:** `exports.efetuarPagamentoCrediario` em `pagamento_crediario.js` (linha 111)

Esta função executa uma **transação (`runTransaction`)** que atualiza **7 coleções de forma atômica**:

| Passo | Coleção | Ação |
|-------|---------|------|
| 2a | `clientes_comercial/{clienteId}/parcelas/{parcelaId}` | Marca `status: "pago"`, `valor_em_aberto: 0`, `data_pagamento`, `protocolo_pagamento` |
| 2b | `clientes_comercial/{clienteId}` | Atualiza `total_em_aberto`, `qtd_parcelas_em_aberto`, `total_pago_historico`, `ultimo_pagamento_*`, `credito_utilizado` |
| 2c | `recebimentos_cliente/{autoId}` | Cria registro de recebimento com todos os detalhes |
| 2d | `historico_financeiro_cliente/{autoId}` | Cria registro no histórico financeiro |
| 2e | `historico_vendas/{autoId}` | Cria registro de venda |
| 2f | `dashboard_comercial/{lojaId}` | Atualiza `total_recebido_hoje/mes`, `qtd_recebimentos_hoje/mes` |
| 2g | `audit_logs/{autoId}` | Registra log de auditoria |

```javascript
const resultado = await db.runTransaction(async (transaction) => {
    // 2a. Marcar parcelas como pagas
    for (const doc of parcelasSnap.docs) {
        transaction.update(doc.ref, {
            status: "pago",
            valor_em_aberto: 0,
            valor_pago: doc.data().valor_em_aberto,
            data_pagamento: agora,
            protocolo_pagamento: protocolo,
            forma_pagamento: forma,
            pagamento_detalhe: dadosPagamento,
            pago_por: usuarioNome,
            pago_uid: uid,
            atualizado_em: agora,
        });
    }
    // 2b-2g: atualiza cliente, recebimentos, histórico, vendas, dashboard, audit
    // ...
});
```

---

## Resumo da Arquitetura

```
┌──────────────────────────────────────────────────────────────────┐
│                        FRONTEND (Flutter Web)                     │
│                                                                   │
│  comercial_renegociar_divida_modal.dart                            │
│                                                                   │
│  [Gerar PIX]                                                      │
│    ↓ gerarCobrancaPixCrediario (callable)                        │
│    ↓ recebe { qr_code_base64, copia_cola, mp_payment_id }       │
│    ↓ EXIBE QR CODE E COPIA E COLA DIRETOS DA API                 │
│                                                                   │
│  Polling a cada 5s:                                               │
│    ↓ consultarCobrancaPixCrediario (callable)                     │
│    ↓ backend consulta GET /v1/payments/{id} no MP                │
│    ↓ status "approved"? → efetuarPagamentoCrediario (callable)   │
│    ↓ → backend baixa parcelas em transação (7 coleções)          │
│                                                                   │
│  Webhook (também registrado mas com INCOMPATIBILIDADE):           │
│    MP → gestaoComercialConfirmarPagamentoMpToken                 │
│    → busca em gestao_comercial_tokens_pagamento                   │
│    → cobrança salva em cobrancas_pix_crediario                    │
│    → NÃO ENCONTRA (coleção diferente)                             │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                   BACKEND (Cloud Functions)                       │
│                                                                   │
│  pagamento_crediario.js                                           │
│  ├── gerarCobrancaPixCrediario → POST /v1/payments               │
│  ├── consultarCobrancaPixCrediario → GET /v1/payments/{id}       │
│  └── efetuarPagamentoCrediario → transação Firestore             │
│                                                                   │
│  gestao_comercial_functions.js                                    │
│  └── gestaoComercialConfirmarPagamentoMpToken (webhook)           │
│      → _processarConfirmacaoPagamentoToken                        │
│      → busca em gestao_comercial_tokens_pagamento                 │
│      → (INCOMPATÍVEL com crediário)                               │
└──────────────────────────────────────────────────────────────────┘
```

## Conclusões

| Pergunta | Resposta |
|----------|----------|
| PIX gerado por API oficial? | **Sim.** Chama `POST https://api.mercadopago.com/v1/payments` do Mercado Pago. |
| QR Code é direto da API? | **Sim.** `qr_code_base64` vindo da resposta MP é exibido sem modificações. |
| Pix Copia e Cola é direto da API? | **Sim.** `qr_code` (EMV) vindo da resposta MP é exibido sem modificações. |
| ID da transação é real? | **Sim.** `mpData.id` da API MP. |
| Confirmação é via webhook? | **Não funcional para crediário.** O webhook busca em coleção errada (`gestao_comercial_tokens_pagamento` vs `cobrancas_pix_crediario`). |
| Confirmação funcional atual? | **Polling frontend a cada 5s** → `consultarCobrancaPixCrediario` → quando `approved`, chama `efetuarPagamentoCrediario`. |
| Baixa de parcelas é automática? | **Sim, via backend.** `efetuarPagamentoCrediario` executa transação atômica em 7 coleções. |

> **Observação:** A incompatibilidade do webhook (item 7.1) significa que, se o frontend fechar o modal antes do polling detectar o status `approved`, o pagamento não será baixado automaticamente. O webhook deveria buscar também em `cobrancas_pix_crediario` para garantir confirmação mesmo sem frontend aberto.
