"use strict";

/**
 * Motor central de FCM: segmentação por papel (loja / cliente / entregador)
 * e envio apenas ao token do usuário alvo (users/{uid}.fcm_token).
 * Todos os valores em `data` são strings (requisito FCM).
 */

const admin = require("firebase-admin");

/** iOS (APNS): alerta com prioridade alta — necessário para som/banner com app fechado ou em background. */
const FCM_APNS_ALERTA = {
    headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
    },
    payload: {
        aps: {
            sound: "default",
            badge: 1,
        },
    },
};

const ROLES = {
    LOJA: "lojista",
    CLIENTE: "cliente",
    ENTREGADOR: "entregador",
};

function roleDoUsuario(data) {
    if (!data) return "";
    return String(data.role || data.tipoUsuario || "").trim();
}

/**
 * Igual a saque_solicitar.js / painel_google_login.js: muitos lojistas têm
 * `role: "cliente"` legado e `tipoUsuario: "lojista"` — não usar só o primeiro campo.
 */
function docIndicaLojista(u) {
    if (!u) return false;
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(u[k] || "").toLowerCase().trim() === ROLES.LOJA) return true;
    }
    return false;
}

function docIndicaEntregador(u) {
    if (!u) return false;
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(u[k] || "").toLowerCase().trim() === ROLES.ENTREGADOR) return true;
    }
    return false;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @param {string} segmentoEsperado - 'loja' | 'cliente' | 'entregador'
 */
async function obterTokenValidado(db, uid, segmentoEsperado) {
    if (!uid) return { token: null, ok: false, motivo: "sem_uid" };
    const doc = await db.collection("users").doc(String(uid)).get();
    if (!doc.exists) return { token: null, ok: false, motivo: "usuario_inexistente" };
    const d = doc.data();
    const role = roleDoUsuario(d);
    const map = {
        loja: ROLES.LOJA,
        cliente: ROLES.CLIENTE,
        entregador: ROLES.ENTREGADOR,
    };
    const esperado = map[segmentoEsperado];
    if (esperado) {
        let okRole = false;
        if (segmentoEsperado === "cliente") {
            const r = String(role || "").toLowerCase();
            okRole = !r || r === ROLES.CLIENTE;
        } else if (segmentoEsperado === "loja") {
            okRole = docIndicaLojista(d);
        } else if (segmentoEsperado === "entregador") {
            okRole = docIndicaEntregador(d);
        }
        if (!okRole) {
            console.warn(
                `[dispatcher] Segmento ${segmentoEsperado} incompatível (role/tipo efetivo='${role}') uid=${uid}`,
            );
            return { token: null, ok: false, motivo: "role_incompativel" };
        }
    }
    const token = d.fcm_token || null;
    if (!token) {
        console.log(`[dispatcher] Sem fcm_token uid=${uid} segmento=${segmentoEsperado}`);
        return { token: null, ok: false, motivo: "sem_token" };
    }
    return { token, ok: true, motivo: "" };
}

function dataSoStrings(obj) {
    const out = {};
    if (!obj || typeof obj !== "object") return out;
    for (const [k, v] of Object.entries(obj)) {
        if (v === undefined || v === null) continue;
        out[String(k)] = typeof v === "string" ? v : JSON.stringify(v);
    }
    return out;
}

/**
 * Serializa itens do pedido (array ou objeto) para JSON string curta.
 */
function itensPedidoResumo(pedido) {
    const items = pedido.items || pedido.itens;
    if (!items) return "[]";
    try {
        const s = JSON.stringify(items);
        return s.length > 3500 ? s.slice(0, 3490) + "…" : s;
    } catch (_) {
        return "[]";
    }
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} lojaId
 * @param {string} pedidoId
 * @param {object} pedido - snapshot data
 */
function valorProdutosNovoPedidoFmt(pedido) {
    const sub = Number(pedido.subtotal);
    if (Number.isFinite(sub) && sub >= 0) {
        return (Math.round(sub * 100) / 100).toFixed(2);
    }
    const tp = Number(pedido.total_produtos);
    if (Number.isFinite(tp) && tp >= 0) {
        return (Math.round(tp * 100) / 100).toFixed(2);
    }
    const tot = Number(pedido.total || 0);
    const taxa = Number(pedido.taxa_entrega || 0);
    const v = Math.max(0, tot - taxa);
    return (Math.round(v * 100) / 100).toFixed(2);
}

