"use strict";

/**
 * Gestão Comercial — camada unificada de pagamento PIX/cartão.
 * Valida respostas do gateway no backend; nunca monta BR Code manualmente.
 */

const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");
const {
    carregarGatewayAtivo,
    criarProvider,
    criarWebhookUrl,
} = require("./payment_gateway_provider");
const {
    MSG_CHAVE_PIX_INVALIDA,
    MSG_RESPOSTA_PIX_INVALIDA,
    cpfValidoMod11,
    cnpjValidoMod11,
    cpfPagadorValidoParaApi,
    analisarCopiaColaPixApi,
    ambienteTokenMercadoPago,
} = require("./pix_emv_validacao");

const MP_API = "https://api.mercadopago.com";

function validarRespostaPagamentoPixMp(mpBody, opts) {
    opts = opts || {};
    const tx = (mpBody && mpBody.point_of_interaction && mpBody.point_of_interaction.transaction_data) || {};
    const qrCode = String(tx.qr_code || "");
    const qrBase64 = String(tx.qr_code_base64 || "");

    if (!qrCode) {
        return { ok: false, motivo: "A API não retornou point_of_interaction.transaction_data.qr_code.", codigo: "sem_qr_code" };
    }
    if (!qrBase64) {
        return { ok: false, motivo: "A API não retornou qr_code_base64.", codigo: "sem_qr_base64" };
    }

    const status = String(mpBody.status || "").toLowerCase();
    const statusDetail = String(mpBody.status_detail || "").toLowerCase();
    if (status !== "pending") {
        const hint = status === "cancelled" || status === "expired"
            ? " A cobrança foi cancelada/expirada pelo gateway ao criar — verifique token e configuração PIX da conta."
            : "";
        return {
            ok: false,
            motivo: "Status inesperado da cobrança: " + status + hint,
            codigo: "status_invalido",
        };
    }
    if (statusDetail && statusDetail !== "pending_waiting_transfer") {
        console.warn("[gc-pagamento] status_detail PIX:", statusDetail);
    }

    const br = analisarCopiaColaPixApi(qrCode, { exigirPixDinamico: true });
    if (!br.ok) {
        return Object.assign({}, br, { qrCode, qrBase64 });
    }

    const tokenAmb = ambienteTokenMercadoPago(opts.accessToken);
    const liveMode = mpBody.live_mode === true;
    if (opts.ambienteEsperado === "sandbox" && liveMode) {
        return { ok: false, motivo: "Token de sandbox gerou cobrança em live_mode. Verifique o ambiente.", codigo: "live_mode_sandbox" };
    }
    if (opts.ambienteEsperado === "producao" && !liveMode && tokenAmb === "producao") {
        return { ok: false, motivo: "Token de produção gerou cobrança fora do live_mode.", codigo: "live_mode_producao" };
    }

    if (opts.collectorIdEsperado != null && String(mpBody.collector_id) !== String(opts.collectorIdEsperado)) {
        return {
            ok: false,
            motivo: "collector_id da cobrança não corresponde à conta configurada.",
            codigo: "collector_divergente",
        };
    }

    return {
        ok: true,
        qrCode,
        qrBase64,
        paymentId: mpBody.id,
        collectorId: mpBody.collector_id,
        liveMode,
        status,
        statusDetail,
        br,
        tokenAmbiente: tokenAmb,
    };
}

// =============================================================================
// Firestore — status da integração
// =============================================================================

async function marcarIntegracaoPagamentoValida(db, lojaId, gatewayTipo, dados) {
    dados = dados || {};
    await db.collection("gestao_comercial_configuracoes").doc(lojaId).set({
        pagamentos: {
            [gatewayTipo]: Object.assign({
                pix_valido: true,
                pix_erro_validacao: admin.firestore.FieldValue.delete(),
                pix_validado_em: admin.firestore.FieldValue.serverTimestamp(),
                conexao_valida: true,
                conexao_mensagem: dados.mensagem || "Conexão validada com sucesso.",
                conexao_validada_em: admin.firestore.FieldValue.serverTimestamp(),
            }, dados.collectorId != null ? { mp_collector_id: String(dados.collectorId) } : {}),
        },
    }, { merge: true });
}

