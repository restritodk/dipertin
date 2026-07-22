"use strict";

/**
 * Mercado Pago — Webhook e funções PIX do módulo Gestão Comercial.
 *
 * Cada lojista possui suas próprias credenciais Mercado Pago.
 * O webhook é único para todos os lojistas.
 *
 * FLUXO PIX:
 * 1. Frontend chama createPdvPixPayment -> cria PIX no MP + cobrança no Firestore.
 * 2. Cobrança fica em "aguardando_pagamento" por ate 5 minutos.
 * 3. Frontend escuta Firestore em tempo real para detectar mudanca de status.
 * 4. Webhook do MP chega -> processarNotificacaoPagamento -> atualiza Firestore.
 * 5. Frontend detecta status "pago" -> mostra modal de sucesso.
 * 6. Se 5 minutos sem pagamento -> checkPdvPixPaymentStatus marca como "expirado".
 *
 * REGRAS:
 * - NUNCA marcar como cancelado/recusado antes dos 5 minutos.
 * - So marcar "cancelado" via acao manual do operador (botao Cancelar cobranca).
 * - So finalizar venda quando backend confirmar pagamento aprovado.
 * - Idempotencia via flag "processed" para evitar duplicidade.
 * - Logs seguros: nunca logar access_token, client_secret ou api_key.
 */

const functions = require("firebase-functions/v1");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const MP_API = "https://api.mercadopago.com";

// =============================================================================
// VALIDAÇÃO COMPARTILHADA (Gestão Comercial)
// =============================================================================

async function assertGcAcessoLoja(request) {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login necessario.");
    }
    const callerUid = request.auth.uid;
    const callerSnap = await admin.firestore().collection("users").doc(callerUid).get();
    if (!callerSnap.exists) {
        throw new HttpsError("failed-precondition", "Perfil nao encontrado.");
    }
    const caller = callerSnap.data() || {};
    const role = String(caller.role || caller.tipoUsuario || "").toLowerCase();
    if (role !== "lojista") {
        throw new HttpsError("permission-denied", "Apenas lojistas.");
    }
    const ownerUid = String(caller.lojista_owner_uid || "").trim();
    if (ownerUid) {
        const nivel = Number(caller.painel_colaborador_nivel || 0);
        if (nivel < 2) {
            throw new HttpsError("permission-denied", "Sem permissao.");
        }
    }
}

// =============================================================================
// WEBHOOK PRINCIPAL
// =============================================================================

/**
 * POST /webhooks/mercadopago
 * Endpoint unico para notificacoes de pagamento do modulo Gestao Comercial.
 * Dominio sugerido: https://planos.dipertin.com.br/webhooks/mercadopago
 */
exports.webhookMercadoPagoGestaoComercial = functions.https.onRequest(
    async (req, res) => {
        res.set("Cache-Control", "no-store");

        if (req.method === "GET") {
            return res.status(200).send("ok");
        }
        if (req.method !== "POST") {
            return res.status(405).send("Method Not Allowed");
        }

        // Extrair body
        let body = {};
        try {
            if (typeof req.body === "string") {
                body = JSON.parse(req.body || "{}");
            } else if (req.body && typeof req.body === "object") {
                body = req.body;
            }
        } catch (e) {
            console.error("[mp-gestao] JSON invalido:", e);
            return res.status(400).send("bad json");
        }

        // Extrair paymentId
        const paymentId = extrairPaymentId(body);
        if (!paymentId) {
            console.log("[mp-gestao] Webhook sem paymentId, ignorando.");
            return res.status(200).send("no payment id");
        }

        const action = body.action || body.type || "";
        if (action && String(action).includes("merchant_order") && !body.data?.id) {
            return res.status(200).send("ignored merchant_order");
        }

        console.log("[mp-gestao] Webhook recebido: paymentId=" + paymentId + ", action=" + action);

        try {
            await processarNotificacaoPagamento(String(paymentId));
            return res.status(200).send("ok");
        } catch (e) {
            console.error("[mp-gestao] Erro ao processar pagamento:", e.message || e);
            return res.status(500).send("error");
        }
    },
);

// =============================================================================
// HELPERS DE EXTRACAO
// =============================================================================

/**
 * Extrai paymentId do body do webhook.
 * Suporta formatos: data.id, id, resource_id, resource.id, payment_id, payment.id
 */
function extrairPaymentId(body) {
    if (!body || typeof body !== "object") return null;
    const data = body.data || {};
    const id =
        data.id ||
        body.id ||
        body.resource_id ||
        body.resource?.id ||
        body.payment_id ||
        body.payment?.id;
    return id ? String(id).trim() : null;
}

