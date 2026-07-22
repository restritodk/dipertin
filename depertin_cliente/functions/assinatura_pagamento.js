"use strict";

/**
 * Assinatura de Planos — Pagamento via Mercado Pago (PIX + Cartão).
 *
 * Usa as credenciais globais da plataforma em gateways_pagamento/mercado_pago
 * (mesmo token do marketplace). NÃO usa gateway por loja.
 *
 * Fluxo:
 * 1. Lojista escolhe plano → clica "Escolher plano"
 * 2. Modal de pagamento (PIX ou Cartão)
 * 3. PIX: cria cobrança → frontend mostra QR Code → frontend polling status
 * 4. Cartão: processa pagamento síncrono → retorna aprovado/recusado
 * 5. Pagamento aprovado → cria assinatura ativa em assinaturas_clientes
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const MP_API = "https://api.mercadopago.com";
const ASSINATURA_MP_WEBHOOK_URL =
    "https://us-central1-depertin-f940f.cloudfunctions.net/webhookMercadoPagoGestaoComercial";

// =============================================================================
// HELPERS MP
// =============================================================================

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

async function getMercadoPagoGatewayConfig() {
    const doc = await admin
        .firestore()
        .collection("gateways_pagamento")
        .doc("mercado_pago")
        .get();
    if (!doc.exists || doc.data().ativo !== true) return null;
    const d = doc.data() || {};
    const accessToken = d.access_token && String(d.access_token).trim()
        ? String(d.access_token).trim()
        : null;
    const publicKey = d.public_key && String(d.public_key).trim()
        ? String(d.public_key).trim()
        : null;
    if (!accessToken) return null;
    return { accessToken, publicKey: publicKey || null };
}

/**
 * Cria pagamento PIX no Mercado Pago.
 */