async function marcarIntegracaoPagamentoInvalida(db, lojaId, gatewayTipo, motivo, codigo) {
    await db.collection("gestao_comercial_configuracoes").doc(lojaId).set({
        pagamentos: {
            [gatewayTipo]: {
                pix_valido: false,
                pix_erro_validacao: String(motivo || MSG_CHAVE_PIX_INVALIDA).substring(0, 900),
                pix_erro_codigo: codigo || "validacao_falhou",
                pix_validado_em: admin.firestore.FieldValue.serverTimestamp(),
                conexao_valida: false,
                conexao_mensagem: String(motivo || "").substring(0, 900),
                conexao_validada_em: admin.firestore.FieldValue.serverTimestamp(),
            },
        },
    }, { merge: true });
}

// =============================================================================
// Mercado Pago — helpers HTTP
// =============================================================================

async function obterUsuarioMercadoPago(accessToken) {
    const res = await fetch(MP_API + "/users/me", {
        method: "GET",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
        },
    });
    const body = await res.json().catch(function () { return {}; });
    if (!res.ok) {
        const err = new Error(body.message || "MP users/me " + res.status);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

async function cancelarPagamentoMpPendente(accessToken, paymentId) {
    if (!paymentId) return;
    try {
        await fetch(MP_API + "/v1/payments/" + encodeURIComponent(String(paymentId)), {
            method: "PUT",
            headers: {
                Authorization: "Bearer " + accessToken,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ status: "cancelled" }),
        });
    } catch (e) {
        console.warn("[gc-pagamento] Falha ao cancelar PIX teste " + paymentId + ":", e.message || e);
    }
}

/**
 * Teste completo Mercado Pago: token, ambiente, PIX ativo, BR Code válido.
 */
async function validarGatewayMercadoPagoCompleto(accessToken, ambienteConfigurado, lojaId) {
    const db = admin.firestore();
    const tokenAmb = ambienteTokenMercadoPago(accessToken);
    const ambiente = String(ambienteConfigurado || "producao").toLowerCase();

    if (tokenAmb === "desconhecido") {
        return { valido: false, mensagem: "Formato de Access Token não reconhecido (esperado APP_USR- ou TEST-)." };
    }
    if (ambiente === "sandbox" && tokenAmb !== "sandbox") {
        return { valido: false, mensagem: "Ambiente configurado como sandbox, mas o token parece ser de produção (APP_USR-)." };
    }
    if (ambiente === "producao" && tokenAmb === "sandbox") {
        return { valido: false, mensagem: "Ambiente configurado como produção, mas o token é de teste (TEST-)." };
    }

    let usuario;
    try {
        usuario = await obterUsuarioMercadoPago(accessToken);
    } catch (e) {
        if (e.status === 401) {
            return { valido: false, mensagem: "Access Token inválido ou revogado." };
        }
        if (e.status === 403) {
            return { valido: false, mensagem: "Access Token sem permissão para consultar a conta." };
        }
        return { valido: false, mensagem: "Erro ao validar token: " + (e.message || e) };
    }

    const collectorId = usuario.id;
    const idempotencyKey = "gc_test_pix_" + Date.now();
    const externalRef = "gc_test_" + idempotencyKey;

    const payload = {
        transaction_amount: 0.01,
        description: "DiPertin GC - teste conexao PIX",
        payment_method_id: "pix",
        payer: {
            email: "teste.conexao@pg.dipertin.com.br",
        },
        external_reference: externalRef,
    };

    let mpBody;
    try {
        const res = await fetch(MP_API + "/v1/payments", {
            method: "POST",
            headers: {
                Authorization: "Bearer " + accessToken,
                "Content-Type": "application/json",
                "X-Idempotency-Key": idempotencyKey,
            },
            body: JSON.stringify(payload),
        });
        mpBody = await res.json().catch(function () { return {}; });
        if (!res.ok) {
            const msg = mpBody.message || mpBody.error || "HTTP " + res.status;
            if (String(msg).toLowerCase().includes("pix")) {
                return { valido: false, mensagem: "Conta sem PIX habilitado no Mercado Pago: " + msg };
            }
            return { valido: false, mensagem: "Não foi possível criar cobrança PIX de teste: " + msg };
        }
    } catch (e) {
        return { valido: false, mensagem: "Falha de rede ao testar PIX: " + (e.message || e) };
    }

    const validacao = validarRespostaPagamentoPixMp(mpBody, {
        accessToken,
        ambienteEsperado: ambiente === "sandbox" ? "sandbox" : "producao",
        collectorIdEsperado: collectorId,
    });

    await cancelarPagamentoMpPendente(accessToken, mpBody.id);

    if (!validacao.ok) {
        if (lojaId) {
            await marcarIntegracaoPagamentoInvalida(db, lojaId, "mercado_pago", validacao.motivo, validacao.codigo);
        }
        return {
            valido: false,
            mensagem: validacao.motivo,
            codigo: validacao.codigo,
            collector_id: collectorId,
            live_mode: mpBody.live_mode,
            chave_tipo: validacao.chaveTipo,
        };
    }

    if (lojaId) {
        await marcarIntegracaoPagamentoValida(db, lojaId, "mercado_pago", {
            mensagem: "Conexão validada. PIX ativo e QR Code aceito pela validação DiPertin.",
            collectorId: collectorId,
        });
    }

    return {
        valido: true,
        mensagem: "Access Token válido. PIX ativo. Ambiente "
            + (validacao.liveMode ? "produção (live)" : "sandbox")
            + ". Chave no QR: "
            + (validacao.br.chaveTipo || "dinâmica")
            + (validacao.br.chaveValor ? " (" + validacao.br.chaveValor + ")" : "")
            + ".",
        collector_id: collectorId,
        live_mode: validacao.liveMode,
        chave_tipo: validacao.br.chaveTipo,
        chave_valor: validacao.br.chaveValor,
        payment_id_teste: mpBody.id,
    };
}