async function enviarNovoPedidoParaLoja(db, lojaId, pedidoId, pedido) {
    const { token, ok } = await obterTokenValidado(db, lojaId, "loja");
    if (!ok || !token) return { enviado: false };

    const valorProdutos = valorProdutosNovoPedidoFmt(pedido);
    const clienteId = pedido.cliente_id != null ? String(pedido.cliente_id) : "";

    const data = dataSoStrings({
        type: "NOVO_PEDIDO",
        tipoNotificacao: "novo_pedido",
        segmento: "loja",
        evento: "order_created",
        pedido_id: String(pedidoId),
        order_id: String(pedidoId),
        loja_id: String(lojaId),
        cliente_id: clienteId,
        valor_total: valorProdutos,
        valor_produtos: valorProdutos,
        itens: itensPedidoResumo(pedido),
    });

    const mensagem = {
        notification: {
            title: "Novo pedido no DiPertin",
            body: `Pedido: R$ ${valorProdutos} (produtos)`,
        },
        android: {
            priority: "high",
            collapseKey: `novo_pedido_${pedidoId}`,
            notification: {
                channelId: "loja_novo_pedido",
                sound: "pedido",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: FCM_APNS_ALERTA,
        data,
        token,
    };

    await admin.messaging().send(mensagem);
    console.log(`[dispatcher] novo_pedido → loja ${lojaId} pedido=${pedidoId}`);
    return { enviado: true };
}

/**
 * Cliente cancelou pedido em andamento — notifica a loja (segmento loja).
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} lojaId
 * @param {string} pedidoId
 * @param {object} pedido - snapshot depois do update
 */
async function enviarClienteCancelouPedidoParaLoja(db, lojaId, pedidoId, pedido) {
    const { token, ok } = await obterTokenValidado(db, lojaId, "loja");
    if (!ok || !token) return { enviado: false };

    const cod = String(pedido.cancelado_cliente_codigo || "").trim();
    const det = String(pedido.cancelado_cliente_detalhe || "").trim();
    let body = "O cliente cancelou o pedido.";
    if (cod === "desistencia") {
        body = "Cliente desistiu do pedido.";
    } else if (cod === "demora_loja") {
        body = "Cliente cancelou: a loja está demorando para o envio.";
    } else if (cod === "outro" && det) {
        body = det.length > 140 ? `${det.slice(0, 137)}…` : det;
    }

    const data = dataSoStrings({
        type: "CLIENTE_CANCEL_PEDIDO",
        tipoNotificacao: "cliente_cancelou_pedido",
        segmento: "loja",
        evento: "cliente_pedido_cancelado",
        pedido_id: String(pedidoId),
        order_id: String(pedidoId),
        loja_id: String(lojaId),
        cancelado_cliente_codigo: cod,
    });

    const mensagem = {
        notification: {
            title: "Pedido cancelado pelo cliente",
            body,
        },
        android: {
            priority: "high",
            collapseKey: `cliente_cancel_${pedidoId}`,
            notification: {
                channelId: "loja_novo_pedido",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: FCM_APNS_ALERTA,
        data,
        token,
    };

    await admin.messaging().send(mensagem);
    console.log(`[dispatcher] cliente_cancelou_pedido → loja ${lojaId} pedido=${pedidoId}`);
    return { enviado: true };
}

/**
 * Cliente cancelou pedido em andamento — aviso ao entregador designado (se houver).
 * Tom informativo; canal geral (sem som de chamada de corrida).
 */
async function enviarClienteCancelouPedidoParaEntregador(db, entregadorId, pedidoId, pedido) {
    if (!entregadorId) return { enviado: false, motivo: "sem_entregador" };
    const { token, ok } = await obterTokenValidado(db, String(entregadorId), "entregador");
    if (!ok || !token) return { enviado: false };

    const lojaNomeRaw =
        pedido.loja_nome != null
            ? String(pedido.loja_nome).trim()
            : pedido.nome_loja != null
              ? String(pedido.nome_loja).trim()
              : "";
    const lojaNome = lojaNomeRaw.length > 0 ? lojaNomeRaw : "Loja parceira";

    const data = dataSoStrings({
        type: "PEDIDO_CANCELADO_CLIENTE_ENTREGADOR",
        tipoNotificacao: "cliente_cancelou_pedido_entregador",
        segmento: "entregador",
        evento: "cliente_pedido_cancelado_entregador",
        pedido_id: String(pedidoId),
        order_id: String(pedidoId),
        loja_id: String(pedido.loja_id || pedido.lojista_id || ""),
        loja_nome: lojaNome,
    });

    const mensagem = {
        notification: {
            title: "Pedido cancelado pelo cliente",
            body:
                `O pedido em ${lojaNome} foi cancelado pelo cliente. ` +
                "Não é necessário concluir a entrega; você pode seguir disponível para novas corridas.",
        },
        android: {
            priority: "high",
            collapseKey: `cliente_cancel_entregador_${pedidoId}`,
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: FCM_APNS_ALERTA,
        data,
        token,
    };

    await admin.messaging().send(mensagem);
    console.log(
        `[dispatcher] cliente_cancelou_pedido → entregador ${entregadorId} pedido=${pedidoId}`,
    );
    return { enviado: true };
}

/**
 * Status do pedido para o cliente (ex.: payment_confirmed, preparing).
 * @param {string} evento - payment_confirmed | preparing | out_for_delivery | delivered
 */
async function enviarStatusPedidoParaCliente(db, clienteId, pedidoId, evento, titulo, corpo, extraData = {}) {
    if (!clienteId) return { enviado: false, motivo: "sem_cliente" };
    const { token, ok } = await obterTokenValidado(db, clienteId, "cliente");
    if (!ok || !token) return { enviado: false };

    const tipoNotificacao = `pedido_${evento}`;
    const typeExtra =
        evento === "payment_confirmed"
            ? { type: "PAGAMENTO_CONFIRMADO", status: "aprovado" }
            : {};
    const data = dataSoStrings({
        ...typeExtra,
        tipoNotificacao,
        segmento: "cliente",
        evento,
        pedido_id: String(pedidoId),
        order_id: String(pedidoId),
        cliente_id: String(clienteId),
        ...extraData,
    });

    const mensagem = {
        notification: {
            title: titulo,
            body: corpo,
        },
        android: {
            priority: "high",
            collapseKey: `pedido_cliente_${pedidoId}_${evento}`,
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: FCM_APNS_ALERTA,
        data,
        token,
    };

    await admin.messaging().send(mensagem);
    console.log(`[dispatcher] ${tipoNotificacao} → cliente ${clienteId} pedido=${pedidoId}`);
    return { enviado: true };
}

/**
 * Cliente cancelou pedido em andamento — confirmação + reembolso (mesmo canal FCM dos demais pedidos).
 */
async function enviarClienteConfirmacaoCancelamentoReembolso(
    db,
    clienteId,
    pedidoId,
    comPagamentoMp,
) {
    if (!clienteId) return { enviado: false, motivo: "sem_cliente" };
    const { token, ok } = await obterTokenValidado(db, clienteId, "cliente");
    if (!ok || !token) return { enviado: false };

    const titulo = "Pedido cancelado";
    const corpo = comPagamentoMp
        ? "Cancelamento efetuado com sucesso: Seu reembolso está disponível em breve."
        : "Cancelamento efetuado com sucesso.";

    const data = dataSoStrings({
        tipoNotificacao: "pedido_cancelamento_reembolso",
        segmento: "cliente",
        evento: "cancelamento_cliente",
        pedido_id: String(pedidoId),
        order_id: String(pedidoId),
        cliente_id: String(clienteId),
        com_pagamento_mp: comPagamentoMp ? "1" : "0",
    });

    const mensagem = {
        notification: {
            title: titulo,
            body: corpo,
        },
        android: {
            priority: "high",
            collapseKey: `pedido_cliente_${pedidoId}_cancel_confirm`,
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: FCM_APNS_ALERTA,
        data,
        token,
    };

    await admin.messaging().send(mensagem);
    console.log(
        `[dispatcher] pedido_cancelamento_reembolso → cliente ${clienteId} pedido=${pedidoId}`,
    );
    return { enviado: true };
}

/**
 * Pedido entregue → notificação para a loja (segmento loja).
 */
async function enviarPedidoEntregueParaLoja(db, lojaId, pedidoId, pedido) {
    const { token, ok } = await obterTokenValidado(db, lojaId, "loja");
    if (!ok || !token) return { enviado: false };

    const valorTotal = pedido.total != null ? Number(pedido.total).toFixed(2) : "0.00";

    const data = dataSoStrings({
        type: "PEDIDO_ENTREGUE",
        tipoNotificacao: "pedido_entregue_loja",
        segmento: "loja",
        evento: "delivered",
        pedido_id: String(pedidoId),
        order_id: String(pedidoId),
        loja_id: String(lojaId),
    });

    const mensagem = {
        notification: {
            title: "Pedido entregue",
            body: `O pedido de R$ ${valorTotal} foi entregue ao cliente.`,
        },
        android: {
            priority: "high",
            collapseKey: `pedido_entregue_loja_${pedidoId}`,
            notification: {
                channelId: "loja_novo_pedido",
                sound: "pedido",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: FCM_APNS_ALERTA,
        data,
        token,
    };

    await admin.messaging().send(mensagem);
    console.log(`[dispatcher] pedido_entregue → loja ${lojaId} pedido=${pedidoId}`);
    return { enviado: true };
}

/**
 * Master recusou saque PIX → crédito na carteira (`credito_saque_recusado`).
 * Notifica lojista ou entregador com o motivo (campo `motivo` do doc em estornos).
 */
async function enviarEstornoCreditoSaqueRecusado(db, uid, estornoId, d) {
    if (!uid) return { enviado: false, motivo: "sem_uid" };
    const userDoc = await db.collection("users").doc(String(uid)).get();
    if (!userDoc.exists) return { enviado: false, motivo: "usuario_inexistente" };
    const role = roleDoUsuario(userDoc.data());
    let segmento = "loja";
    if (role === ROLES.ENTREGADOR) segmento = "entregador";
    else if (role !== ROLES.LOJA) {
        console.warn(`[dispatcher] estorno_saque role inesperado uid=${uid} role='${role}'`);
        return { enviado: false, motivo: "role_incompativel" };
    }

    const { token, ok } = await obterTokenValidado(db, uid, segmento);
    if (!ok || !token) return { enviado: false };

    const valor = d.valor != null ? Number(d.valor).toFixed(2) : "0.00";
    const motivo = String(d.motivo || "").trim() || "Não informado";
    let body = `Foram devolvidos R$ ${valor} à sua carteira. Motivo: ${motivo}`;
    if (body.length > 220) {
        body = `${body.slice(0, 217)}…`;
    }

    const data = dataSoStrings({
        type: "ESTORNO_SAQUE_PIX",
        tipoNotificacao: "estorno_saque_pix",
        segmento,
        evento: "credito_saque_recusado",
        estorno_id: String(estornoId),
        saque_solicitacao_id: String(d.saque_solicitacao_id || ""),
        motivo,
        valor_estorno: valor,
    });

    const mensagem = {
        notification: {
            title: "Saque PIX não realizado",
            body,
        },
        android: {
            priority: "high",
            collapseKey: `estorno_saque_${estornoId}`,
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: FCM_APNS_ALERTA,
        data,
        token,
    };

    await admin.messaging().send(mensagem);
    console.log(`[dispatcher] estorno_saque_pix → ${segmento} uid=${uid} estorno=${estornoId}`);
    return { enviado: true };
}

module.exports = {
    obterTokenValidado,
    dataSoStrings,
    itensPedidoResumo,
    enviarNovoPedidoParaLoja,
    enviarClienteCancelouPedidoParaLoja,
    enviarClienteCancelouPedidoParaEntregador,
    enviarStatusPedidoParaCliente,
    enviarClienteConfirmacaoCancelamentoReembolso,
    enviarPedidoEntregueParaLoja,
    enviarEstornoCreditoSaqueRecusado,
    ROLES,
};