async function criarPagamentoPixMp(accessToken, payload, idRef) {
    const idempotencyKey = "assinatura-pix-" + String(idRef || Date.now());
    const res = await fetch(MP_API + "/v1/payments", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
            "X-Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify(payload),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const err = new Error(body.message || "MP PIX " + res.status);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

/**
 * Cria pagamento com cartão no Mercado Pago.
 */
async function criarPagamentoMpComCartao(accessToken, payload) {
    const idempotencyKey = "assinatura-card-" + String(payload.external_reference || Date.now());
    const res = await fetch(MP_API + "/v1/payments", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
            "X-Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify(payload),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const err = new Error(body.message || "MP CARD " + res.status);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

/**
 * Tokeniza cartão no MP (backend).
 */
function normalizarExpiracaoCartao(mesRaw, anoRaw) {
    const mes = parseInt(String(mesRaw || "").replace(/\D/g, ""), 10);
    let ano = parseInt(String(anoRaw || "").replace(/\D/g, ""), 10);
    if (!Number.isFinite(mes) || mes < 1 || mes > 12) return null;
    if (!Number.isFinite(ano) || ano <= 0) return null;
    if (ano < 100) ano += 2000;
    if (ano < 2000 || ano > 2099) return null;
    return { mes: mes, ano: ano };
}

function mensagemErroTokenizacaoMp(err) {
    const body = err && err.body && typeof err.body === "object" ? err.body : {};
    const causa = Array.isArray(body.cause) && body.cause.length
        ? String(body.cause[0].description || body.cause[0].code || "")
        : "";
    const msg = String(body.message || (err && err.message) || "").trim();
    const texto = (causa + " " + msg).toLowerCase();
    if (/expiration|validade|date|expir|e301/.test(texto)) {
        return "Data de validade inválida. Use MM/AA (ex.: 03/33).";
    }
    if (/security|cvv|cvc|security_code/.test(texto)) {
        return "CVV inválido. Verifique o código de segurança.";
    }
    if (/card_number|bin|number|card number/.test(texto)) {
        return "Número do cartão inválido.";
    }
    if (/identification|cpf|user identification/.test(texto)) {
        return "CPF do titular inválido.";
    }
    if (/cardholder|titular|name/.test(texto)) {
        return "Nome do titular inválido (use como está no cartão).";
    }
    if (causa) return causa;
    if (msg && !/^mp tokenize/i.test(msg)) return msg;
    return "Dados do cartão inválidos. Verifique o número, validade e CVV.";
}

function cpfValidoMp(cpfRaw) {
    const cpf = String(cpfRaw || "").replace(/\D/g, "");
    if (!cpf || cpf.length !== 11) return false;
    if (/^(\d)\1{10}$/.test(cpf)) return false;
    const calcDig = (ate) => {
        let soma = 0;
        for (let i = 0; i < ate; i++) {
            soma += Number(cpf[i]) * ((ate + 1) - i);
        }
        const r = (soma * 10) % 11;
        return r === 10 ? 0 : r;
    };
    return calcDig(9) === Number(cpf[9]) && calcDig(10) === Number(cpf[10]);
}

async function tokenizarCartaoMp(gateway, dadosCartao) {
    const exp = normalizarExpiracaoCartao(
        dadosCartao.mesExpiracao,
        dadosCartao.anoExpiracao,
    );
    if (!exp) {
        const err = new Error("expiration_invalid");
        err.body = { message: "Data de validade inválida." };
        throw err;
    }

    const payload = {
        card_number: String(dadosCartao.numeroCartao || "").replace(/\D/g, ""),
        expiration_month: exp.mes,
        expiration_year: exp.ano,
        security_code: String(dadosCartao.cvv || "").replace(/\D/g, ""),
        cardholder: {
            name: String(dadosCartao.nomeTitular || "").trim().toUpperCase(),
            identification: {
                type: "CPF",
                number: String(dadosCartao.cpf || "").replace(/\D/g, ""),
            },
        },
    };

    const authCandidates = [];
    if (gateway && gateway.accessToken) authCandidates.push(gateway.accessToken);
    if (gateway && gateway.publicKey) authCandidates.push(gateway.publicKey);

    let lastError = null;
    for (const credential of authCandidates) {
        const res = await fetch(MP_API + "/v1/card_tokens", {
            method: "POST",
            headers: {
                Authorization: "Bearer " + credential,
                "Content-Type": "application/json",
            },
            body: JSON.stringify(payload),
        });
        const body = await res.json().catch(() => ({}));
        if (res.ok && body && body.id) {
            return body;
        }
        lastError = new Error(body.message || "MP tokenize " + res.status);
        lastError.status = res.status;
        lastError.body = body;
    }

    if (lastError) throw lastError;
    throw new Error("Falha ao tokenizar cartão.");
}

/**
 * Resolve payment_method_id oficial pelo BIN (anti diff_param_bins).
 */
async function resolverMetodoPagamentoPorBinMp(gateway, bin) {
    const binLimpo = String(bin || "").replace(/\D/g, "").slice(0, 8);
    if (binLimpo.length < 6) return null;
    const publicKey = gateway && gateway.publicKey ? String(gateway.publicKey).trim() : "";
    if (!publicKey) {
        console.warn("[assinatura-pagamento] BIN search: public_key ausente no gateway");
        return null;
    }
    const authCandidates = [];
    if (gateway && gateway.accessToken) authCandidates.push(gateway.accessToken);
    authCandidates.push(publicKey);
    const urlBase =
        MP_API + "/v1/payment_methods/search?bin=" + binLimpo.slice(0, 8) +
        "&public_key=" + encodeURIComponent(publicKey);
    try {
        for (const credential of authCandidates) {
            const res = await fetch(urlBase, {
                headers: { Authorization: "Bearer " + credential },
            });
            const body = await res.json().catch(() => ({}));
            if (res.ok && body.results && body.results.length > 0) {
                const credito = body.results.find(
                    (r) => String(r.payment_type_id || "").toLowerCase() === "credit_card",
                );
                const r = credito || body.results[0];
                return {
                    payment_method_id: r.id,
                    payment_type_id: r.payment_type_id,
                    issuer_id: r.issuer_id,
                };
            }
        }
    } catch (e) {
        console.warn("[assinatura-pagamento] BIN search failed:", e.message);
    }
    return null;
}

/**
 * Busca status do pagamento no MP.
 * Falha se HTTP não for 2xx ou se o body não tiver id/status válidos.
 */
async function fetchPaymentFromMp(accessToken, paymentId) {
    const id = String(paymentId || "").trim();
    if (!id) {
        throw new Error("payment_id_ausente");
    }
    const res = await fetch(MP_API + "/v1/payments/" + encodeURIComponent(id), {
        headers: { Authorization: "Bearer " + accessToken },
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
        const msg = (body && (body.message || body.error)) || ("HTTP " + res.status);
        throw new Error("mp_fetch_falhou: " + msg);
    }
    if (!body || body.id == null) {
        throw new Error("mp_resposta_invalida");
    }
    return body;
}

/**
 * PIX (e renovação) só confirma com status exatamente "approved".
 * "authorized" NÃO conta — é fluxo de cartão/pré-autorização, não pagamento liquidado.
 */
function mpStatusEhAprovado(status) {
    return String(status || "").trim().toLowerCase() === "approved";
}

/**
 * Polling de conclusão para cartão.
 */
async function aguardarConclusaoPagamentoMp(accessToken, paymentId, tentativas, intervaloMs) {
    tentativas = tentativas || 10;
    intervaloMs = intervaloMs || 2000;
    let ultimo = null;
    for (let i = 0; i < tentativas; i++) {
        ultimo = await fetchPaymentFromMp(accessToken, paymentId);
        const st = String(ultimo.status || "");
        if (st === "approved" || st === "authorized" || st === "rejected" || st === "cancelled" || st === "refunded") {
            return ultimo;
        }
        await new Promise(function (resolve) { setTimeout(resolve, intervaloMs); });
    }
    return ultimo;
}

// =============================================================================
// ATIVAR ASSINATURA (criar documento ativo)
// =============================================================================

async function ativarAssinatura(db, assinaturaId, dados) {
    const now = admin.firestore.Timestamp.now();

    // ── Ler configurações completas do plano ──
    let toleranciaDias = 3;
    let multaPercentual = 0;
    let jurosPercentual = 0;
    let cobrarMulta = false;
    let cobrarJuros = false;
    let suspenderInadimplencia = false;
    let suspenderAposDias = null;
    let duracaoDias = 30;
    let vencimentoPadrao = 'Todo dia 10';

    try {
        const planSnap = await db.collection("modulos_planos").doc(dados.planId).get();
        if (planSnap.exists) {
            const p = planSnap.data() || {};
            toleranciaDias = (p.tolerancia_dias != null) ? Number(p.tolerancia_dias) : 3;
            multaPercentual = (p.multa_percentual != null) ? Number(p.multa_percentual) : 0;
            jurosPercentual = (p.juros_percentual != null) ? Number(p.juros_percentual) : 0;
            cobrarMulta = p.cobrar_multa === true;
            cobrarJuros = p.cobrar_juros === true;
            suspenderInadimplencia = p.suspender_inadimplencia === true;
            suspenderAposDias = (p.suspender_apos_dias != null && p.suspender_inadimplencia === true)
                ? Number(p.suspender_apos_dias) : null;
            duracaoDias = (p.duracao_dias != null && Number(p.duracao_dias) > 0)
                ? Number(p.duracao_dias) : 30;
            vencimentoPadrao = String(p.vencimento_padrao || 'Todo dia 10');
        }
    } catch (e) {
        console.warn("[assinatura] erro ao ler plano:", e.message);
    }

    // ── next_billing_date baseado na duração REAL do plano ──
    const nextBillingSeconds = Math.floor(Date.now() / 1000) + duracaoDias * 24 * 60 * 60;

    const assinaturaData = {
        store_id: dados.lojaId,
        store_name: dados.lojaNome || "",
        owner_name: dados.ownerName || "",
        email: dados.ownerEmail || "",
        phone: dados.ownerPhone || "",
        plan_id: dados.planId,
        plan_name: dados.planName || "",
        status: "ativo",
        monthly_amount: dados.valor || 0,
        // ── Configurações financeiras propagadas do plano ──
        tolerancia_dias: toleranciaDias,
        multa_percentual: multaPercentual,
        juros_percentual: jurosPercentual,
        cobrar_multa: cobrarMulta,
        cobrar_juros: cobrarJuros,
        suspender_inadimplencia: suspenderInadimplencia,
        suspender_apos_dias: suspenderAposDias,
        duracao_dias: duracaoDias,
        vencimento_padrao: vencimentoPadrao,
        next_billing_date: new admin.firestore.Timestamp(
            nextBillingSeconds,
            0,
        ),
        last_payment_date: now,
        gateway: "Mercado Pago",
        modulos_extras: dados.modulos || [],
        historico: [
            {
                tipo: "contratacao",
                descricao: "Plano contratado com pagamento aprovado via Mercado Pago.",
                data_em: now,
            },
        ],
        created_at: now,
        updated_at: now,
        created_by: dados.lojaId,
        pagamento_mp_payment_id: dados.mpPaymentId || null,
        pagamento_mp_status: "approved",
        pagamento_aprovado_em: now,
    };

    // Preservar address_city e address_state do documento pendente (se existirem)
    try {
        const pendenteSnap = await db.collection("assinaturas_clientes").doc(assinaturaId).get();
        if (pendenteSnap.exists) {
            const pendenteData = pendenteSnap.data() || {};
            const city = String(pendenteData.address_city || "").trim();
            const state = String(pendenteData.address_state || "").trim().toUpperCase();
            if (city) assinaturaData.address_city = city;
            if (state) assinaturaData.address_state = state;
        }
    } catch (_) {
        // Silencioso — dados de endereço são opcionais
    }

    await db.collection("assinaturas_clientes").doc(assinaturaId).set(assinaturaData);

    // Registrar audit log
    try {
        await db.collection("audit_logs").add({
            acao: "assinatura_plano_contratado",
            categoria: "assinaturas",
            origem: "callable",
            criado_em: now,
            ator_uid: dados.lojaId,
            detalhe: {
                assinatura_id: assinaturaId,
                plan_name: dados.planName,
                valor: dados.valor,
                pagamento: "mp",
            },
        });
    } catch (e) {
        console.warn("[assinatura] audit log error:", e.message);
    }
}

// =============================================================================
// CALLABLE 1: CRIAR PIX PARA ASSINATURA
// =============================================================================

/**
 * onCall v2: Cria pagamento PIX para contratar um plano de assinatura.
 *
 * Entrada: { planId, lojaId, lojaNome, ownerName, ownerEmail, ownerPhone, valor, planName, modulos[] }
 * Resposta: { assinaturaId, paymentId, qrCode, qrCodeBase64, pixCopiaECola, expiresAt }
 */
exports.assinarPlanoCriarPagamentoPix = onCall(
    // TODO: voltar para `enforceAppCheck: true` após corrigir a Secret Key do
    // reCAPTCHA v3 no Firebase Console → App Check → depertin_web.
    // Sem token App Check o cliente recebe 401 UNAUTHENTICATED (Auth ok).
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }

        const data = request.data || {};
        const planId = String(data.planId || "").trim();
        const lojaId = String(data.lojaId || "").trim();
        const lojaNome = String(data.lojaNome || "").trim();
        const ownerName = String(data.ownerName || "").trim();
        const ownerEmail = String(data.ownerEmail || "").trim();
        const ownerPhone = String(data.ownerPhone || "").trim();
        const valor = Number(data.valor);
        const planName = String(data.planName || "").trim();
        const modulos = Array.isArray(data.modulos) ? data.modulos : [];

        if (!planId || !lojaId || !valor || valor <= 0) {
            throw new HttpsError("invalid-argument", "planId, lojaId e valor são obrigatórios.");
        }

        // Lojista só pode contratar para si mesmo
        if (lojaId !== request.auth.uid) {
            // Verificar se é colaborador autorizado
        }

        const db = admin.firestore();

        // 1. Ler token MP global
        const gateway = await getMercadoPagoGatewayConfig();
        if (!gateway || !gateway.accessToken) {
            throw new HttpsError(
                "failed-precondition",
                "Gateway de pagamento não configurado. Configure o Mercado Pago no painel administrativo.",
            );
        }

        // 2. Criar documento da assinatura com status pendente
        const assinaturaRef = db.collection("assinaturas_clientes").doc();
        const assinaturaId = assinaturaRef.id;
        const externalRef = "assinatura_" + assinaturaId;
        const now = admin.firestore.Timestamp.now();
        const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 min

        // Buscar dados de endereço do lojista
        let addressCity = "";
        let addressState = "";
        try {
            const lojaSnap = await db.collection("users").doc(lojaId).get();
            if (lojaSnap.exists) {
                const lojaData = lojaSnap.data() || {};
                addressCity = String(lojaData.endereco_cidade || lojaData.cidade || lojaData.cidade_normalizada || "").trim();
                addressState = String(lojaData.uf || lojaData.estado || "").trim().toUpperCase();
            }
        } catch (_) {
            console.warn("[assinatura] Não foi possível buscar endereço do lojista", lojaId);
        }

        // Gravar documento pendente
        await assinaturaRef.set({
            store_id: lojaId,
            store_name: lojaNome,
            owner_name: ownerName,
            email: ownerEmail,
            phone: ownerPhone,
            plan_id: planId,
            plan_name: planName,
            status: "pagamento_pendente",
            monthly_amount: valor,
            gateway: "Mercado Pago",
            modulos_extras: modulos,
            historico: [
                {
                    tipo: "criacao",
                    descricao: "Pagamento PIX aguardando confirmação.",
                    data_em: now,
                },
            ],
            created_at: now,
            updated_at: now,
            created_by: lojaId,
            external_reference: externalRef,
            pix_expira_em: expiresAt.toISOString(),
            address_city: addressCity,
            address_state: addressState,
        });

        // 3. Montar payload PIX
        const description = "Assinatura " + (planName || "Plano DiPertin") + " - " + lojaNome;
        const pixPayload = {
            transaction_amount: valor,
            description: description,
            payment_method_id: "pix",
            payer: {
                email: ownerEmail || request.auth.token.email || "nao-informado@dipertin.com",
                first_name: ownerName || lojaNome || "Lojista",
            },
            external_reference: externalRef,
            notification_url: ASSINATURA_MP_WEBHOOK_URL,
            metadata: {
                tipo: "assinatura_contratacao",
                assinatura_id: assinaturaId,
                assinaturaId: assinaturaId,
                store_id: lojaId,
                storeId: lojaId,
                plan_id: planId,
            },
        };

        // 4. Criar PIX no MP
        let mpResponse;
        try {
            mpResponse = await criarPagamentoPixMp(gateway.accessToken, pixPayload, assinaturaId);
        } catch (mpErr) {
            // Se falhar, remover o documento pendente
            await assinaturaRef.delete().catch(function () {});
            console.error("[assinatura-pix] MP error:", mpErr.message);
            throw new HttpsError("internal", "Erro ao gerar PIX. Tente novamente.");
        }

        const paymentId = mpResponse.id;
        const transactionData = mpResponse.point_of_interaction && mpResponse.point_of_interaction.transaction_data;
        const qrCode = transactionData ? transactionData.qr_code : "";
        const qrCodeBase64 = transactionData ? transactionData.qr_code_base64 : "";

        // 5. Atualizar assinatura com dados do MP
        await assinaturaRef.update({
            mp_payment_id: paymentId,
            mp_status: mpResponse.status || "pending",
            mp_qr_code: qrCode,
            mp_qr_code_base64: qrCodeBase64,
        });

        console.log("[assinatura-pix] PIX criado: assinatura=" + assinaturaId + ", payment=" + paymentId);

        return {
            assinaturaId: assinaturaId,
            paymentId: paymentId,
            qrCode: qrCode,
            qrCodeBase64: qrCodeBase64,
            pixCopiaECola: qrCode,
            expiresAt: expiresAt.toISOString(),
            status: mpResponse.status || "pending",
        };
    },
);

// =============================================================================
// CALLABLE 2: CONSULTAR STATUS PIX DA ASSINATURA
// =============================================================================

/**
 * onCall v2: Consulta status do PIX e ativa assinatura se pago.
 *
 * Entrada: { assinaturaId }
 * Resposta: { status, pago, plano, assinaturaId }
 */
exports.assinarPlanoConsultarStatusPix = onCall(
    // TODO: voltar para enforceAppCheck:true após corrigir Secret Key reCAPTCHA.
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 30 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }

        const data = request.data || {};
        const assinaturaId = String(data.assinaturaId || "").trim();

        if (!assinaturaId) {
            throw new HttpsError("invalid-argument", "assinaturaId é obrigatório.");
        }

        const db = admin.firestore();
        const assinaturaRef = db.collection("assinaturas_clientes").doc(assinaturaId);
        const assinaturaSnap = await assinaturaRef.get();

        if (!assinaturaSnap.exists) {
            return { status: "nao_encontrado", pago: false };
        }

        const assinatura = assinaturaSnap.data() || {};

        // Se já está ativo, retorna sucesso (ativação prévia com pagamento real)
        if (assinatura.status === "ativo") {
            return {
                success: true,
                payment_status: "approved",
                approved: true,
                status: "ativo",
                pago: true,
                plano: assinatura.plan_name || "",
                assinaturaId: assinaturaId,
                payment_id: assinatura.mp_payment_id || assinatura.pagamento_mp_payment_id || null,
            };
        }

        // Se não está mais pendente (expirado/cancelado)
        if (assinatura.status !== "pagamento_pendente") {
            return {
                status: assinatura.status || "cancelado",
                pago: false,
                assinaturaId: assinaturaId,
            };
        }

        // Verificar expiração
        const expiresAt = assinatura.pix_expira_em ? new Date(assinatura.pix_expira_em) : null;
        if (expiresAt && expiresAt < new Date()) {
            await assinaturaRef.update({
                status: "expirado",
                updated_at: admin.firestore.Timestamp.now(),
            });
            return { status: "expirado", pago: false, assinaturaId: assinaturaId };
        }

        // Consultar MP
        const gateway = await getMercadoPagoAccessToken();
        if (!gateway) {
            return { status: "erro_gateway", pago: false, assinaturaId: assinaturaId };
        }

        const paymentId = assinatura.mp_payment_id;
        if (!paymentId) {
            return { status: "pagamento_pendente", pago: false, assinaturaId: assinaturaId };
        }

        let mpPayment;
        try {
            mpPayment = await fetchPaymentFromMp(gateway, paymentId);
        } catch (e) {
            console.warn("[assinatura-status] MP fetch error:", e.message);
            return { status: "pagamento_pendente", pago: false, assinaturaId: assinaturaId };
        }

        const mpStatus = String(mpPayment.status || "");

        // PIX: somente status === "approved" (não "authorized")
        if (mpStatusEhAprovado(mpStatus)) {
            // Ativar assinatura!
            await ativarAssinatura(db, assinaturaId, {
                lojaId: assinatura.store_id,
                lojaNome: assinatura.store_name,
                ownerName: assinatura.owner_name,
                ownerEmail: assinatura.email,
                ownerPhone: assinatura.phone,
                planId: assinatura.plan_id,
                planName: assinatura.plan_name,
                valor: assinatura.monthly_amount,
                modulos: assinatura.modulos_extras || [],
                mpPaymentId: paymentId,
            });

            return {
                success: true,
                payment_status: "approved",
                approved: true,
                status: "ativo",
                pago: true,
                plano: assinatura.plan_name || "",
                assinaturaId: assinaturaId,
                payment_id: paymentId,
            };
        }

        if (mpStatus === "rejected" || mpStatus === "cancelled" || mpStatus === "refunded") {
            await assinaturaRef.update({
                status: "recusado",
                mp_status: mpStatus,
                updated_at: admin.firestore.Timestamp.now(),
            });
            return {
                success: true,
                payment_status: mpStatus,
                approved: false,
                status: "recusado",
                pago: false,
                assinaturaId: assinaturaId,
                payment_id: paymentId,
            };
        }

        return {
            success: true,
            payment_status: mpStatus || "pending",
            approved: false,
            status: "pagamento_pendente",
            pago: false,
            assinaturaId: assinaturaId,
            payment_id: paymentId,
        };
    },
);

// =============================================================================
// CALLABLE 3: PROCESSAR PAGAMENTO COM CARTÃO
// =============================================================================

/**
 * onCall v2: Processa pagamento com cartão de crédito para contratar plano.
 *
 * Entrada: { planId, lojaId, lojaNome, ownerName, ownerEmail, ownerPhone,
 *            valor, planName, modulos[],
 *            numeroCartao, nomeTitular, mesExpiracao, anoExpiracao, cvv,
 *            cpf, paymentMethodId, parcelas }
 * Resposta: { aprovado, assinaturaId, mp_status, mensagem }
 */
exports.assinarPlanoProcessarCartao = onCall(
    // TODO: voltar para enforceAppCheck:true após corrigir Secret Key reCAPTCHA.
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 120 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }

        const data = request.data || {};
        const planId = String(data.planId || "").trim();
        const lojaId = String(data.lojaId || "").trim();
        const lojaNome = String(data.lojaNome || "").trim();
        const ownerName = String(data.ownerName || "").trim();
        const ownerEmail = String(data.ownerEmail || "").trim();
        const ownerPhone = String(data.ownerPhone || "").trim();
        const valor = Number(data.valor);
        const planName = String(data.planName || "").trim();
        const modulos = Array.isArray(data.modulos) ? data.modulos : [];

        const numeroCartao = String(data.numeroCartao || "").replace(/\D/g, "");
        const nomeTitular = String(data.nomeTitular || "").trim().toUpperCase();
        const mesExpiracao = String(data.mesExpiracao || "").trim();
        const anoExpiracao = String(data.anoExpiracao || "").trim();
        const cvv = String(data.cvv || "").trim();
        const cpf = String(data.cpf || "").replace(/\D/g, "");
        const paymentMethodIdFront = String(data.paymentMethodId || "").trim();
        const parcelas = Math.max(1, Number(data.parcelas) || 1);

        // Validações
        if (!planId || !lojaId || !valor || valor <= 0) {
            throw new HttpsError("invalid-argument", "planId, lojaId e valor são obrigatórios.");
        }

        if (cpf.length !== 11 || !cpfValidoMp(cpf)) {
            throw new HttpsError("invalid-argument", "CPF do titular inválido. Confira os dígitos.");
        }
        if (!numeroCartao || numeroCartao.length < 13) {
            throw new HttpsError("invalid-argument", "Número do cartão inválido.");
        }
        if (!nomeTitular || nomeTitular.length < 3) {
            throw new HttpsError("invalid-argument", "Informe o nome do titular como está no cartão.");
        }
        if (!cvv || String(cvv).replace(/\D/g, "").length < 3) {
            throw new HttpsError("invalid-argument", "CVV inválido.");
        }
        if (!normalizarExpiracaoCartao(mesExpiracao, anoExpiracao)) {
            throw new HttpsError(
                "invalid-argument",
                "Data de validade inválida. Use MM/AA (ex.: 11/30).",
            );
        }

        const db = admin.firestore();

        // 1. Ler MP config
        const gateway = await getMercadoPagoGatewayConfig();
        if (!gateway || !gateway.accessToken) {
            throw new HttpsError(
                "failed-precondition",
                "Gateway de pagamento não configurado.",
            );
        }

        // 2. Resolver BIN para payment_method_id oficial
        const bin = numeroCartao.slice(0, 6);
        const binInfo = await resolverMetodoPagamentoPorBinMp(gateway, bin);
        const paymentMethodId = (binInfo && binInfo.payment_method_id) || paymentMethodIdFront || "visa";
        const paymentTypeId = (binInfo && binInfo.payment_type_id) || "credit_card";

        // 3. Tokenizar cartão
        let cardToken;
        try {
            cardToken = await tokenizarCartaoMp(gateway, {
                numeroCartao: numeroCartao,
                mesExpiracao: mesExpiracao,
                anoExpiracao: anoExpiracao,
                cvv: cvv,
                nomeTitular: nomeTitular,
                cpf: cpf,
            });
        } catch (tokenErr) {
            console.warn("[assinatura-card] tokenize falhou:", tokenErr.message || tokenErr, tokenErr.body || "");
            throw new HttpsError("invalid-argument", mensagemErroTokenizacaoMp(tokenErr));
        }

        if (!cardToken || !cardToken.id) {
            throw new HttpsError("invalid-argument", "Não foi possível validar o cartão. Tente novamente.");
        }

        const description = "Assinatura " + (planName || "Plano DiPertin") + " - " + lojaNome;

        // 4. Montar payload de pagamento
        const cardPayload = {
            transaction_amount: valor,
            token: cardToken.id,
            description: description,
            installments: parcelas,
            payment_method_id: paymentMethodId,
            payment_type_id: paymentTypeId,
            binary_mode: true,
            capture: true,
            statement_descriptor: "DIPERTIN",
            payer: {
                email: ownerEmail || request.auth.token.email || "nao-informado@dipertin.com",
                first_name: nomeTitular.split(" ")[0] || ownerName || lojaNome || "Lojista",
                last_name: nomeTitular.split(" ").slice(1).join(" ") || "",
                identification: {
                    type: "CPF",
                    number: cpf,
                },
            },
            external_reference: "assinatura_card_" + lojaId + "_" + Date.now(),
        };

        // 5. Criar assinatura pendente antes do pagamento
        const assinaturaRef = db.collection("assinaturas_clientes").doc();
        const assinaturaId = assinaturaRef.id;
        const now = admin.firestore.Timestamp.now();

        // Buscar dados de endereço do lojista
        let addressCityCard = "";
        let addressStateCard = "";
        try {
            const lojaSnap = await db.collection("users").doc(lojaId).get();
            if (lojaSnap.exists) {
                const lojaData = lojaSnap.data() || {};
                addressCityCard = String(lojaData.endereco_cidade || lojaData.cidade || lojaData.cidade_normalizada || "").trim();
                addressStateCard = String(lojaData.uf || lojaData.estado || "").trim().toUpperCase();
            }
        } catch (_) {
            console.warn("[assinatura-card] Não foi possível buscar endereço do lojista", lojaId);
        }

        await assinaturaRef.set({
            store_id: lojaId,
            store_name: lojaNome,
            owner_name: ownerName,
            email: ownerEmail,
            phone: ownerPhone,
            plan_id: planId,
            plan_name: planName,
            status: "pagamento_pendente",
            monthly_amount: valor,
            gateway: "Mercado Pago",
            modulos_extras: modulos,
            historico: [
                {
                    tipo: "criacao",
                    descricao: "Pagamento com cartão em processamento.",
                    data_em: now,
                },
            ],
            created_at: now,
            updated_at: now,
            created_by: lojaId,
            mp_payment_method_id: paymentMethodId,
            address_city: addressCityCard,
            address_state: addressStateCard,
        });

        // 6. Processar pagamento
        let mpPayment;
        try {
            mpPayment = await criarPagamentoMpComCartao(gateway.accessToken, cardPayload);
        } catch (mpErr) {
            await assinaturaRef.update({
                status: "erro_pagamento",
                mp_erro: mpErr.message,
                updated_at: admin.firestore.Timestamp.now(),
            });
            throw new HttpsError("internal", "Erro ao processar pagamento. Tente novamente.");
        }

        // 7. Aguardar conclusão (polling)
        mpPayment = await aguardarConclusaoPagamentoMp(gateway.accessToken, mpPayment.id, 10, 2000);

        const mpStatus = String(mpPayment.status || "");

        if (mpStatus === "approved" || mpStatus === "authorized") {
            // Ativar assinatura!
            await ativarAssinatura(db, assinaturaId, {
                lojaId: lojaId,
                lojaNome: lojaNome,
                ownerName: ownerName,
                ownerEmail: ownerEmail,
                ownerPhone: ownerPhone,
                planId: planId,
                planName: planName,
                valor: valor,
                modulos: modulos,
                mpPaymentId: mpPayment.id,
            });

            return {
                aprovado: true,
                assinaturaId: assinaturaId,
                mp_status: "approved",
                plano: planName,
                mensagem: "Pagamento aprovado! Seu plano " + planName + " já está ativo.",
            };
        }

        // Pagamento recusado
        const statusDetail = mpPayment.status_detail || "";
        const recusaMensagem = traduzirRecusaMp(statusDetail);

        await assinaturaRef.update({
            status: "recusado",
            mp_status: mpStatus,
            mp_status_detail: statusDetail,
            mp_payment_id: mpPayment.id,
            mp_recusa_mensagem: recusaMensagem,
            updated_at: admin.firestore.Timestamp.now(),
        });

        return {
            aprovado: false,
            assinaturaId: assinaturaId,
            mp_status: mpStatus,
            mensagem: recusaMensagem,
        };
    },
);