// =============================================================================
// Cobrança PIX unificada (qualquer gateway configurado pela loja)
// =============================================================================

async function carregarProviderLoja(db, lojaId) {
    const gatewayInfo = await carregarGatewayAtivo(db, lojaId);
    if (!gatewayInfo) {
        throw new HttpsError(
            "failed-precondition",
            "Configure um gateway de pagamento em Configurações Comercial > Banco e Pagamentos.",
        );
    }
    const provider = criarProvider(gatewayInfo.tipo, gatewayInfo.config);
    if (!provider || typeof provider.createPixCharge !== "function") {
        throw new HttpsError(
            "failed-precondition",
            "Gateway \"" + gatewayInfo.tipo + "\" não suporta PIX ou está mal configurado.",
        );
    }
    return { gatewayInfo, provider };
}

/**
 * Cria cobrança PIX via gateway da loja + valida resposta antes de retornar ao frontend.
 */
async function criarCobrancaPixGestaoComercial(db, params) {
    const {
        lojaId,
        valor,
        descricao,
        externalReference,
        idempotencyKey,
        clienteNome,
        clienteCpf,
        clienteEmail,
        notificationUrl,
    } = params;

    const { gatewayInfo, provider } = await carregarProviderLoja(db, lojaId);
    const cpfPagador = cpfPagadorValidoParaApi(clienteCpf);
    const webhookUrl = notificationUrl || criarWebhookUrl(gatewayInfo.tipo);

    let chargeResult;
    try {
        chargeResult = await provider.createPixCharge({
            valor,
            clienteNome,
            clienteCpf: cpfPagador || undefined,
            clienteEmail,
            descricao,
            externalReference,
            notificationUrl: webhookUrl,
            idempotencyKey,
        });
    } catch (e) {
        console.error("[gc-pagamento] Erro createPixCharge:", gatewayInfo.tipo, e.message || e);
        throw new HttpsError("internal", "Erro ao criar cobrança PIX: " + (e.message || e));
    }

    const copiaCola = String(chargeResult.copiaCola || "");
    const qrBase64 = String(chargeResult.qrCode || "");

    if (!copiaCola) {
        throw new HttpsError("internal", "O gateway não retornou o código PIX (copia e cola).");
    }

    let validacao;
    if (gatewayInfo.tipo === "mercado_pago" && chargeResult.raw) {
        const accessToken = gatewayInfo.config.token || gatewayInfo.config.accessToken || "";
        validacao = validarRespostaPagamentoPixMp(chargeResult.raw, {
            accessToken,
            ambienteEsperado: gatewayInfo.config.ambiente || ambienteTokenMercadoPago(accessToken),
            collectorIdEsperado: null,
        });
    } else {
        const br = analisarCopiaColaPixApi(copiaCola);
        validacao = {
            ok: br.ok,
            motivo: br.motivo,
            codigo: br.codigo,
            qrCode: copiaCola,
            qrBase64: qrBase64,
            br,
        };
        if (!qrBase64 && br.ok) {
            validacao.ok = false;
            validacao.motivo = "O gateway não retornou imagem QR (qr_code_base64).";
            validacao.codigo = "sem_qr_base64";
        }
    }

    if (!validacao.ok) {
        console.error("[gc-pagamento] PIX inválido:", validacao.codigo, validacao.motivo);
        await marcarIntegracaoPagamentoInvalida(
            db,
            lojaId,
            gatewayInfo.tipo,
            validacao.motivo,
            validacao.codigo,
        );
        if (gatewayInfo.tipo === "mercado_pago" && chargeResult.paymentId) {
            const token = gatewayInfo.config.token || gatewayInfo.config.accessToken;
            await cancelarPagamentoMpPendente(token, chargeResult.paymentId);
        }
        throw new HttpsError("failed-precondition", validacao.motivo || MSG_CHAVE_PIX_INVALIDA);
    }

    await marcarIntegracaoPagamentoValida(db, lojaId, gatewayInfo.tipo, {
        mensagem: "Última cobrança PIX validada com sucesso.",
        collectorId: validacao.collectorId,
    });

    return {
        gatewayInfo,
        chargeResult,
        validacao,
        pixCopiaECola: validacao.qrCode || copiaCola,
        qrCodeBase64: validacao.qrBase64 || qrBase64,
        paymentId: String(chargeResult.paymentId || chargeResult.id || ""),
        status: chargeResult.status || "pending",
    };
}

