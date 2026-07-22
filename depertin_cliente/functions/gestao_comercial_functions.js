"use strict";

/**
 * Módulo Gestão Comercial — Cloud Functions Gen2 (região South America).
 *
 * Todas as funções usam:
 *   region: "southamerica-east1"
 *   cpu: 1
 *   memory: "512MiB"
 *   maxInstances: 10
 *   timeoutSeconds: 60
 *
 * Acessam o mesmo Firestore do projeto (sem isolar banco).
 * NÃO alteram funções legadas do marketplace/delivery em us-central1.
 */

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const https = require("https");
const http = require("http");
const QRCodeLib = require("qrcode");
const {
    baixarEstoqueGestaoComercialVenda,
    pedidoExisteParaVendaGestaoComercial,
} = require("./estoque_pedido");
const { carregarGatewayAtivo, criarProvider } = require("./payment_gateway_provider");
const {
    criarCobrancaPixGestaoComercial,
    criarCobrancaCartaoGestaoComercial,
    validarGatewayMercadoPagoCompleto,
    MSG_CHAVE_PIX_INVALIDA,
} = require("./gestao_comercial_pagamento");
const { aplicarBaixaCrediarioInterno } = require("./pagamento_crediario");

const MP_API = "https://api.mercadopago.com";

// =============================================================================
// CONFIG PADRÃO DAS FUNÇÕES
// =============================================================================

const CONFIG_PADRAO = {
    region: "southamerica-east1",
    cpu: 1,
    memory: "512MiB",
    maxInstances: 10,
    timeoutSeconds: 60,
    // Painel web roda sem App Check (reCAPTCHA desativado).
    // Sem enforceAppCheck:false, app:MISSING gera UNAUTHENTICATED / "Unauthenticated".
    enforceAppCheck: false,
    // Garante que o token App Check ausente não seja consumido/rejeitado.
    consumeAppCheckToken: false,
};

// =============================================================================
// HELPER DE VALIDAÇÃO COMPARTILHADO
// =============================================================================

/**
 * Valida que o caller é um lojista apto a usar a Gestão Comercial.
 * - Proprietário (sem lojista_owner_uid): permitido
 * - Colaborador: exige painel_colaborador_nivel >= 2
 * - Qualquer outro perfil (cliente, entregador, etc.): negado
 * - Loja bloqueada: negado
 *
 * Lança HttpsError com mensagem descritiva se a validação falhar.
 * Retorna { callerUid, lojaId, ownerUid } em caso de sucesso.
 */
async function assertGestaoComercialAccess(db, request) {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login necessario.");
    }
    const callerUid = request.auth.uid;
    const callerSnap = await db.collection("users").doc(callerUid).get();
    if (!callerSnap.exists) {
        throw new HttpsError("failed-precondition", "Perfil nao encontrado.");
    }
    const caller = callerSnap.data();
    const role = String(caller.role || caller.tipoUsuario || "").toLowerCase();
    if (role !== "lojista") {
        throw new HttpsError("permission-denied", "Apenas lojistas podem acessar a Gestao Comercial.");
    }
    // Se for colaborador, validar nivel >= 2
    const ownerUid = String(caller.lojista_owner_uid || "").trim();
    if (ownerUid) {
        const nivel = Number(caller.painel_colaborador_nivel || 0);
        if (nivel < 2) {
            throw new HttpsError(
                "permission-denied",
                "Voce nao tem permissao para acessar a Gestao Comercial."
            );
        }
        // Verificar se a loja (dono) esta bloqueada
        const ownerSnap = await db.collection("users").doc(ownerUid).get();
        if (ownerSnap.exists) {
            const owner = ownerSnap.data();
            const bloqueado = owner.block_lojista
                || owner.conta_bloqueada
                || owner.status_loja === "bloqueada";
            if (bloqueado) {
                throw new HttpsError("permission-denied", "A loja esta bloqueada.");
            }
        }
        return { callerUid, lojaId: ownerUid, ownerUid };
    }
    // Proprietario: verificar bloqueio da propria loja
    const block = caller.block_lojista
        || caller.conta_bloqueada
        || caller.status_loja === "bloqueada";
    if (block) {
        throw new HttpsError("permission-denied", "Sua loja esta bloqueada.");
    }
    return { callerUid, lojaId: callerUid, ownerUid: "" };
}

// Para funções que exigem mais tempo ou recursos
const CONFIG_PESADO = {
    region: "southamerica-east1",
    cpu: 1,
    memory: "1GiB",
    maxInstances: 5,
    timeoutSeconds: 120,
    enforceAppCheck: false,
};

// =============================================================================
// HELPERS COMPARTILHADOS
// =============================================================================

const WEBHOOK_BASE_PLANOS = "https://planos.dipertin.com.br/webhooks";

function _fmtDataBR(d) {
    if (!d || isNaN(d.getTime())) return "—";
    const dia = String(d.getDate()).padStart(2, "0");
    const mes = String(d.getMonth() + 1).padStart(2, "0");
    const ano = d.getFullYear();
    return dia + "/" + mes + "/" + ano;
}
function _fmtHoraBR(d) {
    if (!d || isNaN(d.getTime())) return "—";
    const h = String(d.getHours()).padStart(2, "0");
    const m = String(d.getMinutes()).padStart(2, "0");
    return h + ":" + m;
}

function _formatarMoedaBR(valor) {
    const n = Number(valor);
    if (!Number.isFinite(n)) return "R$ 0,00";
    return "R$ " + n.toFixed(2).replace(".", ",");
}

function _rotuloFormaPagamento(forma) {
    const f = String(forma || "").trim().toLowerCase();
    if (f === "pix") return "PIX";
    if (f === "cartao" || f === "cartão" || f === "credit_card") return "Cartão de crédito";
    if (f === "debito" || f === "debit_card") return "Cartão de débito";
    if (f === "boleto") return "Boleto";
    if (f === "dinheiro") return "Dinheiro";
    return f ? f.charAt(0).toUpperCase() + f.slice(1) : "—";
}

function _resumoParcelasToken(parcelasDetalhe) {
    if (!parcelasDetalhe || !parcelasDetalhe.length) return "—";
    if (parcelasDetalhe.length === 1) {
        const p = parcelasDetalhe[0];
        const cod = String(p.codigo_venda || "").trim();
        return "Parcela " + (p.numero_parcela || 1) + "/" + (p.total_parcelas || 1)
            + (cod ? " · " + cod : "");
    }
    return parcelasDetalhe.length + " parcelas quitadas";
}

function _montarLinhasParcelasHtml(parcelasDetalhe) {
    if (!parcelasDetalhe || !parcelasDetalhe.length) {
        return '<tr><td colspan="2" style="padding:12px 0;color:#64748B;font-size:14px;">—</td></tr>';
    }
    return parcelasDetalhe.map(function (p) {
        const cod = String(p.codigo_venda || "").trim();
        const titulo = "Parcela " + (p.numero_parcela || 1) + "/" + (p.total_parcelas || 1)
            + (cod ? " · " + cod : "");
        return "<tr>"
            + '<td style="padding:14px 0;border-bottom:1px solid #E8E6EE;font-family:Arial,sans-serif;font-size:14px;color:#1A1A2E;">' + titulo + "</td>"
            + '<td style="padding:14px 0;border-bottom:1px solid #E8E6EE;font-family:Arial,sans-serif;font-size:14px;color:#1A1A2E;text-align:right;font-weight:600;">' + _formatarMoedaBR(p.valor) + "</td>"
            + "</tr>";
    }).join("");
}

function _montarHtmlComprovantePagamentoTokenPremium(opts) {
    const corPrincipal = opts.corPrincipal || "#6A1B9A";
    const corSecundaria = opts.corSecundaria || "#FF8F00";
    const logoUrl = opts.logoUrl || "";
    const logoHtml = logoUrl
        ? '<img src="' + logoUrl + '" alt="" style="max-height:44px;margin-bottom:12px;" />'
        : "";

    const linhasDetalhe = [
        { rotulo: "Cliente", valor: opts.clienteNome || "—" },
        { rotulo: "Parcela(s)", valor: opts.parcelaResumo || "—" },
        { rotulo: "Valor pago", valor: opts.valorFmt || "—", destaque: true },
        { rotulo: "Forma de pagamento", valor: opts.formaRotulo || "—" },
        { rotulo: "Recebido por", valor: opts.lojaNome || "—" },
        { rotulo: "Data e hora", valor: opts.dataHora || "—" },
    ];

    const detalheRows = linhasDetalhe.map(function (item) {
        const valStyle = item.destaque
            ? "font-size:22px;font-weight:700;color:" + corPrincipal + ";"
            : "font-size:15px;font-weight:600;color:#1A1A2E;";
        return "<tr>"
            + '<td style="padding:12px 0;width:42%;font-family:Arial,sans-serif;font-size:13px;color:#64748B;vertical-align:top;">' + item.rotulo + "</td>"
            + '<td style="padding:12px 0;font-family:Arial,sans-serif;' + valStyle + '">' + item.valor + "</td>"
            + "</tr>";
    }).join("");

    const detalhamentoParcelas = (opts.parcelasDetalhe && opts.parcelasDetalhe.length > 1)
        ? '<p style="font-family:Arial,sans-serif;color:#1A1A2E;font-size:14px;font-weight:600;margin:28px 0 12px;">Detalhamento das parcelas</p>'
            + '<table width="100%" cellpadding="0" cellspacing="0" role="presentation">' + _montarLinhasParcelasHtml(opts.parcelasDetalhe) + "</table>"
        : "";

    return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        + "<title>Comprovante de pagamento</title></head>"
        + '<body style="margin:0;padding:0;background:#F5F4F8;">'
        + '<table width="100%" cellpadding="0" cellspacing="0" role="presentation"><tr><td align="center" style="padding:32px 16px;">'
        + '<table width="100%" style="max-width:600px;background:#fff;border-radius:20px;overflow:hidden;box-shadow:0 8px 32px rgba(106,27,154,0.12);" role="presentation">'
        + '<tr><td style="background:linear-gradient(135deg,#16A34A 0%,#22C55E 100%);padding:36px 28px;text-align:center;">'
        + '<div style="width:56px;height:56px;margin:0 auto 16px;background:rgba(255,255,255,0.2);border-radius:14px;line-height:56px;font-size:28px;color:#fff;">✓</div>'
        + '<h1 style="font-family:\'Segoe UI\',Arial,sans-serif;color:#fff;font-size:24px;margin:0 0 8px;font-weight:700;">Pagamento confirmado</h1>'
        + '<p style="font-family:Arial,sans-serif;color:rgba(255,255,255,0.92);font-size:15px;margin:0;line-height:1.5;">Seu pagamento foi recebido com sucesso.</p>'
        + "</td></tr>"
        + '<tr><td style="background:linear-gradient(135deg,' + corPrincipal + " 0%," + corPrincipal + 'dd 100%);padding:20px 28px;text-align:center;">'
        + logoHtml
        + '<p style="font-family:Arial,sans-serif;color:#fff;font-size:16px;margin:0;font-weight:600;">' + (opts.lojaNome || "Loja") + "</p>"
        + "</td></tr>"
        + '<tr><td style="padding:28px 28px 8px;">'
        + '<p style="font-family:Arial,sans-serif;color:#1A1A2E;font-size:16px;margin:0 0 20px;line-height:1.6;">Olá <strong>' + (opts.clienteNome || "Cliente") + "</strong>,</p>"
        + '<p style="font-family:Arial,sans-serif;color:#64748B;font-size:14px;margin:0 0 24px;line-height:1.6;">Este é o comprovante do seu pagamento. Guarde este e-mail para sua referência.</p>'
        + '<table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background:#FAFAFB;border-radius:14px;padding:4px 20px;">'
        + detalheRows
        + "</table>"
        + detalhamentoParcelas
        + '<div style="margin:28px 0 8px;padding:16px 18px;background:linear-gradient(135deg,rgba(106,27,154,0.08),rgba(255,143,0,0.08));border-radius:12px;border-left:4px solid ' + corSecundaria + ';">'
        + '<p style="font-family:Arial,sans-serif;color:#64748B;font-size:12px;margin:0;line-height:1.5;">Referência da transação: <span style="color:#1A1A2E;font-weight:600;">' + (opts.transactionId || "—") + "</span></p>"
        + "</div>"
        + "</td></tr>"
        + '<tr><td style="padding:8px 28px 28px;font-family:Arial,sans-serif;color:#64748B;font-size:12px;line-height:1.6;text-align:center;">'
        + "Pagamento processado com segurança via DiPertin.<br>"
        + 'Em caso de dúvidas, entre em contato com <strong style="color:#1A1A2E;">' + (opts.lojaNome || "a loja") + "</strong>."
        + "</td></tr>"
        + "</table></td></tr></table></body></html>";
}

/** Envia comprovante premium por e-mail após confirmação do link /pagar (best-effort). */
async function _enviarComprovanteEmailPagamentoToken(db, params) {
    const emailHelpers = _emailHelpers;
    if (!emailHelpers || !emailHelpers.enviarEmailLoja) {
        console.warn("[gc-token-email] Servico de e-mail indisponivel.");
        return { ok: false, motivo: "servico_indisponivel" };
    }

    const lojaId = params.lojaId;
    const clienteId = params.clienteId;
    const transactionId = String(params.transactionId || "").trim();

    if (params.tokenRef && transactionId) {
        try {
            const tokenSnap = await params.tokenRef.get();
            const tokenData = tokenSnap.exists ? (tokenSnap.data() || {}) : {};
            if (tokenData.comprovante_email_transaction_id === transactionId) {
                return { ok: true, motivo: "ja_enviado" };
            }
        } catch (_) {}
    }

    let clienteEmail = String(params.clienteEmail || "").trim();
    let clienteNome = String(params.clienteNome || "").trim();
    if (!clienteEmail || !clienteNome) {
        try {
            const cliSnap = await db.collection("users").doc(lojaId)
                .collection("clientes_comercial").doc(clienteId).get();
            if (cliSnap.exists) {
                const cli = cliSnap.data() || {};
                if (!clienteEmail) clienteEmail = String(cli.email || "").trim();
                if (!clienteNome) {
                    clienteNome = String(cli.nome || cli.razao_social || cli.cliente_nome || "").trim();
                }
            }
        } catch (_) {}
    }

    if (!clienteEmail) {
        console.warn("[gc-token-email] Cliente sem e-mail cadastrado:", clienteId);
        return { ok: false, motivo: "sem_email" };
    }

    let lojaNome = String(params.lojaNome || "").trim();
    let lojaLogo = String(params.lojaLogo || "").trim();
    if (!lojaNome) {
        try {
            const lojaSnap = await db.collection("users").doc(lojaId).get();
            if (lojaSnap.exists) {
                const loja = lojaSnap.data() || {};
                lojaNome = String(loja.nome_loja || loja.nome_fantasia || loja.nome || "Loja").trim();
                if (!lojaLogo) {
                    lojaLogo = String(loja.foto || loja.foto_perfil || loja.foto_logo || "").trim();
                }
            }
        } catch (_) {}
    }

    const agora = params.agora instanceof Date ? params.agora : new Date();
    const parcelasDetalhe = params.parcelasDetalhe || [];
    const valorFmt = _formatarMoedaBR(params.valorTotalPago);
    const formaRotulo = _rotuloFormaPagamento(params.formaPagamento);
    const parcelaResumo = _resumoParcelasToken(parcelasDetalhe);
    const dataHora = _fmtDataBR(agora) + " às " + _fmtHoraBR(agora);
    const codigosVenda = parcelasDetalhe.map(function (p) { return String(p.codigo_venda || "").trim(); }).filter(Boolean).join(", ");

    const variaveis = {
        cliente: clienteNome || "Cliente",
        loja: lojaNome || "Loja",
        valor: valorFmt,
        valor_total: valorFmt,
        forma_pagamento: formaRotulo,
        parcela: parcelaResumo,
        parcelas: parcelaResumo,
        codigo_venda: codigosVenda || "—",
        data: _fmtDataBR(agora),
        hora: _fmtHoraBR(agora),
        data_hora: dataHora,
        transaction_id: transactionId || "—",
        vencimento: "—",
        link: "https://www.dipertin.com.br",
        link_pagamento: "https://www.dipertin.com.br",
    };

    const slug = "pagamento_recebido";
    let html = "";
    let textContent = "";
    let assuntoTpl = "Pagamento confirmado — {loja}";
    let identidade = { corPrincipal: "#6A1B9A", corSecundaria: "#FF8F00", logoUrl: lojaLogo, nomeLoja: lojaNome };

    try {
        const tplSnap = await db.collection("gestao_comercial_email_templates")
            .doc(lojaId).collection("templates").doc(slug).get();
        const tplData = tplSnap.exists ? (tplSnap.data() || {}) : {};
        const blocks = tplData.blocks;
        identidade = Object.assign({}, identidade, tplData.identidadeVisual || {});
        assuntoTpl = String(tplData.assunto || assuntoTpl).trim();

        if (Array.isArray(blocks) && blocks.length && emailHelpers.blocksToHtml) {
            html = emailHelpers.blocksToHtml(blocks, variaveis, identidade, assuntoTpl);
            textContent = emailHelpers.textoLegadoFromBlocks ? emailHelpers.textoLegadoFromBlocks(blocks) : "";
            if (textContent && emailHelpers.substituirVariaveis) {
                textContent = emailHelpers.substituirVariaveis(textContent, variaveis);
            }
        }
    } catch (tplErr) {
        console.warn("[gc-token-email] Erro ao carregar template:", tplErr.message || tplErr);
    }

    if (!html) {
        html = _montarHtmlComprovantePagamentoTokenPremium({
            clienteNome: variaveis.cliente,
            lojaNome: variaveis.loja,
            logoUrl: identidade.logoUrl || lojaLogo,
            corPrincipal: identidade.corPrincipal || "#6A1B9A",
            corSecundaria: identidade.corSecundaria || "#FF8F00",
            valorFmt: valorFmt,
            formaRotulo: formaRotulo,
            parcelaResumo: parcelaResumo,
            dataHora: dataHora,
            transactionId: transactionId,
            parcelasDetalhe: parcelasDetalhe,
        });
        textContent = "Olá " + variaveis.cliente + ",\n\n"
            + "Seu pagamento foi confirmado.\n\n"
            + "Parcela(s): " + parcelaResumo + "\n"
            + "Valor: " + valorFmt + "\n"
            + "Forma de pagamento: " + formaRotulo + "\n"
            + "Loja: " + variaveis.loja + "\n"
            + "Data e hora: " + dataHora + "\n"
            + (transactionId ? ("Referência: " + transactionId + "\n") : "")
            + "\nObrigado pela preferência!\n" + variaveis.loja;
    }

    const assunto = emailHelpers.substituirVariaveis
        ? emailHelpers.substituirVariaveis(assuntoTpl, variaveis)
        : assuntoTpl;

    try {
        const r = await emailHelpers.enviarEmailLoja(lojaId, clienteEmail, assunto, html, textContent, slug);
        if (params.tokenRef && transactionId) {
            try {
                await params.tokenRef.update({
                    comprovante_email_transaction_id: transactionId,
                    comprovante_email_enviado_em: admin.firestore.FieldValue.serverTimestamp(),
                    comprovante_email_destino: clienteEmail,
                });
            } catch (_) {}
        }
        console.log("[gc-token-email] Comprovante enviado para " + clienteEmail + " (loja " + lojaId + ")");
        return { ok: true, messageId: r.messageId, destino: clienteEmail };
    } catch (err) {
        const errMsg = emailHelpers.mapSmtpError ? emailHelpers.mapSmtpError(err) : (err.message || String(err));
        console.error("[gc-token-email] Falha ao enviar:", errMsg);
        return { ok: false, motivo: errMsg };
    }
}

function resolverChaveGatewayPadrao(pagamentos) {
    const gp = pagamentos && pagamentos.gatewayPadrao;
    if (!gp || typeof gp !== "object") return "mercado_pago";
    const tipo = gp.tipo && String(gp.tipo).trim();
    if (tipo && tipo !== "PIX") return tipo;
    const provedor = gp.provedor && String(gp.provedor).trim();
    if (provedor) return provedor;
    return "mercado_pago";
}

function lerCredenciaisIntegracao(integData) {
    if (!integData || typeof integData !== "object") return null;
    if (integData.ativo === false) return null;
    const accessToken = integData.token && String(integData.token).trim()
        ? String(integData.token).trim()
        : null;
    if (!accessToken) return null;
    const publicKey = integData.clientId && String(integData.clientId).trim()
        ? String(integData.clientId).trim()
        : null;
    return {
        accessToken: accessToken,
        publicKey: publicKey,
        ambiente: integData.ambiente || "producao",
        apiUrl: integData.apiUrl && String(integData.apiUrl).trim()
            ? String(integData.apiUrl).trim()
            : null,
        webhookUrl: integData.webhookUrl && String(integData.webhookUrl).trim()
            ? String(integData.webhookUrl).trim()
            : null,
    };
}

/**
 * Resolve credenciais do gateway de pagamento da loja (Gestão Comercial).
 * Usa gatewayPadrao em gestao_comercial_configuracoes/{lojaId}.pagamentos.
 * @param {FirebaseFirestore} db
 * @param {string} lojaId
 * @param {string|null} provedorPreferido — força um provedor (ex.: mercado_pago)
 * @returns {Promise<{provedor:string, accessToken:string, publicKey:string|null, ambiente:string, apiUrl:string|null, webhookUrl:string|null}|null>}
 */
async function getLojaGatewayCreds(db, lojaId, provedorPreferido) {
    const configDoc = await db
        .collection("gestao_comercial_configuracoes")
        .doc(lojaId)
        .get();

    if (configDoc.exists) {
        const pagamentos = (configDoc.data() || {}).pagamentos || {};
        const chave = provedorPreferido || resolverChaveGatewayPadrao(pagamentos);
        const creds = lerCredenciaisIntegracao(pagamentos[chave]);
        if (creds) {
            return Object.assign({ provedor: chave }, creds);
        }
    }

    // Localização legada: gestao_comercial_integracoes_pagamento/{lojaId}/gateways/mercado_pago
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
                return {
                    provedor: "mercado_pago",
                    accessToken: accessToken,
                    publicKey: publicKey,
                    ambiente: d.ambiente || "producao",
                    apiUrl: null,
                    webhookUrl: WEBHOOK_BASE_PLANOS + "/mercadopago",
                };
            }
        }
    }

    return null;
}

/**
 * Busca credenciais Mercado Pago do lojista (gateway padrão MP ou integração mercado_pago).
 * @param {FirebaseFirestore} db
 * @param {string} lojaId
 * @returns {Promise<{accessToken:string, publicKey:string|null, ambiente:string}|null>}
 */
async function getLojaMercadoPagoCreds(db, lojaId) {
    const gateway = await getLojaGatewayCreds(db, lojaId);
    if (gateway && gateway.provedor === "mercado_pago") {
        return {
            accessToken: gateway.accessToken,
            publicKey: gateway.publicKey,
            ambiente: gateway.ambiente,
        };
    }

    // Gateway padrão não é MP — tenta integração mercado_pago mesmo assim
    const configDoc = await db
        .collection("gestao_comercial_configuracoes")
        .doc(lojaId)
        .get();

    if (configDoc.exists) {
        const pagamentos = (configDoc.data() || {}).pagamentos || {};
        const mpCreds = lerCredenciaisIntegracao(pagamentos.mercado_pago);
        if (mpCreds) {
            return {
                accessToken: mpCreds.accessToken,
                publicKey: mpCreds.publicKey,
                ambiente: mpCreds.ambiente,
            };
        }
    }

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
                return { accessToken, publicKey, ambiente: d.ambiente || "producao" };
            }
        }
    }

    return null;
}

/** Fallback: token da plataforma (gateways_pagamento/mercado_pago). */
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

