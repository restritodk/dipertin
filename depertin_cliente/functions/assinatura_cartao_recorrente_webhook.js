"use strict";

/**
 * Webhook do Mercado Pago — Cartão Recorrente (preapproval).
 *
 * Endpoint: https://us-central1-depertin-f940f.cloudfunctions.net/webhookCartaoRecorrente
 *
 * Processa APENAS notificações de tipo "preapproval_payment" (cobranças automáticas
 * de assinaturas via cartão de crédito).
 *
 * IMPORTANTE: Este arquivo gerencia APENAS cartão recorrente. NÃO processa:
 *  - PIX recorrente (assinatura_cobrancas.js)
 *  - Cartão avulso (assinatura_pagamento.js)
 *  - Pedidos (mercadopago_webhook.js)
 *  - PDV (mercado_pago_gestao_comercial.js)
 *
 * Fluxo:
 *  1. MP envia webhook (preapproval_payment)
 *  2. Valida HMAC (se MP_WEBHOOK_SECRET estiver configurado)
 *  3. Extrai data.id
 *  4. GET /preapproval_payments/{id} para detalhes
 *  5. Localiza assinatura por mp_preapproval_id
 *  6. Cria/atualiza cobrança em assinaturas_cobrancas
 *  7. Renova assinatura se aprovado
 */

const crypto = require("crypto");
const functions = require("firebase-functions/v1");
const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const MP_API = "https://api.mercadopago.com";
const COLECAO_ASSINATURAS = "assinaturas_clientes";
const COLECAO_COBRANCAS = "assinaturas_cobrancas";

// =============================================================================
// HELPERS
// =============================================================================

/**
 * Lê credenciais globais do Mercado Pago.
 */
async function getMercadoPagoAccessToken() {
    const doc = await admin
        .firestore()
        .collection("gateways_pagamento")
        .doc("mercado_pago")
        .get();
    if (!doc.exists || doc.data().ativo !== true) return null;
    const t = doc.data().access_token;
    return t && String(t).trim() ? String(t).trim() : null;
}

/**
 * Valida assinatura HMAC do webhook Mercado Pago.
 * Headers esperados:
 *  - x-signature: ts=1234567890,v1=abc123...
 *  - x-request-id: uuid
 *
 * String para assinar (oficial MP):
 *   id:<data.id>;request-id:<x-request-id>;ts:<x-timestamp>;
 *
 * SEGURANÇA:
 *  - Em produção: REJEITA se MP_WEBHOOK_SECRET não estiver configurado
 *  - Em desenvolvimento: aceita com warning (Firestore flag "webhook_dev_aceitar_sem_hmac"=true)
 */
async function validarAssinaturaWebhookMp(req, body) {
    try {
        const secret = process.env.MP_WEBHOOK_SECRET;
        if (!secret) {
            // Fallback: verifica flag no Firestore para ambiente dev
            const db = admin.firestore();
            const flagSnap = await db
                .collection("billing_settings")
                .doc("webhook_dev_flags")
                .get();
            const flagData = flagSnap.exists ? flagSnap.data() : {};
            const permitirDev = flagData.aceitar_sem_hmac === true;
            const isProduction = process.env.NODE_ENV === "production" ||
                process.env.FUNCTION_TARGET === "production";

            if (isProduction || !permitirDev) {
                console.error(
                    "[cartao-recorrente-webhook] MP_WEBHOOK_SECRET não configurado em PRODUÇÃO — REJEITANDO"
                );
                return false;
            }
            console.warn(
                "[cartao-recorrente-webhook] MP_WEBHOOK_SECRET ausente mas flag dev ativa — aceitando"
            );
            return true;
        }

        const xSignature = req.headers["x-signature"] || "";
        const xRequestId = req.headers["x-request-id"] || "";

        // Extrair ts e v1 do header x-signature
        const parts = xSignature.split(",");
        let ts = "";
        let v1 = "";
        for (const p of parts) {
            const [key, value] = p.split("=");
            if (key === "ts") ts = value;
            if (key === "v1") v1 = value;
        }

        if (!ts || !v1) return false;

        // Construir string para assinar
        const dataId = (body && body.data && body.data.id) ? String(body.data.id) : "";
        const stringToSign = `id:${dataId};request-id:${xRequestId};ts:${ts};`;

        // Calcular HMAC
        const hmac = crypto.createHmac("sha256", secret);
        hmac.update(stringToSign);
        const calculated = hmac.digest("hex");

        // Comparação segura contra timing attacks
        const a = Buffer.from(calculated, "hex");
        const b = Buffer.from(v1, "hex");
        if (a.length !== b.length || a.length === 0) return false;
        return crypto.timingSafeEqual(a, b);
    } catch (e) {
        console.warn("[cartao-recorrente-webhook] Erro validação HMAC:", e.message);
        return false;
    }
}

