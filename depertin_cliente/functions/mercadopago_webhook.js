"use strict";

/**
 * Mercado Pago — webhook + vínculo PIX + processamento de status.
 * Credenciais: Firestore gateways_pagamento/mercado_pago (access_token).
 * Segredo webhook: MP_WEBHOOK_SECRET no functions/.env (painel MP → Webhooks).
 */

const crypto = require("crypto");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, ".env") });

const functions = require("firebase-functions/v1");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const notificationDispatcher = require("./notification_dispatcher");
const repasseFinanceiro = require("./repasse_financeiro");

const MP_API = "https://api.mercadopago.com";

/** Prazo para pagar o PIX após gerar o QR (minutos). */
const PIX_PRAZO_MINUTOS = 5;
const PAYMENT_CALLABLE_OPTIONS = {
    region: "us-central1",
    // App já ativa App Check (Flutter). Para exigir token nas callables:
    // 1) Firebase Console → App Check → Android → token de debug (Logcat ao rodar debug)
    // 2) Aqui: enforceAppCheck: true + firebase deploy --only functions
    enforceAppCheck: false,
};

/** Compara valores monetários (evita falha por float Firestore vs MP). */
function amountsMatch(a, b) {
    const x = Math.round(Number(a) * 100) / 100;
    const y = Math.round(Number(b) * 100) / 100;
    if (Number.isNaN(x) || Number.isNaN(y)) return false;
    return Math.abs(x - y) <= 0.05;
}

function pagamentoEstaPago(statusMp) {
    return statusMp === "approved" || statusMp === "authorized";
}

/** Checkout multi-loja: valor cobrado no MP pode ser o total do grupo (campo no pedido líder). */
function valorMercadoPagoEsperadoNoPedido(ped) {
    const raw = ped && ped.checkout_valor_mp_total_cobranca;
    const n = Number(raw);
    if (Number.isFinite(n) && n > 0) return n;
    return Number(ped.total);
}

function idsGrupoCheckoutDoPedido(ped) {
    const raw = ped && ped.checkout_grupo_pedido_ids;
    if (!Array.isArray(raw) || raw.length === 0) return null;
    const ids = [...new Set(raw.map((x) => String(x || "").trim()).filter(Boolean))];
    return ids.length ? ids : null;
}

/**
 * Irmãos do checkout recebem `checkout_cobranca_pedido_mp_id` = ID Firestore do pedido líder (não o payment_id do MP).
 * O `mp_payment_id` fica no documento do líder.
 */
async function resolverMpPaymentIdParaPedido(db, depois, antes) {
    const local =
        depois.mp_payment_id != null && String(depois.mp_payment_id).trim() !== ""
            ? String(depois.mp_payment_id).trim()
            : antes.mp_payment_id != null && String(antes.mp_payment_id).trim() !== ""
              ? String(antes.mp_payment_id).trim()
              : "";
    if (local) return local;

    const liderDocIdRaw =
        depois.checkout_cobranca_pedido_mp_id != null
            ? String(depois.checkout_cobranca_pedido_mp_id).trim()
            : antes.checkout_cobranca_pedido_mp_id != null
              ? String(antes.checkout_cobranca_pedido_mp_id).trim()
              : "";
    if (!liderDocIdRaw) return null;

    const snap = await db.collection("pedidos").doc(liderDocIdRaw).get();
    if (!snap.exists) return null;
    const ld = snap.data() || {};
    const mp = ld.mp_payment_id != null ? String(ld.mp_payment_id).trim() : "";
    return mp || null;
}

/**
 * Cancela todos os pedidos do mesmo checkout em `aguardando_pagamento` (PIX/cartão abandonado).
 */
async function cancelarPedidosGrupoCheckoutEmEspera(db, pedidoIdInicial, patchExtras) {
    const ref0 = db.collection("pedidos").doc(String(pedidoIdInicial).trim());
    const snap0 = await ref0.get();
    if (!snap0.exists) return 0;
    const ped0 = snap0.data() || {};
    const ids = idsGrupoCheckoutDoPedido(ped0) || [ref0.id];
    const patch = {
        status: "cancelado",
        cancelado_em: admin.firestore.FieldValue.serverTimestamp(),
        ...patchExtras,
    };
    let n = 0;
    const batch = db.batch();
    for (const id of ids) {
        const ref = db.collection("pedidos").doc(id);
        const s = await ref.get();
        if (!s.exists) continue;
        const d = s.data() || {};
        if (d.status !== "aguardando_pagamento") continue;
        batch.update(ref, patch);
        n++;
    }
    if (n > 0) await batch.commit();
    return n;
}

/** Replica prazo/campos PIX para os irmãos do grupo (mesmo checkout). */
async function copiarPixGrupoParaIrmaos(db, liderId, liderData, camposPix) {
    const ids = idsGrupoCheckoutDoPedido(liderData);
    const grupo = liderData.checkout_grupo_id != null ? String(liderData.checkout_grupo_id).trim() : "";
    if (!ids || ids.length < 2 || !grupo) return;
    const batch = db.batch();
    let n = 0;
    for (const id of ids) {
        if (id === liderId) continue;
        const ref = db.collection("pedidos").doc(id);
        const s = await ref.get();
        if (!s.exists) continue;
        const d = s.data() || {};
        if (String(d.checkout_grupo_id || "") !== grupo) continue;
        if (d.status !== "aguardando_pagamento") continue;
        batch.update(ref, camposPix);
        n++;
    }
    if (n > 0) await batch.commit();
}

/** Após pagamento aprovado no pedido líder (MP), coloca irmãos em `pendente` e notifica cada loja. */
async function promoverIrmaosGrupoAposPagamentoAprovado(
    db,
    liderId,
    liderData,
    payment,
    baseUpdate,
    statusMp,
) {
    const ids = idsGrupoCheckoutDoPedido(liderData);
    const grupo = liderData.checkout_grupo_id != null ? String(liderData.checkout_grupo_id).trim() : "";
    if (!ids || ids.length < 2 || !grupo) return;

    const forma = liderData.forma_pagamento || "PIX";
    const batch = db.batch();
    const irmaos = [];
    for (const id of ids) {
        if (id === liderId) continue;
        const ref = db.collection("pedidos").doc(id);
        const s = await ref.get();
        if (!s.exists) continue;
        const d = s.data() || {};
        if (String(d.checkout_grupo_id || "") !== grupo) continue;
        if (d.status !== "aguardando_pagamento") continue;
        batch.update(ref, {
            status: "pendente",
            forma_pagamento: forma,
            pagamento_confirmado_em: admin.firestore.FieldValue.serverTimestamp(),
            checkout_cobranca_pedido_mp_id: liderId,
            mp_status: statusMp,
            mp_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });
        irmaos.push(id);
    }
    if (irmaos.length) await batch.commit();

    for (const id of irmaos) {
        const ref = db.collection("pedidos").doc(id);
        const s = await ref.get();
        if (!s.exists) continue;
        const depois = s.data() || {};
        const lojaIdFcm = depois.loja_id || depois.lojista_id;
        if (!lojaIdFcm) continue;
        try {
            await notificationDispatcher.enviarNovoPedidoParaLoja(db, String(lojaIdFcm), id, depois);
        } catch (e) {
            console.error("[mp] enviarNovoPedidoParaLoja irmão grupo:", id, e.message || e);
        }
    }
}