function gerarExternalRefPdv(lojaId, cobrancaId) {
    // MP limita external_reference a 64 chars (alfanumérico, hífen, underscore)
    const lojaSuf = String(lojaId || "").replace(/[^a-zA-Z0-9]/g, "").slice(-8);
    const ref = "pdv_" + lojaSuf + "_" + String(cobrancaId || "");
    return ref.slice(0, 64);
}

function sanitizeMpExternalId(valor, maxLen) {
    return String(valor || "").replace(/[^a-zA-Z0-9]/g, "").slice(0, maxLen);
}

function extrairMensagemErroMp(body, fallback) {
    if (!body || typeof body !== "object") return fallback;
    const partes = [];
    if (body.message) partes.push(String(body.message));
    if (body.error) partes.push(String(body.error));
    if (Array.isArray(body.errors)) {
        for (const e of body.errors) {
            if (e && e.message) partes.push(String(e.message));
            if (e && e.code) partes.push(String(e.code));
            if (Array.isArray(e.details)) {
                for (const d of e.details) partes.push(String(d));
            }
        }
    }
    if (Array.isArray(body.cause)) {
        for (const c of body.cause) {
            if (c && c.code) partes.push(String(c.code));
            if (c && c.description) partes.push(String(c.description));
        }
    }
    return partes.length > 0 ? partes.join(" — ") : fallback;
}

function montarItemOrdemMpPdv(item, idx, fallbackTitulo, fallbackPreco) {
    return {
        title: String(item.nome || fallbackTitulo || "Item").substring(0, 150),
        unit_price: formatarValorMp(item.preco != null ? item.preco : fallbackPreco),
        quantity: Math.max(1, Number(item.quantidade) || 1),
        unit_measure: "un",
        external_code: String(item.id || ("item_" + idx)).substring(0, 30),
    };
}

async function obterMpUserId(accessToken) {
    const res = await fetch(MP_API + "/users/me", {
        headers: { Authorization: "Bearer " + accessToken },
    });
    const body = await res.json().catch(function () { return {}; });
    if (!res.ok) {
        throw new Error(extrairMensagemErroMp(body, "MP users/me HTTP " + res.status));
    }
    const userId = String(body.id || "").trim();
    if (!userId) throw new Error("Mercado Pago nao retornou user_id.");
    return userId;
}

const UF_PARA_ESTADO_MP = {
    AC: "Acre", AL: "Alagoas", AP: "Amapá", AM: "Amazonas", BA: "Bahia",
    CE: "Ceará", DF: "Distrito Federal", ES: "Espírito Santo", GO: "Goiás",
    MA: "Maranhão", MT: "Mato Grosso", MS: "Mato Grosso do Sul", MG: "Minas Gerais",
    PA: "Pará", PB: "Paraíba", PR: "Paraná", PE: "Pernambuco", PI: "Piauí",
    RJ: "Rio de Janeiro", RN: "Rio Grande do Norte", RS: "Rio Grande do Sul",
    RO: "Rondônia", RR: "Roraima", SC: "Santa Catarina", SP: "São Paulo",
    SE: "Sergipe", TO: "Tocantins",
};

function defaultLocalizacaoLojaMp() {
    return {
        street_number: "SN",
        street_name: "Comercio Local",
        city_name: "Toledo",
        state_name: "Paraná",
        latitude: -24.7136,
        longitude: -53.7431,
        reference: "DiPertin Gestao Comercial",
    };
}

function removerAcentosMp(texto) {
    return String(texto || "")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "");
}

function tituloPalavraMp(palavra) {
    const p = String(palavra || "").trim();
    if (!p) return p;
    return p.charAt(0).toUpperCase() + p.slice(1).toLowerCase();
}

function normalizarCidadeMp(cidade) {
    const raw = String(cidade || "").trim();
    if (!raw) return "Toledo";

    const lower = raw.toLowerCase();
    const semAcento = removerAcentosMp(lower);
    /** Cidades DiPertin + capitais com grafia oficial exigida pelo MP */
    const conhecidas = {
        rondonopolis: "Rondonópolis",
        rondonópolis: "Rondonópolis",
        toledo: "Toledo",
        "sao paulo": "São Paulo",
        saopaulo: "São Paulo",
        "belo horizonte": "Belo Horizonte",
        curitiba: "Curitiba",
        cascavel: "Cascavel",
    };
    if (conhecidas[lower]) return conhecidas[lower];
    if (conhecidas[semAcento]) return conhecidas[semAcento];

    return raw
        .split(/\s+/)
        .map(function (parte) {
            const pl = parte.toLowerCase();
            if (pl === "de" || pl === "da" || pl === "do" || pl === "dos" || pl === "das") return pl;
            return tituloPalavraMp(parte);
        })
        .join(" ");
}

function montarCandidatosLocalizacaoMp(location) {
    const padrao = defaultLocalizacaoLojaMp();
    const base = location || padrao;
    const titulo = Object.assign({}, base, {
        city_name: normalizarCidadeMp(base.city_name),
        state_name: normalizarEstadoMp(base.state_name || base.uf),
    });
    const semAcentoCidade = Object.assign({}, titulo, {
        city_name: removerAcentosMp(titulo.city_name),
    });
    // Toledo/PR primeiro — formato validado pelo MP; fallback para endereco da loja
    const lista = [padrao, titulo, semAcentoCidade];
    const vistos = new Set();
    return lista.filter(function (loc) {
        const chave = JSON.stringify(loc);
        if (vistos.has(chave)) return false;
        vistos.add(chave);
        return true;
    });
}

async function postLojaMp(accessToken, userId, externalStoreId, location) {
    const res = await fetch(MP_API + "/users/" + encodeURIComponent(userId) + "/stores", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            name: "DiPertin PDV",
            external_id: externalStoreId,
            location: location,
        }),
    });
    const body = await res.json().catch(function () { return {}; });
    return { ok: res.ok, status: res.status, body: body, storeId: body.id != null ? Number(body.id) : null };
}

function normalizarEstadoMp(ufOuNome) {
    const raw = String(ufOuNome || "").trim();
    if (!raw) return "Paraná";
    const uf = raw.length === 2 ? raw.toUpperCase() : "";
    if (uf && UF_PARA_ESTADO_MP[uf]) return UF_PARA_ESTADO_MP[uf];
    // Nome parcial sem acento → tenta UF conhecida
    const lower = raw.toLowerCase();
    if (lower.includes("parana") || lower === "pr") return "Paraná";
    if (lower.includes("sao paulo") || lower === "sp") return "São Paulo";
    if (lower.includes("rondonia") || lower === "ro") return "Rondônia";
    if (lower.includes("mato grosso") && lower.includes("sul")) return "Mato Grosso do Sul";
    if (lower.includes("mato grosso") || lower === "mt") return "Mato Grosso";
    return raw.length > 2 ? raw : "Paraná";
}

async function carregarLocalizacaoLojaMp(db, lojaId) {
    const padrao = defaultLocalizacaoLojaMp();
    try {
        const lojaSnap = await db.collection("users").doc(lojaId).get();
        if (!lojaSnap.exists) return padrao;
        const loja = lojaSnap.data() || {};
        const uf = String(loja.endereco_uf || loja.uf || loja.estado || "PR").trim();
        const cidade = String(
            loja.endereco_cidade || loja.cidade || loja.cidade_normalizada || padrao.city_name,
        ).trim();
        const rua = String(
            loja.endereco_rua || loja.endereco_logradouro || loja.endereco || padrao.street_name,
        ).trim();
        const numero = String(loja.endereco_numero || loja.numero || "SN").trim();
        const lat = Number(loja.latitude ?? loja.endereco_latitude);
        const lng = Number(loja.longitude ?? loja.endereco_longitude);
        return {
            street_number: (numero || "SN").slice(0, 20),
            street_name: (rua || padrao.street_name).slice(0, 100),
            city_name: normalizarCidadeMp(cidade || padrao.city_name).slice(0, 80),
            state_name: normalizarEstadoMp(uf),
            latitude: Number.isFinite(lat) ? lat : padrao.latitude,
            longitude: Number.isFinite(lng) ? lng : padrao.longitude,
            reference: "DiPertin Gestao Comercial",
        };
    } catch (e) {
        console.warn("[gc-pix] Falha ao ler endereco loja " + lojaId + ":", e.message || e);
        return padrao;
    }
}

async function criarOuObterLojaMp(accessToken, userId, externalStoreId, location) {
    const candidatos = montarCandidatosLocalizacaoMp(location);
    let ultimoErro = null;

    for (let i = 0; i < candidatos.length; i++) {
        const loc = candidatos[i];
        console.log("[gc-pix] Tentativa loja MP (" + (i + 1) + "/" + candidatos.length + "): "
            + loc.city_name + "/" + loc.state_name);
        const tentativa = await postLojaMp(accessToken, userId, externalStoreId, loc);
        if (tentativa.ok && tentativa.storeId != null) {
            return tentativa.storeId;
        }
        ultimoErro = extrairMensagemErroMp(tentativa.body, "HTTP " + tentativa.status);
        console.warn("[gc-pix] Loja MP rejeitada:", ultimoErro);
        const ehLocation = /city_name|state_name|location|street/i.test(ultimoErro);
        if (!ehLocation) break;
    }

    // Loja ja existe — buscar na listagem
    const listRes = await fetch(
        MP_API + "/users/" + encodeURIComponent(userId) + "/stores/search?external_id="
        + encodeURIComponent(externalStoreId),
        {
            headers: { Authorization: "Bearer " + accessToken },
        },
    );
    const listBody = await listRes.json().catch(function () { return {}; });
    if (listRes.ok) {
        const results = listBody.results || listBody.data || listBody;
        if (Array.isArray(results) && results.length > 0 && results[0].id != null) {
            return Number(results[0].id);
        }
    }

    // Fallback: listar todas as lojas e filtrar por external_id
    const allRes = await fetch(
        MP_API + "/users/" + encodeURIComponent(userId) + "/stores",
        { headers: { Authorization: "Bearer " + accessToken } },
    );
    const allBody = await allRes.json().catch(function () { return {}; });
    if (allRes.ok) {
        const rows = allBody.results || allBody.data || (Array.isArray(allBody) ? allBody : []);
        if (Array.isArray(rows)) {
            const found = rows.find(function (s) {
                return String(s.external_id || "") === externalStoreId;
            });
            if (found && found.id != null) return Number(found.id);
        }
    }

    throw new Error(ultimoErro || "Falha ao criar loja MP.");
}

async function criarOuObterPosMp(accessToken, storeId, externalStoreId, externalPosId) {
    /** MCCs validos no BR para varejo/artesanato (621102 da doc MP falha com pos_unknown_mcc) */
    const mccLista = [5999, 5947, 5411, 5331];
    let ultimoErro = null;
    let ultimoStatus = 0;
    let ultimoBody = {};

    for (let i = 0; i <= mccLista.length; i++) {
        const payload = {
            name: "DiPertin PDV Caixa",
            fixed_amount: false,
            store_id: Number(storeId),
            external_store_id: externalStoreId,
            external_id: externalPosId,
        };
        if (i < mccLista.length) {
            payload.category = mccLista[i];
        }

        const res = await fetch(MP_API + "/pos", {
            method: "POST",
            headers: {
                Authorization: "Bearer " + accessToken,
                "Content-Type": "application/json",
            },
            body: JSON.stringify(payload),
        });
        const body = await res.json().catch(function () { return {}; });
        ultimoStatus = res.status;
        ultimoBody = body;
        if (res.ok) {
            console.log("[gc-pix] Caixa MP criada, mcc=" + (payload.category || "sem"));
            return body;
        }

        ultimoErro = extrairMensagemErroMp(body, "HTTP " + res.status);
        console.warn("[gc-pix] Caixa MP rejeitada (mcc=" + (payload.category || "sem") + "):", ultimoErro);
        const ehMcc = /mcc|category|unknown_mcc/i.test(ultimoErro);
        if (!ehMcc) break;
    }

    if (ultimoStatus === 409 || String(ultimoErro || "").toLowerCase().includes("exists")) {
        const getRes = await fetch(
            MP_API + "/pos?external_id=" + encodeURIComponent(externalPosId),
            { headers: { Authorization: "Bearer " + accessToken } },
        );
        const getBody = await getRes.json().catch(function () { return {}; });
        if (getRes.ok) {
            const rows = getBody.results || getBody.data || [];
            if (Array.isArray(rows) && rows.length > 0) return rows[0];
        }
        return { external_id: externalPosId };
    }

    throw new Error(extrairMensagemErroMp(ultimoBody, ultimoErro || "Falha ao criar caixa MP (HTTP " + ultimoStatus + ")"));
}

/**
 * Orders API exige config.qr.external_pos_id (loja + caixa criados no MP).
 * Provisiona automaticamente na 1a cobranca e persiste em gestao_comercial_configuracoes.
 */
async function garantirExternalPosIdPdv(db, lojaId, accessToken) {
    const configRef = db.collection("gestao_comercial_configuracoes").doc(lojaId);
    const snap = await configRef.get();
    const mpCfg = snap.exists ? (snap.data()?.pagamentos?.mercado_pago || {}) : {};

    const posSalvo = mpCfg.external_pos_id && String(mpCfg.external_pos_id).trim();
    if (posSalvo) return String(posSalvo).trim();

    const externalStoreId = sanitizeMpExternalId("D" + lojaId, 40);
    const externalPosId = sanitizeMpExternalId(externalStoreId + "POS1", 40);

    console.log("[gc-pix] Provisionando loja/caixa MP: store=" + externalStoreId + ", pos=" + externalPosId);

    const location = await carregarLocalizacaoLojaMp(db, lojaId);
    console.log("[gc-pix] Local MP:", location.city_name + "/" + location.state_name);

    const userId = await obterMpUserId(accessToken);
    let storeId = mpCfg.mp_store_id != null ? Number(mpCfg.mp_store_id) : null;
    if (!storeId || Number.isNaN(storeId)) {
        storeId = await criarOuObterLojaMp(accessToken, userId, externalStoreId, location);
    }

    await criarOuObterPosMp(accessToken, storeId, externalStoreId, externalPosId);

    await configRef.set({
        pagamentos: {
            mercado_pago: {
                external_pos_id: externalPosId,
                external_store_id: externalStoreId,
                mp_store_id: storeId,
                mp_pos_provisionado_em: admin.firestore.FieldValue.serverTimestamp(),
            },
        },
    }, { merge: true });

    console.log("[gc-pix] Caixa MP pronta: external_pos_id=" + externalPosId + ", store_id=" + storeId);
    return externalPosId;
}

function formatarValorMp(num) {
    const n = Number(num);
    if (!Number.isFinite(n) || n <= 0) return "0.00";
    return (Math.round(n * 100) / 100).toFixed(2);
}

/**
 * Valida PIX dinâmico real (cobrança com location BACEN/MP).
 * Rejeita QR estático br.gov.bcb.pix01 (CPF, telefone, e-mail) — apps bancários
 * interpretam como transferência e o pagamento não associa à cobrança.
 */
function validarQrPixDinamicoGestaoComercial(qrData) {
    if (!qrData || typeof qrData !== "string") {
        return { ok: false, motivo: "Codigo PIX vazio." };
    }
    if (!qrData.startsWith("000201")) {
        return { ok: false, motivo: "Codigo PIX invalido (nao inicia com 000201)." };
    }
    if (!/6304[0-9A-Fa-f]{4}$/.test(qrData)) {
        return { ok: false, motivo: "Codigo PIX invalido (terminador CRC 6304 ausente)." };
    }

    const temLocationMp = /pix-qr\.mercadopago\.com/i.test(qrData);
    const temQrLocationBcb = /br\.gov\.bcb\.qr01/i.test(qrData);
    const temChaveEstaticaPix = /br\.gov\.bcb\.pix01/i.test(qrData);

    if (temChaveEstaticaPix) {
        return {
            ok: false,
            motivo: "QR estatico detectado (chave PIX CPF/telefone). "
                + "Use cobranca dinamica via Orders API do Mercado Pago.",
        };
    }

    if (temLocationMp || temQrLocationBcb) {
        return { ok: true, formato: "orders_dynamic_location" };
    }

    return {
        ok: false,
        motivo: "QR sem location de cobranca dinamica (br.gov.bcb.qr01 ou pix-qr.mercadopago.com).",
    };
}

/** Gera PNG base64 (data URL) a partir do copia-e-cola PIX — mesmo pacote usado no PDV Flutter (qr_flutter). */
async function gerarQrCodeBase64PixCopiaCola(textoPix) {
    const texto = String(textoPix || "").trim();
    if (!texto) return "";
    try {
        return await QRCodeLib.toDataURL(texto, {
            errorCorrectionLevel: "M",
            margin: 2,
            width: 440,
            color: { dark: "#1A1A2E", light: "#FFFFFF" },
        });
    } catch (e) {
        console.warn("[gc-pix] Falha ao gerar QR base64:", e.message || e);
        return "";
    }
}