/**
 * Consulta pagamento de preapproval no MP.
 */
async function fetchPreapprovalPaymentFromMp(accessToken, paymentId) {
    const res = await fetch(`${MP_API}/preapproval_payments/${paymentId}`, {
        headers: { Authorization: `Bearer ${accessToken}` },
    });
    return await res.json().catch(() => ({}));
}

/**
 * Calcula o ciclo (YYYYMM) de uma data.
 */
function cicloDe(date) {
    return `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, "0")}`;
}

// =============================================================================
// WEBHOOK PRINCIPAL
// =============================================================================

exports.webhookCartaoRecorrente = functions.https.onRequest(async (req, res) => {
    res.set("Cache-Control", "no-store");

    // GET: health check
    if (req.method === "GET") {
        return res.status(200).send("ok");
    }
    if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
    }

    // Parse body
    let body = {};
    try {
        if (typeof req.body === "string") {
            body = JSON.parse(req.body || "{}");
        } else if (req.body && typeof req.body === "object") {
            body = req.body;
        }
    } catch (e) {
        console.error("[cartao-recorrente-webhook] JSON inválido:", e.message);
        return res.status(400).send("bad json");
    }

    console.log(
        "[cartao-recorrente-webhook] Recebido: type=" + (body.type || "n/a") +
        ", action=" + (body.action || "n/a")
    );

    // FILTRO: processar APENAS preapproval_payment
    const tipo = String(body.type || "");
    if (tipo !== "preapproval_payment") {
        // Não é uma cobrança recorrente — ignorar silenciosamente
        return res.status(200).send("ignored: not preapproval_payment");
    }

    // Validar HMAC
    if (!validarAssinaturaWebhookMp(req, body)) {
        console.warn("[cartao-recorrente-webhook] Assinatura HMAC inválida — ignorando");
        return res.status(401).send("invalid signature");
    }

    // Extrair data.id
    const dataId = body.data && body.data.id ? String(body.data.id).trim() : "";
    if (!dataId) {
        console.warn("[cartao-recorrente-webhook] Sem data.id");
        return res.status(200).send("no data.id");
    }

    try {
        await processarCobrancaRecorrente(dataId);
        return res.status(200).send("ok");
    } catch (e) {
        console.error("[cartao-recorrente-webhook] Erro:", e.message || e);
        return res.status(500).send("error");
    }
});

// =============================================================================
// PROCESSAMENTO DA COBRANÇA RECORRENTE
// =============================================================================