// =============================================================================
// RENOVAR ASSINATURA — PIX
// =============================================================================

async function renovarAssinatura(db, assinaturaId, dados) {
    const now = admin.firestore.Timestamp.now();

    // Ler duracao_dias do documento atual da assinatura
    let duracaoDias = 30;
    try {
        const snap = await db.collection("assinaturas_clientes").doc(assinaturaId).get();
        if (snap.exists) {
            const a = snap.data() || {};
            duracaoDias = (a.duracao_dias != null && Number(a.duracao_dias) > 0)
                ? Number(a.duracao_dias) : 30;
        }
    } catch (e) {
        console.warn("[assinatura] erro ao ler assinatura na renovação:", e.message);
    }

    const novoNextBilling = new admin.firestore.Timestamp(
        Math.floor(Date.now() / 1000) + duracaoDias * 24 * 60 * 60,
        0,
    );
    await db.collection("assinaturas_clientes").doc(assinaturaId).update({
        status: "ativo",
        last_payment_date: now,
        next_billing_date: novoNextBilling,
        monthly_amount: dados.valor || 0,
        pagamento_mp_payment_id: dados.mpPaymentId || null,
        pagamento_mp_status: "approved",
        pagamento_aprovado_em: now,
        renovacao_processada_payment_id: dados.mpPaymentId || null,
        renovacao_processada_em: now,
        // Limpa atraso e bloqueio
        dias_em_atraso: 0,
        multa_calculada: 0,
        juros_calculados: 0,
        total_atualizado: dados.valor || 0,
        ultimo_pagamento_valor: dados.valor || 0,
        updated_at: now,
        blocked_at: admin.firestore.FieldValue.delete(),
        block_reason: admin.firestore.FieldValue.delete(),
        status_renovacao: admin.firestore.FieldValue.delete(),
        renovacao_valor: admin.firestore.FieldValue.delete(),
        renovacao_external_ref: admin.firestore.FieldValue.delete(),
        renovacao_expira_em: admin.firestore.FieldValue.delete(),
        renovacao_mp_payment_id: admin.firestore.FieldValue.delete(),
        renovacao_mp_status: admin.firestore.FieldValue.delete(),
        renovacao_qr_code: admin.firestore.FieldValue.delete(),
        renovacao_qr_code_base64: admin.firestore.FieldValue.delete(),
        historico: admin.firestore.FieldValue.arrayUnion({
            tipo: "renovacao",
            descricao: "Assinatura renovada com pagamento aprovado via Mercado Pago.",
            data_em: now,
            valor_pago: dados.valor || 0,
            mp_payment_id: dados.mpPaymentId || null,
            origem: dados.origem || "polling",
        }),
    });
    // Audit log
    try {
        await db.collection("audit_logs").add({
            acao: "assinatura_renovada",
            categoria: "assinaturas",
            origem: "callable",
            criado_em: now,
            ator_uid: dados.lojaId,
            detalhe: {
                assinatura_id: assinaturaId,
                plan_name: dados.planName || "",
                valor_pago: dados.valor || 0,
                pagamento: "mp",
            },
        });
    } catch (e) {
        console.warn("[assinatura] renovacao audit log error:", e.message);
    }
}