async function criarOrdemPixDinamicoMercadoPago(accessToken, orderPayload, idempotencyKey) {
    const res = await fetch(MP_API + "/v1/orders", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
            "X-Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify(orderPayload),
    });
    const body = await res.json().catch(function () { return {}; });
    if (!res.ok) {
        const err = new Error(extrairMensagemErroMp(body, "MP Orders HTTP " + res.status));
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

async function criarPagamentoPixMpPdv(accessToken, payload, idempotencyKey) {
    const res = await fetch(MP_API + "/v1/payments", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
            "X-Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify(payload),
    });
    const body = await res.json().catch(function () { return {}; });
    if (!res.ok) {
        const err = new Error(extrairMensagemErroMp(body, "MP PIX HTTP " + res.status));
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

async function fetchOrderFromMp(accessToken, orderId) {
    const url = MP_API + "/v1/orders/" + encodeURIComponent(String(orderId));
    const res = await fetch(url, {
        method: "GET",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
        },
    });
    const body = await res.json().catch(function () { return {}; });
    if (!res.ok) {
        const err = new Error(body.message || "MP GET order " + res.status);
        err.status = res.status;
        err.body = body;
        throw err;
    }
    return body;
}

function extrairPagamentoOrdemMp(orderBody) {
    const payments = orderBody?.transactions?.payments;
    if (Array.isArray(payments) && payments.length > 0) return payments[0];
    if (payments && typeof payments === "object" && payments.id) return payments;
    return null;
}

function mapStatusPagamentoOrdemMp(paymentTx) {
    const st = String(paymentTx?.status || "").toLowerCase();
    const detail = String(paymentTx?.status_detail || "").toLowerCase();
    if (st === "processed" || st === "approved" || detail === "accredited" || detail === "approved") {
        return { statusMp: "approved", pago: true };
    }
    if (st === "created" || st === "processing" || detail === "ready_to_process" || detail === "pending" || detail === "waiting_payment" || detail === "in_process") {
        return { statusMp: "pending", pago: false };
    }
    if (st === "cancelled" || st === "canceled") {
        return { statusMp: "cancelled", pago: false };
    }
    if (st === "refunded") {
        return { statusMp: "refunded", pago: false };
    }
    return { statusMp: st || "pending", pago: false };
}

function montarPaymentCompativelOrdem(orderBody, cobrancaValor) {
    const paymentTx = extrairPagamentoOrdemMp(orderBody) || {};
    const mapped = mapStatusPagamentoOrdemMp(paymentTx);
    const orderSt = String(orderBody?.status || "").toLowerCase();
    const orderDetail = String(orderBody?.status_detail || "").toLowerCase();
    let statusMp = mapped.statusMp;
    if (orderSt === "processed" && (orderDetail === "accredited" || orderDetail === "partially_refunded")) {
        statusMp = "approved";
    }
    return {
        id: paymentTx.id || orderBody.id,
        status: statusMp,
        status_detail: paymentTx.status_detail || orderBody.status_detail || "",
        transaction_amount: Number(orderBody.total_amount || paymentTx.amount || cobrancaValor || 0),
    };
}

/**
 * Consulta status no MP: PAY id direto (mais confiavel pos-PIX) + fallback Orders API.
 */
async function consultarPagamentoMpParaCobranca(cobrancaData, accessToken) {
    const paymentId = cobrancaData.paymentId ? String(cobrancaData.paymentId) : "";
    const mpOrderId = cobrancaData.mpOrderId ? String(cobrancaData.mpOrderId) : "";

    if (paymentId && paymentId.startsWith("PAY")) {
        try {
            const payment = await fetchPaymentFromMp(accessToken, paymentId);
            const st = String(payment.status || "").toLowerCase();
            if (st === "approved" || st === "authorized") {
                return payment;
            }
            if (!mpOrderId) return payment;
        } catch (e) {
            console.warn("[gc-mp] GET payment " + paymentId + ":", e.message || e);
        }
    }

    if (mpOrderId) {
        const orderBody = await fetchOrderFromMp(accessToken, mpOrderId);
        return montarPaymentCompativelOrdem(orderBody, cobrancaData.valor);
    }

    if (paymentId) {
        return await fetchPaymentFromMp(accessToken, paymentId);
    }

    return null;
}

async function marcarCobrancaPagaGestaoComercial(db, cobrancaRef, cobrancaData, paymentMp, statusMp) {
    const valorRecebido = paymentMp.transaction_amount || cobrancaData.valor || 0;
    const paymentId = paymentMp.id || cobrancaData.paymentId;

    await cobrancaRef.update({
        status: "pago",
        mpStatus: statusMp,
        mpStatusDetail: String(paymentMp.status_detail || ""),
        pagoEm: admin.firestore.FieldValue.serverTimestamp(),
        valorRecebido: valorRecebido,
        processed: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
        await finalizarVendaPdv(db, cobrancaData, paymentId, statusMp, paymentMp);
    } catch (e) {
        console.error("[gc-pix] Erro ao finalizar venda:", e.message || e);
    }

    return valorRecebido;
}

// =============================================================================
// FINALIZAR VENDA PDV (helper interno)
// =============================================================================

async function finalizarVendaPdv(db, cobrancaData, paymentId, statusMp, payment) {
    if (cobrancaData.origem !== "pdv") {
        console.log("[gc-finalizar] Origem nao eh pdv (" + (cobrancaData.origem || "vazio") + "). Pulando.");
        return;
    }
    if (statusMp !== "approved" && statusMp !== "authorized") {
        console.log("[gc-finalizar] Status MP nao aprovado (" + statusMp + "). Pulando.");
        return;
    }

    const lojaId = cobrancaData.lojaId;
    const vendaId = cobrancaData.vendaId;
    const valorRecebido = payment.transaction_amount || cobrancaData.valor || 0;

    if (!vendaId || !lojaId) {
        console.warn("[gc-finalizar] vendaId ou lojaId ausentes.");
        return;
    }

    // IDEMPOTENCIA: verificar status da venda
    const vendaRef = db.collection("gestao_comercial_vendas").doc(vendaId);
    const vendaSnap = await vendaRef.get();

    if (vendaSnap.exists) {
        const vendaData = vendaSnap.data() || {};
        if (vendaData.status === "pago" || vendaData.status === "quitado" || vendaData.status === "finalizada") {
            console.log("[gc-finalizar] Venda " + vendaId + " ja finalizada (idempotencia). Pulando.");
            return;
        }
    }

    // IDEMPOTENCIA: verificar recebimento existente
    const cobrancaId = cobrancaData.cobrancaId || "";
    if (cobrancaId) {
        const recebimentosExistentes = await db
            .collection("gestao_comercial_recebimentos")
            .where("cobranca_id", "==", cobrancaId)
            .limit(1)
            .get();

        if (!recebimentosExistentes.empty) {
            console.log("[gc-finalizar] Recebimento ja existe para cobranca " + cobrancaId + ". Pulando.");
            return;
        }
    }

    // Batch atomico
    try {
        const recebimentoRef = db.collection("gestao_comercial_recebimentos").doc();
        const batch = db.batch();

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
        console.log("[gc-finalizar] Venda " + vendaId + " finalizada via PIX " + paymentId + ". Recebimento " + recebimentoRef.id);

        try {
            const vendaAtualSnap = await vendaRef.get();
            const vendaAtual = vendaAtualSnap.exists ? (vendaAtualSnap.data() || {}) : {};
            if (!(await pedidoExisteParaVendaGestaoComercial(db, vendaId))) {
                await baixarEstoqueGestaoComercialVenda(db, vendaId, Object.assign({}, vendaAtual, {
                    status: "pago",
                    loja_id: lojaId,
                    itens: vendaAtual.itens || cobrancaData.itens || [],
                }));
            }
        } catch (estErr) {
            console.error("[gc-finalizar] Erro baixa estoque venda " + vendaId + ":", estErr.message || estErr);
        }
    } catch (e) {
        console.error("[gc-finalizar] Erro na transacao:", e.message || e);
        throw e;
    }
}

// =============================================================================
// 1. GESTAO_COMERCIAL_CRIAR_PAGAMENTO_PIX (CORRIGIDO)
// =============================================================================
//
// CORRECAO (jul/2026):
// - ANTES: usava Orders API (POST /v1/orders) — complexa, exigia external_pos_id,
//   provisionamento de POS, retornava qr_code_base64 vazio e validacao excessiva de QR.
// - AGORA: usa Payments API (POST /v1/payments) — mesma abordagem simples e testada
//   do marketplace (mpCriarPagamentoPix) e do PDV legado (createPdvPixPayment).
// - Remove validacao validarQrPixDinamicoGestaoComercial (rejeitava QR estatico valido).
// - QR code e qr_code_base64 vêm direto da resposta oficial do MP (point_of_interaction).

/**
 * Cria pagamento PIX no Mercado Pago para PDV/Gestao Comercial.
 *
 * Recebe: { lojaId, vendaId, valor, itens[], clienteId?, operadorId?, clienteNome? }
 * Retorna: { cobrancaId, paymentId, qrCodeBase64, pixCopiaECola, expiresAt, status }
 */
exports.gestaoComercialCriarPagamentoPix = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false, secrets: [] }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const valor = Number(data.valor);
        const vendaId = String(data.vendaId || "").trim();
        const itens = Array.isArray(data.itens) ? data.itens : [];
        const operadorId = String(data.operadorId || "").trim();
        const clienteId = String(data.clienteId || "").trim() || null;
        const clienteNome = String(data.clienteNome || "").trim() || null;
        const clienteCpf = data.clienteCpf != null ? String(data.clienteCpf) : null;

        if (!lojaId || !valor || valor <= 0 || !vendaId) {
            throw new HttpsError("invalid-argument", "lojaId, vendaId e valor sao obrigatorios.");
        }

        const db = admin.firestore();
        const cobrancaRef = db.collection("gestao_comercial_cobrancas").doc();
        const cobrancaId = cobrancaRef.id;
        const externalRef = gerarExternalRefPdv(lojaId, cobrancaId);
        const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

        const description = itens.length > 0
            ? "PDV " + lojaId.slice(-6) + " - " + itens.length + " item(ns)"
            : "Venda PDV " + vendaId.slice(-8);

        console.log("[gc-pix] Criando PIX via gateway da loja: loja=" + lojaId + ", valor=" + valor);

        let pixResult;
        try {
            pixResult = await criarCobrancaPixGestaoComercial(db, {
                lojaId,
                valor,
                descricao: description.substring(0, 150),
                externalReference: externalRef,
                idempotencyKey: cobrancaId,
                clienteNome: clienteNome || "Cliente PDV",
                clienteCpf,
                operadorId,
            });
        } catch (e) {
            if (e instanceof HttpsError) throw e;
            console.error("[gc-pix] Erro:", e.message || e);
            throw new HttpsError("internal", "Erro ao criar cobranca PIX.");
        }

        const paymentId = pixResult.paymentId;
        const pixCopiaECola = pixResult.pixCopiaECola;
        const qrCodeBase64 = pixResult.qrCodeBase64;
        const gatewayTipo = pixResult.gatewayInfo.tipo;

        await cobrancaRef.set({
            lojaId,
            vendaId,
            clienteId,
            clienteNome,
            operadorId,
            gateway: gatewayTipo,
            paymentId,
            mpPixModo: "payments_api_validado",
            externalReference: externalRef,
            valor,
            status: "aguardando_pagamento",
            qrCodeBase64,
            pixCopiaECola,
            pix_validacao: pixResult.validacao.br || null,
            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
            origem: "pdv",
            itens: itens.map(function (item) {
                const pid = item.id || item.produto_id || item.id_produto || "";
                return Object.assign({}, item, { id: pid, produto_id: pid });
            }),
            processed: false,
            metadata: { lojaId, vendaId, operadorId, origem: "pdv" },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const operadorNome = request.auth.token?.name || "Operador PDV";
        await db.collection("gestao_comercial_vendas").doc(vendaId).set({
            loja_id: lojaId,
            venda_id: vendaId,
            cobranca_id: cobrancaId,
            codigo_venda: vendaId.slice(-8).toUpperCase(),
            cliente_id: clienteId || "venda_balcao",
            cliente_nome: clienteNome || "Cliente PDV",
            itens: itens.map(function (item) {
                const pid = item.id || item.produto_id || item.id_produto || "";
                return Object.assign({}, item, { id: pid, produto_id: pid });
            }),
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

        console.log("[gc-pix] PIX " + paymentId + " validado e criado via " + gatewayTipo);

        return {
            cobrancaId,
            paymentId,
            qrCodeBase64,
            pixCopiaECola,
            expiresAt: expiresAt.toISOString(),
            status: "aguardando_pagamento",
            gateway: gatewayTipo,
        };
    },
);

// =============================================================================
// 2. GESTAO_COMERCIAL_CONSULTAR_STATUS_PIX
// =============================================================================

/**
 * Consulta status de cobranca PIX.
 * Equivalente a checkPdvPixPaymentStatus, mas em southamerica-east1.
 *
 * Recebe: { cobrancaId }
 * Retorna: { status, pago, expirado, valorRecebido, vendaId, pagamento }
 */
exports.gestaoComercialConsultarStatusPix = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        try {
            if (!request.auth) {
                throw new HttpsError("unauthenticated", "Login necessario.");
            }
            await assertGestaoComercialAccess(admin.firestore(), request);

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

            let data = snap.data() || {};
            let status = data.status || "aguardando_pagamento";

            // Se aguardando, consultar MP diretamente (Orders API ou Payments legado)
            if ((status === "aguardando_pagamento" || status === "aguardando") && data.lojaId) {
                try {
                    const lojaCreds = await getLojaMercadoPagoCreds(db, data.lojaId);
                    if (lojaCreds && lojaCreds.accessToken) {
                        const paymentMp = await consultarPagamentoMpParaCobranca(data, lojaCreds.accessToken);
                        const statusMp = paymentMp
                            ? String(paymentMp.status || "").toLowerCase()
                            : "";

                        if (paymentMp && statusMp) {
                            if (statusMp === "approved" || statusMp === "authorized") {
                                console.log("[gc-check] Pagamento aprovado via consulta MP: " + (data.paymentId || data.mpOrderId));

                                await marcarCobrancaPagaGestaoComercial(
                                    db, cobrancaRef, data, paymentMp, statusMp,
                                );
                                status = "pago";
                            } else if (statusMp === "pending" || statusMp === "in_process" || statusMp === "in_mediation") {
                                await cobrancaRef.update({
                                    mpStatus: statusMp,
                                    mpStatusDetail: String(paymentMp.status_detail || ""),
                                    mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                                });
                                console.log("[gc-check] Cobranca " + cobrancaId + " ainda pendente no MP: " + statusMp);
                            } else {
                                await cobrancaRef.update({
                                    mpStatus: statusMp,
                                    mpStatusDetail: String(paymentMp.status_detail || ""),
                                    mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                                });
                                console.log("[gc-check] Cobranca " + cobrancaId + " MP status: " + statusMp + ". Mantendo aguardando.");
                            }
                        }
                    }
                } catch (e) {
                    console.warn("[gc-check] Erro consulta MP p/ " + (data.paymentId || data.mpOrderId) + ":", e.message || e);
                }
            }

            // Re-ler documento apos possivel update
            const snapAtual = await cobrancaRef.get();
            if (snapAtual.exists) {
                data = snapAtual.data() || data;
                status = data.status || status;
            }

            // Verificar expiracao (5 min)
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
                    console.log("[gc-check] Cobranca " + cobrancaId + " expirada apos 5 min sem pagamento.");
                }
            }

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
                    console.warn("[gc-check] Erro ao ler venda " + data.vendaId + ":", e.message || e);
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

            console.log("[gc-check] Status cobranca " + cobrancaId + ": " + status +
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
            console.error("[gc-check] Erro fatal:", e?.message || e, e?.stack || "");
            throw new HttpsError("internal", "Erro ao verificar status: " + (e?.message || e));
        }
    },
);

// =============================================================================
// 3. GESTAO_COMERCIAL_TESTAR_CONEXAO_MERCADO_PAGO
// =============================================================================

/**
 * Testa se Access Token Mercado Pago e valido.
 * Equivalente a testarConexaoMercadoPago, mas em southamerica-east1.
 */
exports.gestaoComercialTestarConexaoMercadoPago = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const accessToken = String(request.data?.accessToken || "").trim();
        const ambiente = String(request.data?.ambiente || "producao").trim();
        const lojaId = String(request.data?.lojaId || "").trim() || null;

        if (!accessToken) {
            throw new HttpsError("invalid-argument", "Access Token e obrigatorio.");
        }

        return validarGatewayMercadoPagoCompleto(accessToken, ambiente, lojaId);
    },
);

// =============================================================================
// 3b. GESTAO_COMERCIAL_TESTAR_CONEXAO_GATEWAY (todos os provedores)
// =============================================================================

async function validarTokenMercadoPagoApi(accessToken) {
    const url = MP_API + "/v1/payments/search?limit=1";
    const res = await fetch(url, {
        method: "GET",
        headers: {
            Authorization: "Bearer " + accessToken,
            "Content-Type": "application/json",
        },
    });

    if (res.ok) {
        return { valido: true, mensagem: "Access Token Mercado Pago válido! Conexão realizada com sucesso." };
    }

    const body = await res.json().catch(function () { return {}; });
    const message = body?.message || "HTTP " + res.status;

    if (res.status === 401) {
        return { valido: false, mensagem: "Access Token inválido ou revogado. Verifique as credenciais." };
    }
    if (res.status === 403) {
        return { valido: false, mensagem: "Access Token sem permissão. Verifique as permissões da aplicação." };
    }

    return { valido: false, mensagem: "Erro ao validar token: " + message };
}

/**
 * Testa credenciais de qualquer gateway cadastrado (MP valida na API; demais validação estrutural).
 */
exports.gestaoComercialTestarConexaoGateway = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const provedor = String(request.data?.provedor || "mercado_pago").trim();
        const accessToken = String(request.data?.accessToken || "").trim();
        const publicKey = String(request.data?.publicKey || "").trim();
        const ambiente = String(request.data?.ambiente || "producao").trim();
        const lojaId = String(request.data?.lojaId || "").trim() || null;

        if (!accessToken) {
            throw new HttpsError("invalid-argument", "Access Token e obrigatorio.");
        }

        if (provedor === "mercado_pago") {
            return validarGatewayMercadoPagoCompleto(accessToken, ambiente, lojaId);
        }

        if (accessToken.length < 8) {
            return {
                valido: false,
                mensagem: "Access Token muito curto. Verifique se copiou a credencial completa.",
            };
        }

        const slugMap = {
            mercado_pago: "mercadopago",
            asaas: "asaas",
            cora: "cora",
            "banco_itaú": "banco-itau",
            banco_itau: "banco-itau",
            banco_bradesco: "bradesco",
            banco_santander: "santander",
            banco_do_brasil: "bb",
            sicoob: "sicoob",
            sicredi: "sicredi",
            stone: "stone",
            pagseguro: "pagseguro",
            api_personalizada: "api-personalizada",
        };
        const slug = slugMap[provedor] || provedor.replace(/_/g, "-");
        const webhookUrl = WEBHOOK_BASE_PLANOS + "/" + slug;

        return {
            valido: true,
            mensagem: "Credenciais registradas. Configure o webhook "
                + webhookUrl
                + " no painel do provedor."
                + (publicKey ? " Public Key informada." : "")
                + " Teste PIX completo disponível apenas para Mercado Pago.",
        };
    },
);

// =============================================================================
// 4. GESTAO_COMERCIAL_WEBHOOK_MERCADO_PAGO
// =============================================================================

/**
 * Webhook HTTP para notificacoes de pagamento Mercado Pago (Gestao Comercial).
 * Endpoint publico para MP enviar notificacoes.
 * URL: https://southamerica-east1-depertin-f940f.cloudfunctions.net/gestaoComercialWebhookMercadoPago
 */
exports.gestaoComercialWebhookMercadoPago = onRequest(
    Object.assign({}, CONFIG_PADRAO),
    async (req, res) => {
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
            console.error("[gc-webhook] JSON invalido:", e);
            return res.status(400).send("bad json");
        }

        const paymentId = extrairPaymentId(body);
        if (!paymentId) {
            console.log("[gc-webhook] Sem paymentId, ignorando.");
            return res.status(200).send("no payment id");
        }

        const action = body.action || body.type || body.topic || "";
        if (action && String(action).includes("merchant_order") && !body.data?.id) {
            return res.status(200).send("ignored merchant_order");
        }

        console.log("[gc-webhook] Recebido: paymentId=" + paymentId + ", action=" + action);

        try {
            await processarNotificacaoPagamento(String(paymentId));
            return res.status(200).send("ok");
        } catch (e) {
            console.error("[gc-webhook] Erro:", e.message || e);
            return res.status(500).send("error");
        }
    },
);

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