async function processarCobrancaRecorrente(preapprovalPaymentId) {
    const db = admin.firestore();
    const token = await getMercadoPagoAccessToken();
    if (!token) {
        throw new Error("Mercado Pago access token não disponível");
    }

    // 1. Consultar pagamento no MP
    const payment = await fetchPreapprovalPaymentFromMp(token, preapprovalPaymentId);
    if (!payment || !payment.id) {
        throw new Error("Pagamento não encontrado no MP");
    }

    const statusMp = String(payment.status || "").toLowerCase();
    const preapprovalId =
        payment.preapproval_id || (payment.preapproval && payment.preapproval.id) || null;
    const externalRef = String(payment.external_reference || "").trim();

    console.log(
        "[cartao-recorrente-webhook] Pagamento " + preapprovalPaymentId +
        ": status=" + statusMp + ", preapproval=" + (preapprovalId || "n/a")
    );

    if (!preapprovalId) {
        console.warn("[cartao-recorrente-webhook] Sem preapproval_id — ignorando");
        return;
    }

    // 2. Localizar assinatura
    const assSnap = await db
        .collection(COLECAO_ASSINATURAS)
        .where("mp_preapproval_id", "==", preapprovalId)
        .limit(1)
        .get();

    if (assSnap.empty) {
        console.warn(
            "[cartao-recorrente-webhook] Assinatura não encontrada para preapproval=" +
            preapprovalId
        );
        return;
    }

    const assRef = assSnap.docs[0].ref;
    const assinatura = assSnap.docs[0].data() || {};
    const storeId = String(assinatura.store_id || "").trim();
    const valorPago = Number(payment.transaction_amount) || Number(assinatura.monthly_amount) || 0;

    // 3. Determinar ciclo
    const dataCobranca = payment.date_approved
        ? new Date(payment.date_approved)
        : (payment.date_created ? new Date(payment.date_created) : new Date());
    const ciclo = cicloDe(dataCobranca);
    // ID com prefixo "cartao_" para evitar conflito com PIX recorrente
    const cobrancaId = `cartao_${storeId}_${ciclo}`;
    const cobrancaRef = db.collection(COLECAO_COBRANCAS).doc(cobrancaId);

    // 4. Processar tudo em transação (idempotente)
    const now = admin.firestore.Timestamp.now();
    const isAprovado = (statusMp === "approved" || statusMp === "authorized");

    await db.runTransaction(async (tx) => {
        // 4a. Verificar/criar/atualizar cobrança
        const cobSnap = await tx.get(cobrancaRef);
        const cobrancaExistente = cobSnap.data() || {};

        // IDEMPOTÊNCIA 1: já está paga → não faz nada
        if (cobrancaExistente.status === "paga" && statusMp === "approved") {
            console.log(
                "[cartao-recorrente-webhook] Cobrança " + cobrancaId +
                " já paga, ignorando."
            );
            return;
        }

        // IDEMPOTÊNCIA 2: verifica se o mp_payment_id já foi processado
        if (
            cobrancaExistente.mp_payment_id === preapprovalPaymentId &&
            cobrancaExistente.status === "paga"
        ) {
            console.log(
                "[cartao-recorrente-webhook] mp_payment_id " +
                preapprovalPaymentId + " já processado"
            );
            return;
        }

        // 4b. Definir status da cobrança
        // - Aprovado: sempre "paga"
        // - Falhou: "em_aberto" se vencimento não passou, "vencida" se já passou
        let statusCobranca;
        let statusGateway;
        if (isAprovado) {
            statusCobranca = "paga";
            statusGateway = "aprovado";
        } else {
            // Verifica se a data de vencimento já passou
            const vencimentoDate = new Date(dataCobranca);
            const hoje = new Date();
            const vence = new Date(vencimentoDate.getFullYear(), vencimentoDate.getMonth(), vencimentoDate.getDate());
            const hj = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate());
            if (vence.getTime() < hj.getTime()) {
                statusCobranca = "vencida";
            } else {
                statusCobranca = "em_aberto";
            }
            statusGateway = "falhou";
        }

        // 4c. Criar/atualizar cobrança
        if (cobSnap.exists) {
            tx.update(cobrancaRef, {
                status: statusCobranca,
                pago_em: isAprovado ? now : (cobrancaExistente.pago_em || null),
                mp_payment_id: preapprovalPaymentId,
                mp_status: statusMp,
                mp_external_reference: externalRef,
                tipo_cobranca: "cartao_recorrente",
                status_pagamento_gateway: statusGateway,
                valor: valorPago,
                atualizado_em: now,
                historico: admin.firestore.FieldValue.arrayUnion({
                    tipo: statusCobranca === "paga" ? "pagamento_recorrente_aprovado" : "pagamento_recorrente_falhou",
                    descricao: statusCobranca === "paga"
                        ? "Cobrança recorrente aprovada via cartão (preapproval)."
                        : "Cobrança recorrente falhou no cartão.",
                    data_em: now,
                    payment_id: preapprovalPaymentId,
                    status_mp: statusMp,
                    origem: "webhook_preapproval",
                }),
            });
        } else {
            tx.set(cobrancaRef, {
                assinatura_id: storeId,
                store_id: storeId,
                store_name: String(assinatura.store_name || ""),
                owner_name: String(assinatura.owner_name || ""),
                email: String(assinatura.email || ""),
                plan_name: String(assinatura.plan_name || ""),
                modulo: "gestao_comercial",
                tipo_cobranca: "cartao_recorrente",
                valor: valorPago,
                fatura: "#FAT-" + ciclo,
                fatura_seq: Number(ciclo.substring(4, 6)) || 1,
                ciclo: ciclo,
                vencimento: now,
                status: statusCobranca,
                pago_em: isAprovado ? now : null,
                mp_payment_id: preapprovalPaymentId,
                mp_status: statusMp,
                mp_external_reference: externalRef,
                status_pagamento_gateway: statusGateway,
                origem: "preapproval",
                criado_em: now,
                atualizado_em: now,
                historico: [{
                    tipo: "geracao",
                    descricao: "Cobrança gerada automaticamente (preapproval).",
                    data_em: now,
                }, {
                    tipo: statusCobranca === "paga" ? "pagamento_recorrente_aprovado" : "pagamento_recorrente_falhou",
                    descricao: statusCobranca === "paga"
                        ? "Cobrança recorrente aprovada via cartão (preapproval)."
                        : "Cobrança recorrente falhou no cartão.",
                    data_em: now,
                    payment_id: preapprovalPaymentId,
                    status_mp: statusMp,
                    origem: "webhook_preapproval",
                }],
            });
        }

        // 4d. Se aprovado, renovar assinatura
        if (isAprovado) {
            // Calcular próxima cobrança (+30 dias ou duracao_dias)
            const duracaoDias = Number(assinatura.duracao_dias) > 0
                ? Number(assinatura.duracao_dias)
                : 30;
            const proxVencimento = new Date();
            proxVencimento.setDate(proxVencimento.getDate() + duracaoDias);

            tx.update(assRef, {
                status: "ativo",
                last_payment_date: now,
                next_billing_date: admin.firestore.Timestamp.fromDate(proxVencimento),
                proxima_cobranca_recorrente: admin.firestore.Timestamp.fromDate(proxVencimento),
                dias_em_atraso: 0,
                multa_calculada: 0,
                juros_calculados: 0,
                total_atualizado: valorPago,
                ultimo_pagamento_valor: valorPago,
                updated_at: now,
                blocked_at: admin.firestore.FieldValue.delete(),
                block_reason: admin.firestore.FieldValue.delete(),
                historico: admin.firestore.FieldValue.arrayUnion({
                    tipo: "renovacao_cartao_recorrente",
                    descricao: "Assinatura renovada automaticamente via cartão recorrente (preapproval).",
                    data_em: now,
                    valor_pago: valorPago,
                    payment_id: preapprovalPaymentId,
                    origem: "webhook_preapproval",
                }),
            });
        } else {
            // Falha: NÃO suspende aqui. Apenas registra e marca em_atraso se config permitir.
            // Bloqueio continua exclusivo da rotina de tolerância/suspensão.
            if (assinatura.suspender_inadimplencia === true) {
                tx.update(assRef, {
                    status: "em_atraso",
                    updated_at: now,
                    historico: admin.firestore.FieldValue.arrayUnion({
                        tipo: "falha_pagamento_recorrente",
                        descricao: "Falha na cobrança automática do cartão recorrente.",
                        data_em: now,
                        payment_id: preapprovalPaymentId,
                        status_mp: statusMp,
                        origem: "webhook_preapproval",
                    }),
                });
            } else {
                tx.update(assRef, {
                    updated_at: now,
                    historico: admin.firestore.FieldValue.arrayUnion({
                        tipo: "tentativa_pagamento_recorrente",
                        descricao: "Tentativa de cobrança automática (sem suspender).",
                        data_em: now,
                        payment_id: preapprovalPaymentId,
                        status_mp: statusMp,
                        origem: "webhook_preapproval",
                    }),
                });
            }
        }
    });

    // E-mail de falha (best-effort, fora da transação) — não bloqueia
    if (!isAprovado) {
        try {
            const avisos = require("./assinatura_avisos");
            await avisos.enviarEmailFalhaCartao({
                email: assinatura.email || "",
                lojaNome: assinatura.store_name || "",
                planoNome: assinatura.plan_name || "",
                valor: valorPago,
                vencimento: avisos.formatDateBr(assinatura.next_billing_date),
                situacao: "Falha no débito automático",
                formaPagamento: "Cartão recorrente",
                fatura: cobrancaId,
                cobrancaId,
            });
        } catch (eMail) {
            console.warn("[cartao-recorrente-webhook] e-mail falha:", eMail.message || eMail);
        }
    } else {
        try {
            const avisos = require("./assinatura_avisos");
            await avisos.enviarEmailPagamentoAprovado({
                email: assinatura.email || "",
                lojaNome: assinatura.store_name || "",
                planoNome: assinatura.plan_name || "",
                valor: valorPago,
                situacao: "Ativo / renovado",
                formaPagamento: "Cartão recorrente",
                fatura: cobrancaId,
                cobrancaId,
            });
        } catch (_) { /* best-effort */ }
    }

    console.log(
        "[cartao-recorrente-webhook] PROCESSADO: payment=" + preapprovalPaymentId +
        ", preapproval=" + preapprovalId + ", status=" + statusMp
    );
}
