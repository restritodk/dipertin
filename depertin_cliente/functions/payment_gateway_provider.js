"use strict";

/**
 * Payment Gateway Provider System
 *
 * Camada de abstração para múltiplos gateways de pagamento.
 * Cada gateway implementa a mesma interface:
 *   createPixCharge(params)  → { id, qrCode, copiaCola, status }
 *   getPaymentStatus(id)     → { id, status, valorPago }
 *   createCardPayment(params) → { id, status, authorizationCode }
 *   cancelPayment(id)        → { success }
 *   processNotification(body, headers) → { paymentId, externalRef, gateway }
 *
 * Gateways suportados:
 *   mercado_pago, asaas, api_personalizada, e genérico REST
 */

const { v4: uuidv4 } = require("uuid");
const { cpfPagadorValidoParaApi } = require("./pix_emv_validacao");

// ── URLs base ──
const MP_API = "https://api.mercadopago.com";
const ASAAS_API = "https://api.asaas.com";
const ASAAS_SANDBOX = "https://sandbox.asaas.com";

// ──────────────────────────────────────────────────────────
// HTTP helper (usa fetch nativo do Node 18+)
// ──────────────────────────────────────────────────────────
async function _httpRequest(url, options = {}) {
    const resp = await fetch(url, {
        method: options.method || "GET",
        headers: options.headers || { "Content-Type": "application/json" },
        body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const text = await resp.text();
    let data;
    try { data = JSON.parse(text); } catch (_) { data = text; }
    return { ok: resp.ok, status: resp.status, data, text };
}

// ──────────────────────────────────────────────────────────
// PUBLIC API
// ──────────────────────────────────────────────────────────

/**
 * Carrega o gateway ativo da loja.
 * @param {Firestore} db
 * @param {string} lojaId
 * @returns {Promise<{tipo: string, config: object, nome: string}|null>}
 */
async function carregarGatewayAtivo(db, lojaId) {
    const configDoc = await db
        .collection("gestao_comercial_configuracoes")
        .doc(lojaId)
        .get();

    if (!configDoc.exists) return null;

    const pagamentos = (configDoc.data() || {}).pagamentos || {};

    // 1. Tenta gatewayPadrao primeiro
    const padrao = pagamentos.gatewayPadrao;
    if (padrao && padrao.tipo) {
        const integ = pagamentos[padrao.tipo];
        if (integ) {
            const credencial = _extrairCredencial(integ);
            if (credencial) {
                return { tipo: padrao.tipo, config: integ, nome: integ.nome || padrao.tipo };
            }
        }
    }

    // 2. Procura qualquer integração ativa com credenciais
    for (const [key, integ] of Object.entries(pagamentos)) {
        if (key === "gatewayPadrao") continue;
        if (integ.ativo) {
            const credencial = _extrairCredencial(integ);
            if (credencial) {
                return { tipo: key, config: integ, nome: integ.nome || key };
            }
        }
    }

    return null;
}

/**
 * Extrai a credencial principal da integração.
 */
function _extrairCredencial(integ) {
    return (integ.token || integ.accessToken || integ.apiKey || integ.clientSecret || "").trim();
}

/**
 * Cria o provider adequado para o gateway.
 * @param {string} tipo - Chave do gateway (mercado_pago, asaas, api_personalizada, etc.)
 * @param {object} config - Configuração completa da integração
 * @returns {object} Provider com métodos padronizados
 */
function criarProvider(tipo, config) {
    switch (tipo) {
        case "mercado_pago":
            return _criarMpProvider(config);
        case "asaas":
            return _criarAsaasProvider(config);
        default:
            // API Personalizada ou genérico REST (exige apiUrl)
            if (config && config.apiUrl && config.apiUrl.trim()) {
                return _criarCustomProvider(config);
            }
            // Fallback: Mercado Pago (compatibilidade)
            return _criarMpProvider(config);
    }
}

/**
 * Cria a URL do webhook com parâmetro do gateway.
 */
function criarWebhookUrl(tipo) {
    const base = "https://southamerica-east1-depertin-f940f.cloudfunctions.net/gestaoComercialConfirmarPagamentoMpToken";
    return base + "?gateway=" + encodeURIComponent(tipo);
}

// ──────────────────────────────────────────────────────────
// PROVIDER: MERCADO PAGO
// ──────────────────────────────────────────────────────────

function _criarMpProvider(config) {
    const accessToken = config.token || config.accessToken || "";
    const publicKey = config.clientId || config.publicKey || "";

    async function _get(path) {
        const resp = await _httpRequest(MP_API + path, {
            headers: { Authorization: "Bearer " + accessToken },
        });
        if (!resp.ok) throw new Error("MP error " + resp.status + ": " + JSON.stringify(resp.data));
        return resp.data;
    }

    async function _post(path, body, idempotencyKey) {
        const resp = await _httpRequest(MP_API + path, {
            method: "POST",
            headers: {
                Authorization: "Bearer " + accessToken,
                "Content-Type": "application/json",
                "X-Idempotency-Key": idempotencyKey || uuidv4(),
            },
            body,
        });
        if (!resp.ok) {
            const errMsg = typeof resp.data === "object" ? JSON.stringify(resp.data) : resp.text;
            throw new Error("MP error " + resp.status + ": " + errMsg);
        }
        return resp.data;
    }

    return {
        tipo: "mercado_pago",

        /**
         * Cria cobrança PIX — payload alinhado ao marketplace (mpCriarPagamentoPix).
         * O MP monta o BR Code; não enviamos CPF/CNPJ do pagador no PIX (evita QR inválido no app bancário).
         */
        async createPixCharge({
            valor,
            clienteNome,
            clienteCpf,
            clienteEmail,
            descricao,
            externalReference,
            notificationUrl,
            idempotencyKey,
        }) {
            void clienteNome;
            void clienteCpf;

            const refSlug = (externalReference || uuidv4())
                .replace(/[^a-zA-Z0-9]/g, "")
                .substring(0, 12);
            const email = String(clienteEmail || "").trim()
                || ("pg." + refSlug + "@pg.dipertin.com.br");

            // Marketplace (mpCriarPagamentoPix) não envia date_of_expiration — o MP define a validade.
            // Enviar expiração curta aqui fazia o MP cancelar/expirar a cobrança imediatamente em produção.
            const payload = {
                transaction_amount: Math.round(valor * 100) / 100,
                description: descricao || "Pagamento",
                payment_method_id: "pix",
                payer: { email },
                external_reference: externalReference,
            };

            if (notificationUrl) {
                payload.notification_url = notificationUrl;
            }

            const result = await _post("/v1/payments", payload, idempotencyKey || uuidv4());
            const pixData = result.point_of_interaction?.transaction_data || {};

            return {
                id: String(result.id),
                paymentId: result.id,
                status: result.status || "pending",
                qrCode: pixData.qr_code_base64 || "",
                copiaCola: pixData.qr_code || "",
                ticketUrl: pixData.ticket_url || "",
                expiration: result.date_of_expiration,
                raw: result,
            };
        },

        /**
         * Consulta status de pagamento.
         */
        async getPaymentStatus(paymentId) {
            const result = await _get("/v1/payments/" + paymentId);
            return {
                id: String(result.id),
                paymentId: result.id,
                status: result.status || "pending",
                statusDetail: result.status_detail || "",
                valorPago: result.transaction_amount || 0,
                valorRecebido: result.transaction_details?.net_received_amount || 0,
                aprovado: result.status === "approved" || result.status === "authorized",
                pendente: ["pending", "in_process", "waiting_payment"].includes(result.status),
                recusado: ["rejected", "cancelled", "refunded", "charged_back"].includes(result.status),
                raw: result,
            };
        },

        /**
         * Processa notificação webhook e extrai paymentId.
         * Mercado Pago envia: { action, data: { id } }
         */
        processNotification(body) {
            const paymentId = body.data?.id || body.id || "";
            const action = body.action || body.type || "";
            return {
                paymentId: String(paymentId),
                externalRef: body.external_reference || "",
                action,
                isMerchantOrder: String(action).includes("merchant_order"),
            };
        },

        /**
         * Cria pagamento com cartão de crédito (total à vista, sem parcelamento).
         */
        async createCardPayment({
            valor,
            clienteNome,
            clienteCpf,
            clienteEmail,
            cardToken,
            descricao,
            externalReference,
            paymentMethodId,
            installments,
            idempotencyKey,
        }) {
            const cpfPagador = cpfPagadorValidoParaApi(clienteCpf);
            const email = clienteEmail || "pg_" + (externalReference || uuidv4()).replace(/[^a-zA-Z0-9]/g, "").substring(0, 10) + "@pg.dipertin.com.br";

            const payload = {
                transaction_amount: Math.round(valor * 100) / 100,
                description: descricao || "Pagamento cartão de crédito",
                payment_method_id: paymentMethodId || "master",
                token: cardToken,
                installments: Math.max(1, Number(installments) || 1),
                payer: { email, first_name: clienteNome || "Cliente" },
                external_reference: externalReference,
            };

            if (cpfPagador) {
                payload.payer.identification = { type: "CPF", number: cpfPagador };
            }

            const result = await _post("/v1/payments", payload, idempotencyKey || uuidv4());

            return {
                id: String(result.id),
                paymentId: result.id,
                status: result.status || "pending",
                statusDetail: result.status_detail || "",
                authorizationCode: result.authorization_code || "",
                aprovado: result.status === "approved" || result.status === "authorized",
                recusado: result.status === "rejected",
                raw: result,
            };
        },

        /**
         * Cancela um pagamento.
         */
        async cancelPayment(paymentId) {
            return await _post("/v1/payments/" + paymentId + "/refunds", {});
        },

        /**
         * Estorna um pagamento.
         */
        async refundPayment(paymentId, amount) {
            const body = amount ? { amount: Math.round(amount * 100) / 100 } : {};
            return await _post("/v1/payments/" + paymentId + "/refunds", body);
        },
    };
}

// ──────────────────────────────────────────────────────────
// PROVIDER: ASAAS
// ──────────────────────────────────────────────────────────

function _criarAsaasProvider(config) {
    const apiKey = config.token || config.apiKey || "";
    const ambiente = config.ambiente || "producao";
    const baseUrl = ambiente === "sandbox" || ambiente === "teste" ? ASAAS_SANDBOX : ASAAS_API;

    async function _post(path, body) {
        const resp = await _httpRequest(baseUrl + path, {
            method: "POST",
            headers: {
                access_token: apiKey,
                "Content-Type": "application/json",
            },
            body,
        });
        if (!resp.ok) {
            const errMsg = typeof resp.data === "object" ? JSON.stringify(resp.data) : resp.text;
            throw new Error("Asaas error " + resp.status + ": " + errMsg);
        }
        return resp.data;
    }

    async function _get(path) {
        const resp = await _httpRequest(baseUrl + path, {
            headers: { access_token: apiKey },
        });
        if (!resp.ok) throw new Error("Asaas error " + resp.status);
        return resp.data;
    }

    return {
        tipo: "asaas",

        /**
         * Cria cobrança PIX via Asaas.
         * 1. POST /v3/payments (cria cobrança)
         * 2. GET  /v3/payments/{id}/pixQrCode (obtém QR code)
         */
        async createPixCharge({ valor, clienteNome, clienteCpf, clienteEmail, descricao, externalReference, notificationUrl }) {
            const cpfLimpo = (clienteCpf || "").replace(/\D/g, "").substring(0, 11);
            const email = clienteEmail || externalReference + "@pg.dipertin.com.br";

            // 1. Cria cobrança
            const payment = await _post("/v3/payments", {
                customer: null, // cobrança avulsa
                billingType: "PIX",
                value: Math.round(valor * 100) / 100,
                description: descricao || "Pagamento crediário",
                dueDate: new Date(Date.now() + 5 * 60 * 1000).toISOString().split("T")[0],
                externalReference: externalReference,
                notificationUrl: notificationUrl,
            });

            const paymentId = payment.id;

            // 2. Obtém QR Code PIX
            let qrCode = "", copiaCola = "", encodedImage = "";
            try {
                const pixQr = await _get("/v3/payments/" + paymentId + "/pixQrCode");
                copiaCola = pixQr.payload || "";
                encodedImage = pixQr.encodedImage || "";
            } catch (_) {
                // QR pode levar alguns segundos para ficar disponível
            }

            return {
                id: String(paymentId),
                paymentId: paymentId,
                status: "pending",
                qrCode: encodedImage,
                copiaCola: copiaCola,
                ticketUrl: payment.invoiceUrl || "",
                expiration: payment.dueDate,
                raw: payment,
            };
        },

        /**
         * Consulta status de pagamento no Asaas.
         */
        async getPaymentStatus(paymentId) {
            const result = await _get("/v3/payments/" + paymentId);

            const statusMap = {
                PENDING: "pending",
                RECEIVED: "approved",
                CONFIRMED: "approved",
                OVERDUE: "expired",
                REFUNDED: "refunded",
                RECEIVED_IN_CASH: "approved",
                PARTIAL_RECEIVED: "approved", // valor parcial
                REFUND_REQUESTED: "pending",
                CHARGEBACK_REQUESTED: "pending",
                CHARGEBACK_DISPUTE: "pending",
                AWAITING_CHARGEBACK_REVERSAL: "pending",
                DUNNING_REQUESTED: "pending",
                DUNNING_RECEIVED: "approved",
                CANCELLED: "cancelled",
            };

            const mappedStatus = statusMap[result.status] || "pending";

            return {
                id: String(paymentId),
                paymentId: paymentId,
                status: mappedStatus,
                statusDetail: result.status,
                valorPago: result.value || 0,
                valorRecebido: result.netValue || 0,
                aprovado: mappedStatus === "approved",
                pendente: mappedStatus === "pending",
                recusado: mappedStatus === "cancelled" || mappedStatus === "refunded",
                raw: result,
            };
        },

        /**
         * Processa notificação webhook do Asaas.
         * Asaas envia: { event, payment: { id, externalReference, status } }
         */
        processNotification(body) {
            const payment = body.payment || {};
            return {
                paymentId: String(payment.id || ""),
                externalRef: String(payment.externalReference || body.externalReference || ""),
                action: body.event || "",
            };
        },

        /**
         * Cria pagamento com cartão de crédito no Asaas (à vista).
         */
        async createCardPayment({ valor, clienteNome, clienteCpf, clienteEmail, cardToken, cardHolderName, cardNumber, cardExpiryMonth, cardExpiryYear, cardCvv, descricao, externalReference }) {
            const cpfLimpo = (clienteCpf || "").replace(/\D/g, "").substring(0, 11);

            // Asaas usa creditCard + creditCardHolderInfo
            const payload = {
                customer: null,
                billingType: "CREDIT_CARD",
                value: Math.round(valor * 100) / 100,
                description: descricao || "Pagamento cartão de crédito",
                dueDate: new Date().toISOString().split("T")[0],
                externalReference: externalReference,
                creditCard: {
                    holderName: cardHolderName || clienteNome || "Cliente",
                    number: cardNumber,
                    expiryMonth: String(cardExpiryMonth || ""),
                    expiryYear: String(cardExpiryYear || ""),
                    ccv: String(cardCvv || ""),
                },
                creditCardHolderInfo: {
                    name: cardHolderName || clienteNome || "Cliente",
                    email: clienteEmail || "cliente@email.com",
                    cpfCnpj: cpfLimpo || "00000000000",
                    postalCode: "00000000",
                    addressNumber: "0",
                    phone: "00000000000",
                },
            };

            const result = await _post("/v3/payments", payload);

            return {
                id: String(result.id),
                paymentId: result.id,
                status: result.status === "CONFIRMED" ? "approved" : (result.status || "pending"),
                statusDetail: result.status || "",
                authorizationCode: result.id,
                aprovado: result.status === "CONFIRMED" || result.status === "RECEIVED",
                recusado: result.status === "CANCELLED" || result.status === "REFUNDED",
                raw: result,
            };
        },

        async cancelPayment(paymentId) {
            return await _post("/v3/payments/" + paymentId + "/refund", {});
        },

        async refundPayment(paymentId, amount) {
            const body = amount ? { value: Math.round(amount * 100) / 100 } : {};
            return await _post("/v3/payments/" + paymentId + "/refund", body);
        },
    };
}

// ──────────────────────────────────────────────────────────
// PROVIDER: API PERSONALIZADA (genérico REST)
// ──────────────────────────────────────────────────────────

function _criarCustomProvider(config) {
    const baseUrl = (config.apiUrl || "").replace(/\/+$/, "");
    const token = config.token || config.apiKey || config.clientSecret || "";
    const clientId = config.clientId || "";

    // Mapeamento customizável de campos
    const mapping = config.campoMapping || {};

    async function _request(method, endpoint, body) {
        const url = endpoint.startsWith("http") ? endpoint : baseUrl + endpoint;
        const headers = { "Content-Type": "application/json" };

        // Headers personalizados
        if (config.headers) {
            try {
                const extra = typeof config.headers === "string" ? JSON.parse(config.headers) : config.headers;
                Object.assign(headers, extra);
            } catch (_) {}
        }

        if (token) headers["Authorization"] = "Bearer " + token;
        if (clientId) headers["X-Client-Id"] = clientId;

        const resp = await _httpRequest(url, { method, headers, body });
        if (!resp.ok) {
            const errMsg = typeof resp.data === "object" ? JSON.stringify(resp.data) : resp.text;
            throw new Error("CustomAPI error " + resp.status + ": " + errMsg);
        }
        return resp.data;
    }

    function _extrairCampo(data, campoPath) {
        if (!campoPath) return "";
        const parts = String(campoPath).split(".");
        let val = data;
        for (const p of parts) {
            if (val && typeof val === "object" && p in val) {
                val = val[p];
            } else {
                return "";
            }
        }
        return val !== null && val !== undefined ? String(val) : "";
    }

    function _mapearStatus(status) {
        const statusLower = String(status || "").toLowerCase();
        if (["approved", "confirmed", "paid", "received", "authorized", "completed", "success", "aprovado", "confirmado", "pago", "recebido"].includes(statusLower)) return "approved";
        if (["pending", "waiting", "in_process", "processing", "aguardando", "processando", "pendente"].includes(statusLower)) return "pending";
        if (["rejected", "cancelled", "refunded", "failed", "error", "recusado", "cancelado", "falhou"].includes(statusLower)) return "rejected";
        if (["expired", "expirado", "overdue"].includes(statusLower)) return "expired";
        return statusLower;
    }

    return {
        tipo: "api_personalizada",

        /**
         * Cria cobrança PIX via API personalizada.
         */
        async createPixCharge({ valor, clienteNome, clienteCpf, clienteEmail, descricao, externalReference, notificationUrl }) {
            const endpoint = mapping.endpointCriarPix || config.endpointPix || "/pix/cobranca";
            const body = {};
            Object.assign(body, config.payloadBase || {});

            // Preenche campos padrão
            body[mapping.valor || "valor"] = Math.round(valor * 100) / 100;
            body[mapping.clienteNome || "cliente_nome"] = clienteNome || "Cliente";
            if (mapping.clienteCpf) body[mapping.clienteCpf] = (clienteCpf || "").replace(/\D/g, "");
            if (mapping.clienteEmail) body[mapping.clienteEmail] = clienteEmail || externalReference + "@pg.dipertin.com.br";
            if (mapping.descricao) body[mapping.descricao] = descricao || "Pagamento crediário";
            if (mapping.externalReference) body[mapping.externalReference] = externalReference;
            if (mapping.notificationUrl) body[mapping.notificationUrl] = notificationUrl;

            const result = await _request("POST", endpoint, body);

            return {
                id: _extrairCampo(result, mapping.transactionId || "id"),
                paymentId: _extrairCampo(result, mapping.transactionId || "id"),
                status: _mapearStatus(_extrairCampo(result, mapping.status || "status")),
                qrCode: _extrairCampo(result, mapping.qrCode || "qr_code_base64"),
                copiaCola: _extrairCampo(result, mapping.copiaCola || "copia_cola"),
                ticketUrl: _extrairCampo(result, mapping.ticketUrl || "ticket_url"),
                raw: result,
            };
        },

        /**
         * Consulta status de pagamento via API personalizada.
         */
        async getPaymentStatus(paymentId) {
            const endpointTemplate = mapping.endpointConsultar || config.endpointStatus || "/pix/{id}";
            const endpoint = endpointTemplate.replace("{id}", paymentId);
            const result = await _request("GET", endpoint);

            const statusResult = _mapearStatus(_extrairCampo(result, mapping.status || "status"));

            return {
                id: paymentId,
                paymentId: paymentId,
                status: statusResult,
                statusDetail: _extrairCampo(result, mapping.statusDetail || "status_detail"),
                valorPago: parseFloat(_extrairCampo(result, mapping.valorPago || "valorPago")) || 0,
                aprovado: statusResult === "approved",
                pendente: statusResult === "pending",
                recusado: statusResult === "rejected" || statusResult === "cancelled",
                raw: result,
            };
        },

        /**
         * Processa notificação webhook (genérica).
         * Tenta extrair paymentId de vários formatos comuns.
         */
        processNotification(body) {
            const candidates = [
                body.data?.id, body.id, body.paymentId, body.payment_id,
                body.transactionId, body.transaction_id, body.cobranca?.id,
                body.pagamento?.id, body.PaymentId,
            ];
            const paymentId = candidates.find(c => c !== undefined && c !== null && c !== "") || "";
            const externalRef = body.externalReference || body.external_reference || body.referencia || "";

            return {
                paymentId: String(paymentId),
                externalRef: String(externalRef),
                action: body.action || body.event || body.type || "",
            };
        },

        async createCardPayment({ valor, clienteNome, clienteCpf, descricao, externalReference }) {
            const endpoint = mapping.endpointCriarCartao || config.endpointCartao || "/cartao/cobranca";
            const body = {};
            Object.assign(body, config.payloadBase || {});

            body[mapping.valor || "valor"] = Math.round(valor * 100) / 100;
            body[mapping.clienteNome || "cliente_nome"] = clienteNome || "Cliente";
            if (mapping.clienteCpf) body[mapping.clienteCpf] = (clienteCpf || "").replace(/\D/g, "");
            if (mapping.descricao) body[mapping.descricao] = descricao || "Pagamento cartão de crédito";
            if (mapping.externalReference) body[mapping.externalReference] = externalReference;

            const result = await _request("POST", endpoint, body);
            const statusResult = _mapearStatus(_extrairCampo(result, mapping.status || "status"));

            return {
                id: _extrairCampo(result, mapping.transactionId || "id"),
                paymentId: _extrairCampo(result, mapping.transactionId || "id"),
                status: statusResult,
                statusDetail: _extrairCampo(result, mapping.statusDetail || "status_detail"),
                aprovado: statusResult === "approved",
                recusado: statusResult === "rejected",
                raw: result,
            };
        },
    };
}

// ──────────────────────────────────────────────────────────
// EXPORTS
// ──────────────────────────────────────────────────────────

module.exports = {
    carregarGatewayAtivo,
    criarProvider,
    criarWebhookUrl,
    _criarMpProvider,
    _criarAsaasProvider,
    _criarCustomProvider,
};