async function processarNotificacaoPagamento(paymentId) {
    const db = admin.firestore();
    const idStr = String(paymentId || "").trim();

    let cobrancaDoc = null;
    let cobrancaData = null;

    // Orders API: webhook pode enviar ORD... ou PAY...
    if (idStr.startsWith("ORD")) {
        const orderSnap = await db
            .collection("gestao_comercial_cobrancas")
            .where("mpOrderId", "==", idStr)
            .limit(1)
            .get();
        if (!orderSnap.empty) {
            cobrancaDoc = orderSnap.docs[0];
            cobrancaData = cobrancaDoc.data() || {};
        }
    }

    // Buscar cobranca pelo paymentId
    if (!cobrancaData) {
        const cobrancasSnap = await db
            .collection("gestao_comercial_cobrancas")
            .where("paymentId", "==", idStr)
            .limit(1)
            .get();

        if (!cobrancasSnap.empty) {
            cobrancaDoc = cobrancasSnap.docs[0];
            cobrancaData = cobrancaDoc.data() || {};
        }
    }

    // Fallback: buscar por mpOrderId (Orders API)
    if (!cobrancaData) {
        const orderSnap = await db
            .collection("gestao_comercial_cobrancas")
            .where("mpOrderId", "==", idStr)
            .limit(1)
            .get();
        if (!orderSnap.empty) {
            cobrancaDoc = orderSnap.docs[0];
            cobrancaData = cobrancaDoc.data() || {};
        }
    }

    // Fallback: buscar por external_reference via Payments API
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
                console.warn("[gc-webhook] Erro ao buscar payment externo:", e.message || e);
            }
        }
    }

    if (!cobrancaData) {
        console.warn("[gc-webhook] Cobranca nao encontrada para paymentId=" + paymentId);
        // Tentar processar como pagamento de token (link de cobrança)
        try {
            const tokenResult = await _processarConfirmacaoPagamentoToken(paymentId);
            if (tokenResult.processado) {
                console.log("[gc-webhook] Pagamento token processado: " + paymentId + " -> " + tokenResult.status);
            } else {
                console.log("[gc-webhook] Nao e pagamento de token: " + (tokenResult.motivo || "desconhecido"));
            }
        } catch (tokenErr) {
            console.error("[gc-webhook] Erro ao processar token:", tokenErr.message || tokenErr);
        }
        return;
    }

    // IDEMPOTENCIA
    if (cobrancaData.processed === true) {
        console.log("[gc-webhook] Cobranca " + cobrancaDoc.id + " ja processada. Ignorando.");
        return;
    }
    if (cobrancaData.status === "pago") {
        console.log("[gc-webhook] Cobranca " + cobrancaDoc.id + " ja esta paga. Ignorando.");
        return;
    }

    const lojaId = cobrancaData.lojaId || "";
    if (!lojaId) {
        console.warn("[gc-webhook] Cobranca sem lojaId:", cobrancaDoc.id);
        return;
    }

    const lojaCreds = await getLojaMercadoPagoCreds(db, lojaId);
    if (!lojaCreds || !lojaCreds.accessToken) {
        console.warn("[gc-webhook] Credenciais MP nao encontradas para loja " + lojaId);
        return;
    }

    let payment;
    try {
        payment = await consultarPagamentoMpParaCobranca(cobrancaData, lojaCreds.accessToken);
        if (!payment) {
            console.warn("[gc-webhook] Nao foi possivel consultar pagamento/order no MP");
            return;
        }
        console.log("[gc-webhook] Status MP: " + payment.status + " ref=" + (cobrancaData.mpOrderId || idStr));
    } catch (e) {
        console.error("[gc-webhook] Erro consulta payment/order " + idStr + ":", e.message);
        return;
    }

    const statusMp = String(payment.status || "").toLowerCase();
    const pago = statusMp === "approved" || statusMp === "authorized";

    if (pago) {
        console.log("[gc-webhook] Pagamento aprovado: ref=" + idStr + ", loja=" + lojaId);

        await marcarCobrancaPagaGestaoComercial(
            db, cobrancaDoc.ref, cobrancaData, payment, statusMp,
        );

        console.log("[gc-webhook] Pagamento processado: " + statusMp);
    } else if (cobrancaData.status === "aguardando_pagamento" || cobrancaData.status === "aguardando") {
        const agora = new Date();
        const expiresTs = cobrancaData.expiresAt?.toDate
            ? cobrancaData.expiresAt.toDate()
            : cobrancaData.expiresAt
                ? new Date(cobrancaData.expiresAt)
                : null;
        const expirado = expiresTs && !isNaN(expiresTs.getTime()) && agora >= expiresTs;

        if (statusMp === "rejected" || statusMp === "cancelled" || statusMp === "refunded") {
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
                console.log("[gc-webhook] Cobranca " + cobrancaDoc.id + " expirada. MP: " + statusMp);
            } else {
                await cobrancaDoc.ref.update({
                    mpStatus: statusMp,
                    mpStatusDetail: String(payment.status_detail || ""),
                    mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log("[gc-webhook] Cobranca " + cobrancaDoc.id + " dentro prazo. MP: " + statusMp + ". Mantendo aguardando.");
            }
        } else {
            const updateFields = {
                mpStatus: statusMp,
                mpStatusDetail: String(payment.status_detail || ""),
                mpAtualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (cobrancaData.status === "aguardando") {
                updateFields.status = "aguardando_pagamento";
            }
            await cobrancaDoc.ref.update(updateFields);
            console.log("[gc-webhook] Cobranca " + cobrancaDoc.id + " aguardando. MP: " + statusMp);
        }
    } else {
        console.log("[gc-webhook] Cobranca " + cobrancaDoc.id + " status=" + cobrancaData.status + ". Ignorado.");
    }
}

// =============================================================================
// 5. GESTAO_COMERCIAL_ABRIR_CAIXA
// =============================================================================

/**
 * Abre o caixa diario de uma loja.
 * Recebe: { lojaId, operadorId, saldoInicial? }
 * Retorna: { caixaId, status, abertoEm }
 */
exports.gestaoComercialAbrirCaixa = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const operadorId = String(data.operadorId || request.auth.uid || "").trim();
        const saldoInicial = Number(data.saldoInicial) || 0;

        if (!lojaId) {
            throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        }

        const db = admin.firestore();
        const hoje = new Date();
        const dataKey = hoje.toISOString().slice(0, 10); // YYYY-MM-DD

        // Verificar se ja existe caixa aberto hoje
        const caixaExistente = await db
            .collection("gestao_comercial_caixas")
            .where("loja_id", "==", lojaId)
            .where("data_key", "==", dataKey)
            .where("status", "==", "aberto")
            .limit(1)
            .get();

        if (!caixaExistente.empty) {
            const existente = caixaExistente.docs[0];
            console.log("[gc-caixa] Caixa ja aberto hoje p/ loja " + lojaId + ": " + existente.id);
            return {
                caixaId: existente.id,
                status: "aberto",
                abertoEm: existente.data().aberto_em?.toDate?.()?.toISOString() || new Date().toISOString(),
                mensagem: "Caixa ja esta aberto para hoje.",
            };
        }

        const caixaRef = db.collection("gestao_comercial_caixas").doc();
        const operadorNome = request.auth.token?.name || "Operador";

        await caixaRef.set({
            loja_id: lojaId,
            data_key: dataKey,
            status: "aberto",
            saldo_inicial: saldoInicial,
            saldo_atual: saldoInicial,
            total_entradas: 0,
            total_saidas: 0,
            operador_id_abertura: operadorId,
            operador_nome_abertura: operadorNome,
            aberto_em: admin.firestore.FieldValue.serverTimestamp(),
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("[gc-caixa] Caixa " + caixaRef.id + " aberto p/ loja " + lojaId + " (" + dataKey + ")");

        return {
            caixaId: caixaRef.id,
            status: "aberto",
            abertoEm: new Date().toISOString(),
            saldoInicial: saldoInicial,
        };
    },
);

// =============================================================================
// 6. GESTAO_COMERCIAL_FECHAR_CAIXA
// =============================================================================

/**
 * Fecha o caixa diario de uma loja.
 * Recebe: { lojaId, caixaId?, saldoFinal?, observacao? }
 * Retorna: { caixaId, status, fechadoEm, resumo }
 */
exports.gestaoComercialFecharCaixa = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const observacao = String(data.observacao || "").trim();

        if (!lojaId) {
            throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        }

        const db = admin.firestore();
        const hoje = new Date();
        const dataKey = hoje.toISOString().slice(0, 10);

        // Buscar caixa aberto (por ID ou pelo mais recente)
        let caixaDoc;
        if (data.caixaId) {
            caixaDoc = await db.collection("gestao_comercial_caixas").doc(String(data.caixaId).trim()).get();
        } else {
            const caixaSnap = await db
                .collection("gestao_comercial_caixas")
                .where("loja_id", "==", lojaId)
                .where("data_key", "==", dataKey)
                .where("status", "==", "aberto")
                .limit(1)
                .get();
            if (!caixaSnap.empty) {
                caixaDoc = caixaSnap.docs[0];
            } else {
                throw new HttpsError("not-found", "Nenhum caixa aberto encontrado para hoje.");
            }
        }

        if (!caixaDoc || !caixaDoc.exists) {
            throw new HttpsError("not-found", "Caixa nao encontrado.");
        }

        const caixaData = caixaDoc.data() || {};
        if (caixaData.status !== "aberto") {
            throw new HttpsError("failed-precondition", "Caixa ja esta fechado.");
        }

        const operadorId = String(data.operadorId || request.auth.uid || "").trim();
        const operadorNome = request.auth.token?.name || "Operador";
        const saldoInformado = Number(data.saldoFinal) >= 0 ? Number(data.saldoFinal) : caixaData.saldo_atual || 0;

        // Consolidar totais do dia
        const vendasSnap = await db
            .collection("gestao_comercial_vendas")
            .where("loja_id", "==", lojaId)
            .where("data_venda", ">=", new Date(dataKey + "T00:00:00"))
            .where("data_venda", "<=", new Date(dataKey + "T23:59:59"))
            .get();

        let totalVendas = 0;
        let totalPix = 0;
        let totalDinheiro = 0;
        let totalCartao = 0;
        let totalFiado = 0;
        let quantidadeVendas = 0;

        vendasSnap.forEach(function (doc) {
            const v = doc.data() || {};
            if (v.status === "pago" || v.status === "quitado" || v.status === "finalizada") {
                totalVendas += Number(v.valor_total) || 0;
                quantidadeVendas++;
                const fp = String(v.forma_pagamento || "").toLowerCase();
                if (fp.includes("pix")) totalPix += Number(v.valor_total) || 0;
                else if (fp.includes("dinheiro")) totalDinheiro += Number(v.valor_total) || 0;
                else if (fp.includes("cartao") || fp.includes("crédito") || fp.includes("debito")) totalCartao += Number(v.valor_total) || 0;
                else if (fp.includes("fiado") || fp.includes("credito")) totalFiado += Number(v.valor_total) || 0;
            }
        });

        // Atualizar caixa
        await caixaDoc.ref.update({
            status: "fechado",
            saldo_final: saldoInformado,
            total_vendas: totalVendas,
            quantidade_vendas: quantidadeVendas,
            total_pix: totalPix,
            total_dinheiro: totalDinheiro,
            total_cartao: totalCartao,
            total_fiado: totalFiado,
            operador_id_fechamento: operadorId,
            operador_nome_fechamento: operadorNome,
            observacao: observacao,
            fechado_em: admin.firestore.FieldValue.serverTimestamp(),
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("[gc-caixa] Caixa " + caixaDoc.id + " fechado p/ loja " + lojaId + ": R$" + totalVendas + " (" + quantidadeVendas + " vendas)");

        return {
            caixaId: caixaDoc.id,
            status: "fechado",
            fechadoEm: new Date().toISOString(),
            resumo: {
                totalVendas: totalVendas,
                quantidadeVendas: quantidadeVendas,
                totalPix: totalPix,
                totalDinheiro: totalDinheiro,
                totalCartao: totalCartao,
                totalFiado: totalFiado,
                saldoInformado: saldoInformado,
            },
        };
    },
);

// =============================================================================
// 7. GESTAO_COMERCIAL_RECEBER_PAGAMENTO
// =============================================================================

/**
 * Registra recebimento de pagamento (dinheiro, cartao, etc.).
 * Recebe: { lojaId, vendaId, valor, formaPagamento, clienteId?, observacao? }
 * Retorna: { recebimentoId, status }
 */
exports.gestaoComercialReceberPagamento = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const vendaId = String(data.vendaId || "").trim();
        const valor = Number(data.valor);
        const formaPagamento = String(data.formaPagamento || data.forma_pagamento || "").trim();
        const clienteId = String(data.clienteId || "").trim() || null;
        const clienteNome = String(data.clienteNome || data.cliente_nome || "").trim() || null;
        const observacao = String(data.observacao || "").trim();

        if (!lojaId || !vendaId || !valor || valor <= 0 || !formaPagamento) {
            throw new HttpsError("invalid-argument", "lojaId, vendaId, valor e formaPagamento sao obrigatorios.");
        }

        const db = admin.firestore();
        const vendaRef = db.collection("gestao_comercial_vendas").doc(vendaId);
        const vendaSnap = await vendaRef.get();

        if (!vendaSnap.exists) {
            throw new HttpsError("not-found", "Venda nao encontrada.");
        }

        const vendaData = vendaSnap.data() || {};
        if (vendaData.status === "pago" || vendaData.status === "quitado" || vendaData.status === "finalizada") {
            throw new HttpsError("already-exists", "Venda ja foi paga anteriormente.");
        }

        const operadorId = String(data.operadorId || request.auth.uid || "").trim();
        const operadorNome = request.auth.token?.name || "Operador";

        const recebimentoRef = db.collection("gestao_comercial_recebimentos").doc();

        // IDEMPOTENCIA: verificar se ja existe recebimento para esta venda+forma
        const existente = await db
            .collection("gestao_comercial_recebimentos")
            .where("venda_id", "==", vendaId)
            .where("forma_pagamento", "==", formaPagamento)
            .limit(1)
            .get();

        if (!existente.empty) {
            console.log("[gc-receber] Recebimento ja existe para venda " + vendaId + " (" + formaPagamento + "). Ignorando.");
            return {
                recebimentoId: existente.docs[0].id,
                status: "existente",
                mensagem: "Recebimento ja registrado para esta venda.",
            };
        }

        const batch = db.batch();

        batch.update(vendaRef, {
            status: "pago",
            statusPagamento: "pago",
            valor_pago: valor,
            valor_pendente: Math.max(0, (vendaData.valor_total || 0) - valor),
            pagoEm: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        batch.set(recebimentoRef, {
            loja_id: lojaId,
            venda_id: vendaId,
            cliente_id: clienteId || vendaData.cliente_id || "venda_balcao",
            cliente_nome: clienteNome || vendaData.cliente_nome || "Cliente PDV",
            valor_original: vendaData.valor_total || valor,
            valor_recebido: valor,
            forma_pagamento: formaPagamento,
            recebido_por_id: operadorId,
            recebido_por_nome: operadorNome,
            observacao: observacao,
            data_recebimento: admin.firestore.FieldValue.serverTimestamp(),
            status: "confirmado",
            origem: "pdv_manual",
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        await batch.commit();

        console.log("[gc-receber] Recebimento " + recebimentoRef.id + " registrado p/ venda " + vendaId + " (" + formaPagamento + ")");

        return {
            recebimentoId: recebimentoRef.id,
            status: "confirmado",
            formaPagamento: formaPagamento,
            valor: valor,
        };
    },
);

// =============================================================================
// 8. GESTAO_COMERCIAL_CONCEDER_CREDITO
// =============================================================================

/**
 * Concede/ajusta limite de credito de cliente comercial.
 * Recebe: { lojaId, clienteId, limite, observacao? }
 * Retorna: { clienteId, limite, status }
 */
exports.gestaoComercialConcederCredito = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const clienteId = String(data.clienteId || "").trim();
        const limite = Number(data.limite);
        const observacao = String(data.observacao || "").trim();

        if (!lojaId || !clienteId || limite < 0) {
            throw new HttpsError("invalid-argument", "lojaId, clienteId e limite (>=0) sao obrigatorios.");
        }

        const db = admin.firestore();
        const clienteRef = db.collection("clientes_comercial").doc(clienteId);
        const clienteSnap = await clienteRef.get();

        if (!clienteSnap.exists) {
            throw new HttpsError("not-found", "Cliente comercial nao encontrado.");
        }

        const clienteAtual = clienteSnap.data() || {};
        const limiteAnterior = Number(clienteAtual.limite_credito || 0);

        const operadorId = String(data.operadorId || request.auth.uid || "").trim();
        const operadorNome = request.auth.token?.name || "Operador";

        // Atualizar limite
        await clienteRef.update({
            limite_credito: limite,
            credito_disponivel: limite - (Number(clienteAtual.credito_utilizado || 0)),
            limite_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            limite_atualizado_por: operadorId,
            limite_atualizado_por_nome: operadorNome,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("[gc-credito] Limite de " + clienteId + " alterado: R$" + limiteAnterior + " -> R$" + limite);

        return {
            clienteId: clienteId,
            limite: limite,
            limiteAnterior: limiteAnterior,
            status: "concedido",
            mensagem: "Limite de credito atualizado para R$ " + limite.toFixed(2),
        };
    },
);

// =============================================================================
// 9. GESTAO_COMERCIAL_CONSULTAR_PENDENCIAS
// =============================================================================

/**
 * Retorna resumo de pendencias financeiras de uma loja.
 * Recebe: { lojaId, clienteId? }
 * Retorna: { totalPendente, totalVencido, clientes[], ... }
 */
exports.gestaoComercialConsultarPendencias = onCall(
    Object.assign({}, CONFIG_PESADO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const clienteFiltro = String(data.clienteId || "").trim() || null;

        if (!lojaId) {
            throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        }

        const db = admin.firestore();
        const agora = new Date();

        // Buscar todas as parcelas pendentes da loja
        let query = db
            .collection("parcelas_cliente")
            .where("loja_id", "==", lojaId)
            .where("status", "in", ["pendente", "vencido", "parcial"]);

        const snap = await query.get();

        let totalPendente = 0;
        let totalVencido = 0;
        let totalParcelas = 0;
        const clientesMap = {};

        snap.forEach(function (doc) {
            const p = doc.data() || {};
            const valorParcela = Number(p.valor || p.valor_parcela || 0);
            const dataVencimento = p.data_vencimento?.toDate
                ? p.data_vencimento.toDate()
                : p.data_vencimento
                    ? new Date(p.data_vencimento)
                    : null;

            totalPendente += valorParcela;
            totalParcelas++;

            const vencido = dataVencimento && !isNaN(dataVencimento.getTime()) && dataVencimento < agora;

            if (vencido) {
                totalVencido += valorParcela;
            }

            const cId = p.cliente_id || "unknown";
            if (!clientesMap[cId]) {
                clientesMap[cId] = { cliente_id: cId, cliente_nome: p.cliente_nome || "Cliente", total: 0, vencido: 0, parcelas: 0 };
            }
            clientesMap[cId].total += valorParcela;
            if (vencido) clientesMap[cId].vencido += valorParcela;
            clientesMap[cId].parcelas++;
        });

        const clientes = Object.values(clientesMap);

        // Ordenar por maior vencido
        clientes.sort(function (a, b) { return b.vencido - a.vencido; });

        if (clienteFiltro) {
            const filtrado = clientes.filter(function (c) { return c.cliente_id === clienteFiltro; });
            return {
                totalPendente: totalPendente,
                totalVencido: totalVencido,
                totalParcelas: totalParcelas,
                clientes: filtrado,
            };
        }

        return {
            totalPendente: totalPendente,
            totalVencido: totalVencido,
            totalParcelas: totalParcelas,
            topDevedores: clientes.slice(0, 10),
            clientes: clientes,
        };
    },
);

// =============================================================================
// 10. GESTAO_COMERCIAL_HISTORICO_VENDAS
// =============================================================================

/**
 * Retorna historico de vendas com filtros.
 * Recebe: { lojaId, dataInicio?, dataFim?, status?, limite? }
 * Retorna: { vendas[], total }
 */
exports.gestaoComercialHistoricoVendas = onCall(
    Object.assign({}, CONFIG_PESADO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const statusFiltro = String(data.status || "").trim() || null;
        const limite = Math.min(Number(data.limite) || 100, 500);

        if (!lojaId) {
            throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        }

        const db = admin.firestore();
        let query = db
            .collection("gestao_comercial_vendas")
            .where("loja_id", "==", lojaId);

        // Filtro por data
        if (data.dataInicio) {
            const dataInicio = new Date(data.dataInicio);
            if (!isNaN(dataInicio.getTime())) {
                query = query.where("data_venda", ">=", dataInicio);
            }
        }
        if (data.dataFim) {
            const dataFim = new Date(data.dataFim);
            if (!isNaN(dataFim.getTime())) {
                query = query.where("data_venda", "<=", dataFim);
            }
        }

        query = query.orderBy("data_venda", "desc").limit(limite);

        const snap = await query.get();
        const vendas = [];

        snap.forEach(function (doc) {
            const v = doc.data() || {};
            if (statusFiltro && v.status !== statusFiltro) return;
            vendas.push({
                vendaId: doc.id,
                codigo: v.codigo_venda || "",
                clienteNome: v.cliente_nome || "",
                valorTotal: v.valor_total || 0,
                valorPago: v.valor_pago || 0,
                status: v.status || "",
                formaPagamento: v.forma_pagamento || "",
                dataVenda: v.data_venda?.toDate?.()?.toISOString() || null,
                quantidadeItens: v.quantidade_itens || 0,
                operadorNome: v.operador_nome || "",
            });
        });

        return { vendas: vendas, total: vendas.length };
    },
);

// =============================================================================
// 11. GESTAO_COMERCIAL_RELATORIO
// =============================================================================

/**
 * Gera relatorio financeiro consolidado.
 * Recebe: { lojaId, periodoInicio?, periodoFim? }
 * Retorna: { resumo, vendas, recebimentos }
 */
exports.gestaoComercialRelatorio = onCall(
    Object.assign({}, CONFIG_PESADO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        if (!lojaId) {
            throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        }

        const db = admin.firestore();
        const periodoInicio = data.periodoInicio ? new Date(data.periodoInicio) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        const periodoFim = data.periodoFim ? new Date(data.periodoFim) : new Date();

        // Vendas no periodo
        const vendasSnap = await db
            .collection("gestao_comercial_vendas")
            .where("loja_id", "==", lojaId)
            .where("data_venda", ">=", periodoInicio)
            .where("data_venda", "<=", periodoFim)
            .get();

        let totalVendas = 0;
        let totalPago = 0;
        let qtdPago = 0;
        let qtdPendente = 0;
        let qtdCancelada = 0;
        const porFormaPagamento = {};

        vendasSnap.forEach(function (doc) {
            const v = doc.data() || {};
            const val = Number(v.valor_total) || 0;
            totalVendas += val;

            if (v.status === "pago" || v.status === "quitado" || v.status === "finalizada") {
                totalPago += val;
                qtdPago++;
                const fp = v.forma_pagamento || "outros";
                porFormaPagamento[fp] = (porFormaPagamento[fp] || 0) + val;
            } else if (v.status === "cancelado" || v.status === "cancelada" || v.status === "cancelado_pelo_cliente" || v.status === "estornado") {
                qtdCancelada++;
            } else {
                qtdPendente++;
            }
        });

        // Recebimentos no periodo
        const recebimentosSnap = await db
            .collection("gestao_comercial_recebimentos")
            .where("loja_id", "==", lojaId)
            .where("data_recebimento", ">=", periodoInicio)
            .where("data_recebimento", "<=", periodoFim)
            .get();

        let totalRecebido = 0;
        const recebimentos = [];
        recebimentosSnap.forEach(function (doc) {
            const r = doc.data() || {};
            const val = Number(r.valor_recebido) || 0;
            totalRecebido += val;
            recebimentos.push({
                id: doc.id,
                venda_id: r.venda_id || "",
                valor: val,
                forma: r.forma_pagamento || "",
                data: r.data_recebimento?.toDate?.()?.toISOString() || null,
                cliente: r.cliente_nome || "",
            });
        });

        return {
            periodo: {
                inicio: periodoInicio.toISOString(),
                fim: periodoFim.toISOString(),
            },
            resumo: {
                totalVendas: totalVendas,
                totalPago: totalPago,
                totalRecebido: totalRecebido,
                qtdPago: qtdPago,
                qtdPendente: qtdPendente,
                qtdCancelada: qtdCancelada,
                ticketMedio: qtdPago > 0 ? (totalPago / qtdPago) : 0,
            },
            porFormaPagamento: porFormaPagamento,
            vendas: vendasSnap.size,
            recebimentos: recebimentos,
        };
    },
);

// =============================================================================
// 12. GESTAO_COMERCIAL_FINANCEIRO_CLIENTE
// =============================================================================

/**
 * Retorna situacao financeira detalhada de um cliente.
 * Recebe: { lojaId, clienteId }
 * Retorna: { cliente, limite, utilizado, disponivel, parcelas[], totalPendente }
 */
exports.gestaoComercialFinanceiroCliente = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const clienteId = String(data.clienteId || "").trim();

        if (!lojaId || !clienteId) {
            throw new HttpsError("invalid-argument", "lojaId e clienteId sao obrigatorios.");
        }

        const db = admin.firestore();

        // Dados do cliente
        const clienteSnap = await db.collection("clientes_comercial").doc(clienteId).get();
        if (!clienteSnap.exists) {
            throw new HttpsError("not-found", "Cliente nao encontrado.");
        }

        const cliente = clienteSnap.data() || {};
        const limite = Number(cliente.limite_credito || 0);
        const utilizado = Number(cliente.credito_utilizado || 0);
        const disponivel = Math.max(0, limite - utilizado);

        // Parcelas pendentes
        const parcelasSnap = await db
            .collection("parcelas_cliente")
            .where("loja_id", "==", lojaId)
            .where("cliente_id", "==", clienteId)
            .where("status", "in", ["pendente", "vencido", "parcial"])
            .orderBy("data_vencimento", "asc")
            .get();

        const agora = new Date();
        let totalPendente = 0;
        let totalVencido = 0;
        const parcelas = [];

        parcelasSnap.forEach(function (doc) {
            const p = doc.data() || {};
            const val = Number(p.valor || p.valor_parcela || 0);
            const dataVenc = p.data_vencimento?.toDate
                ? p.data_vencimento.toDate()
                : p.data_vencimento
                    ? new Date(p.data_vencimento)
                    : null;

            totalPendente += val;
            const vencido = dataVenc && !isNaN(dataVenc.getTime()) && dataVenc < agora;
            if (vencido) totalVencido += val;

            parcelas.push({
                parcelaId: doc.id,
                vendaId: p.venda_id || "",
                numero: p.numero_parcela || 1,
                valor: val,
                valorPago: Number(p.valor_pago || 0),
                dataVencimento: dataVenc?.toISOString() || null,
                status: p.status || "pendente",
                vencido: vencido,
                diasAtraso: dataVenc && !isNaN(dataVenc.getTime())
                    ? Math.max(0, Math.floor((agora - dataVenc) / (1000 * 60 * 60 * 24)))
                    : 0,
            });
        });

        return {
            cliente: {
                id: clienteId,
                nome: cliente.nome || cliente.razao_social || cliente.cliente_nome || "Cliente",
                telefone: cliente.telefone || cliente.whatsapp || "",
                cidade: cliente.cidade || "",
            },
            credito: {
                limite: limite,
                utilizado: utilizado,
                disponivel: disponivel,
            },
            parcelas: parcelas,
            totalPendente: totalPendente,
            totalVencido: totalVencido,
            quantidadeParcelas: parcelas.length,
        };
    },
);

// =============================================================================
// 13. GESTAO_COMERCIAL_CONSULTAR_PARCELAS
// =============================================================================

/**
 * Retorna parcelas de uma venda ou de todas as vendas pendentes.
 * Recebe: { lojaId, vendaId?, clienteId? }
 * Retorna: { parcelas[], totalPendente }
 */
exports.gestaoComercialConsultarParcelas = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        await assertGestaoComercialAccess(admin.firestore(), request);

        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const vendaId = String(data.vendaId || "").trim() || null;
        const clienteId = String(data.clienteId || "").trim() || null;

        if (!lojaId) {
            throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        }

        const db = admin.firestore();
        let query = db
            .collection("parcelas_cliente")
            .where("loja_id", "==", lojaId);

        if (vendaId) {
            query = query.where("venda_id", "==", vendaId);
        }
        if (clienteId) {
            query = query.where("cliente_id", "==", clienteId);
        }

        query = query.orderBy("data_vencimento", "asc");

        const snap = await query.get();
        const parcelas = [];
        let totalPendente = 0;

        const agora = new Date();

        snap.forEach(function (doc) {
            const p = doc.data() || {};
            const val = Number(p.valor || p.valor_parcela || 0);
            totalPendente += val;

            const dataVenc = p.data_vencimento?.toDate
                ? p.data_vencimento.toDate()
                : p.data_vencimento
                    ? new Date(p.data_vencimento)
                    : null;

            parcelas.push({
                parcelaId: doc.id,
                vendaId: p.venda_id || "",
                clienteId: p.cliente_id || "",
                clienteNome: p.cliente_nome || "",
                numero: p.numero_parcela || 1,
                totalParcelas: p.total_parcelas || 1,
                valor: val,
                valorPago: Number(p.valor_pago || 0),
                dataVencimento: dataVenc?.toISOString() || null,
                status: p.status || "pendente",
                vencido: dataVenc && !isNaN(dataVenc.getTime()) && dataVenc < agora,
            });
        });

        return { parcelas: parcelas, totalPendente: totalPendente, quantidade: parcelas.length };
    },
);

// =============================================================================
// 14. WHATSAPP — ENVIO DE COBRANÇA
// =============================================================================

/**
 * HTTP request helper (mesmo padrão do gestao_comercial_email.js).
 */