function extrairCodigoMp(body) {
    if (!body || typeof body !== "object") return "";
    const cause = Array.isArray(body.cause) ? body.cause : [];
    const first = cause.length ? cause[0] || {} : {};
    return String(
        first.code ||
        first.error_code ||
        body.error ||
        body.code ||
        body.status_detail ||
        "",
    ).trim();
}

function traduzirRecusaMp({
    status,
    statusDetail,
    erroCodigo,
    erroMensagem,
}) {
    const st = String(status || "").toLowerCase().trim();
    const det = String(statusDetail || "").toLowerCase().trim();
    const cod = String(erroCodigo || "").toLowerCase().trim();
    const msg = String(erroMensagem || "").trim();
    const chave = [cod, det, msg.toLowerCase()].join(" | ");

    const mapa = [
        {
            match: ["cc_rejected_insufficient_amount"],
            code: "cc_rejected_insufficient_amount",
            message: "Cartão informado sem saldo limite suficiente.",
        },
        {
            match: ["cc_rejected_bad_filled_security_code", "e302", "security_code"],
            code: "cc_rejected_bad_filled_security_code",
            message: "Código de segurança (CVV) inválido.",
        },
        {
            match: ["cc_rejected_bad_filled_date", "e301", "expiration_month", "expiration_year"],
            code: "cc_rejected_bad_filled_date",
            message: "Data de validade do cartão inválida.",
        },
        {
            match: ["cc_rejected_bad_filled_card_number", "e203", "card_number"],
            code: "cc_rejected_bad_filled_card_number",
            message: "Número do cartão inválido.",
        },
        {
            match: ["cc_rejected_call_for_authorize"],
            code: "cc_rejected_call_for_authorize",
            message: "Pagamento não autorizado. Peça para o cliente contatar o banco emissor.",
        },
        {
            match: ["cc_rejected_card_disabled"],
            code: "cc_rejected_card_disabled",
            message: "Cartão bloqueado ou desabilitado pelo emissor.",
        },
        {
            match: ["cc_rejected_card_error"],
            code: "cc_rejected_card_error",
            message: "Não foi possível processar o cartão informado.",
        },
        {
            match: ["cc_rejected_blacklist"],
            code: "cc_rejected_blacklist",
            message: "Pagamento recusado por política de segurança do provedor.",
        },
        {
            match: ["cc_rejected_duplicated_payment"],
            code: "cc_rejected_duplicated_payment",
            message: "Tentativa duplicada detectada. Aguarde alguns segundos e tente novamente.",
        },
        {
            match: ["cc_rejected_high_risk", "cc_rejected_other_reason"],
            code: "cc_rejected_other_reason",
            message: "Pagamento recusado pelos controles de segurança do Mercado Pago.",
        },
    ];

    for (const regra of mapa) {
        if (regra.match.some((m) => chave.includes(m))) {
            return { codigo: regra.code, mensagem: regra.message };
        }
    }

    if (st === "cancelled") {
        return { codigo: cod || "payment_cancelled", mensagem: "Pagamento cancelado no provedor." };
    }
    if (st === "refunded") {
        return { codigo: cod || "payment_refunded", mensagem: "Pagamento estornado no provedor." };
    }
    if (st === "rejected") {
        return { codigo: cod || "payment_rejected", mensagem: "Pagamento recusado pelo provedor." };
    }
    return {
        codigo: cod || "payment_not_completed",
        mensagem: msg || "Pagamento não concluído.",
    };
}

async function getMercadoPagoAccessToken() {
    const doc = await admin
        .firestore()
        .collection("gateways_pagamento")
        .doc("mercado_pago")
        .get();
    if (!doc.exists || doc.data().ativo !== true) {
        return null;
    }
    const t = doc.data().access_token;
    return t && String(t).trim() ? String(t).trim() : null;
}

async function getMercadoPagoGatewayConfig() {
    const doc = await admin
        .firestore()
        .collection("gateways_pagamento")
        .doc("mercado_pago")
        .get();
    if (!doc.exists || doc.data().ativo !== true) {
        return null;
    }
    const d = doc.data() || {};
    const accessToken = d.access_token && String(d.access_token).trim()
        ? String(d.access_token).trim()
        : null;
    const publicKey = d.public_key && String(d.public_key).trim()
        ? String(d.public_key).trim()
        : null;
    if (!accessToken) return null;
    return { accessToken, publicKey };
}