// =============================================================================
// PROCESSAMENTO DO WEBHOOK
// =============================================================================

/**
 * Processa notificacao de pagamento recebida via webhook.
 *
 * REGRAS:
 * - Se cobranca ja foi processada (processed===true), ignora.
 * - Se cobranca ja esta paga (status===pago), ignora.
 * - NUNCA marca como cancelado/recusado para cobrancas em aguardando_pagamento
 *   que ainda estao dentro do prazo de 5 minutos (a menos que ja tenha expirado).
 */
async function processarNotificacaoPagamento(paymentId) {
    const db = admin.firestore();

    // 0. ROTEAMENTO: se for pagamento de assinatura_cobranca (Plano GC),
    //    processa pela função dedicada e retorna.
    try {
        const tokenRoteamento = await getMercadoPagoAccessTokenPlataforma();
        if (tokenRoteamento) {
            const paymentRoteamento = await fetchPaymentFromMp(tokenRoteamento, paymentId);
            const meta = (paymentRoteamento && paymentRoteamento.metadata) || {};
            if (meta.tipo === "assinatura_cobranca") {
                console.log(
                    "[mp-gestao] Roteando pagamento " + paymentId + " para processarCobrancaAssinatura"
                );
                const assinaturaCobrancas = require("./assinatura_cobrancas");
                if (typeof assinaturaCobrancas.processarPagamentoGestaoComercial !== "function") {
                    console.error("[mp-gestao] processarPagamentoGestaoComercial NÃO exportado");
                    return;
                }
                const r = await assinaturaCobrancas.processarPagamentoGestaoComercial(paymentRoteamento);
                console.log("[mp-gestao] Resultado processamento assinatura:", JSON.stringify(r));
                return;
            }
            if (meta.tipo === "assinatura_contratacao" || meta.tipo === "assinatura_renovacao") {
                console.log(
                    "[mp-gestao] Roteando pagamento " + paymentId + " para PIX assinatura direta"
                );
                const assinaturaPagamento = require("./assinatura_pagamento");
                const r = await assinaturaPagamento.processarPagamentoPixAssinaturaDireto(paymentRoteamento);
                console.log("[mp-gestao] Resultado PIX assinatura:", JSON.stringify(r));
                return;
            }
            // Fallback por external_reference
            const ext = String(paymentRoteamento.external_reference || "");
            if (/^(assinatura_|renovar_)/.test(ext)) {
                const assinaturaPagamento = require("./assinatura_pagamento");
                const r = await assinaturaPagamento.processarPagamentoPixAssinaturaDireto(paymentRoteamento);
                console.log("[mp-gestao] Resultado PIX por external_reference:", JSON.stringify(r));
                return;
            }
        }
    } catch (eRoteamento) {
        console.warn("[mp-gestao] Erro no roteamento de assinatura (continuando):", eRoteamento.message || eRoteamento);
    }

    // 1. Buscar cobranca pelo paymentId (fluxo PDV/Gestão Comercial normal)
    const cobrancasSnap = await db
        .collection("gestao_comercial_cobrancas")
        .where("paymentId", "==", paymentId)
        .limit(1)
        .get();

    let cobrancaDoc = null;
    let cobrancaData = null;

    if (!cobrancasSnap.empty) {
        cobrancaDoc = cobrancasSnap.docs[0];
        cobrancaData = cobrancaDoc.data() || {};
    }

    // 2. Se nao encontrou por paymentId, tentar pelo external_reference
    if (!cobrancaData) {
        const token = await getMercadoPagoAccessTokenPlataforma();
        if (token) {
            try {
                const payment = await fetchPaymentFromMp(token, paymentId);
                const extRef = payment.external_reference || "";
                if (extRef) {
                    const cobrancasExtSnap = await db
                        .collection("gestao_comercial_cobrancas")
                        .where("externalReference", "==", extRef)
                        .limit(1)
                        .get();
                    if (!cobrancasExtSnap.empty) {
                        cobrancaDoc = cobrancasExtSnap.docs[0];
                        cobrancaData = cobrancaDoc.data() || {};
                    }
                }
            } catch (e) {
                console.warn("[mp-gestao] Erro ao buscar payment externo:", e.message || e);
            }
        }
    }

    if (!cobrancaData) {
        console.warn("[mp-gestao] Cobranca nao encontrada para paymentId=" + paymentId);
        return;
    }

    // IDEMPOTENCIA: se ja processado, ignora
    if (cobrancaData.processed === true) {
        console.log("[mp-gestao] Cobranca " + cobrancaDoc.id + " ja processada anteriormente. Ignorando duplicata.");
        return;
    }

    // IDEMPOTENCIA: se ja esta pago, ignora
    if (cobrancaData.status === "pago") {
        console.log("[mp-gestao] Cobranca " + cobrancaDoc.id + " ja esta paga. Ignorando duplicata.");
        return;
    }

    const lojaId = cobrancaData.lojaId || "";
    if (!lojaId) {
        console.warn("[mp-gestao] Cobranca sem lojaId:", cobrancaDoc.id);
        return;
    }

    // 3. Buscar credenciais da loja
    const lojaCreds = await getLojaMercadoPagoCreds(db, lojaId);
    if (!lojaCreds || !lojaCreds.accessToken) {
        console.warn("[mp-gestao] Credenciais MP nao encontradas para loja " + lojaId);
        return;
    }

    // 4. Consultar pagamento na API MP com o token da loja
    let payment;
    try {
        payment = await fetchPaymentFromMp(lojaCreds.accessToken, paymentId);
    } catch (e) {
        console.error("[mp-gestao] Erro ao consultar payment " + paymentId + " para loja " + lojaId + ":", e.message);
        return;
    }

    const statusMp = String(payment.status || "").toLowerCase();

    // 5. Processar de acordo com o status do MP
    const pago = statusMp === "approved" || statusMp === "authorized";

    if (pago) {
        // Pagamento aprovado -> atualizar cobranca e finalizar venda
        console.log("[mp-gestao] Pagamento aprovado: paymentId=" + paymentId + ", loja=" + lojaId);

        const valorRecebido = payment.transaction_amount || cobrancaData.valor || 0;

        await cobrancaDoc.ref.update({
            status: "pago",
            pagoEm: admin.firestore.FieldValue.serverTimestamp(),
            valorRecebido: valorRecebido,
            mpStatus: statusMp,
            mpStatusDetail: String(payment.status_detail || ""),
            mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            mpPaymentMethod: payment.payment_method_id || "",
            mpPayerEmail: payment.payer?.email || "",
            processed: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Finalizar venda PDV
        try {
            await finalizarVendaPdv(db, cobrancaData, paymentId, statusMp, payment);
        } catch (e) {
            console.error("[mp-gestao] Erro ao finalizar venda PDV:", e.message || e);
        }

        console.log("[mp-gestao] Pagamento " + paymentId + " processado com sucesso para loja " + lojaId + ": " + statusMp);
    } else if (cobrancaData.status === "aguardando_pagamento" || cobrancaData.status === "aguardando") {
        // Dentro do prazo de 5 minutos - NAO cancelar automaticamente
        const statusMpLower = statusMp;
        const agora = new Date();
        const expiresTs = cobrancaData.expiresAt?.toDate
            ? cobrancaData.expiresAt.toDate()
            : cobrancaData.expiresAt
                ? new Date(cobrancaData.expiresAt)
                : null;

        const expirado = expiresTs && !isNaN(expiresTs.getTime()) && agora >= expiresTs;

        if (statusMp === "rejected" || statusMp === "cancelled" || statusMp === "refunded") {
            // So reflete status negativo do MP se a cobranca ja expirou
            if (expirado) {
                const statusFinal = statusMp === "cancelled" ? "cancelado"
                                 : statusMp === "refunded" ? "estornado"
                                 : "recusado";
                await cobrancaDoc.ref.update({
                    status: statusFinal,
                    mpStatus: statusMp,
                    mpStatusDetail: String(payment.status_detail || ""),
                    mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                    expiradoEm: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log("[mp-gestao] Cobranca " + cobrancaDoc.id + " expirada. Status MP: " + statusMp);
            } else {
                // Ainda dentro do prazo -> NAO cancela, so registra mpStatus
                await cobrancaDoc.ref.update({
                    mpStatus: statusMp,
                    mpStatusDetail: String(payment.status_detail || ""),
                    mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log("[mp-gestao] Cobranca " + cobrancaDoc.id + " ainda aguardando (dentro do prazo). MP status: " + statusMp + ". Mantendo aguardando_pagamento.");
            }
        } else {
            // pending / in_process / unknown -> so registra mpStatus
            const updateFields = {
                mpStatus: statusMp,
                mpStatusDetail: String(payment.status_detail || ""),
                mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            // Se a cobranca estiver com status legado "aguardando", migra para o novo padrao
            if (cobrancaData.status === "aguardando") {
                updateFields.status = "aguardando_pagamento";
            }
            await cobrancaDoc.ref.update(updateFields);
            console.log("[mp-gestao] Cobranca " + cobrancaDoc.id + " ainda aguardando pagamento. MP status: " + statusMp);
        }
    } else {
        // Status nao esperado (expirado, cancelado manualmente, etc.)
        console.log("[mp-gestao] Cobranca " + cobrancaDoc.id + " em status " + cobrancaData.status + ". Webhook ignorado para este estado.");
    }
}

// =============================================================================
// HELPERS DE API MP
// =============================================================================

async function fetchPaymentFromMp(accessToken, paymentId) {
    const url = MP_API + "/v1/payments/" + encodeURIComponent(String(paymentId));
    const res = await fetch(url, {
        method: "GET",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
        },
    });
    const body = await res.json().catch(function () { return {}; });
    if (!res.ok) {
        const err = new Error(body.message || "MP GET " + res.status);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

async function getLojaMercadoPagoCreds(db, lojaId) {
    // Localizacao 1 (principal): gestao_comercial_configuracoes/{lojaId}/pagamentos.mercado_pago
    const configDoc = await db
        .collection("gestao_comercial_configuracoes")
        .doc(lojaId)
        .get();

    if (configDoc.exists) {
        const configData = configDoc.data() || {};
        const pagamentos = configData.pagamentos || {};
        const mpData = pagamentos.mercado_pago;
        if (mpData && mpData.ativo === true) {
            const accessToken = mpData.token && String(mpData.token).trim()
                ? String(mpData.token).trim()
                : null;
            const publicKey = mpData.clientId && String(mpData.clientId).trim()
                ? String(mpData.clientId).trim()
                : null;
            if (accessToken) {
                return { accessToken: accessToken, publicKey: publicKey, ambiente: mpData.ambiente || "producao" };
            }
        }
    }

    // Localizacao 2 (legado): gestao_comercial_integracoes_pagamento/{lojaId}/gateways/mercado_pago
    const integracoesDoc = await db
        .collection("gestao_comercial_integracoes_pagamento")
        .doc(lojaId)
        .collection("gateways")
        .doc("mercado_pago")
        .get();

    if (integracoesDoc.exists) {
        const d = integracoesDoc.data() || {};
        if (d.ativo === true) {
            const accessToken = d.accessToken && String(d.accessToken).trim()
                ? String(d.accessToken).trim()
                : null;
            const publicKey = d.publicKey && String(d.publicKey).trim()
                ? String(d.publicKey).trim()
                : null;
            if (accessToken) {
                return { accessToken: accessToken, publicKey: publicKey, ambiente: d.ambiente || "producao" };
            }
        }
    }

    return null;
}

/** Fallback: token da plataforma DiPertin (gateways_pagamento/mercado_pago). */
async function getMercadoPagoAccessTokenPlataforma() {
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
 * Gera external_reference no formato: pdv_{lojaId}_{cobrancaId}_{timestamp}
 */
function gerarExternalRefPdv(lojaId, cobrancaId) {
    return "pdv_" + lojaId + "_" + cobrancaId + "_" + Date.now();
}

// =============================================================================
// CALLABLE: CRIAR PAGAMENTO PIX (PDV)
// =============================================================================

/**
 * onCall v2: cria um pagamento PIX no Mercado Pago para o PDV.
 * Usa as credenciais do lojista, nunca expoe token ao frontend.
 *
 * Recebe: { lojaId, vendaId, valor, itens[], clienteId?, operadorId?, clienteNome? }
 * Retorna: { cobrancaId, paymentId, qrCodeBase64, pixCopiaECola, expiresAt, status }
 */
exports.createPdvPixPayment = onCall(
    { region: "us-central1", enforceAppCheck: false },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGcAcessoLoja(request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const valor = Number(data.valor);
        const vendaId = String(data.vendaId || "").trim();
        const itens = Array.isArray(data.itens) ? data.itens : [];
        const operadorId = String(data.operadorId || "").trim();
        const clienteId = String(data.clienteId || "").trim() || null;
        const clienteNome = String(data.clienteNome || "").trim() || null;

        if (!lojaId || !valor || valor <= 0 || !vendaId) {
            throw new HttpsError("invalid-argument", "lojaId, vendaId e valor sao obrigatorios.");
        }

        const db = admin.firestore();

        // 1. Buscar credenciais Mercado Pago da loja
        const lojaCreds = await getLojaMercadoPagoCreds(db, lojaId);
        if (!lojaCreds || !lojaCreds.accessToken) {
            throw new HttpsError(
                "failed-precondition",
                "Configure um gateway de pagamento antes de receber por PIX. Acesse Configuracoes Comercial > Banco e Pagamentos.",
            );
        }

        // 2. Criar documento de cobranca no Firestore
        const cobrancaRef = db.collection("gestao_comercial_cobrancas").doc();
        const cobrancaId = cobrancaRef.id;
        const externalRef = gerarExternalRefPdv(lojaId, cobrancaId);
        const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutos

        console.log("[mp-pdv] Criando PIX: loja=" + lojaId + ", valor=" + valor + ", venda=" + vendaId);

        // 3. Montar payload para API do Mercado Pago
        const description = itens.length > 0
            ? "PDV " + lojaId.slice(-6) + " - " + itens.length + " item(ns)"
            : "Venda PDV " + vendaId.slice(-8);

        const mpPayload = {
            transaction_amount: valor,
            description: description,
            payment_method_id: "pix",
            installments: 1,
            payer: {
                email: "pgto@dipertin.com.br",
                first_name: clienteNome || "Cliente",
            },
            date_of_expiration: expiresAt.toISOString(),
            external_reference: externalRef,
            metadata: {
                lojaId: lojaId,
                cobrancaId: cobrancaId,
                vendaId: vendaId,
                origem: "pdv",
                operadorId: operadorId,
            },
        };

        // 4. Chamar API MP para criar PIX
        const mpRes = await fetch(MP_API + "/v1/payments", {
            method: "POST",
            headers: {
                Authorization: "Bearer " + lojaCreds.accessToken,
                "Content-Type": "application/json",
                "X-Idempotency-Key": cobrancaId,
            },
            body: JSON.stringify(mpPayload),
        });

        const mpBody = await mpRes.json().catch(function () { return {}; });

        if (!mpRes.ok) {
            console.error("[mp-pdv] Erro MP criar PIX:", mpBody);
            const message = mpBody?.message || "HTTP " + mpRes.status;
            throw new HttpsError("internal", "Erro ao criar cobranca PIX: " + message);
        }

        const paymentId = String(mpBody.id || "");

        // ═══════════════════════════════════════════════════════════════════
        // EXTRAIR DADOS PIX DO MERCADO PAGO
        // Fonte unica de verdade: os campos retornados pela API do MP.
        // NUNCA montar manualmente payload PIX (CPF, chavePix, BR Code, etc.)
        // ═══════════════════════════════════════════════════════════════════
        const transactionData = mpBody?.point_of_interaction?.transaction_data || {};

        // pixCopiaECola = texto copia-e-cola oficial do MP
        const pixCopiaECola = String(transactionData.qr_code || "");

        // qrCodeBase64 = imagem QR Code oficial (PNG base64) do MP
        // USAR EXATAMENTE o que o MP retornou — NÃO gerar manualmente
        const qrCodeBase64 = String(transactionData.qr_code_base64 || "");

        // LOGS TEMPORARIOS
        console.log("[mp-pdv] MP QR_CODE:", transactionData.qr_code);
        console.log("[mp-pdv] MP QR_CODE_BASE64 existe:", !!transactionData.qr_code_base64);
        console.log("[mp-pdv] PIX COPIA E COLA SALVO:", pixCopiaECola);
        console.log("[mp-pdv] pixCopiaECola length:", pixCopiaECola.length);
        console.log("[mp-pdv] pixCopiaECola startsWith 000201:", pixCopiaECola.startsWith("000201"));

        if (!paymentId || !pixCopiaECola) {
            console.error("[mp-pdv] MP nao retornou qr_code:", mpBody);
            throw new HttpsError("internal", "Mercado Pago nao retornou o codigo PIX.");
        }

        // 5. Salvar cobranca no Firestore (com status correto "aguardando_pagamento")
        await cobrancaRef.set({
            lojaId: lojaId,
            vendaId: vendaId,
            clienteId: clienteId,
            clienteNome: clienteNome,
            operadorId: operadorId,
            gateway: "mercado_pago",
            paymentId: paymentId,
            externalReference: externalRef,
            valor: valor,
            status: "aguardando_pagamento",

            // ─── CAMPOS PIX (EXATAMENTE COMO RETORNADO PELO MP) ──────
            qrCodeBase64: qrCodeBase64,       // imagem QR (MP oficial)
            pixCopiaECola: pixCopiaECola,     // texto copia-e-cola (MP oficial)
            // ─────────────────────────────────────────────────────────

            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
            origem: "pdv",
            itens: itens,
            processed: false,
            metadata: {
                lojaId: lojaId,
                vendaId: vendaId,
                operadorId: operadorId,
                origem: "pdv",
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 6. Salvar venda com status "aguardando_pagamento"
        const operadorNome = request.auth.token?.name || "Operador PDV";
        await db.collection("gestao_comercial_vendas").doc(vendaId).set({
            loja_id: lojaId,
            venda_id: vendaId,
            cobranca_id: cobrancaId,
            codigo_venda: vendaId.slice(-8).toUpperCase(),
            cliente_id: clienteId || "venda_balcao",
            cliente_nome: clienteNome || "Cliente PDV",
            itens: itens,
            quantidade_itens: itens.reduce(function (s, i) { return s + (Number(i.quantidade) || 1); }, 0),
            forma_pagamento: "PIX",
            valor_total: valor,
            valor_pago: 0,
            valor_pendente: valor,
            desconto_total: 0,
            status: "aguardando_pagamento",
            operador_id: operadorId,
            operador_nome: operadorNome,
            data_venda: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("[mp-pdv] PIX " + paymentId + " criado com sucesso p/ loja " + lojaId + ", venda " + vendaId + ", expira em 5min");

        return {
            cobrancaId: cobrancaId,
            paymentId: paymentId,
            qrCodeBase64: qrCodeBase64,
            pixCopiaECola: pixCopiaECola,
            expiresAt: expiresAt.toISOString(),
            status: "aguardando_pagamento",
        };
    },
);

// =============================================================================
// CALLABLE: VERIFICAR STATUS PAGAMENTO PIX (PDV)
// =============================================================================

/**
 * onCall v2: consulta o status de uma cobranca PIX.
 *
 * REGRAS:
 * - NUNCA marca como cancelado durante os 5 minutos de espera.
 * - So marca como expirado se now >= expiresAt E ainda estiver aguardando.
 * - So marca como pago se MP confirmar approved/authorized.
 * - "Verificar pagamento" no frontend NAO pode cancelar a cobranca.
 *
 * Recebe: { cobrancaId }
 * Retorna: { status, pago, expirado, valorRecebido, vendaId, pagamento }
 */
exports.checkPdvPixPaymentStatus = onCall(
    { region: "us-central1", enforceAppCheck: false },
    async (request) => {
        try {
            if (!request.auth) {
                throw new HttpsError("unauthenticated", "Login necessario.");
            }
            await assertGcAcessoLoja(request);

            const cobrancaId = String(request.data?.cobrancaId || "").trim();
            if (!cobrancaId) {
                throw new HttpsError("invalid-argument", "cobrancaId e obrigatorio.");
            }

            const db = admin.firestore();
            const cobrancaRef = db.collection("gestao_comercial_cobrancas").doc(cobrancaId);
            const snap = await cobrancaRef.get();

            if (!snap.exists) {
                throw new HttpsError("not-found", "Cobranca nao encontrada.");
            }

            const data = snap.data() || {};
            let status = data.status || "aguardando_pagamento";

            // Se esta aguardando, tentar consultar Mercado Pago para ver se ja foi pago
            if ((status === "aguardando_pagamento" || status === "aguardando") && data.paymentId && data.lojaId) {
                try {
                    const lojaCreds = await getLojaMercadoPagoCreds(db, data.lojaId);
                    if (lojaCreds && lojaCreds.accessToken) {
                        const paymentMp = await fetchPaymentFromMp(lojaCreds.accessToken, data.paymentId);
                        const statusMp = String(paymentMp.status || "").toLowerCase();

                        if (statusMp === "approved" || statusMp === "authorized") {
                            // Pagamento confirmado pelo gateway!
                            console.log("[mp-pdv-check] Pagamento " + data.paymentId + " aprovado via consulta direta.");
                            const valorRecebido = paymentMp.transaction_amount || data.valor || 0;

                            await cobrancaRef.update({
                                status: "pago",
                                mpStatus: statusMp,
                                mpStatusDetail: String(paymentMp.status_detail || ""),
                                pagoEm: admin.firestore.FieldValue.serverTimestamp(),
                                valorRecebido: valorRecebido,
                                processed: true,
                                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                            });
                            status = "pago";

                            try {
                                await finalizarVendaPdv(db, data, data.paymentId, statusMp, paymentMp);
                            } catch (e) {
                                console.error("[mp-pdv-check] Erro ao finalizar venda:", e.message || e);
                            }
                        } else if (statusMp === "pending" || statusMp === "in_process" || statusMp === "in_mediation") {
                            // Ainda pendente no gateway -> mantem aguardando_pagamento
                            await cobrancaRef.update({
                                mpStatus: statusMp,
                                mpStatusDetail: String(paymentMp.status_detail || ""),
                                mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                            });
                            console.log("[mp-pdv-check] Cobranca " + cobrancaId + " ainda pendente no MP: " + statusMp);
                        } else {
                            // rejected / cancelled / refunded -> so atualiza mpStatus,
                            // NAO altera o status principal (aguardando_pagamento)
                            await cobrancaRef.update({
                                mpStatus: statusMp,
                                mpStatusDetail: String(paymentMp.status_detail || ""),
                                mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                            });
                            console.log("[mp-pdv-check] Cobranca " + cobrancaId + " MP status: " + statusMp + ". Mantendo aguardando_pagamento.");
                        }
                    }
                } catch (e) {
                    console.warn("[mp-pdv-check] Erro consulta MP p/ " + data.paymentId + ":", e.message || e);
                }
            }

            // Re-ler status apos possivel atualizacao
            if (status !== "pago") {
                const snap2 = await cobrancaRef.get();
                if (snap2.exists) {
                    status = snap2.data()?.status || status;
                }
            }

            // Verificar expiracao: so marca expirado se now >= expiresAt
            // NUNCA marca expirado antes do prazo
            if ((status === "aguardando_pagamento" || status === "aguardando") && data.expiresAt) {
                const expiresTs = data.expiresAt?.toDate
                    ? data.expiresAt.toDate()
                    : new Date(data.expiresAt);
                const agora = new Date();

                if (!isNaN(expiresTs.getTime()) && agora >= expiresTs) {
                    await cobrancaRef.update({
                        status: "expirado",
                        expiradoEm: admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    status = "expirado";
                    console.log("[mp-pdv-check] Cobranca " + cobrancaId + " expirada apos 5 min sem pagamento.");
                }
            }

            // Montar resposta
            const estaPago = status === "pago";
            const estaExpirado = status === "expirado";
            const estaCancelado = status === "cancelado" || status === "recusado" || status === "estornado";

            let vendaData = null;
            if (estaPago && data.vendaId) {
                try {
                    const vendaSnap = await db.collection("gestao_comercial_vendas").doc(data.vendaId).get();
                    if (vendaSnap.exists) {
                        vendaData = vendaSnap.data();
                    }
                } catch (e) {
                    console.warn("[mp-pdv] Erro ao ler venda " + data.vendaId + ":", e.message || e);
                }
            }

            var pagamento = estaPago
                ? {
                    valor: vendaData?.valor_total ?? data.valor ?? 0,
                    clienteNome: vendaData?.cliente_nome ?? "Cliente PDV",
                    codigoVenda: vendaData?.codigo_venda ?? (data.vendaId ? String(data.vendaId).slice(-8) : ""),
                    formaPagamento: "PIX",
                    dataHora: vendaData?.data_venda?.toDate?.()?.toISOString() ?? new Date().toISOString(),
                    operadorNome: vendaData?.operador_nome ?? "",
                    gateway: "Mercado Pago",
                }
                : null;

            console.log("[mp-pdv-check] Status cobranca " + cobrancaId + ": " + status +
                (estaPago ? " (PAGO)" : "") +
                (estaExpirado ? " (EXPIRADO)" : ""));

            return {
                status: status,
                pago: estaPago,
                expirado: estaExpirado,
                cancelado: estaCancelado,
                valorRecebido: data.valorRecebido ?? 0,
                vendaId: data.vendaId ?? "",
                cobrancaId: cobrancaId,
                pagamento: pagamento,
            };
        } catch (e) {
            console.error("[mp-pdv-check] Erro fatal:", e?.message || e, e?.stack || "");
            throw new HttpsError("internal", "Erro ao verificar status: " + (e?.message || e));
        }
    },
);

// =============================================================================
// FINALIZAR VENDA PDV
// =============================================================================

/**
 * Finaliza a venda PDV apos confirmacao de pagamento.
 *
 * IDEMPOTENCIA:
 * - Verifica se venda ja foi finalizada (status=pago/quitado/finalizada).
 * - Verifica se recebimento ja existe para esta cobranca.
 * - Usa batch write atomico.
 */
async function finalizarVendaPdv(db, cobrancaData, paymentId, statusMp, payment) {
    if (cobrancaData.origem !== "pdv") {
        console.log("[mp-pdv-finalizar] Origem nao é pdv (" + (cobrancaData.origem || "vazio") + "). Pulando.");
        return;
    }
    if (statusMp !== "approved" && statusMp !== "authorized") {
        console.log("[mp-pdv-finalizar] Status MP nao aprovado (" + statusMp + "). Pulando.");
        return;
    }

    const lojaId = cobrancaData.lojaId;
    const vendaId = cobrancaData.vendaId;
    const valorRecebido = payment.transaction_amount || cobrancaData.valor || 0;

    if (!vendaId || !lojaId) {
        console.warn("[mp-pdv-finalizar] vendaId ou lojaId ausentes.");
        return;
    }

    // --- IDEMPOTENCIA: verificar status da venda antes de prosseguir ---
    const vendaRef = db.collection("gestao_comercial_vendas").doc(vendaId);
    const vendaSnap = await vendaRef.get();

    if (vendaSnap.exists) {
        const vendaData = vendaSnap.data() || {};
        if (vendaData.status === "pago" || vendaData.status === "quitado" || vendaData.status === "finalizada") {
            console.log("[mp-pdv-finalizar] Venda " + vendaId + " ja finalizada (idempotencia). Pulando.");
            return;
        }
    }

    // --- IDEMPOTENCIA: verificar se ja existe recebimento para esta cobranca ---
    const cobrancaId = cobrancaData.cobrancaId || "";
    if (cobrancaId) {
        const recebimentosExistentes = await db
            .collection("gestao_comercial_recebimentos")
            .where("cobranca_id", "==", cobrancaId)
            .limit(1)
            .get();

        if (!recebimentosExistentes.empty) {
            console.log("[mp-pdv-finalizar] Recebimento ja existe para cobranca " + cobrancaId + ". Pulando.");
            return;
        }
    }

    // --- Transacao: atualizar venda + criar recebimento ---
    try {
        const recebimentoRef = db.collection("gestao_comercial_recebimentos").doc();
        const batch = db.batch();

        // 1. Atualizar venda para pago
        batch.update(vendaRef, {
            status: "pago",
            statusPagamento: "pago",
            statusVenda: "finalizada",
            valor_pago: valorRecebido,
            valor_pendente: 0,
            forma_pagamento: "PIX",
            pagoEm: admin.firestore.FieldValue.serverTimestamp(),
            paidAt: admin.firestore.FieldValue.serverTimestamp(),
            mpPaymentId: paymentId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 2. Criar documento de recebimento
        batch.set(recebimentoRef, {
            loja_id: lojaId,
            venda_id: vendaId,
            cliente_id: cobrancaData.clienteId || "venda_balcao",
            cliente_nome: cobrancaData.clienteNome || "Cliente PDV",
            valor_original: cobrancaData.valor || valorRecebido,
            valor_recebido: valorRecebido,
            forma_pagamento: "PIX",
            gateway: "mercado_pago",
            payment_id: paymentId,
            cobranca_id: cobrancaId,
            recebido_por_id: cobrancaData.operadorId || "",
            recebido_por_nome: "Operador PDV",
            data_recebimento: admin.firestore.FieldValue.serverTimestamp(),
            status: "confirmado",
            origem: "pdv_pix",
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        await batch.commit();

        console.log("[mp-pdv-finalizar] Venda " + vendaId + " finalizada via PIX " + paymentId + ". Recebimento " + recebimentoRef.id);
    } catch (e) {
        console.error("[mp-pdv-finalizar] Erro na transacao:", e.message || e);
        throw e;
    }
}

// =============================================================================
// CALLABLE: TESTAR CONEXAO MERCADO PAGO
// =============================================================================

/**
 * onCall v2: testa se um Access Token Mercado Pago e valido.
 * Chamado do frontend para evitar CORS ao chamar a API MP diretamente.
 *
 * Recebe: { accessToken }
 * Retorna: { valido: bool, mensagem: string }
 */
exports.testarConexaoMercadoPago = onCall(
    { region: "us-central1", enforceAppCheck: false },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGcAcessoLoja(request);

        const accessToken = String(request.data?.accessToken || "").trim();
        if (!accessToken) {
            throw new HttpsError("invalid-argument", "Access Token e obrigatorio.");
        }

        const url = MP_API + "/v1/payments/search?limit=1";
        const res = await fetch(url, {
            method: "GET",
            headers: {
                Authorization: "Bearer " + accessToken,
                "Content-Type": "application/json",
            },
        });

        if (res.ok) {
            return { valido: true, mensagem: "Access Token valido! Conexao realizada com sucesso." };
        }

        const body = await res.json().catch(function () { return {}; });
        const message = body?.message || "HTTP " + res.status;

        if (res.status === 401) {
            return { valido: false, mensagem: "Access Token invalido ou revogado. Verifique as credenciais." };
        }
        if (res.status === 403) {
            return { valido: false, mensagem: "Access Token sem permissao. Verifique as permissoes da aplicacao." };
        }

        return { valido: false, mensagem: "Erro ao validar token: " + message };
    },
);