function _httpReq(url, options, body) {
    return new Promise((resolve, reject) => {
        const parsed = new URL(url);
        const lib = parsed.protocol === "https:" ? https : http;
        const req = lib.request(
            parsed,
            {
                method: options.method || "GET",
                headers: options.headers || {},
                timeout: options.timeout || 15000,
            },
            (res) => {
                let data = "";
                res.on("data", (c) => (data += c));
                res.on("end", () => resolve({ status: res.statusCode, body: data, headers: res.headers }));
            },
        );
        req.on("error", reject);
        req.on("timeout", () => { req.destroy(); reject(new Error("Timeout")); });
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

const _emailHelpers = (() => {
    try {
        return require("./gestao_comercial_email")._gestaoComercialEmailHelpers;
    } catch (_) {
        return null;
    }
})();

function _decryptToken(stored) {
    if (!stored) return "";
    if (_emailHelpers && _emailHelpers.decryptSecret) {
        return _emailHelpers.decryptSecret(stored);
    }
    return stored;
}

const VZAPS_API_BASE = "https://api.vzaps.com";

/**
 * Normaliza telefone para APIs WhatsApp (VZaps exige DDI, ex.: 5511999999999).
 * Cadastro comercial costuma guardar só DDD+número (10/11 dígitos).
 */
function _normalizarTelefoneWhatsAppIntl(raw) {
    let d = String(raw || "").replace(/\D/g, "");
    if (!d) return "";
    // Remove zeros à esquerda ocasionais (ex.: 055...)
    d = d.replace(/^0+/, "");
    if (!d) return "";
    if (d.startsWith("55") && d.length >= 12 && d.length <= 13) return d;
    // BR local: DDD + número (10) ou celular com 9 (11)
    if (d.length === 10 || d.length === 11) return "55" + d;
    return d;
}

function _normalizarProvedorWhatsApp(raw) {
    const p = String(raw || "").trim().toLowerCase();
    if (p === "vzaps" || p === "v-zaps") return "vzaps";
    if (p === "meta" || p === "meta_cloud" || p === "facebook") return "meta";
    if (p === "evolution" || p === "evolution_api") return "evolution";
    if (p === "zapi" || p === "z-api") return "zapi";
    if (p === "custom" || p === "outro" || p === "generic" || p === "api_personalizada") return "custom";
    return p || "";
}

function _extrairProvedorWhatsApp(apiUrl, provedorHint) {
    const hint = _normalizarProvedorWhatsApp(provedorHint);
    if (hint) return hint === "generic" ? "custom" : hint;
    const url = String(apiUrl || "").toLowerCase();
    if (url.includes("api.vzaps.com") || url.includes("vzaps")) return "vzaps";
    if (url.includes("graph.facebook.com") || url.includes("graph.fb")) return "meta";
    if (url.includes("z-api")) return "zapi";
    if (url.includes("evolution")) return "evolution";
    return "custom";
}

function _resolverCredenciaisWhatsApp(canal, override) {
    const base = canal && typeof canal === "object" ? canal : {};
    const ov = override && typeof override === "object" ? override : {};
    const pick = (key) => {
        const v = ov[key];
        if (v === undefined || v === null) return base[key];
        const s = String(v).trim();
        // Máscara / vazio no override = manter valor já salvo
        if (!s || s === "••••••••" || s === "********") return base[key];
        return v;
    };
    const apiUrlRaw = String(pick("apiUrl") || "").trim();
    const provedor = _extrairProvedorWhatsApp(apiUrlRaw, pick("provedor"));
    return {
        provedor,
        apiUrl: provedor === "vzaps"
            ? (apiUrlRaw || VZAPS_API_BASE)
            : apiUrlRaw,
        token: _decryptToken(pick("token")),
        clientToken: _decryptToken(pick("clientToken")),
        clientSecret: _decryptToken(pick("clientSecret")),
        instanceId: String(pick("instanceId") || "").trim(),
        remetente: String(pick("remetente") || "").trim(),
        authMethod: String(pick("authMethod") || "").trim().toLowerCase() || "bearer",
        endpointEnvio: String(pick("endpointEnvio") || "").trim(),
        templateMensagem: String(pick("templateMensagem") || base.templateMensagem || "").trim(),
        nome: String(pick("nome") || base.nome || "").trim(),
    };
}

function _montarPayloadWhatsApp(provedor, remetente, mensagem, destino) {
    const number = _normalizarTelefoneWhatsAppIntl(destino);
    switch (provedor) {
        case "vzaps":
            return { phone: number, message: mensagem };
        case "meta":
            return {
                messaging_product: "whatsapp",
                recipient_type: "individual",
                to: number,
                type: "text",
                text: { body: mensagem },
            };
        case "zapi":
            return { phone: number, message: mensagem };
        case "evolution":
            return { number, text: mensagem, delay: 1200 };
        default:
            return { to: number, phone: number, text: mensagem, message: mensagem };
    }
}

/**
 * Interpreta resposta HTTP do provedor WhatsApp.
 * VZaps: HTTP 200 = enfileirado; body.success deve ser true (docs: WorkerEnvelopeQueuedMessage).
 */
function _interpretarRespostaEnvioWhatsApp(provedor, r) {
    const status = Number(r && r.status) || 0;
    const parsed = _parseJsonBodySafe(r && r.body);
    const detalhe = (() => {
        if (parsed) {
            return parsed.message || parsed.error || parsed.msg
                || (parsed.success === false ? JSON.stringify(parsed).substring(0, 200) : null)
                || null;
        }
        return String((r && r.body) || "").substring(0, 200) || null;
    })();

    if (provedor === "vzaps") {
        const okHttp = status >= 200 && status < 300;
        const successBody = parsed == null
            ? okHttp
            : (parsed.success === true || parsed.success === "true"
                || Number(parsed.code) === 200);
        if (okHttp && successBody) {
            const messageId = parsed && parsed.data && parsed.data.message_id
                ? String(parsed.data.message_id)
                : null;
            return { ok: true, status, provedor, messageId };
        }
        return {
            ok: false,
            status,
            provedor,
            erro: "Falha no provedor VZAPS (HTTP " + status + ")"
                + (detalhe ? ": " + detalhe : (parsed && parsed.success === false
                    ? ": API aceitou a requisicao mas success=false (verifique o telefone com DDI 55)"
                    : "")),
        };
    }

    if (status >= 200 && status < 300) {
        return { ok: true, status, provedor };
    }
    return {
        ok: false,
        status,
        provedor,
        erro: "Falha no provedor " + String(provedor || "whatsapp").toUpperCase()
            + " (HTTP " + status + ")"
            + (detalhe ? ": " + detalhe : ""),
    };
}

function _montarHeadersWhatsApp(provedor, token, extras) {
    const headers = { "Content-Type": "application/json", Accept: "application/json" };
    const authMethod = String((extras && extras.authMethod) || "").toLowerCase();
    switch (provedor) {
        case "vzaps":
            if (extras && extras.clientToken) headers["X-Client-Token"] = extras.clientToken;
            if (token) headers["X-Instance-Token"] = token;
            break;
        case "meta":
            headers["Authorization"] = "Bearer " + token;
            break;
        case "zapi":
            headers["Client-Token"] = token;
            break;
        case "evolution":
            headers["apikey"] = token;
            break;
        default:
            if (authMethod === "apikey" || authMethod === "header_apikey") {
                headers["apikey"] = token;
            } else if (authMethod === "client_token") {
                headers["Client-Token"] = token;
            } else if (authMethod === "x_api_key") {
                headers["X-API-Key"] = token;
            } else {
                headers["Authorization"] = "Bearer " + token;
            }
    }
    return headers;
}

function _montarUrlEnvioWhatsApp(provedor, apiUrl, remetente, extras) {
    const base = String(apiUrl || "").replace(/\/+$/, "");
    switch (provedor) {
        case "vzaps": {
            const instanceId = String((extras && extras.instanceId) || "").trim();
            return (base || VZAPS_API_BASE) + "/instances/" + instanceId + "/chat/send/text";
        }
        case "meta":
            return base + "/v22.0/" + String(remetente || "").trim() + "/messages";
        case "zapi":
            return base + "/message/sendText";
        case "evolution":
            return base + "/message/sendText/" + String(remetente || "default").trim();
        default: {
            const endpoint = String((extras && extras.endpointEnvio) || "").trim();
            if (endpoint.startsWith("http")) return endpoint;
            if (endpoint) return base + (endpoint.startsWith("/") ? endpoint : "/" + endpoint);
            return base + "/messages";
        }
    }
}

function _montarUrlTesteWhatsApp(provedor, apiUrl, extras) {
    const base = String(apiUrl || "").replace(/\/+$/, "");
    switch (provedor) {
        case "vzaps": {
            const instanceId = String((extras && extras.instanceId) || "").trim();
            return (base || VZAPS_API_BASE) + "/instances/" + instanceId + "/session/status";
        }
        case "meta":
            return base + "/v22.0/me";
        case "zapi":
            return base + "/health";
        case "evolution":
            return base + "/instance/info";
        default: {
            const endpoint = String((extras && extras.endpointEnvio) || "").trim();
            if (endpoint.startsWith("http")) {
                try {
                    const u = new URL(endpoint);
                    return u.origin + "/ping";
                } catch (_) { /* fallthrough */ }
            }
            return base + "/ping";
        }
    }
}

function _parseJsonBodySafe(body) {
    try {
        return JSON.parse(String(body || "{}"));
    } catch (_) {
        return null;
    }
}

/**
 * Testa a conexão com a API WhatsApp.
 * Recebe: { lojaId, credenciais?: { provedor, apiUrl, token, clientToken, instanceId, ... } }
 * Credenciais opcionais permitem testar antes de salvar.
 */
exports.gestaoComercialWhatsAppTestarConexao = onCall(
    Object.assign({}, CONFIG_PADRAO, {
        enforceAppCheck: false,
        consumeAppCheckToken: false,
    }),
    async (request) => {
        // Log diagnóstico (não inclui secrets).
        console.log("[WhatsAppTestar] auth=", request.auth ? request.auth.uid : null,
            "app=", request.app ? "present" : "missing");
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Sessao expirada. Faca login novamente no painel e tente outra vez.",
            );
        }
        await assertGestaoComercialAccess(admin.firestore(), request);
        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");

        const snap = await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId).get();
        const canal = ((snap.data() || {}).cobranca || {}).whatsapp || {};
        const cfg = _resolverCredenciaisWhatsApp(canal, data.credenciais);

        if (cfg.provedor === "vzaps") {
            if (!cfg.instanceId) {
                return { ok: false, mensagem: "Informe o ID da instancia VZaps (ex.: VZ...)." };
            }
            if (!cfg.clientToken) {
                return { ok: false, mensagem: "Informe o Client Token (X-Client-Token) da VZaps." };
            }
            if (!cfg.token) {
                return { ok: false, mensagem: "Informe o Instance Token (X-Instance-Token) da VZaps." };
            }
        } else {
            if (!cfg.apiUrl) return { ok: false, mensagem: "URL da API WhatsApp nao informada." };
            if (!cfg.token) return { ok: false, mensagem: "Token / API Key nao configurada." };
        }

        const extras = {
            instanceId: cfg.instanceId,
            clientToken: cfg.clientToken,
            authMethod: cfg.authMethod,
            endpointEnvio: cfg.endpointEnvio,
        };
        const testUrl = _montarUrlTesteWhatsApp(cfg.provedor, cfg.apiUrl, extras);
        const headers = _montarHeadersWhatsApp(cfg.provedor, cfg.token, extras);

        try {
            const r = await _httpReq(testUrl, { method: "GET", headers });
            const parsed = _parseJsonBodySafe(r.body);
            if (cfg.provedor === "vzaps") {
                const connected = !!(parsed && (
                    (parsed.data && parsed.data.connected === true) ||
                    parsed.connected === true
                ));
                const phone = (parsed && parsed.data && parsed.data.phone)
                    ? String(parsed.data.phone)
                    : "";
                if (r.status >= 200 && r.status < 300 && connected) {
                    return {
                        ok: true,
                        mensagem: "Instancia VZaps conectada ao WhatsApp.",
                        provedor: "vzaps",
                        telefoneConectado: phone,
                        connected: true,
                    };
                }
                if (r.status >= 200 && r.status < 300 && !connected) {
                    return {
                        ok: false,
                        mensagem: "Credenciais validas, mas a instancia ainda nao esta pareada. Escaneie o QR Code no painel VZaps e tente novamente.",
                        provedor: "vzaps",
                        connected: false,
                    };
                }
                return {
                    ok: false,
                    mensagem: "VZaps retornou status " + r.status + ". Verifique Instance ID e tokens.",
                    provedor: "vzaps",
                };
            }
            if (r.status >= 200 && r.status < 500) {
                return {
                    ok: true,
                    mensagem: "Conexao realizada. Provedor: " + cfg.provedor.toUpperCase(),
                    provedor: cfg.provedor,
                };
            }
            return { ok: false, mensagem: "API retornou status " + r.status + ".", provedor: cfg.provedor };
        } catch (err) {
            const m = String(err && err.message ? err.message : err);
            if (/ENOTFOUND|getaddrinfo/i.test(m)) {
                return { ok: false, mensagem: "Host nao encontrado (" + (cfg.apiUrl || VZAPS_API_BASE) + ")." };
            }
            if (/ETIMEDOUT|timeout/i.test(m)) return { ok: false, mensagem: "Timeout — servidor nao respondeu." };
            if (/ECONNREFUSED/i.test(m)) return { ok: false, mensagem: "Servidor recusou conexao." };
            return { ok: false, mensagem: m };
        }
    },
);

/**
 * Envia mensagem WhatsApp.
 * Recebe: { lojaId, destino, variaveis: { cliente, valor, vencimento, link, ... } }
 */
exports.gestaoComercialWhatsAppEnviar = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login necessario.");
        await assertGestaoComercialAccess(admin.firestore(), request);
        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const destino = String(data.destino || "").trim();
        const variaveis = data.variaveis || {};

        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        if (!destino) throw new HttpsError("invalid-argument", "Destino (telefone) e obrigatorio.");

        const snap = await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId).get();
        const canal = ((snap.data() || {}).cobranca || {}).whatsapp || {};
        const cfg = _resolverCredenciaisWhatsApp(canal, null);
        const template = cfg.templateMensagem;

        if (cfg.provedor === "vzaps") {
            if (!cfg.instanceId || !cfg.clientToken || !cfg.token) {
                throw new HttpsError("failed-precondition", "Integracao VZaps incompleta.");
            }
        } else {
            if (!cfg.apiUrl) throw new HttpsError("failed-precondition", "URL da API WhatsApp nao configurada.");
            if (!cfg.token) throw new HttpsError("failed-precondition", "Token / API Key nao configurada.");
        }
        if (!template) throw new HttpsError("failed-precondition", "Template de mensagem nao configurado.");

        const vars = Object.assign({}, variaveis, {
            cliente: variaveis.cliente || "Cliente",
            loja: variaveis.loja || "",
            valor: variaveis.valor || "",
            vencimento: variaveis.vencimento || "",
            link: variaveis.link || "",
            dias_atraso: variaveis.dias_atraso || "",
            multa: variaveis.multa || "",
            juros: variaveis.juros || "",
        });

        let mensagem = template;
        for (const [k, v] of Object.entries(vars)) {
            mensagem = mensagem.split("{" + k + "}").join(String(v ?? ""));
        }

        const extras = {
            instanceId: cfg.instanceId,
            clientToken: cfg.clientToken,
            authMethod: cfg.authMethod,
            endpointEnvio: cfg.endpointEnvio,
        };
        const urlEnvio = _montarUrlEnvioWhatsApp(cfg.provedor, cfg.apiUrl, cfg.remetente, extras);
        const headers = _montarHeadersWhatsApp(cfg.provedor, cfg.token, extras);
        const body = _montarPayloadWhatsApp(cfg.provedor, cfg.remetente, mensagem, destino);

        try {
            const r = await _httpReq(urlEnvio, { method: "POST", headers }, body);
            const interpretado = _interpretarRespostaEnvioWhatsApp(cfg.provedor, r);
            const resposta = (() => {
                try { return JSON.stringify(JSON.parse(r.body)).substring(0, 500); }
                catch (_) { return String(r.body || "").substring(0, 500); }
            })();
            if (interpretado.ok) {
                return {
                    ok: true,
                    mensagem: "Mensagem enviada via " + cfg.provedor.toUpperCase() + ".",
                    statusHttp: r.status,
                    provedor: cfg.provedor,
                    messageId: interpretado.messageId || null,
                    destinoNormalizado: body.phone || body.to || body.number || null,
                };
            }
            return {
                ok: false,
                mensagem: interpretado.erro || ("Falha no envio. Status: " + r.status),
                detalhe: resposta,
                provedor: cfg.provedor,
            };
        } catch (err) {
            return { ok: false, mensagem: "Erro ao enviar: " + String(err && err.message ? err.message : err) };
        }
    },
);

/**
 * Firestore trigger: criptografa secrets do WhatsApp se estiverem em texto puro.
 */
exports.gestaoComercialWhatsAppEncryptTokenOnWrite = onDocumentWritten(
    {
        document: "gestao_comercial_configuracoes/{lojaId}",
        region: "southamerica-east1",
    },
    async (event) => {
        const depois = event.data?.after?.data();
        if (!depois) return;
        const whatsapp = (depois.cobranca || {}).whatsapp;
        if (!whatsapp || typeof whatsapp !== "object") return;
        if (!_emailHelpers || !_emailHelpers.encryptSecret) return;

        const patch = {};
        for (const key of ["token", "clientToken", "clientSecret"]) {
            const raw = String(whatsapp[key] || "").trim();
            if (!raw || raw.startsWith("enc:v1:")) continue;
            const enc = _emailHelpers.encryptSecret(raw);
            if (enc) patch[key] = enc;
        }
        if (Object.keys(patch).length === 0) return;

        await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(event.params.lojaId)
            .set({ cobranca: { whatsapp: patch } }, { merge: true });
    },
);

// =============================================================================
// 15. SMS (COMTELE) — ENVIO DE COBRANÇA
// =============================================================================

/**
 * Testa a conexão com a API Comtele SMS.
 * Recebe: { lojaId, credenciais?: { token, apiUrl, remetente } }
 * Credenciais opcionais permitem testar a Auth Key antes de salvar.
 */
exports.gestaoComercialSmsTestarConexao = onCall(
    Object.assign({}, CONFIG_PADRAO, {
        enforceAppCheck: false,
        consumeAppCheckToken: false,
    }),
    async (request) => {
        console.log("[SmsTestar] auth=", request.auth ? request.auth.uid : null,
            "app=", request.app ? "present" : "missing");
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Sessao expirada. Faca login novamente no painel e tente outra vez.",
            );
        }
        await assertGestaoComercialAccess(admin.firestore(), request);
        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");

        const snap = await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId).get();
        const canal = ((snap.data() || {}).cobranca || {}).sms || {};
        const cred = (data.credenciais && typeof data.credenciais === "object")
            ? data.credenciais
            : {};

        const pickPlain = (raw) => {
            const s = String(raw == null ? "" : raw).trim();
            if (!s || s === "••••••••" || s === "********") return "";
            if (s.startsWith("enc:v1:")) return "";
            return s;
        };

        const tokenOverride = pickPlain(cred.token);
        const token = tokenOverride || _decryptToken(canal.token);
        const apiUrl = String(
            pickPlain(cred.apiUrl) || canal.apiUrl || "https://sms.comtele.com.br/api/v2",
        ).replace(/\/+$/, "");

        if (!token) {
            return {
                ok: false,
                mensagem: "Informe a Auth Key da Comtele no campo do modal e teste novamente.",
            };
        }

        const headers = { "Content-Type": "application/json", "auth-key": token };

        try {
            // Docs Comtele (sms.comtele.com.br/api/v2): GET /credits — NÃO /account/balance
            const creditsUrl = apiUrl.replace(/\/+$/, "") + "/credits";
            console.log("[SmsTestar] GET", creditsUrl);
            const r = await _httpReq(creditsUrl, { method: "GET", headers });
            const parsed = (() => {
                try { return JSON.parse(String(r.body || "{}")); }
                catch (_) { return null; }
            })();

            if (r.status === 200 || r.status === 201) {
                const success = parsed == null
                    ? true
                    : (parsed.Success === true || parsed.success === true
                        || parsed.HasError === false || parsed.hasError === false
                        || parsed.Success === undefined);
                if (parsed && (parsed.Success === false || parsed.success === false
                    || parsed.HasError === true || parsed.hasError === true)) {
                    const msg = parsed.Message || parsed.message || "Auth Key rejeitada pela Comtele.";
                    return { ok: false, mensagem: String(msg) };
                }
                const saldoRaw = parsed && (
                    parsed.Object ?? parsed.object ?? parsed.Balance ?? parsed.balance
                    ?? parsed.credits ?? parsed.Credit ?? null
                );
                const saldo = (saldoRaw !== null && saldoRaw !== undefined && saldoRaw !== "")
                    ? String(saldoRaw)
                    : "";
                return {
                    ok: success !== false,
                    mensagem: saldo
                        ? ("Conexao Comtele OK. Saldo: " + saldo)
                        : "Conexao Comtele realizada com sucesso.",
                };
            }
            if (r.status === 401 || r.status === 403) {
                return { ok: false, mensagem: "Auth Key invalida ou sem permissao na Comtele." };
            }
            const detalhe = (() => {
                if (parsed) {
                    return parsed.Message || parsed.message || JSON.stringify(parsed).substring(0, 160);
                }
                return String(r.body || "").substring(0, 160);
            })();
            return {
                ok: false,
                mensagem: "Comtele retornou HTTP " + r.status
                    + (detalhe ? (": " + detalhe) : "."),
            };
        } catch (err) {
            const m = String(err && err.message ? err.message : err);
            if (/ENOTFOUND|getaddrinfo/i.test(m)) return { ok: false, mensagem: "Host nao encontrado." };
            if (/ETIMEDOUT|timeout/i.test(m)) return { ok: false, mensagem: "Timeout — servidor nao respondeu." };
            return { ok: false, mensagem: m };
        }
    },
);

/**
 * Envia SMS via Comtele.
 * Recebe: { lojaId, destino, variaveis: { cliente, valor, vencimento, link, ... } }
 */
exports.gestaoComercialSmsEnviar = onCall(
    Object.assign({}, CONFIG_PADRAO, {
        enforceAppCheck: false,
        consumeAppCheckToken: false,
    }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Sessao expirada. Faca login novamente no painel e tente outra vez.",
            );
        }
        await assertGestaoComercialAccess(admin.firestore(), request);
        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const destino = String(data.destino || "").trim();
        const variaveis = data.variaveis || {};

        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        if (!destino) throw new HttpsError("invalid-argument", "Destino (telefone) e obrigatorio.");

        const snap = await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId).get();
        const canal = ((snap.data() || {}).cobranca || {}).sms || {};
        const apiUrl = String(canal.apiUrl || "https://sms.comtele.com.br/api/v2").replace(/\/+$/, "");
        const token = _decryptToken(canal.token);
        const remetente = String(canal.remetente || "DiPertin").trim();
        const template = String(canal.templateMensagem || "").trim();

        if (!token) throw new HttpsError("failed-precondition", "Auth Key Comtele nao configurada.");
        if (!template) throw new HttpsError("failed-precondition", "Template de SMS nao configurado.");

        const vars = Object.assign({}, variaveis, {
            cliente: variaveis.cliente || "Cliente",
            loja: variaveis.loja || "",
            valor: variaveis.valor || "",
            vencimento: variaveis.vencimento || "",
            link: variaveis.link || "",
            dias_atraso: variaveis.dias_atraso || "",
        });

        let mensagem = template;
        for (const [k, v] of Object.entries(vars)) {
            mensagem = mensagem.split("{" + k + "}").join(String(v ?? ""));
        }

        // Remove acentos e caracteres especiais para compatibilidade SMS
        mensagem = mensagem
            .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
            .replace(/[^\x20-\x7E\n\r]/g, "");

        const number = String(destino).replace(/\D/g, "");
        const phone = number.startsWith("55") ? number : ("55" + number);
        const sender = remetente.replace(/[^\x20-\x7E]/g, "").substring(0, 11) || "DiPertin";

        try {
            // Docs Comtele: POST /send (não /sms/send); Receivers como string
            const r = await _httpReq(apiUrl.replace(/\/+$/, "") + "/send", {
                method: "POST",
                headers: { "Content-Type": "application/json", "auth-key": token },
            }, {
                Sender: sender,
                Receivers: phone,
                Content: mensagem.substring(0, 160),
            });

            const parsed = (() => {
                try { return JSON.parse(String(r.body || "{}")); }
                catch (_) { return null; }
            })();
            const resposta = parsed ? JSON.stringify(parsed).substring(0, 500) : String(r.body || "").substring(0, 500);
            const successBody = parsed == null
                ? (r.status >= 200 && r.status < 300)
                : (parsed.Success === true || parsed.success === true
                    || (!(parsed.Success === false || parsed.success === false)
                        && r.status >= 200 && r.status < 300));

            if (successBody) {
                return { ok: true, mensagem: "SMS enviado com sucesso via Comtele.", statusHttp: r.status };
            }
            const msgErro = (parsed && (parsed.Message || parsed.message)) || ("Status: " + r.status);
            return { ok: false, mensagem: "Falha no envio SMS. " + msgErro, detalhe: resposta };
        } catch (err) {
            return { ok: false, mensagem: "Erro ao enviar SMS: " + String(err && err.message ? err.message : err) };
        }
    },
);

/**
 * Firestore trigger: criptografa token do SMS se estiver em texto puro.
 */
exports.gestaoComercialSmsEncryptTokenOnWrite = onDocumentWritten(
    {
        document: "gestao_comercial_configuracoes/{lojaId}",
        region: "southamerica-east1",
    },
    async (event) => {
        const depois = event.data?.after?.data();
        if (!depois) return;
        const sms = (depois.cobranca || {}).sms;
        if (!sms || typeof sms !== "object") return;
        const token = String(sms.token || "").trim();
        if (!token || token.startsWith("enc:v1:")) return;
        if (!_emailHelpers || !_emailHelpers.encryptSecret) return;
        const encToken = _emailHelpers.encryptSecret(token);
        if (!encToken) return;
        await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(event.params.lojaId)
            .set({ cobranca: { sms: { token: encToken } } }, { merge: true });
    },
);

// =============================================================================
// 16. API EXTERNA — ENVIO DE COBRANÇA
// =============================================================================

/**
 * Testa a conexão com a API externa.
 * Recebe: { lojaId }
 */