/**
 * onCall v2: Cria PIX para renovar assinatura existente (bloqueada/vencida).
 * Entrada: { assinaturaId, lojaId, ownerName, ownerEmail, ownerPhone, valor, planName }
 */
exports.assinarPlanoRenovarPix = onCall(
    // TODO: voltar para enforceAppCheck:true após corrigir Secret Key reCAPTCHA.
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login necessário.");
        const data = request.data || {};
        const assinaturaId = String(data.assinaturaId || "").trim();
        const lojaId = String(data.lojaId || "").trim();
        const ownerName = String(data.ownerName || "").trim();
        const ownerEmail = String(data.ownerEmail || "").trim();
        const ownerPhone = String(data.ownerPhone || "").trim();
        const valor = Number(data.valor);
        const planName = String(data.planName || "").trim();

        if (!assinaturaId || !lojaId || !valor || valor <= 0) {
            throw new HttpsError("invalid-argument", "assinaturaId, lojaId e valor são obrigatórios.");
        }
        if (lojaId !== request.auth.uid) { /* colaborador ok */ }

        const db = admin.firestore();

        // Verifica se a assinatura existe
        const snap = await db.collection("assinaturas_clientes").doc(assinaturaId).get();
        if (!snap.exists) throw new HttpsError("not-found", "Assinatura não encontrada.");
        const assinaturaAtual = snap.data() || {};

        // MP config
        const gateway = await getMercadoPagoGatewayConfig();
        if (!gateway || !gateway.accessToken) {
            throw new HttpsError("failed-precondition", "Gateway de pagamento não configurado.");
        }

        // Sempre gera um novo PIX de antecipação.
        // NÃO tratar "plano já ativo" / último pagamento antigo como pago desta cobrança.
        const now = admin.firestore.Timestamp.now();
        const expiresAt = new Date(Date.now() + 30 * 60 * 1000);
        const externalRef = "renovar_" + assinaturaId + "_" + Date.now();
        await db.collection("assinaturas_clientes").doc(assinaturaId).update({
            status_renovacao: "renovacao_pendente",
            renovacao_valor: valor,
            renovacao_external_ref: externalRef,
            renovacao_expira_em: expiresAt.toISOString(),
            // limpa espelho do PIX anterior (evita confirmar pagamento velho)
            renovacao_mp_payment_id: admin.firestore.FieldValue.delete(),
            renovacao_mp_status: admin.firestore.FieldValue.delete(),
            renovacao_qr_code: admin.firestore.FieldValue.delete(),
            renovacao_qr_code_base64: admin.firestore.FieldValue.delete(),
            updated_at: now,
        });

        // PIX MP
        const description = "Renovação " + (planName || "Assinatura DiPertin") + " - " + lojaId;
        const pixPayload = {
            transaction_amount: valor,
            description: description,
            payment_method_id: "pix",
            payer: {
                email: ownerEmail || request.auth.token.email || "nao-informado@dipertin.com",
                first_name: ownerName || lojaId || "Lojista",
            },
            external_reference: externalRef,
            notification_url: ASSINATURA_MP_WEBHOOK_URL,
            metadata: {
                tipo: "assinatura_renovacao",
                assinatura_id: assinaturaId,
                assinaturaId: assinaturaId,
                store_id: lojaId,
                storeId: lojaId,
            },
        };

        let mpResponse;
        try {
            mpResponse = await criarPagamentoPixMp(gateway.accessToken, pixPayload, "renovacao_" + assinaturaId);
        } catch (mpErr) {
            await db.collection("assinaturas_clientes").doc(assinaturaId).update({
                status_renovacao: "erro_pix",
                updated_at: admin.firestore.Timestamp.now(),
            });
            throw new HttpsError("internal", "Erro ao gerar PIX. Tente novamente.");
        }

        const paymentId = mpResponse.id;
        const transactionData = mpResponse.point_of_interaction && mpResponse.point_of_interaction.transaction_data;
        const qrCode = transactionData ? transactionData.qr_code : "";
        const qrCodeBase64 = transactionData ? transactionData.qr_code_base64 : "";

        await db.collection("assinaturas_clientes").doc(assinaturaId).update({
            renovacao_mp_payment_id: paymentId,
            renovacao_mp_status: mpResponse.status || "pending",
            renovacao_qr_code: qrCode,
            renovacao_qr_code_base64: qrCodeBase64,
        });

        return {
            assinaturaId: assinaturaId,
            paymentId: paymentId,
            qrCode: qrCode,
            qrCodeBase64: qrCodeBase64,
            pixCopiaECola: qrCode,
            expiresAt: expiresAt.toISOString(),
            status: mpResponse.status || "pending",
        };
    },
);

