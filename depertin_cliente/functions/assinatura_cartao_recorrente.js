"use strict";

/**
 * Assinatura de Planos — Cartão RECORRENTE (preapproval) via Mercado Pago.
 *
 * Usa as credenciais globais da plataforma em gateways_pagamento/mercado_pago.
 * NÃO usa gateway por loja.
 *
 * IMPORTANTE: Este arquivo gerencia apenas cartão recorrente (assinatura mensal
 * automática). NÃO altera:
 *  - assinarPlanoCriarPagamentoPix
 *  - assinarPlanoProcessarCartao (avulso)
 *  - assinarPlanoRenovarCartao (manual)
 *  - webhook principal de pedidos
 *
 * Fluxo do cartão recorrente:
 *  1. Lojista aceita autorização de cobrança automática
 *  2. Lojista preenche dados do cartão
 *  3. Backend: POST /v1/card_tokens → token do cartão
 *  4. Backend: POST /preapproval → cria assinatura recorrente
 *  5. Backend: salva identificadores seguros no Firestore
 *  6. MP cobra automaticamente todo mês (webhook separado processa)
 *
 * Segurança: nunca salva número completo do cartão, CVV ou dados sensíveis.
 * Apenas: preapproval_id, payment_method_id, last_four, bandeira.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const MP_API = "https://api.mercadopago.com";

// =============================================================================
// HELPERS MERCADO PAGO (REUSO)
// =============================================================================

/**
 * Lê credenciais globais do Mercado Pago da coleção `gateways_pagamento`.
 * Reutiliza a estrutura do projeto.
 */
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
    if (!accessToken) return null;
    return { accessToken };
}

/**
 * Cria card_token no MP (token descartável, salvo apenas em memória).
 * NÃO persistimos este token.
 */