exports.gestaoComercialApiExternaTestarConexao = onCall(
    Object.assign({}, CONFIG_PADRAO, {
        enforceAppCheck: false,
        consumeAppCheckToken: false,
    }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Sessao expirada. Faca login novamente no painel e tente outra vez.",
            );
        }
        await assertGestaoComercialAccess(admin.firestore(), request);
        const lojaId = String((request.data || {}).lojaId || "").trim();
        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");

        const snap = await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId).get();
        const canal = ((snap.data() || {}).cobranca || {}).api_externa || {};
        const apiUrl = String(canal.apiUrl || "").trim();
        const token = _decryptToken(canal.token);

        if (!apiUrl) return { ok: false, mensagem: "URL do endpoint nao informada." };
        if (!token) return { ok: false, mensagem: "Token / API Key nao configurada." };

        const headers = { "Content-Type": "application/json", Accept: "application/json", Authorization: "Bearer " + token };

        try {
            const r = await _httpReq(apiUrl.replace(/\/+$/, "") + "/ping", { method: "GET", headers, timeout: 10000 });
            if (r.status >= 200 && r.status < 500) {
                return { ok: true, mensagem: "Conexao realizada. Status HTTP: " + r.status };
            }
            return { ok: false, mensagem: "API retornou status " + r.status + "." };
        } catch (err) {
            const m = String(err && err.message ? err.message : err);
            if (/ENOTFOUND|getaddrinfo/i.test(m)) return { ok: false, mensagem: "Host nao encontrado (" + apiUrl + ")." };
            if (/ECONNREFUSED/i.test(m)) return { ok: false, mensagem: "Servidor recusou conexao." };
            // GET pode falhar se endpoint so aceita POST; tentamos POST como fallback
            try {
                const r2 = await _httpReq(apiUrl.replace(/\/+$/, ""), {
                    method: "POST",
                    headers,
                    timeout: 10000,
                }, { ping: true });
                if (r2.status >= 200 && r2.status < 500) {
                    return { ok: true, mensagem: "Conexao realizada (POST). Status: " + r2.status };
                }
            } catch (_) {}
            return { ok: false, mensagem: m };
        }
    },
);

/**
 * Envia cobrança via API externa (HTTP POST genérico).
 * Recebe: { lojaId, destino, variaveis: { cliente, valor, vencimento, link, ... } }
 */
exports.gestaoComercialApiExternaEnviar = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login necessario.");
        await assertGestaoComercialAccess(admin.firestore(), request);
        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const destino = String(data.destino || "").trim();
        const variaveis = data.variaveis || {};

        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        if (!destino) throw new HttpsError("invalid-argument", "Destino e obrigatorio.");

        const snap = await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId).get();
        const canal = ((snap.data() || {}).cobranca || {}).api_externa || {};
        const apiUrl = String(canal.apiUrl || "").replace(/\/+$/, "");
        const token = _decryptToken(canal.token);
        const remetente = String(canal.remetente || "").trim();
        const template = String(canal.templateMensagem || "").trim();

        if (!apiUrl) throw new HttpsError("failed-precondition", "URL do endpoint nao configurada.");
        if (!token) throw new HttpsError("failed-precondition", "Token / API Key nao configurada.");

        const vars = Object.assign({}, variaveis, {
            cliente: variaveis.cliente || "Cliente",
            loja: variaveis.loja || "",
            valor: variaveis.valor || "",
            vencimento: variaveis.vencimento || "",
            link: variaveis.link || "",
            dias_atraso: variaveis.dias_atraso || "",
        });

        let mensagem = template;
        for (const [k, v] of Object.entries(vars)) {
            mensagem = mensagem.split("{" + k + "}").join(String(v ?? ""));
        }

        const headers = { "Content-Type": "application/json", Authorization: "Bearer " + token };

        const body = {
            to: String(destino).replace(/\D/g, ""),
            message: mensagem,
            sender: remetente,
            template: mensagem,
            ...vars,
        };

        try {
            const r = await _httpReq(apiUrl, { method: "POST", headers }, body);
            const resposta = (() => { try { return JSON.stringify(JSON.parse(r.body)).substring(0, 500); } catch (_) { return String(r.body || "").substring(0, 500); } })();
            if (r.status >= 200 && r.status < 300) {
                return { ok: true, mensagem: "Mensagem enviada com sucesso via API externa.", statusHttp: r.status };
            }
            return { ok: false, mensagem: "API retornou status " + r.status + ".", detalhe: resposta };
        } catch (err) {
            return { ok: false, mensagem: "Erro ao enviar: " + String(err && err.message ? err.message : err) };
        }
    },
);

/**
 * Firestore trigger: criptografa token da API Externa se estiver em texto puro.
 */
exports.gestaoComercialApiExternaEncryptTokenOnWrite = onDocumentWritten(
    {
        document: "gestao_comercial_configuracoes/{lojaId}",
        region: "southamerica-east1",
    },
    async (event) => {
        const depois = event.data?.after?.data();
        if (!depois) return;
        const apiExterna = (depois.cobranca || {}).api_externa;
        if (!apiExterna || typeof apiExterna !== "object") return;
        const token = String(apiExterna.token || "").trim();
        if (!token || token.startsWith("enc:v1:")) return;
        if (!_emailHelpers || !_emailHelpers.encryptSecret) return;
        const encToken = _emailHelpers.encryptSecret(token);
        if (!encToken) return;
        await admin.firestore()
            .collection("gestao_comercial_configuracoes")
            .doc(event.params.lojaId)
            .set({ cobranca: { api_externa: { token: encToken } } }, { merge: true });
    },
);

// =============================================================================
// 17. AUTOMAÇÃO DE COBRANÇA — REGRAS AUTOMÁTICAS
// =============================================================================

/**
 * Envia notificação de cobrança via um canal configurado.
 * Suporta: whatsapp, sms, api_externa
 */
async function _enviarNotificacaoCanal(lojaId, canal, destino, mensagem, variaveis) {
    const db = admin.firestore();
    const snap = await db.collection("gestao_comercial_configuracoes").doc(lojaId).get();
    const cfg = snap.data() || {};
    const canais = (cfg.cobranca || {})[canal] || {};
    const template = mensagem;

    if (!template) return { ok: false, erro: "Template vazio" };

    let msg = template;
    for (const [k, v] of Object.entries(variaveis || {})) {
        msg = msg.split("{" + k + "}").join(String(v ?? ""));
    }

    try {
        switch (canal) {
            case "whatsapp": {
                const wa = _resolverCredenciaisWhatsApp(canais, null);
                if (wa.provedor === "vzaps") {
                    if (!wa.instanceId || !wa.clientToken || !wa.token) {
                        return { ok: false, erro: "Canal WhatsApp (VZaps) nao configurado. Abra Configuracoes → WhatsApp e salve a integracao." };
                    }
                } else if (!wa.apiUrl || !wa.token) {
                    return { ok: false, erro: "Canal WhatsApp nao configurado." };
                }
                const extras = {
                    instanceId: wa.instanceId,
                    clientToken: wa.clientToken,
                    authMethod: wa.authMethod,
                    endpointEnvio: wa.endpointEnvio,
                };
                const url = _montarUrlEnvioWhatsApp(wa.provedor, wa.apiUrl, wa.remetente, extras);
                const headers = _montarHeadersWhatsApp(wa.provedor, wa.token, extras);
                const body = _montarPayloadWhatsApp(wa.provedor, wa.remetente, msg, destino);
                const phoneNorm = body.phone || body.to || body.number || "";
                console.log("[gc-whatsapp] envio", {
                    provedor: wa.provedor,
                    url,
                    destinoOriginal: String(destino || "").replace(/\d(?=\d{4})/g, "*"),
                    destinoNormalizado: String(phoneNorm).replace(/\d(?=\d{4})/g, "*"),
                    instanceId: wa.instanceId || null,
                });
                const r = await _httpReq(url, { method: "POST", headers }, body);
                const interpretado = _interpretarRespostaEnvioWhatsApp(wa.provedor, r);
                console.log("[gc-whatsapp] resposta", {
                    provedor: wa.provedor,
                    status: r.status,
                    ok: interpretado.ok,
                    messageId: interpretado.messageId || null,
                    erro: interpretado.erro || null,
                });
                return interpretado;
            }
            case "sms": {
                const apiUrl = String(canais.apiUrl || "https://sms.comtele.com.br/api/v2").trim();
                const token = _decryptToken(canais.token);
                const remetente = String(canais.remetente || "").trim();
                if (!token) return { ok: false, erro: "Canal SMS nao configurado (Auth Key Comtele)." };
                const base = apiUrl.replace(/\/+$/, "") || "https://sms.comtele.com.br/api/v2";
                const number = String(destino).replace(/\D/g, "");
                const phone = number.startsWith("55") ? number : ("55" + number);
                const smsMsg = msg
                    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
                    .replace(/[^\x20-\x7E\n\r]/g, "").substring(0, 160);
                const sender = remetente.replace(/[^\x20-\x7E]/g, "").substring(0, 11) || "DiPertin";
                const r = await _httpReq(base + "/send", {
                    method: "POST",
                    headers: { "Content-Type": "application/json", "auth-key": token },
                }, {
                    Sender: sender,
                    Receivers: phone,
                    Content: smsMsg,
                });
                const parsed = (() => {
                    try { return JSON.parse(String(r.body || "{}")); }
                    catch (_) { return null; }
                })();
                const ok = r.status >= 200 && r.status < 300 && !(
                    parsed && (parsed.Success === false || parsed.success === false)
                );
                const erro = ok ? null : (
                    (parsed && (parsed.Message || parsed.message))
                    || ("Falha Comtele HTTP " + r.status)
                );
                return { ok, status: r.status, erro };
            }
            case "api_externa": {
                const apiUrl = String(canais.apiUrl || "").trim();
                const token = _decryptToken(canais.token);
                const remetente = String(canais.remetente || "").trim();
                if (!apiUrl || !token) return { ok: false, erro: "Canal nao configurado" };
                const base = apiUrl.replace(/\/+$/, "");
                const r = await _httpReq(base, {
                    method: "POST",
                    headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
                }, { to: destino, message: msg, sender: remetente, ...variaveis });
                return { ok: r.status >= 200 && r.status < 300, status: r.status };
            }
            default:
                return { ok: false, erro: "Canal desconhecido: " + canal };
        }
    } catch (err) {
        return { ok: false, erro: String(err && err.message ? err.message : err) };
    }
}

/**
 * Processa as regras automáticas de cobrança para uma loja.
 * Retorna { processados: number, erros: number, detalhes: [] }
 */
async function _processarAutomacaoLoja(lojaId) {
    const db = admin.firestore();
    const configSnap = await db.collection("gestao_comercial_configuracoes").doc(lojaId).get();
    const cfg = configSnap.data() || {};
    const regras = cfg.regrasAutomaticas || {};
    const canaisCobranca = cfg.cobranca || {};

    // Verifica se há pelo menos uma regra ativa
    const temRegraAtiva = regras.lembreteAntes || regras.lembreteNoVencimento || regras.lembreteApos || regras.bloquearCreditoAutomaticamente;
    if (!temRegraAtiva) return { processados: 0, erros: 0, detalhes: [] };

    // Identifica canais ativos para envio
    const canaisAtivos = [];
    for (const [chave, canal] of Object.entries(canaisCobranca)) {
        if (canal && canal.ativo && canal.templateMensagem) {
            canaisAtivos.push(chave);
        }
    }

    // Busca parcelas pendentes
    const parcelasSnap = await db
        .collection("parcelas_cliente")
        .where("loja_id", "==", lojaId)
        .where("status", "in", ["pendente", "vencido", "parcial"])
        .get();

    if (parcelasSnap.empty) return { processados: 0, erros: 0, detalhes: [] };

    const agora = new Date();
    const hoje = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
    const hojeMs = hoje.getTime();
    const DIA_MS = 86400000;

    let processados = 0;
    let erros = 0;
    const detalhes = [];

    for (const doc of parcelasSnap.docs) {
        const p = doc.data() || {};
        const venc = p.data_vencimento?.toDate ? p.data_vencimento.toDate() : p.data_vencimento ? new Date(p.data_vencimento) : null;
        if (!venc || isNaN(venc.getTime())) continue;

        const vencMs = new Date(venc.getFullYear(), venc.getMonth(), venc.getDate()).getTime();
        const diasAteVenc = Math.round((vencMs - hojeMs) / DIA_MS);
        const diasAtraso = Math.round((hojeMs - vencMs) / DIA_MS);
        const ultimoLembrete = p.ultimo_lembrete_enviado_em?.toDate ? p.ultimo_lembrete_enviado_em.toDate() : null;

    // Busca nome da loja
    let nomeLoja = "Loja";
    try {
        const userSnap = await db.collection("users").doc(lojaId).get();
        if (userSnap.exists) {
            const u = userSnap.data() || {};
            nomeLoja = u.nome_loja || u.nome_fantasia || u.nome || lojaId;
        }
    } catch (_) {}

    const variaveis = {
        cliente: p.cliente_nome || "Cliente",
        loja: nomeLoja,
            valor: "R$ " + Number(p.valor || p.valor_parcela || 0).toFixed(2),
            vencimento: _fmtDataBR(venc),
            link: (function() {
                // Tenta gerar um token de pagamento único
                try {
                    const crypto = require("crypto");
                    const tokenRaw = crypto.randomBytes(24).toString("hex");
                    const tokenHash = crypto.createHash("sha256").update(tokenRaw).digest("hex");
                    const agora = new Date();
                    // Salva o token no Firestore (sem bloquear o fluxo)
                    db.collection("gestao_comercial_tokens_pagamento").doc(tokenHash).set({
                        loja_id: lojaId, cliente_id: p.cliente_id || "",
                        cliente_nome: p.cliente_nome || "Cliente",
                        cliente_cpf: "",
                        loja_nome: nomeLoja,
                        token_hash: tokenHash,
                        parcelas: [{ id: doc.id, valor_parcela: Number(p.valor_parcela || 0), valor_em_aberto: Number(p.valor_em_aberto || p.valor_parcela || 0), data_vencimento: p.data_vencimento || null, numero_parcela: Number(p.numero_parcela || 1), total_parcelas: Number(p.total_parcelas || 1) }],
                        valor_total: Number(p.valor_em_aberto || p.valor_parcela || 0),
                        status: "ativo", criado_em: admin.firestore.FieldValue.serverTimestamp(),
                        expira_em: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
                    }).catch(function(e) { console.error("[gc-auto] Erro criar token:" + e); });
                    const baseLink = String(cfg.cobranca?.link_pagamento || "").trim() || "https://www.dipertin.com.br";
                    return baseLink.replace(/\/+$/, "") + "/pagar?token=" + tokenRaw;
                } catch (e) { return cfg.cobranca?.link_pagamento || ""; }
            })(),
            dias_atraso: String(Math.max(0, diasAtraso)),
            parcela: String(p.numero_parcela || 1) + "/" + String(p.total_parcelas || 1),
        };

        let motivo = "";
        let deveEnviar = false;

        // Regra 1: Lembrete antes do vencimento
        if (regras.lembreteAntes && diasAteVenc > 0 && diasAteVenc <= (regras.diasAntes || 3)) {
            deveEnviar = true;
            motivo = "lembrete_antes";
        }

        // Regra 2: Lembrete no vencimento
        if (regras.lembreteNoVencimento && diasAteVenc === 0) {
            deveEnviar = true;
            motivo = "lembrete_vencimento";
        }

        // Regra 3: Lembrete após vencimento (com repetição)
        if (regras.lembreteApos && diasAtraso >= (regras.diasApos || 1)) {
            const intervalo = regras.repetirACadaDias || 3;
            if (!ultimoLembrete || (hojeMs - ultimoLembrete.getTime()) >= intervalo * DIA_MS) {
                deveEnviar = true;
                motivo = "lembrete_apos";
            }
        }

        if (!deveEnviar) continue;

        // Envia notificação via todos os canais ativos
        const envios = [];
        for (const canal of canaisAtivos) {
            const template = (canaisCobranca[canal] || {}).templateMensagem || "";
            if (!template) continue;
            const telefone = String(p.cliente_telefone || p.cliente_whatsapp || "").trim();
            if (!telefone) {
                detalhes.push({ parcelaId: doc.id, canal, erro: "Sem telefone do cliente" });
                erros++;
                continue;
            }
            const resultado = await _enviarNotificacaoCanal(lojaId, canal, telefone, template, variaveis);
            envios.push({ canal, ok: resultado.ok });
            if (!resultado.ok) {
                detalhes.push({ parcelaId: doc.id, canal, erro: resultado.erro || "Falha no envio" });
                erros++;
            }
        }

        // Marca ultimo lembrete
        if (envios.some(e => e.ok)) {
            await db.collection("parcelas_cliente").doc(doc.id).update({
                ultimo_lembrete_enviado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            processados++;
        }

        // Regra 4: Bloqueio automático de crédito
        if (regras.bloquearCreditoAutomaticamente && diasAtraso >= (regras.bloquearAposDias || 15)) {
            const clienteId = p.cliente_id;
            if (clienteId) {
                const clienteDoc = await db.collection("users").doc(lojaId).collection("clientes_comercial").doc(clienteId).get();
                const jaBloqueado = clienteDoc.exists && clienteDoc.data()?.credito_bloqueado_em != null;

                if (!jaBloqueado) {
                    await db.collection("users").doc(lojaId).collection("clientes_comercial").doc(clienteId).set({
                        loja_id: lojaId,
                        credito_bloqueado_em: admin.firestore.FieldValue.serverTimestamp(),
                        credito_bloqueado_motivo: "Bloqueio automático por atraso superior a " + (regras.bloquearAposDias || 15) + " dias",
                    }, { merge: true });

                    if (regras.enviarAvisoBloqueio && canaisAtivos.length > 0) {
                        const avisoVars = {
                            cliente: p.cliente_nome || "Cliente",
                            loja: nomeLoja,
                            dias_atraso: String(diasAtraso),
                        };
                        for (const canal of canaisAtivos) {
                            const avisoTemplate = "Olá {cliente}, seu crédito foi bloqueado por atraso de {dias_atraso} dias. Procure a {loja} para regularizar.";
                            const telefone = String(p.cliente_telefone || p.cliente_whatsapp || "").trim();
                            if (telefone) {
                                await _enviarNotificacaoCanal(lojaId, canal, telefone, avisoTemplate, avisoVars);
                            }
                        }
                    }
                }
            }
        }
    }

    return { processados, erros, detalhes };
}

/**
 * Scheduled (diário): processa as regras automáticas de TODAS as lojas.
 * Executa diariamente às 08:00 (horário de Brasília).
 */
exports.gestaoComercialAutomacaoProcessar = onSchedule(
    {
        schedule: "0 8 * * *",
        timeZone: "America/Sao_Paulo",
        region: "southamerica-east1",
        memory: "512MiB",
        timeoutSeconds: 300,
        maxInstances: 1,
    },
    async () => {
        const db = admin.firestore();
        const snap = await db.collection("gestao_comercial_configuracoes").get();
        const resultados = [];
        for (const doc of snap.docs) {
            try {
                const r = await _processarAutomacaoLoja(doc.id);
                if (r.processados > 0 || r.erros > 0) {
                    resultados.push({ lojaId: doc.id, ...r });
                }
            } catch (err) {
                resultados.push({ lojaId: doc.id, erro: String(err && err.message ? err.message : err) });
            }
        }
        console.log("Automacao processada:", JSON.stringify(resultados));
        return resultados;
    },
);

/**
 * OnCall: processa as regras automáticas de uma loja específica (manual).
 * Recebe: { lojaId }
 */
exports.gestaoComercialAutomacaoProcessarLoja = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        if (!request.auth) throw new HttpsError("unauthenticated", "Login necessario.");
        await assertGestaoComercialAccess(admin.firestore(), request);
        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");

        const resultado = await _processarAutomacaoLoja(lojaId);
        return resultado;
    },
);

// =============================================================================
// 18. ENVIO INTEGRADO DE COBRANÇA / COMPROVANTE
// =============================================================================

/**
 * Envia cobrança ou comprovante para um cliente via um ou mais canais.
 *
 * Entrada: { lojaId, clienteId, tipo ("cobranca"|"comprovante"), canais (["whatsapp","sms","email"]) }
 *
 * Para cada canal ativo:
 *  - whatsapp / sms: usa o template do canal + variáveis
 *  - email: carrega o template transacional (cobranca ou pagamento_recebido)
 *
 * Grava tudo em gestao_comercial_comunicacoes_historico/{lojaId}/envios/{autoId}.
 */