// =============================================================================
// RENOVAR — CONSULTAR STATUS PIX
// =============================================================================

/**
 * onCall v2: Consulta status do PIX de renovação.
 *
 * REGRA: só confirma pagamento quando Mercado Pago retorna status === "approved".
 * Assinatura já "ativo", HTTP 200, success, payment_id ou QR gerado NÃO confirmam PIX.
 *
 * Resposta (sempre):
 *   success          — consulta executada OK (nunca significa pago)
 *   payment_status   — pending | approved | expired | rejected | ...
 *   approved         — true somente se MP status === approved
 *   pago             — alias de approved (legado)
 *   payment_id
 */
exports.assinarPlanoRenovarConsultarStatusPix = onCall(
    // TODO: voltar para enforceAppCheck:true após corrigir Secret Key reCAPTCHA.
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 30 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login necessário.");
        const data = request.data || {};
        const assinaturaId = String(data.assinaturaId || "").trim();
        if (!assinaturaId) throw new HttpsError("invalid-argument", "assinaturaId é obrigatório.");

        const db = admin.firestore();
        const ref = db.collection("assinaturas_clientes").doc(assinaturaId);
        const snap = await ref.get();
        if (!snap.exists) {
            return {
                success: true,
                payment_status: "nao_encontrado",
                approved: false,
                pago: false,
                status: "nao_encontrado",
                payment_id: null,
            };
        }

        const assinatura = snap.data() || {};
        const storeId = String(assinatura.store_id || "").trim();
        const callerUid = request.auth.uid;
        // Dono da loja ou o próprio store_id
        if (storeId && storeId !== callerUid) {
            // Colaborador: users/{caller}.lojista_owner_uid === storeId
            let permitido = false;
            try {
                const userSnap = await db.collection("users").doc(callerUid).get();
                const u = userSnap.exists ? (userSnap.data() || {}) : {};
                if (String(u.lojista_owner_uid || "").trim() === storeId) permitido = true;
            } catch (_) { /* ignore */ }
            if (!permitido) {
                throw new HttpsError("permission-denied", "Sem acesso a esta assinatura.");
            }
        }

        // Somente o PIX desta antecipação (renovacao_mp_payment_id).
        // Plano já "ativo" / pagamento antigo NÃO confirma esta cobrança.
        const paymentId = assinatura.renovacao_mp_payment_id
            ? String(assinatura.renovacao_mp_payment_id)
            : "";
        const statusRenovacao = String(assinatura.status_renovacao || "");

        // Idempotência: ESTE payment_id da renovação em aberto já foi processado
        if (paymentId
            && String(assinatura.renovacao_processada_payment_id || "") === paymentId
            && String(assinatura.pagamento_mp_status || "") === "approved") {
            return {
                success: true,
                payment_status: "approved",
                approved: true,
                pago: true,
                status: "ativo",
                payment_id: paymentId,
                assinaturaId: assinaturaId,
                already: true,
            };
        }

        if (statusRenovacao !== "renovacao_pendente" && statusRenovacao !== "expirado") {
            return {
                success: true,
                payment_status: "idle",
                approved: false,
                pago: false,
                status: statusRenovacao || "sem_renovacao_pendente",
                payment_id: paymentId || null,
                assinaturaId: assinaturaId,
            };
        }

        if (!paymentId) {
            return {
                success: true,
                payment_status: "pending",
                approved: false,
                pago: false,
                status: "renovacao_pendente",
                payment_id: null,
                assinaturaId: assinaturaId,
            };
        }

        const accessToken = await getMercadoPagoAccessToken();
        if (!accessToken) {
            return {
                success: false,
                payment_status: "erro_gateway",
                approved: false,
                pago: false,
                status: "erro_gateway",
                payment_id: paymentId,
                assinaturaId: assinaturaId,
            };
        }

        let mpPayment;
        try {
            mpPayment = await fetchPaymentFromMp(accessToken, paymentId);
        } catch (e) {
            console.warn("[renovar-status-pix] MP fetch:", e.message || e);
            return {
                success: true,
                payment_status: "pending",
                approved: false,
                pago: false,
                status: "renovacao_pendente",
                payment_id: paymentId,
                assinaturaId: assinaturaId,
            };
        }

        const mpId = String(mpPayment.id || "");
        if (mpId && mpId !== paymentId) {
            return {
                success: true,
                payment_status: "pending",
                approved: false,
                pago: false,
                status: "renovacao_pendente",
                payment_id: paymentId,
                assinaturaId: assinaturaId,
            };
        }

        const meta = mpPayment.metadata || {};
        const metaAssinatura = String(meta.assinatura_id || meta.assinaturaId || "").trim();
        const extRef = String(mpPayment.external_reference || "");
        const extOk = extRef === ("renovar_" + assinaturaId)
            || extRef.indexOf("renovar_" + assinaturaId) === 0;
        const valorEsperado = Number(assinatura.renovacao_valor || assinatura.monthly_amount || 0);
        const valorPago = Number(mpPayment.transaction_amount || 0);
        const mpStatus = String(mpPayment.status || "").trim().toLowerCase();

        try {
            await ref.update({
                renovacao_mp_status: mpStatus || "pending",
                updated_at: admin.firestore.Timestamp.now(),
            });
        } catch (_) { /* ignore */ }

        if (mpStatusEhAprovado(mpStatus)) {
            if (metaAssinatura && metaAssinatura !== assinaturaId) {
                return {
                    success: false,
                    payment_status: "bloqueado",
                    approved: false,
                    pago: false,
                    status: "bloqueado",
                    payment_id: paymentId,
                    assinaturaId: assinaturaId,
                };
            }
            if (!extOk && !metaAssinatura) {
                return {
                    success: false,
                    payment_status: "bloqueado",
                    approved: false,
                    pago: false,
                    status: "bloqueado",
                    payment_id: paymentId,
                    assinaturaId: assinaturaId,
                };
            }
            if (valorEsperado > 0 && Math.abs(valorPago - valorEsperado) > 0.009) {
                return {
                    success: false,
                    payment_status: "bloqueado",
                    approved: false,
                    pago: false,
                    status: "bloqueado",
                    payment_id: paymentId,
                    assinaturaId: assinaturaId,
                };
            }

            const resultadoTx = await db.runTransaction(async (tx) => {
                const fresh = await tx.get(ref);
                if (!fresh.exists) return { ok: false, reason: "nao_encontrado" };
                const a = fresh.data() || {};
                const pid = String(a.renovacao_mp_payment_id || "");
                if (pid !== paymentId) {
                    if (String(a.renovacao_processada_payment_id || "") === paymentId
                        && String(a.pagamento_mp_status || "") === "approved") {
                        return { ok: true, already: true };
                    }
                    return { ok: false, reason: "payment_id_desatualizado" };
                }
                if (String(a.renovacao_processada_payment_id || "") === paymentId
                    && String(a.pagamento_mp_status || "") === "approved") {
                    return { ok: true, already: true };
                }
                tx.update(ref, {
                    status_renovacao: "renovacao_pendente",
                    renovacao_processada_payment_id: paymentId,
                    renovacao_processada_em: admin.firestore.FieldValue.serverTimestamp(),
                });
                return { ok: true, already: false };
            });

            if (resultadoTx && resultadoTx.ok && !resultadoTx.already) {
                await renovarAssinatura(db, assinaturaId, {
                    lojaId: storeId || assinatura.store_id,
                    planName: assinatura.plan_name,
                    valor: valorEsperado || valorPago,
                    mpPaymentId: paymentId,
                    origem: "polling",
                });
            } else if (resultadoTx && !resultadoTx.ok) {
                const again = await ref.get();
                const a2 = again.exists ? (again.data() || {}) : {};
                if (String(a2.renovacao_processada_payment_id || "") === paymentId
                    && String(a2.pagamento_mp_status || "") === "approved") {
                    return {
                        success: true,
                        payment_status: "approved",
                        approved: true,
                        pago: true,
                        status: "ativo",
                        payment_id: paymentId,
                        assinaturaId: assinaturaId,
                        already: true,
                    };
                }
                return {
                    success: true,
                    payment_status: "pending",
                    approved: false,
                    pago: false,
                    status: "renovacao_pendente",
                    payment_id: paymentId,
                    assinaturaId: assinaturaId,
                };
            }

            return {
                success: true,
                payment_status: "approved",
                approved: true,
                pago: true,
                status: "ativo",
                payment_id: paymentId,
                assinaturaId: assinaturaId,
                message: "Pagamento aprovado! Assinatura renovada.",
            };
        }

        if (mpStatus === "rejected" || mpStatus === "cancelled" || mpStatus === "refunded"
            || mpStatus === "charged_back") {
            await ref.update({
                status_renovacao: "recusado",
                updated_at: admin.firestore.Timestamp.now(),
            });
            return {
                success: true,
                payment_status: mpStatus,
                approved: false,
                pago: false,
                status: "recusado",
                payment_id: paymentId,
                assinaturaId: assinaturaId,
            };
        }

        const expiraEm = assinatura.renovacao_expira_em
            ? new Date(assinatura.renovacao_expira_em)
            : null;
        if (expiraEm && expiraEm < new Date()) {
            try {
                await ref.update({
                    status_renovacao: "expirado",
                    updated_at: admin.firestore.Timestamp.now(),
                });
            } catch (_) { /* ignore */ }
            return {
                success: true,
                payment_status: "expired",
                approved: false,
                pago: false,
                status: "expirado",
                payment_id: paymentId,
                assinaturaId: assinaturaId,
                message: "Este PIX expirou. Gere uma nova cobrança para continuar.",
            };
        }

        return {
            success: true,
            payment_status: mpStatus || "pending",
            approved: false,
            pago: false,
            status: "renovacao_pendente",
            payment_id: paymentId,
            assinaturaId: assinaturaId,
            message: "Aguardando confirmação do pagamento",
        };
    },
);