async function criarCardTokenMp(accessToken, dadosCartao) {
    const exp = dadosCartao.mesExpiracao && dadosCartao.anoExpiracao
        ? normalizarExpiracao(dadosCartao.mesExpiracao, dadosCartao.anoExpiracao)
        : null;
    if (!exp) {
        throw new Error("expiracao_invalida");
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

    const res = await fetch(MP_API + "/v1/card_tokens", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || !body || !body.id) {
        const err = new Error(body.message || "MP card_token " + res.status);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body; // { id, card_number_length, last_four_digits, payment_method, ... }
}

function normalizarExpiracao(mesRaw, anoRaw) {
    const mes = parseInt(String(mesRaw || "").replace(/\D/g, ""), 10);
    let ano = parseInt(String(anoRaw || "").replace(/\D/g, ""), 10);
    if (!Number.isFinite(mes) || mes < 1 || mes > 12) return null;
    if (!Number.isFinite(ano) || ano <= 0) return null;
    if (ano < 100) ano += 2000;
    if (ano < 2000 || ano > 2099) return null;
    return { mes, ano };
}

// =============================================================================
// CLOUD FUNCTION: CRIAR CARTÃO RECORRENTE (PREAPPROVAL)
// =============================================================================

/**
 * onCall v2: Cria assinatura recorrente via cartão de crédito (preapproval).
 *
 * Entrada:
 *  - planId, planName, valor (BRL), duracaoDias
 *  - lojaId, lojaNome, ownerName, ownerEmail
 *  - numeroCartao, nomeTitular, mesExpiracao, anoExpiracao, cvv, cpf
 *  - aceitoRecorrencia: boolean (obrigatório true)
 *  - ownerIp: string (opcional, para auditoria LGPD)
 *
 * Saída: { preapprovalId, status, paymentMethodId, lastFour, nextBillingDate }
 */
exports.assinarPlanoCriarCartaoRecorrente = onCall(
    // TODO: voltar para `enforceAppCheck: true` após corrigir a Secret Key do
    // reCAPTCHA v3 no Firebase Console → App Check → depertin_web.
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 90 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }
        const data = request.data || {};

        const planId = String(data.planId || "").trim();
        const planName = String(data.planName || "").trim();
        const valor = Number(data.valor);
        const lojaId = String(data.lojaId || "").trim();
        const lojaNome = String(data.lojaNome || "").trim();
        const ownerName = String(data.ownerName || "").trim();
        const ownerEmail = String(data.ownerEmail || "").trim();
        const aceitoRecorrencia = data.aceitoRecorrencia === true;
        const ownerIp = String(data.ownerIp || "").trim();

        // Validação
        if (!planId || !valor || valor <= 0) {
            throw new HttpsError("invalid-argument", "planId e valor são obrigatórios.");
        }
        if (!lojaId || !lojaNome) {
            throw new HttpsError("invalid-argument", "lojaId e lojaNome são obrigatórios.");
        }
        if (!ownerEmail) {
            throw new HttpsError("invalid-argument", "E-mail do titular é obrigatório.");
        }
        if (!aceitoRecorrencia) {
            throw new HttpsError(
                "failed-precondition",
                "É necessário aceitar a autorização de cobrança automática para usar cartão recorrente."
            );
        }
        if (lojaId !== request.auth.uid) {
            throw new HttpsError("permission-denied", "LojaId não confere com usuário autenticado.");
        }

        // Verificar se já existe assinatura para esta loja
        // Verifica especificamente por assinatura recorrente (com mp_preapproval_id)
        const db = admin.firestore();
        const assinaturaRecorrenteSnap = await db
            .collection("assinaturas_clientes")
            .where("store_id", "==", lojaId)
            .where("mp_preapproval_id", "!=", null)
            .limit(1)
            .get();

        if (!assinaturaRecorrenteSnap.empty) {
            // Já tem assinatura recorrente (cartão ou outra). Não criar duplicada.
            const aExistente = assinaturaRecorrenteSnap.docs[0].data() || {};
            throw new HttpsError(
                "failed-precondition",
                "Lojista já possui assinatura recorrente ativa (preapproval: " +
                    (aExistente.mp_preapproval_id || "") + "). Use a função de atualização."
            );
        }

        // Pegar credenciais do MP
        const gateway = await getMercadoPagoGatewayConfig();
        if (!gateway || !gateway.accessToken) {
            throw new HttpsError(
                "failed-precondition",
                "Gateway Mercado Pago não configurado."
            );
        }

        // 1. Criar card_token
        let cardToken;
        try {
            cardToken = await criarCardTokenMp(gateway.accessToken, {
                numeroCartao: data.numeroCartao,
                nomeTitular: data.nomeTitular,
                mesExpiracao: data.mesExpiracao,
                anoExpiracao: data.anoExpiracao,
                cvv: data.cvv,
                cpf: data.cpf,
            });
        } catch (e) {
            console.error("[cartao-recorrente] Erro tokenize:", e.message);
            throw new HttpsError("invalid-argument", "Dados do cartão inválidos: " + (e.message || e));
        }

        if (!cardToken || !cardToken.id) {
            throw new HttpsError("invalid-argument", "Não foi possível validar o cartão.");
        }

        // Extrair dados seguros do token (apenas metadados, não dados sensíveis)
        const lastFour = cardToken.last_four_digits || "";
        const paymentMethod = cardToken.payment_method || {};
        const paymentMethodId = paymentMethod.id || "";
        const bandeira = paymentMethod.name || paymentMethod.payment_type_id || "";

        // 2. Calcular data de início (próximo mês)
        const startDate = new Date();
        startDate.setMonth(startDate.getMonth() + 1);
        startDate.setDate(1);
        const startDateIso = startDate.toISOString();

        // 3. Montar payload do preapproval
        const externalRef = "ASSINATURA_" + lojaId + "_" + Date.now();
        // URL direta da Cloud Function (sem rewrite/hosting externo)
        const notificationUrl = "https://us-central1-depertin-f940f.cloudfunctions.net/webhookCartaoRecorrente";

        const preapprovalPayload = {
            reason: "Assinatura " + (planName || "Plano DiPertin"),
            external_reference: externalRef,
            payer_email: ownerEmail,
            card_token_id: cardToken.id,
            auto_recurring: {
                frequency: 1,
                frequency_type: "months",
                start_date: startDateIso,
                transaction_amount: valor,
                currency_id: "BRL",
            },
            back_url: "https://dipertin.com.br/sistema/#/lojista/sua-loja",
            notification_url: notificationUrl,
            status: "authorized",
            metadata: {
                // Identificador único do tipo (canônico)
                tipo: "cartao_recorrente",

                // Aceita ambos formatos: camelCase e snake_case
                // para máxima compatibilidade com o webhook da Etapa 3.3
                lojaId: lojaId,
                loja_id: lojaId,
                storeId: lojaId,
                store_id: lojaId,
                planId: planId,
                plan_id: planId,
                valor: valor,
            },
        };

        // 4. Criar preapproval no MP
        const mpRes = await fetch(MP_API + "/preapproval", {
            method: "POST",
            headers: {
                Authorization: "Bearer " + gateway.accessToken,
                "Content-Type": "application/json",
                "X-Idempotency-Key": "assinatura-recorrente-" + lojaId + "-" + planId,
            },
            body: JSON.stringify(preapprovalPayload),
        });
        const mpBody = await mpRes.json().catch(() => ({}));

        if (!mpRes.ok || !mpBody || !mpBody.id) {
            console.error("[cartao-recorrente] Erro preapproval MP:", mpBody);
            throw new HttpsError(
                "internal",
                "Erro ao criar assinatura recorrente: " + (mpBody.message || mpRes.status)
            );
        }

        const preapprovalId = String(mpBody.id);
        const mpStatus = String(mpBody.status || "authorized");

        if (!preapprovalId) {
            throw new HttpsError("internal", "Mercado Pago não retornou preapproval_id válido.");
        }

        // 5. Calcular próxima cobrança
        const proxCobranca = new Date(startDate);

        // 6. Salvar no Firestore
        const now = admin.firestore.Timestamp.now();
        const assinaturaId = lojaId; // Por padrão, assinatura com mesmo ID da loja
        const duracaoDias = Number(data.duracaoDias) || 30;
        if (duracaoDias <= 0) {
            throw new HttpsError("invalid-argument", "duracaoDias inválido.");
        }

        const assinaturaData = {
            store_id: lojaId,
            store_name: lojaNome,
            owner_name: ownerName,
            email: ownerEmail,
            plan_id: planId,
            plan_name: planName,
            status: mpStatus, // "authorized" ou "active"
            monthly_amount: valor,
            duracao_dias: duracaoDias,
            tipo_cobranca: "cartao_recorrente",
            gateway: "Mercado Pago",

            // Identificadores seguros do MP
            mp_preapproval_id: preapprovalId,
            mp_payment_method_id: paymentMethodId,
            // NÃO salvar: número do cartão, CVV, card_token, card_id

            // Metadados seguros do cartão
            cartao_last_four: lastFour,
            cartao_bandeira: bandeira,
            cartao_ativo: true,

            // Autorização (LGPD)
            autorizacao_recorrente_aceita: true,
            autorizacao_recorrente_em: now,
            autorizacao_recorrente_ip: ownerIp,

            // Cobrança
            next_billing_date: admin.firestore.Timestamp.fromDate(proxCobranca),
            proxima_cobranca_recorrente: admin.firestore.Timestamp.fromDate(proxCobranca),
            last_payment_date: null,

            // Configurações padrão
            tolerancia_dias: 3,
            multa_percentual: 0,
            juros_percentual: 0,
            cobrar_multa: false,
            cobrar_juros: false,
            suspender_inadimplencia: true,
            suspender_apos_dias: 5,
            vencimento_padrao: "Todo dia 10",

            // Histórico
            modulos_extras: data.modulos || [],
            historico: admin.firestore.FieldValue.arrayUnion({
                tipo: "criacao_recorrente",
                descricao: "Assinatura recorrente criada via cartão de crédito (preapproval).",
                data_em: now,
                valor: valor,
                preapproval_id: preapprovalId,
                last_four: lastFour,
                bandeira: bandeira,
            }),

            created_at: now,
            updated_at: now,
            created_by: lojaId,
        };

        await db.collection("assinaturas_clientes").doc(assinaturaId).set(
            assinaturaData,
            { merge: true }
        );

        console.log(
            "[cartao-recorrente] Assinatura recorrente criada: loja=" + lojaId +
            ", preapproval=" + preapprovalId + ", last_four=" + lastFour
        );

        return {
            preapprovalId: preapprovalId,
            status: mpStatus,
            paymentMethodId: paymentMethodId,
            lastFour: lastFour,
            bandeira: bandeira,
            nextBillingDate: startDateIso,
            valor: valor,
        };
    },
);