exports.gestaoComercialEnviarComunicacao = onCall(
    Object.assign({}, CONFIG_PADRAO, {
        enforceAppCheck: false,
        consumeAppCheckToken: false,
    }),
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Login necessario.");
        }
        const acesso = await assertGestaoComercialAccess(admin.firestore(), request);
        const data = request.data || {};
        const lojaId = String(data.lojaId || "").trim();
        const clienteId = String(data.clienteId || "").trim();
        const tipo = String(data.tipo || "").trim();
        const canais = Array.isArray(data.canais) ? data.canais : [];

        if (!lojaId) throw new HttpsError("invalid-argument", "lojaId e obrigatorio.");
        if (!clienteId) throw new HttpsError("invalid-argument", "clienteId e obrigatorio.");
        if (!tipo || !["cobranca", "comprovante"].includes(tipo)) throw new HttpsError("invalid-argument", "tipo deve ser 'cobranca' ou 'comprovante'.");
        if (canais.length === 0) throw new HttpsError("invalid-argument", "Selecione ao menos um canal.");

        // Garante que o lojista só envia pela própria loja (dono ou loja do colaborador).
        if (lojaId !== acesso.lojaId) {
            throw new HttpsError(
                "permission-denied",
                "Sem permissao para enviar cobranca desta loja."
            );
        }

        console.log("[gc-envio] inicio", {
            uid: request.auth.uid,
            lojaId,
            clienteId,
            tipo,
            canais,
        });

        const db = admin.firestore();
        const emailHelpers = _emailHelpers;

        // ── 1. Carregar dados do cliente ──
        const clienteSnap = await db
            .collection("users").doc(lojaId)
            .collection("clientes_comercial").doc(clienteId)
            .get();
        if (!clienteSnap.exists) throw new HttpsError("not-found", "Cliente nao encontrado.");
        const cliente = clienteSnap.data() || {};

        const clienteNome = cliente.nome || cliente.razao_social || cliente.cliente_nome || "Cliente";
        const clienteTelefone = String(cliente.telefone || cliente.whatsapp || cliente.celular || "").trim();
        const clienteEmail = String(cliente.email || "").trim();
        const clienteWhatsApp = String(cliente.whatsapp || cliente.telefone || "").trim();

        // ── 2. Carregar dados da loja ──
        const lojaSnap = await db.collection("users").doc(lojaId).get();
        const lojaData = lojaSnap.data() || {};
        const lojaNome = lojaData.nome_loja || lojaData.nome_fantasia || lojaData.nome || "Loja";
        const lojaWhatsApp = String(lojaData.whatsapp || lojaData.telefone || "").trim();
        const lojaTelefone = String(lojaData.telefone || "").trim();
        const lojaSite = String(lojaData.site || "").trim() || "https://www.dipertin.com.br";
        const lojaLogo = String(lojaData.foto || lojaData.foto_perfil || lojaData.foto_logo || "").trim();

        // ── 3. Carregar config (canais, regras, link pagamento) ──
        const configSnap = await db.collection("gestao_comercial_configuracoes").doc(lojaId).get();
        const configData = configSnap.data() || {};
        const cobrancaConfig = configData.cobranca || {};

        // ── 3b. Carregar dados do cliente a partir de clientes_comercial para ter CPF ──
        let clienteCpf = "";
        let clienteData = null;
        try {
            const cliSnap = await db
                .collection("users").doc(lojaId)
                .collection("clientes_comercial").doc(clienteId)
                .get();
            if (cliSnap.exists) {
                clienteData = cliSnap.data() || {};
                clienteCpf = String(clienteData.cpf || "").trim();
            }
        } catch (_) {}

        // ── 4. Buscar parcelas pendentes para calcular valores (apenas cobranca) ──
        let valorTotalAberto = 0;
        let dataVencimentoRef = null;
        let vencimentoStr = "";
        let qtdParcelas = 0;
        let parcelasCobranca = []; // armazena parcelas para o token

        if (tipo === "cobranca") {
            try {
                const parcelasSnap = await db
                    .collection("users").doc(lojaId)
                    .collection("parcelas_cliente")
                    .where("status", "in", ["pendente", "vencido", "parcial", "em_aberto", "vence_hoje", "vence_em_breve"])
                    .get();

                parcelasSnap.forEach(function (doc) {
                    const p = doc.data() || {};
                    const pClienteId = String(p.cliente_id || "").trim();
                    if (pClienteId !== clienteId) return;

                    qtdParcelas++;
                    const v = Number(p.valor || p.valor_parcela || 0);
                    const pend = Number(p.valor_em_aberto !== undefined ? p.valor_em_aberto : v);
                    if (pend > 0) valorTotalAberto += pend;
                    if (!dataVencimentoRef) {
                        const dv = p.data_vencimento && typeof p.data_vencimento.toDate === "function"
                            ? p.data_vencimento.toDate()
                            : p.data_vencimento ? new Date(p.data_vencimento) : null;
                        if (dv && !isNaN(dv.getTime())) dataVencimentoRef = dv;
                    }
                    // Guarda snapshot das parcelas
                    parcelasCobranca.push({
                        id: doc.id,
                        cliente_id: p.cliente_id || clienteId,
                        valor_parcela: v,
                        valor_em_aberto: pend,
                        data_vencimento: p.data_vencimento || null,
                        codigo_venda: String(p.codigo_venda || "").trim(),
                        numero_parcela: Number(p.numero_parcela || 1),
                        total_parcelas: Number(p.total_parcelas || 1),
                    });
                });
            } catch (_) {
                // Fallback: parcelas podem nao existir
            }
        }

        if (dataVencimentoRef) {
            vencimentoStr = _fmtDataBR(dataVencimentoRef);
        }

        // ── 4b. Gerar token seguro de pagamento (apenas cobranca) ──
        let linkPagamento = String(cobrancaConfig.link_pagamento || "").trim() || lojaSite;
        let tokenId = "";
        if (tipo === "cobranca" && parcelasCobranca.length > 0) {
            try {
                const crypto = require("crypto");
                const tokenRaw = crypto.randomBytes(24).toString("hex");
                const tokenHash = crypto.createHash("sha256").update(tokenRaw).digest("hex");
                tokenId = tokenHash; // hash do token como ID do documento

                // Salva em coleção de tokens de pagamento
                const tokenDoc = {
                    loja_id: lojaId,
                    cliente_id: clienteId,
                    cliente_nome: clienteNome,
                    cliente_cpf: clienteCpf,
                    loja_nome: lojaNome,
                    loja_telefone: lojaTelefone,
                    loja_logo: lojaLogo,
                    token_hash: tokenHash,
                    token_raw: null, // não guarda raw por segurança
                    parcelas: parcelasCobranca,
                    valor_total: valorTotalAberto,
                    qtd_parcelas: qtdParcelas,
                    status: "ativo", // ativo | usado | expirado
                    criado_em: admin.firestore.FieldValue.serverTimestamp(),
                    expira_em: admin.firestore.Timestamp.fromDate(
                        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // 30 dias
                    ),
                };

                await db.collection("gestao_comercial_tokens_pagamento").doc(tokenHash).set(tokenDoc);

                // Só guarda o raw na resposta (nunca no Firestore)
                const linkCompleto = (linkPagamento.endsWith("/") ? linkPagamento : linkPagamento + "/")
                    + "pagar?token=" + tokenRaw;
                linkPagamento = linkCompleto;
            } catch (tokenErr) {
                console.error("[gc-envio] Erro ao gerar token:", tokenErr);
            }
        }

        // ── 5. Montar variáveis ──
        const agora = new Date();
        const variaveis = {
            cliente: clienteNome,
            loja: lojaNome,
            valor: "R$ " + valorTotalAberto.toFixed(2).replace(".", ","),
            valor_total: "R$ " + valorTotalAberto.toFixed(2).replace(".", ","),
            vencimento: vencimentoStr || "—",
            telefone: clienteTelefone || lojaTelefone,
            whatsapp: clienteWhatsApp || lojaWhatsApp,
            site: lojaSite,
            link_pagamento: linkPagamento,
            link: linkPagamento, // alias
            data: _fmtDataBR(agora),
            hora: _fmtHoraBR(agora),
            qtd_parcelas: String(qtdParcelas),
        };

        // ── 6. Enviar por cada canal ──
        const resultados = [];

        for (const canal of canais) {
            const canalConfig = cobrancaConfig[canal] || {};
            const templateCanal = String(canalConfig.templateMensagem || "").trim();

            if (canal === "whatsapp") {
                const destino = clienteWhatsApp;
                if (!destino) {
                    resultados.push({ canal, ok: false, erro: "Cliente nao possui WhatsApp cadastrado." });
                    continue;
                }
                if (!templateCanal) {
                    resultados.push({ canal, ok: false, erro: "Template de cobranca WhatsApp nao configurado." });
                    continue;
                }
                const r = await _enviarNotificacaoCanal(lojaId, "whatsapp", destino, templateCanal, variaveis);
                resultados.push({
                    canal,
                    ok: r.ok,
                    erro: r.erro || null,
                    status: r.status || null,
                    messageId: r.messageId || null,
                });
            }

            else if (canal === "sms") {
                const destino = clienteTelefone;
                if (!destino) {
                    resultados.push({ canal, ok: false, erro: "Cliente nao possui telefone cadastrado." });
                    continue;
                }
                if (!templateCanal) {
                    resultados.push({ canal, ok: false, erro: "Template de SMS nao configurado." });
                    continue;
                }
                const r = await _enviarNotificacaoCanal(lojaId, "sms", destino, templateCanal, variaveis);
                resultados.push({ canal, ok: r.ok, erro: r.erro || null });
            }

            else if (canal === "email") {
                const destino = clienteEmail;
                if (!destino) {
                    resultados.push({ canal, ok: false, erro: "Cliente nao possui e-mail cadastrado." });
                    continue;
                }
                if (!emailHelpers || !emailHelpers.enviarEmailLoja) {
                    resultados.push({ canal, ok: false, erro: "Servico de e-mail nao disponivel." });
                    continue;
                }
                try {
                    const slug = tipo === "comprovante" ? "pagamento_recebido" : "cobranca";

                    // Carregar template
                    const tplSnap = await db
                        .collection("gestao_comercial_email_templates")
                        .doc(lojaId)
                        .collection("templates")
                        .doc(slug)
                        .get();
                    const tplData = tplSnap.data() || {};
                    const blocks = tplData.blocks;
                    const identidade = tplData.identidadeVisual || {};
                    const assuntoTpl = String(tplData.assunto || (tipo === "comprovante" ? "Pagamento recebido - {loja}" : "Cobranca - {loja}")).trim();

                    // REGRA: Nunca usar html_preview para envio real!
                    // html_preview contém valores fictícios pré-renderizados (Maria Silva, etc.)
                    // que NÃO podem ser substituídos por dados reais.
                    //
                    // 1. Se blocks existirem → renderizar com variáveis reais
                    // 2. Se não → fallback inline com variáveis reais
                    let html = "";
                    let textContent = "";

                    if (Array.isArray(blocks) && blocks.length) {
                        html = emailHelpers.blocksToHtml(blocks, variaveis, identidade, assuntoTpl);
                        // Texto plano a partir dos blocks, com variáveis substituídas
                        textContent = emailHelpers.textoLegadoFromBlocks(blocks);
                        if (typeof textContent === "string" && textContent) {
                            textContent = emailHelpers.substituirVariaveis(textContent, variaveis);
                        }
                    } else {
                        // Fallback inline — usa sempre dados reais
                        const corPrincipal = identidade.corPrincipal || "#6A1B9A";
                        const logoUrl = identidade.logoUrl || "";
                        const nomeLoja = identidade.nomeLoja || lojaNome;

                        const logoHtml = logoUrl
                            ? '<img src="' + logoUrl + '" alt="" style="max-height:48px;margin-bottom:16px;" />'
                            : "";

                        const botaoHtml = linkPagamento && tipo === "cobranca"
                            ? '<p style="text-align:center;margin:24px 0;"><a href="' + linkPagamento + '" style="background:' + corPrincipal + ";color:#fff;text-decoration:none;padding:14px 28px;border-radius:8px;font-weight:bold;font-family:Arial,sans-serif;display:inline-block;\">Pagar Agora</a></p>"
                            : "";

                        const corpoMsg = tipo === "cobranca"
                            ? "<p>Olá <strong>" + clienteNome + "</strong>,</p><p>Você possui uma cobrança pendente no valor de <strong>" + variaveis.valor + "</strong> com vencimento em <strong>" + vencimentoStr + "</strong>.</p><p>Clique no botão abaixo para acessar sua cobrança e realizar o pagamento de forma segura.</p>"
                            : "<p>Olá <strong>" + clienteNome + "</strong>,</p><p>Recebemos o pagamento no valor de <strong>" + variaveis.valor + "</strong>.</p><p>Agradecemos pela preferência!</p>";

                        html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>' + assuntoTpl.replace(/<[^>]*>/g, "") + '</title></head>'
                            + '<body style="margin:0;padding:0;background:#F5F4F8;">'
                            + '<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 16px;">'
                            + '<table width="100%" style="max-width:560px;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(106,27,154,0.1);">'
                            + '<tr><td style="background:linear-gradient(135deg,' + corPrincipal + ',' + corPrincipal + "dd);padding:32px 24px;text-align:center;\">"
                            + logoHtml
                            + '<h1 style="font-family:Arial,sans-serif;color:#fff;font-size:22px;margin:0;">' + (tipo === "cobranca" ? "Cobrança" : "Pagamento recebido") + "</h1>"
                            + '<p style="font-family:Arial,sans-serif;color:rgba(255,255,255,0.85);font-size:14px;margin:8px 0 0;">' + nomeLoja + "</p>"
                            + '</td></tr>'
                            + '<tr><td style="padding:32px 24px;font-family:Arial,sans-serif;color:#1A1A2E;font-size:15px;line-height:1.6;">'
                            + corpoMsg
                            + botaoHtml
                            + '</td></tr>'
                            + '<tr><td style="padding:16px 24px 24px;font-family:Arial,sans-serif;color:#64748B;font-size:12px;line-height:1.5;text-align:center;">'
                            + "Recebeu este e-mail porque possui cadastro na loja.<br>"
                            + nomeLoja
                            + '</td></tr>'
                            + '</table></td></tr></table></body></html>';

                        // Texto plano do fallback
                        const textoBase = tipo === "cobranca"
                            ? "Olá " + clienteNome + ",\n\nVocê possui uma cobrança pendente no valor de " + variaveis.valor + " com vencimento em " + vencimentoStr + ".\n\nAcesse o link para pagar: " + (linkPagamento || "entre em contato conosco") + "\n\n" + nomeLoja
                            : "Olá " + clienteNome + ",\n\nRecebemos o pagamento no valor de " + variaveis.valor + ".\n\nAgradecemos pela preferência!\n\n" + nomeLoja;
                        textContent = textoBase;
                    }

                    const assunto = emailHelpers.substituirVariaveis ?
                        emailHelpers.substituirVariaveis(assuntoTpl, variaveis) :
                        assuntoTpl;

                    const r = await emailHelpers.enviarEmailLoja(lojaId, destino, assunto, html, textContent, slug);
                    resultados.push({ canal, ok: true, messageId: r.messageId, tempoMs: r.tempoMs });
                } catch (err) {
                    const errMsg = emailHelpers.mapSmtpError ? emailHelpers.mapSmtpError(err) : (err && err.message ? err.message : String(err));
                    resultados.push({ canal, ok: false, erro: errMsg });
                }
            }
        }

        // ── 7. Gravar histórico ──
        const historicoRef = db
            .collection("gestao_comercial_comunicacoes_historico")
            .doc(lojaId)
            .collection("envios")
            .doc();

        const operadorNome = request.auth.token?.name || request.auth.uid;

        await historicoRef.set({
            loja_id: lojaId,
            cliente_id: clienteId,
            cliente_nome: clienteNome,
            tipo: tipo,
            canais_solicitados: canais,
            resultados: resultados,
            variaveis_utilizadas: variaveis,
            operador_uid: request.auth.uid,
            operador_nome: operadorNome,
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
            ok: resultados.some(function (r) { return r.ok; }),
            resultados: resultados,
            historicoId: historicoRef.id,
            linkPagamento: linkPagamento,
        };
    },
);

// =============================================================================
// Token de pagamento — consultar cobrança via token (sem auth)
// Usado pela página pública de pagamento (site/pagar/)
// =============================================================================

exports.gestaoComercialConsultarCobrancaPorToken = onRequest(
    Object.assign({}, CONFIG_PADRAO),
    async (req, res) => {
        res.set("Cache-Control", "no-store");
        res.set("Access-Control-Allow-Origin", "https://www.dipertin.com.br");
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type");

        if (req.method === "OPTIONS") { return res.status(204).send(""); }
        if (req.method !== "POST") { return res.status(405).send("Method Not Allowed"); }

        let body = {};
        try {
            body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {});
        } catch (e) {
            return res.status(400).json({ ok: false, erro: "JSON invalido" });
        }

        const tokenRaw = String(body.token || "").trim();
        if (!tokenRaw) { return res.status(400).json({ ok: false, erro: "Token obrigatorio" }); }

        const crypto = require("crypto");
        const tokenHash = crypto.createHash("sha256").update(tokenRaw).digest("hex");

        try {
            const tokenDoc = await admin.firestore().collection("gestao_comercial_tokens_pagamento").doc(tokenHash).get();
            if (!tokenDoc.exists) {
                return res.status(404).json({ ok: false, erro: "Link de pagamento invalido ou expirado." });
            }

            const data = tokenDoc.data() || {};
            if (data.status !== "ativo") {
                return res.status(410).json({ ok: false, erro: "Este link de pagamento ja foi utilizado ou expirou.", status: data.status });
            }
            if (data.expira_em && data.expira_em.toMillis) {
                if (Date.now() > data.expira_em.toMillis()) {
                    return res.status(410).json({ ok: false, erro: "Este link de pagamento expirou. Solicite um novo." });
                }
            }

            const parcelas = (data.parcelas || []).map(function (p) {
                return {
                    id: p.id,
                    valor_parcela: p.valor_parcela,
                    valor_em_aberto: p.valor_em_aberto,
                    data_vencimento: p.data_vencimento ? _fmtTSOuString(p.data_vencimento) : null,
                    codigo_venda: p.codigo_venda,
                    numero_parcela: p.numero_parcela,
                    total_parcelas: p.total_parcelas,
                };
            });

            return res.json({
                ok: true,
                loja_nome: data.loja_nome,
                loja_logo: data.loja_logo || "",
                cliente_nome: data.cliente_nome,
                valor_total: data.valor_total,
                qtd_parcelas: data.qtd_parcelas,
                parcelas: parcelas,
            });
        } catch (err) {
            console.error("[gc-token-consulta] Erro:", err);
            return res.status(500).json({ ok: false, erro: "Erro interno ao consultar cobranca." });
        }
    },
);

// =============================================================================
// Validar CPF do token (chamado pela página pública)
// =============================================================================

/** Lê millis de Timestamp Firestore, Date, ISO string ou objeto serializado */
function _lerMillisTimestamp(v) {
    if (v == null) return NaN;
    if (typeof v.toMillis === "function") return v.toMillis();
    if (typeof v.toDate === "function") return v.toDate().getTime();
    if (typeof v._seconds === "number") {
        return v._seconds * 1000 + Math.floor((v._nanoseconds || 0) / 1e6);
    }
    if (v instanceof Date) return v.getTime();
    const t = new Date(v).getTime();
    return t;
}

function _sessaoTokenValida(sessao, sessaoIdEsperado) {
    if (!sessao || sessao.sessao_id !== sessaoIdEsperado) return false;
    const expira = _lerMillisTimestamp(sessao.expira_em);
    return !isNaN(expira) && expira > Date.now();
}

exports.gestaoComercialValidarCpfToken = onRequest(
    Object.assign({}, CONFIG_PADRAO),
    async (req, res) => {
        res.set("Cache-Control", "no-store");
        res.set("Access-Control-Allow-Origin", "https://www.dipertin.com.br");
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type");

        if (req.method === "OPTIONS") return res.status(204).send("");
        if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

        let body = {};
        try { body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {}); } catch (e) { return res.status(400).json({ ok: false, erro: "JSON invalido" }); }

        const tokenRaw = String(body.token || "").trim();
        const cpfInput = String(body.cpf || "").trim().replace(/\D/g, "");
        if (!tokenRaw || !cpfInput) { return res.status(400).json({ ok: false, erro: "Token e CPF obrigatorios" }); }

        const crypto = require("crypto");
        const tokenHash = crypto.createHash("sha256").update(tokenRaw).digest("hex");

        try {
            const tokenDoc = await admin.firestore().collection("gestao_comercial_tokens_pagamento").doc(tokenHash).get();
            if (!tokenDoc.exists) { return res.status(404).json({ ok: false, erro: "Link de pagamento invalido." }); }
            const data = tokenDoc.data() || {};
            if (data.status !== "ativo") { return res.status(410).json({ ok: false, erro: "Este link ja foi utilizado." }); }

            const cpfVinculado = String(data.cliente_cpf || "").trim().replace(/\D/g, "");
            if (!cpfVinculado) { return res.status(400).json({ ok: false, erro: "CPF nao cadastrado para este cliente. Entre em contato com a loja." }); }
            if (cpfInput !== cpfVinculado) {
                console.warn("[gc-token-cpf] CPF invalido tentado p/ token " + tokenHash.slice(0, 12) + "; input=" + cpfInput);
                return res.status(403).json({ ok: false, erro: "CPF nao encontrado ou nao corresponde a esta cobranca." });
            }

            const sessaoId = crypto.randomBytes(16).toString("hex");
            const sessaoExpira = new Date(Date.now() + 30 * 60 * 1000);
            const sessoes = (data.sessoes_validas || []).filter(function (s) {
                const exp = _lerMillisTimestamp(s.expira_em);
                return !isNaN(exp) && exp > Date.now();
            });
            sessoes.push({
                sessao_id: sessaoId,
                criado_em: admin.firestore.Timestamp.fromDate(new Date()),
                expira_em: admin.firestore.Timestamp.fromDate(sessaoExpira),
            });
            await tokenDoc.ref.update({ sessoes_validas: sessoes, ultima_consulta_cpf_ok: admin.firestore.FieldValue.serverTimestamp() });

            return res.json({
                ok: true, sessao_id: sessaoId,
                cliente_nome: data.cliente_nome, loja_nome: data.loja_nome,
                loja_logo: data.loja_logo || "",
                valor_total: data.valor_total, qtd_parcelas: data.qtd_parcelas,
                parcelas: (data.parcelas || []).map(function (p) { return {
                    id: p.id, valor_parcela: p.valor_parcela, valor_em_aberto: p.valor_em_aberto,
                    data_vencimento: p.data_vencimento ? _fmtTSOuString(p.data_vencimento) : null,
                    codigo_venda: p.codigo_venda, numero_parcela: p.numero_parcela, total_parcelas: p.total_parcelas,
                }; }),
            });
        } catch (err) {
            console.error("[gc-token-cpf] Erro:", err);
            return res.status(500).json({ ok: false, erro: "Erro interno ao validar CPF." });
        }
    },
);

// =============================================================================
// Processar pagamento via token (PIX ou Cartão)
// =============================================================================

exports.gestaoComercialProcessarPagamentoToken = onRequest(
    Object.assign({}, CONFIG_PADRAO),
    async (req, res) => {
        res.set("Cache-Control", "no-store");
        res.set("Access-Control-Allow-Origin", "https://www.dipertin.com.br");
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type");

        if (req.method === "OPTIONS") return res.status(204).send("");
        if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

        let body = {};
        try { body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {}); } catch (e) { return res.status(400).json({ ok: false, erro: "JSON invalido" }); }

        const tokenRaw = String(body.token || "").trim();
        const sessaoId = String(body.sessao_id || "").trim();
        const formaPagamento = String(body.forma_pagamento || "").trim();
        const parcelasIds = Array.isArray(body.parcelas_ids) ? body.parcelas_ids : [];

        if (!tokenRaw || !sessaoId || !formaPagamento || parcelasIds.length === 0) {
            return res.status(400).json({ ok: false, erro: "token, sessao_id, forma_pagamento e parcelas_ids obrigatorios" });
        }
        if (!["pix", "cartao"].includes(formaPagamento)) {
            return res.status(400).json({ ok: false, erro: "Forma de pagamento invalida. Use 'pix' ou 'cartao'." });
        }

        const crypto = require("crypto");
        const tokenHash = crypto.createHash("sha256").update(tokenRaw).digest("hex");
        const db = admin.firestore();

        try {
            const tokenDoc = await db.collection("gestao_comercial_tokens_pagamento").doc(tokenHash).get();
            if (!tokenDoc.exists) { return res.status(404).json({ ok: false, erro: "Link invalido." }); }
            const data = tokenDoc.data() || {};
            if (data.status !== "ativo") { return res.status(410).json({ ok: false, erro: "Este link ja foi utilizado ou expirou." }); }

            const sessoes = data.sessoes_validas || [];
            const sessaoValida = sessoes.some(function (s) { return _sessaoTokenValida(s, sessaoId); });
            if (!sessaoValida) {
                console.warn("[gc-token-pagamento] Sessao invalida ou expirada; token=" + tokenHash.slice(0, 12) + "; sessao=" + sessaoId.slice(0, 8));
                return res.status(403).json({ ok: false, erro: "Sessao expirada. Faca a validacao do CPF novamente.", codigo: "sessao_expirada" });
            }

            const lojaId = data.loja_id;
            const clienteId = data.cliente_id;
            const parcelasDisponiveis = data.parcelas || [];
            const parcelasSelecionadas = parcelasDisponiveis.filter(function (p) { return parcelasIds.includes(p.id); });
            if (parcelasSelecionadas.length === 0) { return res.status(400).json({ ok: false, erro: "Nenhuma parcela valida selecionada." }); }

            const valorTotal = parcelasSelecionadas.reduce(function (acc, p) { return acc + Number(p.valor_em_aberto || p.valor_parcela || 0); }, 0);
            if (valorTotal <= 0) { return res.status(400).json({ ok: false, erro: "Valor total invalido." }); }

            const externalRef = "token_" + tokenHash.slice(0, 20) + "_" + Date.now();
            const idempotencyKey = "token_pag_" + tokenHash + "_" + Date.now();
            const clienteCpfToken = data.cliente_cpf != null ? String(data.cliente_cpf) : "";
            const clienteNomeToken = data.cliente_nome != null ? String(data.cliente_nome) : "Cliente";

            if (formaPagamento === "pix") {
                const expiresAt = new Date(Date.now() + 5 * 60 * 1000);
                const externalRefPix = externalRef.slice(0, 64);
                const idempotencyKeyPix = "token_pix_" + tokenHash + "_" + Date.now();
                const description = "Cobranca " + lojaId.slice(-6) + " - " + parcelasSelecionadas.length + " parcela(s)";

                let pixResult;
                try {
                    pixResult = await criarCobrancaPixGestaoComercial(db, {
                        lojaId,
                        valor: valorTotal,
                        descricao: description.substring(0, 150),
                        externalReference: externalRefPix,
                        idempotencyKey: idempotencyKeyPix,
                        clienteNome: clienteNomeToken,
                        clienteCpf: clienteCpfToken,
                    });
                } catch (pixErr) {
                    const msg = pixErr instanceof HttpsError
                        ? pixErr.message
                        : (pixErr.message || MSG_CHAVE_PIX_INVALIDA);
                    console.error("[gc-token-pix] Erro:", msg);
                    return res.status(502).json({ ok: false, erro: msg });
                }

                const paymentIdStr = pixResult.paymentId;
                const pixCopiaECola = pixResult.pixCopiaECola;
                const qrCodeBase64 = pixResult.qrCodeBase64;

                const pagamentos = data.pagamentos_gerados || [];
                pagamentos.push({
                    payment_id: paymentIdStr,
                    mp_pix_modo: "payments_api_validado",
                    external_reference: externalRefPix,
                    forma: "pix",
                    valor: valorTotal,
                    parcelas_ids: parcelasIds,
                    status_mp: "pending",
                    criado_em: new Date(),
                    expira_em: expiresAt,
                    gateway: pixResult.gatewayInfo.tipo,
                });

                await tokenDoc.ref.update({
                    pagamentos_gerados: pagamentos,
                    ultimo_pagamento_em: new Date(),
                    payment_ids_index: admin.firestore.FieldValue.arrayUnion(paymentIdStr),
                });

                return res.json({
                    ok: true,
                    forma: "pix",
                    payment_id: paymentIdStr,
                    qr_code: pixCopiaECola,
                    qr_code_base64: qrCodeBase64,
                    copia_e_cola: pixCopiaECola,
                    valor_total: valorTotal,
                    expira_em: expiresAt.toISOString(),
                    gateway: pixResult.gatewayInfo.tipo,
                });
            } else {
                const cardToken = String(body.card_token || "").trim();
                const installments = Number(body.installments || 1);
                const payerEmail = String(body.payer_email || "cliente@dipertin.com.br").trim();
                const paymentMethodId = String(body.payment_method_id || "master").trim();
                if (!cardToken) {
                    return res.status(400).json({ ok: false, erro: "Token do cartao obrigatorio." });
                }

                let cardResultWrap;
                try {
                    cardResultWrap = await criarCobrancaCartaoGestaoComercial(db, {
                        lojaId,
                        valor: valorTotal,
                        descricao: "Pagamento cobranca " + lojaId.slice(-6),
                        externalReference: externalRef,
                        clienteNome: clienteNomeToken,
                        clienteCpf: clienteCpfToken,
                        clienteEmail: payerEmail,
                        cardToken,
                        paymentMethodId,
                        installments,
                        idempotencyKey,
                    });
                } catch (cardErr) {
                    const msg = cardErr instanceof HttpsError
                        ? cardErr.message
                        : (cardErr.message || "Erro ao processar cartao.");
                    return res.status(502).json({ ok: false, erro: msg });
                }

                const mpResponse = cardResultWrap.cardResult.raw || cardResultWrap.cardResult;
                const approved = cardResultWrap.cardResult.aprovado === true
                    || mpResponse.status === "approved"
                    || mpResponse.status === "authorized";
                const pagamentos = data.pagamentos_gerados || [];
                const paymentIdStr = String(cardResultWrap.cardResult.paymentId || mpResponse.id || "");
                pagamentos.push({
                    payment_id: paymentIdStr,
                    external_reference: externalRef,
                    forma: "cartao",
                    valor: valorTotal,
                    parcelas_ids: parcelasIds,
                    status_mp: mpResponse.status || cardResultWrap.cardResult.status || "pending",
                    criado_em: new Date(),
                    gateway: cardResultWrap.gatewayInfo.tipo,
                });
                await tokenDoc.ref.update({
                    pagamentos_gerados: pagamentos,
                    ultimo_pagamento_em: new Date(),
                    payment_ids_index: admin.firestore.FieldValue.arrayUnion(paymentIdStr),
                });

                if (approved) {
                    await _baixarParcelasToken(db, lojaId, clienteId, parcelasIds, {
                        forma: "cartao",
                        valor: valorTotal,
                        transactionId: paymentIdStr,
                        gateway: cardResultWrap.gatewayInfo.tipo,
                        status_mp: mpResponse.status,
                    }, {
                        clienteNome: data.cliente_nome,
                        lojaNome: data.loja_nome,
                        lojaLogo: data.loja_logo,
                        tokenRef: tokenDoc.ref,
                    });
                    await tokenDoc.ref.update({ status: "usado", pago_em: new Date() });
                }

                return res.json({
                    ok: true,
                    forma: "cartao",
                    payment_id: paymentIdStr,
                    status_mp: mpResponse.status || cardResultWrap.cardResult.status,
                    approved,
                    detalhe_recusa: mpResponse.status_detail || cardResultWrap.cardResult.statusDetail || null,
                    valor_total: valorTotal,
                    gateway: cardResultWrap.gatewayInfo.tipo,
                });
            }
        } catch (err) {
            console.error("[gc-token-pagamento] Erro:", err);
            return res.status(500).json({ ok: false, erro: "Erro interno: " + String(err.message || err) });
        }
    },
);