// =============================================================================
// RENOVAR — CARTÃO
// =============================================================================

/**
 * onCall v2: Processa pagamento com cartão para renovar assinatura existente.
 */
exports.assinarPlanoRenovarCartao = onCall(
    // TODO: voltar para enforceAppCheck:true após corrigir Secret Key reCAPTCHA.
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 120 },
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login necessário.");

        const data = request.data || {};
        const assinaturaId = String(data.assinaturaId || "").trim();
        const lojaId = String(data.lojaId || "").trim();
        const valor = Number(data.valor);
        const planName = String(data.planName || "").trim();
        const ownerName = String(data.ownerName || "").trim();
        const ownerEmail = String(data.ownerEmail || "").trim();
        const ownerPhone = String(data.ownerPhone || "").trim();

        const numeroCartao = String(data.numeroCartao || "").replace(/\D/g, "");
        const nomeTitular = String(data.nomeTitular || "").trim().toUpperCase();
        const mesExpiracao = String(data.mesExpiracao || "").trim();
        const anoExpiracao = String(data.anoExpiracao || "").trim();
        const cvv = String(data.cvv || "").trim();
        const cpf = String(data.cpf || "").replace(/\D/g, "");

        if (!assinaturaId || !lojaId || !valor || valor <= 0) {
            throw new HttpsError("invalid-argument", "assinaturaId, lojaId e valor são obrigatórios.");
        }
        if (cpf.length !== 11 || !cpfValidoMp(cpf)) {
            throw new HttpsError("invalid-argument", "CPF do titular inválido. Confira os dígitos.");
        }
        if (!numeroCartao || numeroCartao.length < 13) {
            throw new HttpsError("invalid-argument", "Número do cartão inválido.");
        }
        if (!nomeTitular || nomeTitular.length < 3) {
            throw new HttpsError("invalid-argument", "Informe o nome do titular como está no cartão.");
        }
        if (!cvv || String(cvv).replace(/\D/g, "").length < 3) {
            throw new HttpsError("invalid-argument", "CVV inválido.");
        }
        if (!normalizarExpiracaoCartao(mesExpiracao, anoExpiracao)) {
            throw new HttpsError(
                "invalid-argument",
                "Data de validade inválida. Use MM/AA (ex.: 11/30).",
            );
        }

        const db = admin.firestore();
        const snap = await db.collection("assinaturas_clientes").doc(assinaturaId).get();
        if (!snap.exists) throw new HttpsError("not-found", "Assinatura não encontrada.");

        const gateway = await getMercadoPagoGatewayConfig();
        if (!gateway || !gateway.accessToken) throw new HttpsError("failed-precondition", "Gateway não configurado.");

        const bin = numeroCartao.slice(0, 6);
        const binInfo = await resolverMetodoPagamentoPorBinMp(gateway, bin);
        const paymentMethodId = (binInfo && binInfo.payment_method_id) || data.paymentMethodId || "visa";
        const paymentTypeId = (binInfo && binInfo.payment_type_id) || "credit_card";

        let cardToken;
        try {
            cardToken = await tokenizarCartaoMp(gateway, {
                numeroCartao, mesExpiracao, anoExpiracao, cvv, nomeTitular, cpf,
            });
        } catch (tokenErr) {
            console.warn("[assinatura-renovar-card] tokenize falhou:", tokenErr.message || tokenErr, tokenErr.body || "");
            throw new HttpsError("invalid-argument", mensagemErroTokenizacaoMp(tokenErr));
        }
        if (!cardToken || !cardToken.id) throw new HttpsError("invalid-argument", "Não foi possível validar o cartão.");

        const description = "Renovação " + (planName || "Assinatura DiPertin") + " - " + lojaId;
        const cardPayload = {
            transaction_amount: valor,
            token: cardToken.id,
            description: description,
            installments: Math.max(1, Number(data.parcelas) || 1),
            payment_method_id: paymentMethodId,
            payment_type_id: paymentTypeId,
            binary_mode: true,
            capture: true,
            statement_descriptor: "DIPERTIN",
            payer: {
                email: ownerEmail || request.auth.token.email || "nao-informado@dipertin.com",
                first_name: nomeTitular.split(" ")[0] || ownerName || lojaId,
                last_name: nomeTitular.split(" ").slice(1).join(" ") || "",
                identification: { type: "CPF", number: cpf },
            },
            external_reference: "renovar_card_" + assinaturaId + "_" + Date.now(),
        };

        let mpPayment;
        try {
            mpPayment = await criarPagamentoMpComCartao(gateway.accessToken, cardPayload);
        } catch (mpErr) {
            throw new HttpsError("internal", "Erro ao processar pagamento.");
        }

        mpPayment = await aguardarConclusaoPagamentoMp(gateway.accessToken, mpPayment.id, 10, 2000);
        const mpStatus = String(mpPayment.status || "");

        if (mpStatus === "approved" || mpStatus === "authorized") {
            await renovarAssinatura(db, assinaturaId, {
                lojaId, planName,
                valor,
                mpPaymentId: mpPayment.id,
            });
            return {
                aprovado: true,
                assinaturaId: assinaturaId,
                mp_status: "approved",
                plano: planName,
                mensagem: "Pagamento aprovado! Sua assinatura foi renovada.",
            };
        }

        const recusaMsg = traduzirRecusaMp(mpPayment.status_detail || "");
        return {
            aprovado: false,
            assinaturaId: assinaturaId,
            mp_status: mpStatus,
            mensagem: recusaMsg,
        };
    },
);