/**
 * Cartão via gateway da loja (token MP / dados Asaas).
 */
async function criarCobrancaCartaoGestaoComercial(db, params) {
    const {
        lojaId,
        valor,
        descricao,
        externalReference,
        clienteNome,
        clienteCpf,
        clienteEmail,
        cardToken,
        cardHolderName,
        cardNumber,
        cardExpiryMonth,
        cardExpiryYear,
        cardCvv,
        paymentMethodId,
        installments,
    } = params;

    const { gatewayInfo, provider } = await carregarProviderLoja(db, lojaId);
    if (typeof provider.createCardPayment !== "function") {
        throw new HttpsError("failed-precondition", "Gateway não suporta cartão.");
    }

    const cpfPagador = cpfPagadorValidoParaApi(clienteCpf);

    try {
        const cardResult = await provider.createCardPayment({
            valor,
            clienteNome,
            clienteCpf: cpfPagador || undefined,
            clienteEmail,
            cardToken,
            cardHolderName,
            cardNumber,
            cardExpiryMonth,
            cardExpiryYear,
            cardCvv,
            descricao,
            externalReference,
            paymentMethodId,
            installments: installments || 1,
        });
        return { gatewayInfo, cardResult };
    } catch (e) {
        console.error("[gc-pagamento] Erro createCardPayment:", e.message || e);
        throw new HttpsError("internal", "Erro ao processar cartão: " + (e.message || e));
    }
}

module.exports = {
    MSG_CHAVE_PIX_INVALIDA,
    cpfValidoMod11,
    cnpjValidoMod11,
    cpfPagadorValidoParaApi,
    analisarCopiaColaPixApi,
    validarRespostaPagamentoPixMp,
    validarGatewayMercadoPagoCompleto,
    criarCobrancaPixGestaoComercial,
    criarCobrancaCartaoGestaoComercial,
    marcarIntegracaoPagamentoInvalida,
    marcarIntegracaoPagamentoValida,
    cancelarPagamentoMpPendente,
    ambienteTokenMercadoPago,
    criarWebhookUrl,
};