// =============================================================================
// Webhook para confirmação de pagamento PIX (Mercado Pago)
// URL: https://southamerica-east1-depertin-f940f.cloudfunctions.net/gestaoComercialConfirmarPagamentoMpToken
// =============================================================================

exports.gestaoComercialConfirmarPagamentoMpToken = onRequest(
    Object.assign({}, CONFIG_PADRAO),
    async (req, res) => {
        res.set("Cache-Control", "no-store");
        if (req.method === "GET") return res.status(200).send("ok");
        if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

        let body = {};
        try { body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {}); } catch (e) { return res.status(400).send("bad json"); }

        const paymentId = body.data?.id || body.id || body.paymentId || body.payment_id || "";
        const action = body.action || body.type || body.topic || "";

        if (action && String(action).includes("merchant_order") && !body.data?.id) {
            return res.status(200).send("ignored");
        }
        if (!paymentId) { return res.status(200).send("no payment id"); }

        try {
            const result = await _processarConfirmacaoPagamentoToken(paymentId);
            return res.status(200).json({ ok: true, processado: result.processado, status: result.status || null, aprovado: !!result.aprovado });
        } catch (err) {
            console.error("[gc-token-webhook] Erro:", err);
            return res.status(500).send("erro");
        }
    },
);

// =============================================================================
// Consulta status PIX do token (polling público — confirmação via backend/MP)
// =============================================================================

exports.gestaoComercialConsultarStatusPagamentoToken = onRequest(
    Object.assign({}, CONFIG_PADRAO),
    async (req, res) => {
        res.set("Cache-Control", "no-store");
        res.set("Access-Control-Allow-Origin", "https://www.dipertin.com.br");
        res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.set("Access-Control-Allow-Headers", "Content-Type");

        if (req.method === "OPTIONS") return res.status(204).send("");
        if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

        let body = {};
        try { body = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {}); } catch (e) {
            return res.status(400).json({ ok: false, erro: "JSON invalido" });
        }

        const tokenRaw = String(body.token || "").trim();
        const sessaoId = String(body.sessao_id || "").trim();
        const paymentId = String(body.payment_id || "").trim();

        if (!tokenRaw || !sessaoId || !paymentId) {
            return res.status(400).json({ ok: false, erro: "token, sessao_id e payment_id obrigatorios" });
        }

        const crypto = require("crypto");
        const tokenHash = crypto.createHash("sha256").update(tokenRaw).digest("hex");
        const db = admin.firestore();

        try {
            const tokenDoc = await db.collection("gestao_comercial_tokens_pagamento").doc(tokenHash).get();
            if (!tokenDoc.exists) {
                return res.status(404).json({ ok: false, erro: "Link invalido." });
            }

            const data = tokenDoc.data() || {};
            const sessoes = data.sessoes_validas || [];
            const sessaoValida = sessoes.some(function (s) { return _sessaoTokenValida(s, sessaoId); });
            if (!sessaoValida) {
                return res.status(403).json({ ok: false, erro: "Sessao expirada. Faca a validacao do CPF novamente.", codigo: "sessao_expirada" });
            }

            const pags = data.pagamentos_gerados || [];
            const pagamentoToken = pags.find(function (p) {
                return String(p.payment_id) === paymentId || String(p.mp_order_id) === paymentId;
            });
            if (!pagamentoToken) {
                return res.status(404).json({ ok: false, erro: "Pagamento nao encontrado para este link." });
            }

            if (data.status === "usado") {
                return res.json({
                    ok: true,
                    aprovado: true,
                    processado: true,
                    status: "ja_processado",
                    status_mp: "approved",
                });
            }

            const result = await _processarConfirmacaoPagamentoToken(paymentId);
            const aprovado = result.aprovado === true
                || result.status === "aprovado"
                || result.status === "ja_processado";

            return res.json({
                ok: true,
                aprovado: aprovado,
                processado: !!result.processado,
                status: result.status || null,
                status_mp: result.status_mp || null,
                motivo: result.motivo || null,
                pendente: !aprovado && (result.motivo === "status_pendente" || result.status_mp === "pending" || result.status_mp === "in_process"),
            });
        } catch (err) {
            console.error("[gc-token-status] Erro:", err);
            return res.status(500).json({ ok: false, erro: "Erro interno ao consultar pagamento." });
        }
    },
);

// ── Helpers internos ──

/** Converte Timestamp/Date/string para ISO string */
function _fmtTSOuString(v) {
    if (!v) return null;
    if (typeof v.toDate === "function") return v.toDate().toISOString();
    if (typeof v === "string") return v;
    if (v instanceof Date) return v.toISOString();
    return String(v);
}

/** Localiza registro de pagamento gerado dentro do token */
function _encontrarPagamentoGeradoToken(data, paymentId) {
    const pags = data.pagamentos_gerados || [];
    const idStr = String(paymentId);
    for (const p of pags) {
        if (String(p.payment_id) === idStr || String(p.mp_order_id) === idStr) return p;
    }
    return null;
}

/** Processa confirmação de pagamento pelo payment_id do MP */
async function _processarConfirmacaoPagamentoToken(paymentId) {
    const db = admin.firestore();
    const paymentIdStr = String(paymentId);

    // Índice plano (array de strings) — evita array_contains com objeto completo
    const tokensSnap = await db.collection("gestao_comercial_tokens_pagamento")
        .where("payment_ids_index", "array-contains", paymentIdStr)
        .limit(1)
        .get();

    if (!tokensSnap.empty) {
        return await _confirmarPagamentoTokenPago(db, tokensSnap.docs[0], paymentIdStr);
    }

    // ── Crediário PIX: busca em cobrancas_pix_crediario ──
    // O payment_id pode ser numérico (MP) ou string (outros gateways)
    const paymentIdNum = Number(paymentIdStr);
    if (!isNaN(paymentIdNum)) {
        const credSnap = await db.collection("cobrancas_pix_crediario")
            .where("mp_payment_id", "==", paymentIdNum)
            .limit(1)
            .get();

        if (!credSnap.empty) {
            return await _confirmarPagamentoCrediarioPago(db, credSnap.docs[0], paymentIdStr);
        }
    }

    // Tenta buscar por payment_id (string - usado pelo provider genérico)
    const credSnapStr = await db.collection("cobrancas_pix_crediario")
        .where("payment_id", "==", paymentIdStr)
        .limit(1)
        .get();

    if (!credSnapStr.empty) {
        return await _confirmarPagamentoCrediarioPago(db, credSnapStr.docs[0], paymentIdStr);
    }

    // Fallback: escaneia tokens ativos
    const allTokens = await db.collection("gestao_comercial_tokens_pagamento")
        .where("status", "==", "ativo")
        .get();

    for (const doc of allTokens.docs) {
        const pags = doc.data().pagamentos_gerados || [];
        for (const p of pags) {
            if (String(p.payment_id) === paymentIdStr || String(p.mp_order_id) === paymentIdStr) {
                return await _confirmarPagamentoTokenPago(db, doc, paymentIdStr);
            }
        }
    }

    // Token já marcado como usado (ex.: webhook processou antes do polling)
    const usadosSnap = await db.collection("gestao_comercial_tokens_pagamento")
        .where("status", "==", "usado")
        .get();
    for (const doc of usadosSnap.docs) {
        const pags = doc.data().pagamentos_gerados || [];
        for (const p of pags) {
            if (String(p.payment_id) === paymentIdStr || String(p.mp_order_id) === paymentIdStr) {
                return { processado: true, status: "ja_processado", aprovado: true, status_mp: "approved" };
            }
        }
    }

    return { processado: false, motivo: "token_nao_encontrado", aprovado: false };
}

/** Exportado para polling crediário / webhook unificado */
exports.processarConfirmacaoPagamentoGestaoComercial = _processarConfirmacaoPagamentoToken;

async function _confirmarPagamentoTokenPago(db, tokenDoc, paymentId) {
    const data = tokenDoc.data() || {};
    if (data.status === "usado") {
        return { processado: true, status: "ja_processado", aprovado: true, status_mp: "approved" };
    }

    const lojaId = data.loja_id;
    const clienteId = data.cliente_id;

    let accessToken = null;
    try {
        const creds = await getLojaMercadoPagoCreds(db, lojaId);
        if (creds) accessToken = creds.accessToken;
    } catch (_) {}
    if (!accessToken) {
        try {
            const gSnap = await db.collection("gateways_pagamento").doc("mercado_pago").get();
            accessToken = (gSnap.data() || {}).access_token || null;
        } catch (_) {}
    }
    if (!accessToken) return { processado: false, motivo: "sem_access_token", aprovado: false };

    try {
        const pagRef = _encontrarPagamentoGeradoToken(data, paymentId);
        let payment = null;

        if (pagRef && pagRef.mp_pix_modo === "orders_dynamic" && pagRef.mp_order_id) {
            payment = await consultarPagamentoMpParaCobranca({
                paymentId: pagRef.payment_id || paymentId,
                mpOrderId: pagRef.mp_order_id,
                valor: pagRef.valor,
            }, accessToken);
        } else {
            const httpResp = await _httpReq("https://api.mercadopago.com/v1/payments/" + paymentId, {
                method: "GET",
                headers: { Authorization: "Bearer " + accessToken },
            });
            payment = typeof httpResp.body === "string" ? JSON.parse(httpResp.body) : httpResp.body;
        }

        if (!payment || !payment.status) {
            return { processado: false, motivo: "resposta_invalida_mp", aprovado: false };
        }

        const statusMp = String(payment.status || "").toLowerCase();

        if (statusMp === "approved" || statusMp === "authorized") {
            const pagamentos = data.pagamentos_gerados || [];
            let parcelasIds = [], valorPago = 0;
            const pagMatch = pagRef || pagamentos.find(function (p) {
                return String(p.payment_id) === String(paymentId)
                    || String(p.mp_order_id) === String(paymentId)
                    || p.external_reference === payment.external_reference;
            });
            if (pagMatch) {
                parcelasIds = pagMatch.parcelas_ids || [];
                valorPago = pagMatch.valor || 0;
            }
            if (parcelasIds.length === 0) {
                return { processado: false, motivo: "parcelas_nao_encontradas", aprovado: false, status_mp: statusMp };
            }

            await _baixarParcelasToken(db, lojaId, clienteId, parcelasIds, {
                forma: pagMatch?.forma || "pix",
                valor: valorPago || Number(payment.transaction_amount || 0),
                transactionId: String(payment.id || paymentId),
                gateway: "mercado_pago",
                status_mp: payment.status,
            }, {
                clienteNome: data.cliente_nome,
                lojaNome: data.loja_nome,
                lojaLogo: data.loja_logo,
                tokenRef: tokenDoc.ref,
            });

            await tokenDoc.ref.update({ status: "usado", pago_em: admin.firestore.FieldValue.serverTimestamp(), confirmacao_mp: payment });
            return { processado: true, status: "aprovado", aprovado: true, status_mp: statusMp };
        }

        if (["rejected", "cancelled", "refunded"].includes(statusMp)) {
            await tokenDoc.ref.update({ ultimo_status_mp: payment.status, status_detail_mp: payment.status_detail || "" });
            return { processado: true, status: statusMp, aprovado: false, status_mp: statusMp };
        }

        return { processado: false, motivo: "status_pendente", aprovado: false, status_mp: statusMp };
    } catch (err) {
        return { processado: false, motivo: String(err.message || err), aprovado: false };
    }
}

/** Baixa as parcelas de um pagamento via token */
async function _baixarParcelasToken(db, lojaId, clienteId, parcelasIds, info, contexto) {
    const batch = db.batch();
    const agora = new Date();
    const parcelasRef = db.collection("users").doc(lojaId).collection("parcelas_cliente");
    let valorTotalPago = 0;
    const parcelasDetalhe = [];

    for (const pId of parcelasIds) {
        const pRef = parcelasRef.doc(pId);
        const pSnap = await pRef.get();
        if (!pSnap.exists) continue;
        const pData = pSnap.data() || {};
        const valorAberto = Number(pData.valor_em_aberto !== undefined ? pData.valor_em_aberto : (pData.valor_parcela || pData.valor || 0));

        parcelasDetalhe.push({
            id: pId,
            numero_parcela: Number(pData.numero_parcela || 1),
            total_parcelas: Number(pData.total_parcelas || 1),
            codigo_venda: String(pData.codigo_venda || "").trim(),
            valor: valorAberto,
        });

        batch.update(pRef, {
            status: "pago",
            valor_pago: (Number(pData.valor_pago || 0) + valorAberto),
            valor_em_aberto: 0,
            data_pagamento: agora,
            forma_pagamento: info.forma || "pix",
            transaction_id: info.transactionId || "",
            gateway: info.gateway || "",
            pago_por_token: true,
            atualizado_em: agora,
        });
        valorTotalPago += valorAberto;
    }
    await batch.commit();

    // Registrar recebimento
    try {
        await db.collection("users").doc(lojaId).collection("recebimentos_cliente").add({
            cliente_id: clienteId, valor_recebido: valorTotalPago, valor_pago: valorTotalPago,
            data_pagamento: agora, forma_pagamento: info.forma || "pix",
            transaction_id: info.transactionId || "", gateway: info.gateway || "",
            origem: "link_pagamento", descricao: "Pagamento via link de cobranca",
            criado_em: agora, atualizado_em: agora,
        });
    } catch (_) {}

    // Audit log
    try {
        await db.collection("audit_logs").add({
            acao: "pagamento_token_confirmado", categoria: "financeiro", origem: "gestao_comercial",
            criado_em: agora, detalhe: { loja_id: lojaId, cliente_id: clienteId, valor: valorTotalPago, parcelas: parcelasIds, transaction_id: info.transactionId || "", forma: info.forma },
        });
    } catch (_) {}

    // Comprovante por e-mail (best-effort — não bloqueia a baixa)
    const ctx = contexto || {};
    try {
        await _enviarComprovanteEmailPagamentoToken(db, {
            lojaId: lojaId,
            clienteId: clienteId,
            clienteNome: ctx.clienteNome,
            lojaNome: ctx.lojaNome,
            lojaLogo: ctx.lojaLogo,
            valorTotalPago: valorTotalPago,
            formaPagamento: info.forma || "pix",
            agora: agora,
            parcelasDetalhe: parcelasDetalhe,
            transactionId: info.transactionId || "",
            tokenRef: ctx.tokenRef || null,
        });
    } catch (emailErr) {
        console.error("[gc-token-email] Erro inesperado:", emailErr.message || emailErr);
    }
}

// =============================================================================
// CREDIÁRIO PIX — Confirmação via webhook
// =============================================================================

/**
 * Confirma pagamento de crediário via webhook do Mercado Pago.
 * Busca a cobrança em cobrancas_pix_crediario e processa a baixa.
 */
async function _confirmarPagamentoCrediarioPago(db, cobrancaDoc, paymentIdStr) {
    const cobranca = cobrancaDoc.data() || {};

    // Já processado anteriormente (webhook duplicado ou polling já executou)
    if (cobranca.status === "approved") {
        return { processado: true, status: "ja_processado", aprovado: true, status_final: "approved" };
    }

    const lojaId = cobranca.loja_id;
    const clienteId = cobranca.cliente_id;
    const parcelasIds = cobranca.parcelas_ids || [];

    if (!lojaId || !clienteId) {
        return { processado: false, motivo: "dados_incompletos", aprovado: false };
    }

    // Carrega gateway do tipo armazenado na cobrança (ou fallback Mercado Pago)
    const gatewayTipo = cobranca.gateway_tipo || "mercado_pago";
    let provider = null;

    try {
        // Tenta carregar gateway ativo da loja
        const gatewayInfo = await carregarGatewayAtivo(db, lojaId);
        if (gatewayInfo) {
            provider = criarProvider(gatewayInfo.tipo, gatewayInfo.config);
        }
    } catch (_) {}

    // Se não conseguiu carregar da loja, tenta criar provider mínimo com config vazia
    if (!provider) {
        provider = criarProvider(gatewayTipo, cobranca.gateway_config || {});
    }

    if (!provider || !provider.getPaymentStatus) {
        return { processado: false, motivo: "sem_provider", aprovado: false };
    }

    try {
        const paymentId = paymentIdStr || String(cobranca.payment_id || cobranca.mp_payment_id || "");
        if (!paymentId) {
            return { processado: false, motivo: "sem_payment_id", aprovado: false };
        }

        const statusResult = await provider.getPaymentStatus(paymentId);

        // ── APROVADO → baixa as parcelas ──
        if (statusResult.aprovado) {
            if (!parcelasIds.length) {
                return { processado: false, motivo: "parcelas_nao_encontradas", aprovado: false, status_final: statusResult.status };
            }

            const valorPago = Number(cobranca.valor || 0);

            await _baixarParcelasCrediario(db, lojaId, clienteId, parcelasIds, {
                forma: "pix",
                valor: valorPago,
                valorOriginal: Number(cobranca.valor_original || valorPago),
                juros: Number(cobranca.juros_cobrados || 0),
                multa: Number(cobranca.multa_cobrada || 0),
                transactionId: String(statusResult.paymentId || paymentId),
                gateway: gatewayTipo,
                status_final: statusResult.status,
            });

            // Marca cobrança como aprovada (baixa contábil concluída)
            const updateData = {
                status: "approved",
                baixa_processada: true,
                confirmado_em: admin.firestore.Timestamp.now(),
                transacao_id: String(statusResult.paymentId || paymentId),
                gateway_status: statusResult.status,
                status_detail: statusResult.statusDetail || "",
            };
            await cobrancaDoc.ref.update(updateData);

            return { processado: true, status: "aprovado", aprovado: true, status_final: statusResult.status };
        }

        // ── PENDENTE → aguardando pagamento (NUNCA tratar como erro) ──
        if (statusResult.pendente) {
            await cobrancaDoc.ref.update({
                gateway_status: statusResult.status,
                ultima_consulta_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            return { processado: false, motivo: "status_pendente", aprovado: false, status_final: statusResult.status };
        }

        // ── REJEITADO/CANCELADO → atualiza doc, não baixa parcelas ──
        await cobrancaDoc.ref.update({
            gateway_status: statusResult.status,
            status_detail: statusResult.statusDetail || "",
        });
        return { processado: true, status: statusResult.status, aprovado: false, status_final: statusResult.status };

    } catch (err) {
        console.error("[gc-crediario-webhook] Erro:", err);
        return { processado: false, motivo: String(err.message || err), aprovado: false };
    }
}

/**
 * Baixa parcelas do crediário em users/{lojaId}/parcelas_cliente (via helper compartilhado).
 */
async function _baixarParcelasCrediario(db, lojaId, clienteId, parcelasIds, info) {
    if (!parcelasIds || !parcelasIds.length) return;
    const nomeGateway = info.gateway ? info.gateway.toUpperCase() : "PAGAMENTO";
    await aplicarBaixaCrediarioInterno(db, {
        lojaId,
        clienteId,
        parcelasIds,
        valorPago: Number(info.valor || 0),
        valorOriginal: Number(info.valorOriginal || info.valor || 0),
        jurosCobrados: Number(info.juros || 0),
        multaCobrada: Number(info.multa || 0),
        dadosPagamento: {
            forma: info.forma || "pix",
            transacaoId: info.transactionId || "",
            gateway: info.gateway || "",
            origem: "webhook",
        },
        forma: info.forma || "pix",
        usuarioNome: "Webhook " + nomeGateway,
        usuarioUid: "webhook",
        origem: "webhook_pix_gc",
    });
}