// =============================================================================
// CANCELAR ASSINATURA RECORRENTE NO CARTÃO (preapproval)
// =============================================================================

/**
 * onCall v2: Cancela a cobrança recorrente no cartão (preapproval).
 *
 * NÃO cancela o plano inteiro. Apenas desativa a recorrência automática.
 * A assinatura continua ativa (status="ativo") para cobranças manuais futuras.
 *
 * Entrada: (sem parâmetros — usa request.auth.uid como storeId)
 * Saída: { ok, preapprovalId, status, message }
 */
exports.cancelarAssinaturaCartaoRecorrente = onCall(
    // TODO: voltar para enforceAppCheck:true após corrigir Secret Key reCAPTCHA.
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        // 1. Validar autenticação
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessário.");
        }
        const storeId = String(request.auth.uid || "").trim();
        if (!storeId) {
            throw new HttpsError("unauthenticated", "UID inválido.");
        }

        const db = admin.firestore();

        // 2. Buscar assinatura que tenha recorrência ativa deste lojista
        const assSnap = await db
            .collection("assinaturas_clientes")
            .where("store_id", "==", storeId)
            .where("tipo_cobranca", "==", "cartao_recorrente")
            .where("mp_preapproval_id", "!=", null)
            .limit(1)
            .get();

        if (assSnap.empty) {
            throw new HttpsError(
                "not-found",
                "Nenhuma assinatura recorrente ativa encontrada para este lojista."
            );
        }

        const assRef = assSnap.docs[0].ref;
        const assinatura = assSnap.docs[0].data() || {};
        const preapprovalId = String(assinatura.mp_preapproval_id || "").trim();
        const mpStatus = String(assinatura.mp_status || "");
        const autorizacaoAceita = assinatura.autorizacao_recorrente_aceita === true;

        if (!preapprovalId) {
            throw new HttpsError(
                "failed-precondition",
                "Assinatura não possui preapproval_id válido."
            );
        }

        // 3. IDEMPOTÊNCIA: se já foi cancelado, retornar sem erro
        if (mpStatus === "cancelled" || !autorizacaoAceita) {
            console.log(
                "[cancelar-recorrente] preapproval " + preapprovalId +
                " já estava cancelado (mpStatus=" + mpStatus + ")"
            );
            return {
                ok: true,
                preapprovalId: preapprovalId,
                status: "cancelled",
                message: "Assinatura recorrente já estava cancelada.",
            };
        }

        // 4. Obter credenciais do MP
        const gateway = await getMercadoPagoGatewayConfig();
        if (!gateway || !gateway.accessToken) {
            throw new HttpsError(
                "failed-precondition",
                "Gateway Mercado Pago não configurado."
            );
        }

        // ============================================================
        // 5. PASSO CRÍTICO: Consultar MP ANTES de qualquer alteração
        // ============================================================
        // Só limpamos o Firestore se o MP confirmar o cancelamento
        // OU se o preapproval não existir mais (404)
        // ============================================================

        const now = admin.firestore.Timestamp.now();
        let mpStatusAtual = null;        // status retornado pelo MP
        let mpPreapprovalExiste = true;  // se 404, marcamos como inexistente
        let mpErroComunicacao = false;   // timeout, 500, erro de rede

        // 5a. Primeiro: GET /preapproval/{id} para saber o status atual
        try {
            const getRes = await fetch(
                MP_API + "/preapproval/" + preapprovalId,
                {
                    method: "GET",
                    headers: {
                        Authorization: "Bearer " + gateway.accessToken,
                    },
                }
            );
            if (getRes.status === 404) {
                // Preapproval não existe mais no MP — podemos limpar com segurança
                mpPreapprovalExiste = false;
                console.log(
                    "[cancelar-recorrente] preapproval " + preapprovalId +
                    " não existe no MP (404) — limpando Firestore"
                );
            } else if (getRes.ok) {
                const getData = await getRes.json().catch(() => ({}));
                mpStatusAtual = String(getData.status || "").toLowerCase();
                console.log(
                    "[cancelar-recorrente] preapproval " + preapprovalId +
                    " status atual no MP: " + (mpStatusAtual || "desconhecido")
                );
            } else {
                // 401, 403, 500, etc. — não confiar, abortar
                mpErroComunicacao = true;
                console.warn(
                    "[cancelar-recorrente] GET preapproval retornou " +
                    getRes.status + " — não é seguro continuar"
                );
            }
        } catch (eGet) {
            // Timeout, erro de rede, DNS — não confiar
            mpErroComunicacao = true;
            console.error(
                "[cancelar-recorrente] Erro ao consultar MP:",
                eGet.message
            );
        }

        // 5b. Se já está cancelado no MP → só registrar histórico e retornar
        if (mpStatusAtual === "cancelled" || mpStatusAtual === "paused") {
            console.log(
                "[cancelar-recorrente] preapproval já está " + mpStatusAtual +
                " no MP — só registrando histórico"
            );
            await assRef.update({
                updated_at: now,
                historico: admin.firestore.FieldValue.arrayUnion({
                    tipo: "cancelamento_recorrencia",
                    descricao: "Recorrência já estava " + mpStatusAtual + " no MP.",
                    data_em: now,
                    preapproval_id_cancelado: preapprovalId,
                    mp_confirmou: true,
                    mp_status_verificado: mpStatusAtual,
                    origem: "lojista",
                }),
            });
            return {
                ok: true,
                preapprovalId: preapprovalId,
                status: mpStatusAtual,
                mpConfirmou: true,
                message: "Recorrência já estava cancelada no Mercado Pago.",
            };
        }

        // 5c. Se 404 (não existe no MP) → cancelar no Firestore
        if (!mpPreapprovalExiste) {
            await assRef.update({
                mp_preapproval_id: null,
                tipo_cobranca: "cartao_avulso",
                autorizacao_recorrente_aceita: false,
                autorizacao_recorrente_em: null,
                autorizacao_recorrente_ip: null,
                cartao_ativo: false,
                cobranca_recorrente_pausada: true,
                proxima_cobranca_recorrente: null,
                updated_at: now,
                historico: admin.firestore.FieldValue.arrayUnion({
                    tipo: "cancelamento_recorrencia",
                    descricao: "Preapproval não existe mais no MP (404).",
                    data_em: now,
                    preapproval_id_cancelado: preapprovalId,
                    mp_confirmou: true,
                    mp_status_verificado: "not_found",
                    origem: "lojista",
                }),
            });
            return {
                ok: true,
                preapprovalId: preapprovalId,
                status: "cancelled",
                mpConfirmou: true,
                message: "Recorrência removida (preapproval não existe mais).",
            };
        }

        // 5d. Se houve erro de comunicação → NÃO LIMPAR FIRESTORE
        if (mpErroComunicacao) {
            // Registra APENAS histórico de tentativa
            await assRef.update({
                updated_at: now,
                historico: admin.firestore.FieldValue.arrayUnion({
                    tipo: "cancelamento_recorrencia_falha",
                    descricao:
                        "Falha ao comunicar com Mercado Pago. " +
                        "Recorrência NÃO foi cancelada. Lojista deve tentar novamente.",
                    data_em: now,
                    preapproval_id: preapprovalId,
                    mp_confirmou: false,
                    origem: "lojista",
                }),
            });
            throw new HttpsError(
                "unavailable",
                "Não foi possível confirmar o cancelamento no Mercado Pago. " +
                "Tente novamente em alguns minutos. " +
                "Se o problema persistir, entre em contato com o suporte."
            );
        }

        // ============================================================
        // 5e. PUT /preapproval/{id} com status: cancelled
        // (Já confirmamos que o preapproval existe e está ativo)
        // ============================================================
        let mpCancelOk = false;
        let mpStatusRetornado = null;
        try {
            const res = await fetch(
                MP_API + "/preapproval/" + preapprovalId,
                {
                    method: "PUT",
                    headers: {
                        Authorization: "Bearer " + gateway.accessToken,
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({ status: "cancelled" }),
                }
            );
            if (res.status === 404) {
                // Não existe mais — ok limpar
                mpCancelOk = true;
                mpStatusRetornado = "not_found";
            } else if (res.ok) {
                const data = await res.json().catch(() => ({}));
                mpStatusRetornado = String(data.status || "").toLowerCase();
                if (mpStatusRetornado === "cancelled" || mpStatusRetornado === "paused") {
                    mpCancelOk = true;
                }
            } else {
                // 4xx/5xx — não confiar
                console.warn(
                    "[cancelar-recorrente] PUT retornou " + res.status +
                    " — Firestore NÃO será limpo"
                );
                await assRef.update({
                    updated_at: now,
                    historico: admin.firestore.FieldValue.arrayUnion({
                        tipo: "cancelamento_recorrencia_falha",
                        descricao: "PUT retornou status " + res.status,
                        data_em: now,
                        preapproval_id: preapprovalId,
                        mp_confirmou: false,
                        origem: "lojista",
                    }),
                });
                throw new HttpsError(
                    "unavailable",
                    "O Mercado Pago rejeitou o cancelamento. " +
                    "Tente novamente mais tarde."
                );
            }
        } catch (eMP) {
            console.error("[cancelar-recorrente] Erro MP PUT:", eMP.message);
            await assRef.update({
                updated_at: now,
                historico: admin.firestore.FieldValue.arrayUnion({
                    tipo: "cancelamento_recorrencia_falha",
                    descricao: "Exceção: " + eMP.message,
                    data_em: now,
                    preapproval_id: preapprovalId,
                    mp_confirmou: false,
                    origem: "lojista",
                }),
            });
            throw new HttpsError(
                "unavailable",
                "Falha de comunicação com o Mercado Pago. " +
                "Recorrência NÃO foi cancelada. Tente novamente em alguns minutos."
            );
        }

        // ============================================================
        // 6. PUT bem-sucedido E MP confirmou cancellation
        // AGORA SIM podemos limpar o Firestore
        // ============================================================

        await assRef.update({
            // Limpar campos de recorrência
            mp_preapproval_id: null,
            tipo_cobranca: "cartao_avulso",
            autorizacao_recorrente_aceita: false,
            autorizacao_recorrente_em: null,
            autorizacao_recorrente_ip: null,
            cartao_ativo: false,
            cobranca_recorrente_pausada: true,
            proxima_cobranca_recorrente: null,
            updated_at: now,
            // Registrar no histórico
            historico: admin.firestore.FieldValue.arrayUnion({
                tipo: "cancelamento_recorrencia",
                descricao: "Lojista cancelou a cobrança recorrente no cartão.",
                data_em: now,
                preapproval_id_cancelado: preapprovalId,
                mp_confirmou: true,
                mp_status_retornado: mpStatusRetornado || "cancelled",
                origem: "lojista",
            }),
        });

        console.log(
            "[cancelar-recorrente] CANCELADO: store=" + storeId +
            ", preapproval=" + preapprovalId +
            ", mp_status=" + (mpStatusRetornado || "cancelled")
        );

        return {
            ok: true,
            preapprovalId: preapprovalId,
            status: "cancelled",
            mpConfirmou: true,
            message: "Cobrança recorrente cancelada com sucesso.",
        };
    },
);