async function fetchPaymentFromMp(accessToken, paymentId) {
    const url = `${MP_API}/v1/payments/${encodeURIComponent(String(paymentId))}`;
    const res = await fetch(url, {
        method: "GET",
        headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
        },
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const err = new Error(body.message || `MP GET ${res.status}`);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

async function criarCardTokenMp({ publicKey, accessToken, payload }) {
    const url = `${MP_API}/v1/card_tokens`;
    const authCandidates = [];
    if (publicKey) authCandidates.push(publicKey);
    if (accessToken) authCandidates.push(accessToken);
    let lastError = null;
    for (const credential of authCandidates) {
        const res = await fetch(url, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${credential}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify(payload),
        });
        const body = await res.json().catch(() => ({}));
        if (res.ok && body && body.id) {
            return body;
        }
        lastError = new Error(body.message || `MP CARD TOKEN ${res.status}`);
        lastError.status = res.status;
        lastError.body = body;
    }
    throw lastError || new Error("Falha ao tokenizar cartão.");
}

async function criarPagamentoMpComCartao(accessToken, payload) {
    const res = await fetch(`${MP_API}/v1/payments`, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
            "X-Idempotency-Key": `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
        },
        body: JSON.stringify(payload),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const err = new Error(body.message || `MP PAY ${res.status}`);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

async function criarPagamentoPixMp(accessToken, payload, pedidoId) {
    const idempotencyKey = `pix-${String(pedidoId || "").trim() || Date.now()}`;
    const res = await fetch(`${MP_API}/v1/payments`, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
            "X-Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify(payload),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const err = new Error(body.message || `MP PIX ${res.status}`);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

function roundMoneyMp(v) {
    const n = Number(v);
    if (Number.isNaN(n)) return 0;
    return Math.round(n * 100) / 100;
}

/** Valor ainda reembolsável no pagamento (considera estornos já feitos no MP). */
function valorMaximoReembolsavelApartirDoPagamentoMp(payment) {
    const tx = roundMoneyMp(payment.transaction_amount);
    let ja = 0;
    const a = Number(payment.transaction_amount_refunded);
    if (Number.isFinite(a) && a > 0) {
        ja = roundMoneyMp(a);
    } else {
        const b = Number(payment.total_refunded_amount);
        if (Number.isFinite(b) && b > 0) {
            ja = roundMoneyMp(b);
        } else if (Array.isArray(payment.refunds)) {
            for (const r of payment.refunds) {
                const st = String(r.status || "").toLowerCase();
                if (
                    st === "approved" ||
                    st === "pending" ||
                    st === "in_process" ||
                    st === "accredited"
                ) {
                    ja = roundMoneyMp(ja + Number(r.amount || 0));
                }
            }
        }
    }
    const rest = roundMoneyMp(tx - ja);
    return rest > 0 ? rest : 0;
}

/** PIX: MP pode responder 400 em contingência; header devolve 201 + status in_process. */
const MP_REFUND_HEADERS_EXTRA = {
    "X-Render-In-Process-Refunds": "true",
};

async function criarEstornoTotalMp(accessToken, paymentId) {
    const url = `${MP_API}/v1/payments/${encodeURIComponent(String(paymentId))}/refunds`;
    const res = await fetch(url, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
            ...MP_REFUND_HEADERS_EXTRA,
            "X-Idempotency-Key": `refund-${paymentId}-${Date.now()}`,
        },
        body: JSON.stringify({}),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const err = new Error(body.message || `MP REFUND ${res.status}`);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

/**
 * Estorno parcial (BRL) — Mercado Pago `amount` no corpo.
 * @param {number} valorReembolso - valor a devolver ao pagador (> 0).
 */
async function criarEstornoParcialMp(accessToken, paymentId, valorReembolso) {
    const amt = roundMoneyMp(valorReembolso);
    if (!(amt > 0)) {
        throw new Error("Valor de estorno parcial inválido.");
    }
    const url = `${MP_API}/v1/payments/${encodeURIComponent(String(paymentId))}/refunds`;
    const res = await fetch(url, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
            ...MP_REFUND_HEADERS_EXTRA,
            "X-Idempotency-Key": `refund-partial-${paymentId}-${Date.now()}`,
        },
        body: JSON.stringify({ amount: amt }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const err = new Error(body.message || `MP REFUND_PARTIAL ${res.status}`);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

/** Status em que o cliente já foi avisado "Saiu para entrega" (frete não reembolsado no cancelamento). */
const STATUS_CANCEL_PARCIAL_FRETE = new Set(["saiu_entrega", "em_rota", "a_caminho"]);

/**
 * Após estorno parcial (produtos ao cliente, frete retido), credita na carteira do entregador
 * o valor líquido do frete (mesma base de [processarEntregaConcluida] / repasse).
 */
async function creditarEntregadorFreteCancelamentoCliente(change, context, antes, depois) {
    const db = admin.firestore();
    const pedRef = change.after.ref;
    const entregadorId = String(depois.entregador_id || antes.entregador_id || "").trim();
    if (!entregadorId) {
        return;
    }

    const snapFresh = await pedRef.get();
    const cur = snapFresh.data() || {};
    if (cur.entregador_credito_cancelamento_feito === true) {
        return;
    }

    const merged = { ...antes, ...depois, ...cur };
    let liq = Number(merged.valor_liquido_entregador || 0);
    if (!(liq > 0)) {
        let veiculoEntregador = "";
        try {
            const uSnap = await db.collection("users").doc(entregadorId).get();
            if (uSnap.exists) {
                const eu = uSnap.data() || {};
                veiculoEntregador = String(
                    eu.veiculoTipo || eu.veiculo || eu.tipo_veiculo || "",
                ).trim();
            }
        } catch (_) {
            /* ignore */
        }
        try {
            const campos = await repasseFinanceiro.calcularCamposFinanceirosPedido(db, merged, {
                veiculoEntregador,
            });
            liq = Number(campos.valor_liquido_entregador || 0);
        } catch (e) {
            console.warn("[mp] repasse entregador cancel parcial:", e.message || e);
        }
    }
    if (!(liq > 0)) {
        liq = roundMoneyMp(merged.taxa_entrega != null ? merged.taxa_entrega : 0);
    }
    if (!(liq > 0)) {
        return;
    }

    await db.runTransaction(async (t) => {
        const s = await t.get(pedRef);
        const d = s.data() || {};
        if (d.entregador_credito_cancelamento_feito === true) {
            return;
        }
        t.update(pedRef, {
            entregador_credito_cancelamento_feito: true,
            entregador_credito_cancelamento_valor: liq,
            entregador_credito_cancelamento_em: admin.firestore.FieldValue.serverTimestamp(),
            entregador_credito_cancelamento_tipo: "corrida_cancelada_cliente_frete_retido",
        });
        t.update(db.collection("users").doc(entregadorId), {
            saldo: admin.firestore.FieldValue.increment(liq),
        });
    });
    console.log(
        `[mp] Credito entregador cancel parcial pedido=${context.params.pedidoId} uid=${entregadorId} +R$${liq.toFixed(2)}`,
    );
}

/**
 * Valor a reembolsar no MP: total pago menos taxa de entrega (cupom/saldo já refletidos em `total`).
 */
function valorReembolsoClienteCancelamento(antes, depois) {
    const total = roundMoneyMp(depois.total != null ? depois.total : antes.total);
    const taxa = roundMoneyMp(
        depois.taxa_entrega != null ? depois.taxa_entrega : antes.taxa_entrega,
    );
    let v = roundMoneyMp(total - taxa);
    if (v < 0) v = 0;
    if (v > total) v = total;
    return v;
}

async function aguardarConclusaoPagamentoMp(accessToken, paymentId, tentativas = 8, intervaloMs = 2500) {
    let ultimo = null;
    for (let i = 0; i < tentativas; i++) {
        ultimo = await fetchPaymentFromMp(accessToken, paymentId);
        const st = String(ultimo.status || "");
        if (st === "approved" || st === "authorized" || st === "rejected" || st === "cancelled" || st === "refunded") {
            return ultimo;
        }
        await new Promise((resolve) => setTimeout(resolve, intervaloMs));
    }
    return ultimo;
}

/**
 * Valida x-signature do Mercado Pago (manifest: id:[data.id];request-id:[...];ts:[...];)
 * @see https://www.mercadopago.com.br/developers/pt/docs/your-integrations/notifications/webhooks
 */
function validarAssinaturaWebhook(req, body, secret) {
    if (!secret || String(secret).trim() === "") {
        console.error("[mp] MP_WEBHOOK_SECRET vazio — webhook recusado por segurança.");
        return false;
    }
    const sigHeader = req.headers["x-signature"] || req.headers["X-Signature"];
    const requestId =
        req.headers["x-request-id"] || req.headers["X-Request-Id"] || "";
    if (!sigHeader) {
        console.warn("[mp] Webhook sem x-signature");
        return false;
    }
    let ts;
    let v1;
    String(sigHeader)
        .split(",")
        .forEach((part) => {
            const [k, ...rest] = part.trim().split("=");
            const v = rest.join("=");
            if (k.trim() === "ts") ts = v;
            if (k.trim() === "v1") v1 = v;
        });
    const dataId =
        (body && body.data && body.data.id != null && String(body.data.id)) ||
        (req.query && req.query["data.id"]) ||
        (req.query && req.query.id) ||
        "";
    if (!ts || !v1) {
        console.warn("[mp] x-signature sem ts ou v1");
        return false;
    }
    const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
    const expected = crypto.createHmac("sha256", secret).update(manifest).digest("hex");
    const got = String(v1).trim();
    try {
        const a = Buffer.from(expected, "hex");
        const b = Buffer.from(got, "hex");
        if (a.length !== b.length || a.length === 0) return false;
        return crypto.timingSafeEqual(a, b);
    } catch (e) {
        return false;
    }
}

/**
 * Processa objeto payment da API MP (sempre após GET /v1/payments/{id}).
 * Idempotência: se já pendente com mesmo payment_id, retorna ok.
 */
async function processarPagamentoMercadoPago(payment) {
    const db = admin.firestore();
    const paymentId = payment.id;
    const extRef = payment.external_reference != null ? String(payment.external_reference).trim() : "";
    if (!extRef) {
        console.log("[mp] Pagamento sem external_reference, ignorando.");
        return { ok: false, reason: "no_external_reference" };
    }

    const pedidoRef = db.collection("pedidos").doc(extRef);
    const pedSnap = await pedidoRef.get();
    if (!pedSnap.exists) {
        console.warn("[mp] Pedido não encontrado:", extRef);
        return { ok: false, reason: "pedido_not_found" };
    }

    const ped = pedSnap.data();
    if (ped.status === "cancelado") {
        console.log("[mp] Pedido já cancelado, ignorando notificação MP:", extRef);
        return { ok: false, reason: "pedido_cancelado" };
    }

    const statusMp = payment.status;

    const pedidoTotal = valorMercadoPagoEsperadoNoPedido(ped);
    const txAmt = Number(payment.transaction_amount);
    if (!amountsMatch(pedidoTotal, txAmt)) {
        console.error("[mp] Valor divergente pedido vs MP:", pedidoTotal, txAmt);
        return { ok: false, reason: "amount_mismatch" };
    }

    const qrData = payment.point_of_interaction?.transaction_data?.qr_code || null;
    const baseUpdate = {
        mp_payment_id: paymentId,
        mp_status: statusMp,
        mp_transaction_amount: txAmt,
        mp_date_created: payment.date_created || null,
        mp_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (qrData) {
        baseUpdate.mp_qr_code = qrData;
    }

    if (pagamentoEstaPago(statusMp)) {
        if (ped.status === "pendente" && String(ped.mp_payment_id) === String(paymentId)) {
            return { ok: true, already: true };
        }
        if (ped.status !== "aguardando_pagamento") {
            console.warn("[mp] Pedido não está aguardando pagamento:", ped.status, extRef);
            return { ok: false, reason: "invalid_pedido_state" };
        }

        await pedidoRef.update({
            ...baseUpdate,
            status: "pendente",
            forma_pagamento: ped.forma_pagamento || "PIX",
            pagamento_confirmado_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Push ao cliente: disparado por notificarClienteStatusPedido (aguardando_pagamento → pendente).
        // Push à loja (novo pedido + som pedido): mesmo payload que notificarNovoPedido — aqui garantido
        // no mesmo fluxo do MP (o trigger Firestore onUpdate pode falhar silenciosamente em edge cases).
        const lojaIdFcm = ped.loja_id || ped.lojista_id;
        if (lojaIdFcm) {
            const pedidoParaFcm = {
                ...ped,
                ...baseUpdate,
                status: "pendente",
                forma_pagamento: ped.forma_pagamento || "PIX",
            };
            try {
                await notificationDispatcher.enviarNovoPedidoParaLoja(
                    db,
                    String(lojaIdFcm),
                    extRef,
                    pedidoParaFcm,
                );
            } catch (e) {
                console.error("[mp] enviarNovoPedidoParaLoja pós-PIX:", e.message || e);
            }
        }

        try {
            await promoverIrmaosGrupoAposPagamentoAprovado(db, extRef, ped, payment, baseUpdate, statusMp);
        } catch (e) {
            console.error("[mp] promoverIrmaosGrupoAposPagamentoAprovado:", e.message || e);
        }

        return { ok: true, approved: true };
    }

    if (statusMp === "pending" || statusMp === "in_process") {
        const update = { ...baseUpdate };
        if (!ped.pix_expira_em) {
            const ms = PIX_PRAZO_MINUTOS * 60 * 1000;
            update.pix_expira_em = admin.firestore.Timestamp.fromMillis(Date.now() + ms);
            update.pix_gerado_em = admin.firestore.FieldValue.serverTimestamp();
        }
        await pedidoRef.update(update);
        const merged = { ...ped, ...update };
        try {
            await copiarPixGrupoParaIrmaos(db, extRef, merged, {
                pix_expira_em: merged.pix_expira_em || null,
                pix_gerado_em: merged.pix_gerado_em || null,
                mp_status: statusMp,
                mp_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
        } catch (e) {
            console.error("[mp] copiarPixGrupoParaIrmaos:", e.message || e);
        }
        return { ok: true, pending: true };
    }

    if (statusMp === "rejected" || statusMp === "cancelled" || statusMp === "refunded") {
        await pedidoRef.update({
            ...baseUpdate,
            mp_erro_detalhe: payment.status_detail || null,
            status_pagamento_mp: statusMp,
        });
        return { ok: true, rejected: true };
    }

    await pedidoRef.update(baseUpdate);
    return { ok: true, ignored: true };
}

function extrairPaymentIdDoWebhook(req, body) {
    if (body && body.data && body.data.id != null) {
        return String(body.data.id);
    }
    if (body && body.id != null && (body.type === "payment" || body.topic === "payment")) {
        return String(body.id);
    }
    const q = req.query || {};
    if (q["data.id"]) return String(q["data.id"]);
    if (q.id && (q.type === "payment" || q.topic === "payment")) return String(q.id);
    if (q.id) return String(q.id);
    return null;
}

/**
 * POST /webhookMercadoPago — notificações IPN/Webhooks Mercado Pago.
 */
exports.webhookMercadoPago = functions.https.onRequest(async (req, res) => {
    res.set("Cache-Control", "no-store");
    if (req.method === "GET") {
        return res.status(200).send("ok");
    }
    if (req.method !== "POST") {
        return res.status(405).send("Method Not Allowed");
    }

    let body = {};
    try {
        if (typeof req.body === "string") {
            body = JSON.parse(req.body || "{}");
        } else if (req.body && typeof req.body === "object") {
            body = req.body;
        }
    } catch (e) {
        console.error("[mp] JSON inválido no webhook", e);
        return res.status(400).send("bad json");
    }

    const secret = process.env.MP_WEBHOOK_SECRET || "";
    const allowUnsigned = String(process.env.MP_WEBHOOK_ALLOW_UNSIGNED || "").toLowerCase() === "true";
    if (!secret && !allowUnsigned) {
        console.error("[mp] MP_WEBHOOK_SECRET ausente. Recusando webhook.");
        return res.status(500).send("server misconfigured");
    }
    if (!validarAssinaturaWebhook(req, body, secret) && !allowUnsigned) {
        console.warn("[mp] Assinatura webhook inválida (defina MP_WEBHOOK_ALLOW_UNSIGNED=true só para testes ou corrija o secret no .env)");
        return res.status(401).send("invalid signature");
    }
    if (allowUnsigned && secret) {
        console.warn("[mp] MP_WEBHOOK_ALLOW_UNSIGNED=true — assinatura não bloqueou o processamento");
    }

    const paymentId = extrairPaymentIdDoWebhook(req, body);
    if (!paymentId) {
        console.log("[mp] Webhook sem payment id, body:", JSON.stringify(body).slice(0, 500));
        return res.status(200).send("no payment id");
    }

    const action = body.action || body.type || "";
    if (action && String(action).includes("merchant_order") && !body.data?.id) {
        return res.status(200).send("ignored merchant_order");
    }

    const token = await getMercadoPagoAccessToken();
    if (!token) {
        console.error("[mp] access_token indisponível");
        return res.status(500).send("no token");
    }

    try {
        const payment = await fetchPaymentFromMp(token, paymentId);
        await processarPagamentoMercadoPago(payment);
        return res.status(200).send("ok");
    } catch (e) {
        console.error("[mp] Erro webhook:", e.message || e);
        return res.status(500).send("error");
    }
});

/**
 * Callable (v2): cria pagamento PIX no backend (sem expor access_token no cliente).
 */
exports.mpCriarPagamentoPix = onCall(
    PAYMENT_CALLABLE_OPTIONS,
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }

        const data = request.data || {};
        const pedidoId = data.pedidoId != null ? String(data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new HttpsError("invalid-argument", "pedidoId obrigatório.");
        }

        const uid = request.auth.uid;
        const db = admin.firestore();
        const pedRef = db.collection("pedidos").doc(pedidoId);
        const pedSnap = await pedRef.get();
        if (!pedSnap.exists) {
            throw new HttpsError("not-found", "Pedido não encontrado.");
        }

        const ped = pedSnap.data() || {};
        if (ped.cliente_id !== uid) {
            throw new HttpsError("permission-denied", "Pedido de outro usuário.");
        }
        if (ped.status !== "aguardando_pagamento") {
            throw new HttpsError("failed-precondition", "Pedido não está aguardando pagamento.");
        }

        const token = await getMercadoPagoAccessToken();
        if (!token) {
            throw new HttpsError("failed-precondition", "Gateway Mercado Pago indisponível.");
        }

        const emailPayer =
            (data.email != null ? String(data.email).trim() : "") ||
            (request.auth.token?.email ? String(request.auth.token.email).trim() : "") ||
            "cliente@depertin.com";

        try {
            const payment = await criarPagamentoPixMp(token, {
                transaction_amount: valorMercadoPagoEsperadoNoPedido(ped),
                description: "Pedido DiPertin",
                payment_method_id: "pix",
                payer: { email: emailPayer },
                external_reference: pedidoId,
            }, pedidoId);

            await processarPagamentoMercadoPago(payment);
            const td = payment.point_of_interaction?.transaction_data || {};
            return {
                ok: true,
                paymentId: payment.id || null,
                mp_status: payment.status || null,
                qr_code: td.qr_code || null,
                qr_code_base64: td.qr_code_base64 || null,
            };
        } catch (e) {
            console.error("[mp] mpCriarPagamentoPix:", e.message || e);
            throw new HttpsError("internal", "Falha ao gerar pagamento PIX.");
        }
    },
);

/**
 * Callable (v2): mesmo nome no app.
 */
exports.mpVincularPagamentoPix = onCall(
    PAYMENT_CALLABLE_OPTIONS,
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }
        const data = request.data || {};
        const pedidoId = data.pedidoId != null ? String(data.pedidoId).trim() : "";
        const paymentId = data.paymentId != null ? data.paymentId : null;
        if (!pedidoId || paymentId == null) {
            throw new HttpsError("invalid-argument", "pedidoId e paymentId obrigatórios.");
        }

        const uid = request.auth.uid;
        const db = admin.firestore();
        const pedRef = db.collection("pedidos").doc(pedidoId);
        const pedSnap = await pedRef.get();
        if (!pedSnap.exists) {
            throw new HttpsError("not-found", "Pedido não encontrado.");
        }
        const ped = pedSnap.data();
        if (ped.cliente_id !== uid) {
            throw new HttpsError("permission-denied", "Pedido de outro usuário.");
        }

        if (ped.status === "pendente" && String(ped.mp_payment_id) === String(paymentId)) {
            return {
                ok: true,
                already: true,
                mp_status: ped.mp_status || "approved",
                result: { ok: true, already: true },
            };
        }

        if (ped.status !== "aguardando_pagamento") {
            throw new HttpsError("failed-precondition", "Pedido não aguarda PIX.");
        }

        const token = await getMercadoPagoAccessToken();
        if (!token) {
            throw new HttpsError("failed-precondition", "Gateway indisponível.");
        }

        let payment;
        try {
            payment = await fetchPaymentFromMp(token, paymentId);
        } catch (e) {
            console.error("[mp] mpVincularPagamentoPix fetch:", e);
            throw new HttpsError("internal", "Falha ao consultar Mercado Pago.");
        }

        const ext = payment.external_reference != null ? String(payment.external_reference).trim() : "";
        if (ext !== pedidoId) {
            throw new HttpsError("failed-precondition", "Pagamento não pertence a este pedido.");
        }
        const esperado = valorMercadoPagoEsperadoNoPedido(ped);
        if (!amountsMatch(esperado, payment.transaction_amount)) {
            throw new HttpsError(
                "failed-precondition",
                `Valor divergente (pedido ${esperado} vs MP ${payment.transaction_amount}).`,
            );
        }

        const result = await processarPagamentoMercadoPago(payment);
        return {
            ok: true,
            mp_status: payment.status,
            result,
        };
    }
);

/**
 * Callable (v2): processa pagamento com cartão no Mercado Pago.
 * Mantém o mesmo fluxo de confirmação já existente: status do pedido
 * muda para `pendente` quando o MP confirmar.
 */
exports.mpProcessarPagamentoCartao = onCall(
    PAYMENT_CALLABLE_OPTIONS,
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }
        const data = request.data || {};
        const pedidoId = data.pedidoId != null ? String(data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new HttpsError("invalid-argument", "pedidoId obrigatório.");
        }
        const numero = data.numeroCartao != null ? String(data.numeroCartao).replace(/\D/g, "") : "";
        const nomeTitular = data.nomeTitular != null ? String(data.nomeTitular).trim() : "";
        const mes = Number(data.mesExpiracao || 0);
        const ano = Number(data.anoExpiracao || 0);
        const cvv = data.cvv != null ? String(data.cvv).replace(/\D/g, "") : "";
        const paymentMethodId = data.paymentMethodId != null ? String(data.paymentMethodId).trim().toLowerCase() : "";
        const tipoCartaoRaw = data.tipoCartao != null ? String(data.tipoCartao).trim().toLowerCase() : "credito";
        const isDebito = tipoCartaoRaw === "debito" || tipoCartaoRaw === "debit";
        const cpf = data.cpf != null ? String(data.cpf).replace(/\D/g, "") : "";
        const parcelas = Number(data.parcelas || 1);
        if (!numero || !nomeTitular || !mes || !ano || !cvv || !paymentMethodId) {
            throw new HttpsError("invalid-argument", "Dados do cartão incompletos.");
        }

        const uid = request.auth.uid;
        const db = admin.firestore();
        const pedRef = db.collection("pedidos").doc(pedidoId);
        const pedSnap = await pedRef.get();
        if (!pedSnap.exists) {
            throw new HttpsError("not-found", "Pedido não encontrado.");
        }
        const ped = pedSnap.data() || {};
        if (ped.cliente_id !== uid) {
            throw new HttpsError("permission-denied", "Pedido de outro usuário.");
        }
        if (ped.status === "pendente") {
            return {
                ok: true,
                already: true,
                mp_status: ped.mp_status || "approved",
                result: { ok: true, already: true },
            };
        }
        if (ped.status !== "aguardando_pagamento") {
            throw new HttpsError("failed-precondition", "Pedido não está aguardando pagamento.");
        }

        const registrarTentativa = async (campos = {}) => {
            await pedRef.set(
                {
                    pagamento_tentativa_tipo: "cartao",
                    pagamento_tentativa_em: admin.firestore.FieldValue.serverTimestamp(),
                    pagamento_tentativa_uid: uid,
                    pagamento_tentativa_numero: admin.firestore.FieldValue.increment(1),
                    ...campos,
                },
                { merge: true },
            );
        };

        await registrarTentativa({
            pagamento_tentativa_etapa: "inicio",
            pagamento_tentativa_status: "iniciado",
            pagamento_cartao_tipo_solicitado: isDebito ? "debito" : "credito",
            pagamento_cartao_bandeira_mp: paymentMethodId || null,
        });

        const gateway = await getMercadoPagoGatewayConfig();
        if (!gateway || !gateway.accessToken) {
            throw new HttpsError("failed-precondition", "Gateway Mercado Pago indisponível.");
        }

        const usuarioAuth = request.auth.token || {};
        const emailPayer =
            (data.email != null ? String(data.email).trim() : "") ||
            (usuarioAuth.email ? String(usuarioAuth.email).trim() : "") ||
            "cliente@depertin.com";

        let cardToken;
        try {
            const tokenPayload = {
                card_number: numero,
                expiration_month: mes,
                expiration_year: ano,
                security_code: cvv,
                cardholder: {
                    name: nomeTitular,
                    ...(cpf
                        ? {
                            identification: {
                                type: "CPF",
                                number: cpf,
                            },
                        }
                        : {}),
                },
            };
            cardToken = await criarCardTokenMp({
                publicKey: gateway.publicKey,
                accessToken: gateway.accessToken,
                payload: tokenPayload,
            });
            await registrarTentativa({
                pagamento_tentativa_etapa: "tokenizacao",
                pagamento_tentativa_status: "ok",
                pagamento_tentativa_token_id: cardToken.id || null,
            });
        } catch (e) {
            console.error("[mp] cartão token:", e.message || e);
            const body = e && e.body && typeof e.body === "object" ? e.body : {};
            const causa = Array.isArray(body.cause) && body.cause.length
                ? String(body.cause[0]?.description || "")
                : "";
            const codigoMp = extrairCodigoMp(body);
            const detalhe = (
                causa ||
                String(body.message || "") ||
                String(body.error || "") ||
                String(e.message || "") ||
                "Falha na tokenização do cartão."
            ).trim();
            const traduzido = traduzirRecusaMp({
                status: "rejected",
                statusDetail: "",
                erroCodigo: codigoMp,
                erroMensagem: detalhe,
            });
            await registrarTentativa({
                pagamento_tentativa_etapa: "tokenizacao",
                pagamento_tentativa_status: "erro",
                pagamento_tentativa_erro: traduzido.mensagem,
                pagamento_tentativa_erro_codigo: traduzido.codigo,
            });
            await cancelarPedidosGrupoCheckoutEmEspera(db, pedidoId, {
                cancelado_motivo: "cartao_tokenizacao_erro",
            });
            await pedRef.set(
                {
                    mp_status: "rejected",
                    status_pagamento_mp: "rejected",
                    mp_erro_detalhe: codigoMp || detalhe,
                    pagamento_recusado_codigo: traduzido.codigo,
                    pagamento_recusado_mensagem: traduzido.mensagem,
                    mp_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
            );
            throw new HttpsError("failed-precondition", traduzido.mensagem);
        }

        let payment;
        try {
            const paymentMethodFromToken = String(
                cardToken?.payment_method_id || paymentMethodId || "",
            ).trim().toLowerCase();
            const issuerIdRaw = cardToken?.issuer?.id;
            const issuerId = issuerIdRaw != null ? String(issuerIdRaw).trim() : "";
            const parcelasFinal = isDebito ? 1 : (Number.isFinite(parcelas) && parcelas > 0 ? parcelas : 1);
            payment = await criarPagamentoMpComCartao(gateway.accessToken, {
                transaction_amount: valorMercadoPagoEsperadoNoPedido(ped),
                token: cardToken.id,
                installments: parcelasFinal,
                payment_method_id: paymentMethodFromToken || paymentMethodId,
                payment_type_id: isDebito ? "debit_card" : "credit_card",
                binary_mode: true,
                description: `Pedido DiPertin ${pedidoId}`,
                external_reference: pedidoId,
                ...(issuerId ? { issuer_id: issuerId } : {}),
                payer: {
                    email: emailPayer,
                    ...(cpf
                        ? {
                            identification: {
                                type: "CPF",
                                number: cpf,
                            },
                        }
                        : {}),
                },
            });
            await registrarTentativa({
                pagamento_tentativa_etapa: "criacao_pagamento",
                pagamento_tentativa_status: "ok",
                pagamento_tentativa_payment_id: payment.id || null,
                pagamento_tentativa_payment_method: paymentMethodFromToken || paymentMethodId,
                pagamento_tentativa_issuer_id: issuerId || null,
            });
        } catch (e) {
            console.error("[mp] cartão pagamento:", e.message || e);
            const body = e && e.body && typeof e.body === "object" ? e.body : {};
            const msgBody =
                String(body.message || "") ||
                String(body.error || "") ||
                String(e.message || "");
            const causa = Array.isArray(body.cause) && body.cause.length
                ? String(body.cause[0]?.description || "")
                : "";
            const codigoMp = extrairCodigoMp(body);
            const detalheRaw = (causa || msgBody || "Pagamento recusado pelo provedor.").trim();
            const traduzido = traduzirRecusaMp({
                status: "rejected",
                statusDetail: "",
                erroCodigo: codigoMp,
                erroMensagem: detalheRaw,
            });
            await registrarTentativa({
                pagamento_tentativa_etapa: "criacao_pagamento",
                pagamento_tentativa_status: "erro",
                pagamento_tentativa_erro: traduzido.mensagem,
                pagamento_tentativa_erro_codigo: traduzido.codigo,
                pagamento_tentativa_raw_ref: String(body.id || body.reference || ""),
            });
            await cancelarPedidosGrupoCheckoutEmEspera(db, pedidoId, {
                cancelado_motivo: "cartao_recusado_provedor",
            });
            await pedRef.set(
                {
                    mp_status: "rejected",
                    status_pagamento_mp: "rejected",
                    mp_erro_detalhe: codigoMp || detalheRaw,
                    pagamento_recusado_codigo: traduzido.codigo,
                    pagamento_recusado_mensagem: traduzido.mensagem,
                    pagamento_cartao_tipo_solicitado: isDebito ? "debito" : "credito",
                    pagamento_cartao_bandeira_mp: paymentMethodId || null,
                    mp_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
            );
            throw new HttpsError("failed-precondition", traduzido.mensagem);
        }

        const paymentId = payment.id;
        if (paymentId) {
            payment = await aguardarConclusaoPagamentoMp(gateway.accessToken, paymentId, 8, 2500);
        }
        const result = await processarPagamentoMercadoPago(payment);
        const statusFinal = String(payment.status || "");
        const statusDetailFinal = String(payment.status_detail || "");
        const traduzidoFinal = traduzirRecusaMp({
            status: statusFinal,
            statusDetail: statusDetailFinal,
            erroCodigo: statusDetailFinal,
            erroMensagem: "",
        });
        const tipoSolicitado = isDebito ? "debito" : "credito";
        const tipoMp =
            String(
                payment.payment_method?.payment_type_id ||
                payment.payment_type_id ||
                "",
            ).toLowerCase();
        const bandeiraMp = String(
            payment.payment_method_id ||
            cardToken?.payment_method_id ||
            paymentMethodId ||
            "",
        ).toLowerCase();

        await pedRef.set(
            {
                pagamento_cartao_tipo_solicitado: tipoSolicitado,
                pagamento_cartao_tipo_mp: tipoMp || null,
                pagamento_cartao_bandeira_mp: bandeiraMp || null,
                mp_status: statusFinal || null,
                status_pagamento_mp: statusFinal || null,
                mp_erro_detalhe: statusDetailFinal || null,
                pagamento_recusado_codigo:
                    statusFinal === "approved" || statusFinal === "authorized"
                        ? null
                        : traduzidoFinal.codigo,
                pagamento_recusado_mensagem:
                    statusFinal === "approved" || statusFinal === "authorized"
                        ? null
                        : traduzidoFinal.mensagem,
                mp_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
        );
        await registrarTentativa({
            pagamento_tentativa_etapa: "resultado_final",
            pagamento_tentativa_status:
                statusFinal === "approved" || statusFinal === "authorized"
                    ? "aprovado"
                    : "recusado",
            pagamento_tentativa_payment_id: payment.id || null,
            pagamento_tentativa_mp_status: statusFinal || null,
            pagamento_tentativa_mp_detail: statusDetailFinal || null,
        });

        if (!(statusFinal === "approved" || statusFinal === "authorized")) {
            const snapAtual = await pedRef.get();
            const pedidoAtual = snapAtual.data() || {};
            if (pedidoAtual.status === "aguardando_pagamento") {
                await cancelarPedidosGrupoCheckoutEmEspera(db, pedidoId, {
                    cancelado_motivo: "cartao_nao_concluido",
                });
            }
        }
        return {
            ok: true,
            mp_status: statusFinal,
            payment_id: payment.id || null,
            pagamento_cartao_tipo_solicitado: tipoSolicitado,
            pagamento_cartao_tipo_mp: tipoMp || null,
            result,
        };
    }
);

/**
 * Estorno automático no Mercado Pago quando pedido pago é cancelado.
 * Estorno parcial (sem taxa de entrega) se o pedido estava em saiu_entrega / em_rota / a_caminho.
 */
exports.estornarPagamentoPedidoCancelado = functions.firestore
    .document("pedidos/{pedidoId}")
    .onUpdate(async (change, context) => {
        const db = admin.firestore();
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        if (antes.status === "cancelado" || depois.status !== "cancelado") {
            return null;
        }

        const pagamentoId = await resolverMpPaymentIdParaPedido(db, depois, antes);
        if (!pagamentoId) {
            return null;
        }

        const refundStatus = String(depois.mp_refund_status || "");
        if (
            refundStatus === "succeeded" ||
            refundStatus === "already_refunded" ||
            refundStatus === "processing"
        ) {
            return null;
        }

        const token = await getMercadoPagoAccessToken();
        if (!token) {
            await change.after.ref.set(
                {
                    mp_refund_status: "error",
                    mp_refund_error: "Gateway Mercado Pago indisponível para estorno.",
                    mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
            );
            return null;
        }

        try {
            const pagamento = await fetchPaymentFromMp(token, pagamentoId);
            const statusMp = String(pagamento.status || "");

            if (statusMp === "refunded") {
                await change.after.ref.set(
                    {
                        mp_refund_status: "already_refunded",
                        mp_refund_payment_status: statusMp,
                        mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true },
                );
                return null;
            }

            if (!pagamentoEstaPago(statusMp)) {
                await change.after.ref.set(
                    {
                        mp_refund_status: "skipped_not_paid",
                        mp_refund_payment_status: statusMp,
                        mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true },
                );
                return null;
            }

            await change.after.ref.set(
                {
                    mp_refund_status: "processing",
                    mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
            );

            const statusAnteriorPedido = String(antes.status || "");
            const taxaEntrega = roundMoneyMp(
                depois.taxa_entrega != null ? depois.taxa_entrega : antes.taxa_entrega,
            );
            const parcialFreteRetido =
                STATUS_CANCEL_PARCIAL_FRETE.has(statusAnteriorPedido) && taxaEntrega > 0;

            const maxReembolsavel = valorMaximoReembolsavelApartirDoPagamentoMp(pagamento);
            if (maxReembolsavel <= 0) {
                await change.after.ref.set(
                    {
                        mp_refund_status: "skipped_no_refundable_balance",
                        mp_refund_payment_status: statusMp,
                        mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true },
                );
                return null;
            }

            let valorReembolsoCalc = valorReembolsoClienteCancelamento(antes, depois);
            if (valorReembolsoCalc > maxReembolsavel) {
                valorReembolsoCalc = maxReembolsavel;
            }
            valorReembolsoCalc = roundMoneyMp(valorReembolsoCalc);

            /** Estorno via API total só quando o valor calculado drena o saldo restante no MP. */
            const EPS = 0.03;
            const refundViaTotalApi =
                valorReembolsoCalc > 0 && valorReembolsoCalc >= maxReembolsavel - EPS;
            const usouApiParcial = valorReembolsoCalc > 0 && !refundViaTotalApi;
            const mpRefundParcialFreteRetidoUi = parcialFreteRetido && usouApiParcial;

            let refund;
            if (valorReembolsoCalc <= 0) {
                await change.after.ref.set(
                    {
                        mp_refund_status: "skipped_zero_amount",
                        mp_refund_valor_calculado: 0,
                        mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true },
                );
                return null;
            }

            if (refundViaTotalApi) {
                refund = await criarEstornoTotalMp(token, pagamentoId);
            } else {
                refund = await criarEstornoParcialMp(token, pagamentoId, valorReembolsoCalc);
            }

            await change.after.ref.set(
                {
                    mp_refund_status: "succeeded",
                    mp_refund_id: refund.id || null,
                    mp_refund_total: Number(refund.amount || refund.total_refunded_amount || 0),
                    mp_refund_raw_status: refund.status || null,
                    mp_refund_at: admin.firestore.FieldValue.serverTimestamp(),
                    mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    mp_refund_parcial_frete_retido: mpRefundParcialFreteRetidoUi,
                    mp_refund_valor_calculado: valorReembolsoCalc,
                    mp_refund_taxa_entrega_retida: mpRefundParcialFreteRetidoUi ? taxaEntrega : null,
                },
                { merge: true },
            );

            if (mpRefundParcialFreteRetidoUi) {
                try {
                    await creditarEntregadorFreteCancelamentoCliente(
                        change,
                        context,
                        antes,
                        depois,
                    );
                } catch (credErr) {
                    console.error(
                        "[mp] credito entregador pos-estorno parcial:",
                        credErr.message || credErr,
                    );
                }
            }
            return null;
        } catch (e) {
            console.error("[mp] estorno automático:", e.message || e);
            await change.after.ref.set(
                {
                    mp_refund_status: "error",
                    mp_refund_error: String(e.message || e),
                    mp_refund_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
            );
            return null;
        }
    });

/**
 * Job periódico: cancela pedidos em aguardando_pagamento após pix_expira_em.
 */
exports.cancelarPedidosPixExpirados = functions.pubsub
    .schedule("every 1 minutes")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
        const db = admin.firestore();
        const agora = admin.firestore.Timestamp.now();
        const snap = await db
            .collection("pedidos")
            .where("status", "==", "aguardando_pagamento")
            .where("pix_expira_em", "<=", agora)
            .limit(50)
            .get();
        if (snap.empty) {
            return null;
        }
        const jaProcessado = new Set();
        let n = 0;
        for (const doc of snap.docs) {
            if (jaProcessado.has(doc.id)) continue;
            const d = doc.data() || {};
            const ids = idsGrupoCheckoutDoPedido(d) || [doc.id];
            for (const gid of ids) {
                jaProcessado.add(gid);
            }
            const patch = {
                cancelado_motivo: "pix_expirado",
            };
            const k = await cancelarPedidosGrupoCheckoutEmEspera(db, doc.id, patch);
            n += k;
        }
        console.log(`[mp] Pedidos cancelados por PIX expirado: ${n}`);
        return null;
    });

/**
 * Cliente: ao zerar o cronômetro de 5 min (ou alinhar com o servidor).
 */
exports.cancelarPedidoPixExpirado = onCall(
    PAYMENT_CALLABLE_OPTIONS,
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }
        const pedidoId =
            request.data?.pedidoId != null ? String(request.data.pedidoId).trim() : "";
        if (!pedidoId) {
            throw new HttpsError("invalid-argument", "pedidoId obrigatório.");
        }
        const uid = request.auth.uid;
        const db = admin.firestore();
        const pedRef = db.collection("pedidos").doc(pedidoId);
        const pedSnap = await pedRef.get();
        if (!pedSnap.exists) {
            throw new HttpsError("not-found", "Pedido não encontrado.");
        }
        const ped = pedSnap.data();
        if (ped.cliente_id !== uid) {
            throw new HttpsError("permission-denied", "Pedido de outro usuário.");
        }
        if (ped.status !== "aguardando_pagamento") {
            return { ok: false, reason: "nao_aguarda" };
        }
        const agora = Date.now();
        const expMs = ped.pix_expira_em?.toMillis?.() ?? 0;
        const margemMs = 15000;
        if (expMs > 0 && agora < expMs - margemMs) {
            throw new HttpsError(
                "failed-precondition",
                "O prazo do PIX ainda não terminou.",
            );
        }
        await cancelarPedidosGrupoCheckoutEmEspera(db, pedidoId, {
            cancelado_motivo: "pix_expirado",
        });
        return { ok: true };
    }
);