// =============================================================================
// TRADUÇÃO DE RECUSA
// =============================================================================

function traduzirRecusaMp(statusDetail) {
    const mapa = {
        "cc_rejected_bad_filled_card_number": "Número do cartão inválido.",
        "cc_rejected_bad_filled_date": "Data de validade inválida.",
        "cc_rejected_bad_filled_security_code": "Código de segurança (CVV) inválido.",
        "cc_rejected_bad_filled_other": "Dados do cartão inválidos.",
        "cc_rejected_insufficient_amount": "Saldo insuficiente no cartão.",
        "cc_rejected_other_reason": "Pagamento recusado pelo banco emissor.",
        "cc_rejected_call_for_authorize": "Entre em contato com seu banco para autorizar esta compra.",
        "cc_rejected_blacklist": "Cartão recusado por medida de segurança.",
        "cc_rejected_max_attempts": "Número máximo de tentativas excedido.",
        "cc_rejected_high_risk": "Pagamento recusado por análise de risco.",
        "cc_rejected_card_disabled": "Cartão desabilitado. Entre em contato com seu banco.",
        "cc_rejected_duplicate_payment": "Pagamento duplicado detectado.",
    };
    return mapa[statusDetail] || "Pagamento recusado. Tente novamente com outro cartão.";
}

// =============================================================================
// SUSPENSÃO AUTOMÁTICA DE ASSINATURAS INADIMPLENTES (diária 02:00 BRT)
// =============================================================================

/**
 * onSchedule v2: Executa diariamente para verificar assinaturas que excederam
 * o período de tolerância + suspensão configurado no plano.
 *
 * Regra: suspende se diasAposVencimento > (toleranciaDias + suspenderAposDias)
 */
exports.assinaturaVerificarSuspensaoScheduled = onSchedule(
    {
        schedule: "0 2 * * *",
        timeZone: "America/Sao_Paulo",
        region: "us-central1",
        timeoutSeconds: 540,
    },
    async (event) => {
        const db = admin.firestore();
        const avisos = require("./assinatura_avisos");
        const now = admin.firestore.Timestamp.now();
        const agoraMs = Date.now();
        const UM_DIA_MS = 24 * 60 * 60 * 1000;
        let suspensas = 0;
        let erros = 0;
        const emailsPendentes = [];

        // Buscar assinaturas ativas ou em atraso
        const snap = await db.collection("assinaturas_clientes")
            .where("status", "in", ["ativo", "em_atraso"])
            .get();

        if (snap.empty) {
            console.log("[assinatura-suspensao] Nenhuma assinatura para verificar.");
            return;
        }

        // Processar em lotes de 500 para evitar timeout
        let batch = db.batch();
        let ops = 0;

        for (const doc of snap.docs) {
            try {
                const a = doc.data() || {};

                // Só verifica se tem suspender_apos_dias configurado
                const suspenderApos = a.suspender_apos_dias;
                if (suspenderApos == null || Number(suspenderApos) <= 0) continue;

                const tolerancia = Number(a.tolerancia_dias || 3);
                const nextBilling = a.next_billing_date;

                if (!nextBilling) continue;

                // Calcular dias desde o vencimento
                const vencMs = nextBilling.toMillis ? nextBilling.toMillis() : nextBilling._seconds * 1000;
                const diasAposVencimento = Math.floor((agoraMs - vencMs) / UM_DIA_MS);

                if (diasAposVencimento <= 0) continue;

                // Verificar se excedeu tolerancia + suspender_apos_dias
                // NÃO usa tentativas de e-mail — apenas a regra de dias do plano.
                const limiteSuspensao = tolerancia + Number(suspenderApos);
                if (diasAposVencimento > limiteSuspensao) {
                    batch.update(doc.ref, {
                        status: "suspenso",
                        blocked_at: now,
                        block_reason: "Inadimplência automática — prazo de tolerância e suspensão excedido.",
                        updated_at: now,
                        historico: admin.firestore.FieldValue.arrayUnion({
                            tipo: "suspensao_automatica",
                            descricao: "Assinatura suspensa automaticamente por inadimplência (" +
                                diasAposVencimento + " dias após vencimento, limite " + limiteSuspensao + " dias).",
                            data_em: now,
                        }),
                    });
                    emailsPendentes.push({
                        email: a.email || "",
                        lojaNome: a.store_name || "",
                        planoNome: a.plan_name || "",
                        valor: a.monthly_amount,
                        vencimento: avisos.formatDateBr(nextBilling),
                        situacao: "Suspenso",
                        formaPagamento: a.tipo_cobranca || "—",
                    });
                    suspensas++;
                    ops++;

                    if (ops >= 500) {
                        await batch.commit();
                        batch = db.batch();
                        ops = 0;
                    }
                }
            } catch (e) {
                console.warn("[assinatura-suspensao] erro ao processar", doc.id, ":", e.message);
                erros++;
            }
        }

        if (ops > 0) {
            await batch.commit();
        }

        for (const d of emailsPendentes) {
            try {
                await avisos.enviarEmailSuspenso(d);
            } catch (_) { /* best-effort */ }
        }

        console.log("[assinatura-suspensao] Concluído: " + suspensas + " suspensas, " + erros + " erros.");
    },
);

/**
 * Processa webhook PIX de contratação ou renovação (metadata.tipo).
 * Exportado para mercado_pago_gestao_comercial.js.
 */
async function processarPagamentoPixAssinaturaDireto(payment) {
    const db = admin.firestore();
    const metadata = (payment && payment.metadata) || {};
    const tipo = String(metadata.tipo || "");
    const statusMp = String(payment.status || "").toLowerCase();
    // PIX: somente approved (authorized NÃO confirma liquidação)
    if (!mpStatusEhAprovado(statusMp)) {
        return { ok: false, reason: "status_nao_aprovado", status_mp: statusMp };
    }

    const assinaturaId = String(metadata.assinaturaId || metadata.assinatura_id || "").trim();
    if (!assinaturaId) {
        // Fallback via external_reference
        const ext = String(payment.external_reference || "");
        const m = ext.match(/^(assinatura_|renovar_)([A-Za-z0-9_-]+)/);
        if (m) {
            return processarPagamentoPixAssinaturaDireto({
                ...payment,
                metadata: {
                    ...metadata,
                    tipo: m[1] === "renovar_" ? "assinatura_renovacao" : "assinatura_contratacao",
                    assinatura_id: m[2],
                    assinaturaId: m[2],
                },
            });
        }
        return { ok: false, reason: "assinatura_id_ausente" };
    }

    const ref = db.collection("assinaturas_clientes").doc(assinaturaId);
    const snap = await ref.get();
    if (!snap.exists) return { ok: false, reason: "assinatura_nao_encontrada" };
    const a = snap.data() || {};
    const paymentId = String(payment.id || "");

    if (tipo === "assinatura_renovacao" || String(a.status_renovacao || "") === "renovacao_pendente") {
        // Idempotência: mesmo payment_id já processado
        if (paymentId
            && (String(a.renovacao_processada_payment_id || "") === paymentId
                || (String(a.pagamento_mp_payment_id || "") === paymentId
                    && String(a.pagamento_mp_status || "") === "approved"))) {
            return { ok: true, already: true };
        }
        // Não renovar só porque o plano já está "ativo".
        // Aceita renovacao_pendente, expirado local, ou mesmo payment_id em aberto.
        const pidRenovacao = String(a.renovacao_mp_payment_id || "");
        const stRen = String(a.status_renovacao || "");
        const renovacaoEmAberto = stRen === "renovacao_pendente"
            || stRen === "expirado"
            || (pidRenovacao && pidRenovacao === paymentId);
        if (!renovacaoEmAberto) {
            return { ok: false, reason: "sem_renovacao_pendente" };
        }
        const valorEsperado = Number(a.renovacao_valor || a.monthly_amount || 0);
        const valorPago = Number(payment.transaction_amount || 0);
        if (valorEsperado > 0 && Math.abs(valorPago - valorEsperado) > 0.009) {
            return { ok: false, reason: "valor_divergente", esperado: valorEsperado, pago: valorPago };
        }
        await renovarAssinatura(db, assinaturaId, {
            lojaId: a.store_id,
            planName: a.plan_name,
            valor: valorEsperado || valorPago,
            mpPaymentId: payment.id,
            origem: "webhook",
        });
        return { ok: true, processado: true, tipo: "renovacao" };
    }

    // Contratação
    if (a.status === "ativo") {
        return { ok: true, already: true };
    }
    if (a.status !== "pagamento_pendente") {
        return { ok: false, reason: "status_invalido", status: a.status };
    }

    await ativarAssinatura(db, assinaturaId, {
        lojaId: a.store_id,
        lojaNome: a.store_name,
        ownerName: a.owner_name,
        ownerEmail: a.email,
        ownerPhone: a.phone,
        planId: a.plan_id || a.plano_id,
        planName: a.plan_name,
        valor: Number(payment.transaction_amount || a.monthly_amount || 0),
        modulos: a.modulos_extras || [],
        mpPaymentId: payment.id,
    });
    return { ok: true, processado: true, tipo: "contratacao" };
}

exports.processarPagamentoPixAssinaturaDireto = processarPagamentoPixAssinaturaDireto;
exports.ASSINATURA_MP_WEBHOOK_URL = ASSINATURA_MP_WEBHOOK_URL;
exports.mpStatusEhAprovado = mpStatusEhAprovado;
