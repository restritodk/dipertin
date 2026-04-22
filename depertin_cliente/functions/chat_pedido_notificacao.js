"use strict";

/**
 * Push FCM do chat do pedido (cliente ↔ loja).
 *
 * Trigger: onCreate em `pedidos/{pedidoId}/mensagens/{msgId}`.
 * - Se a mensagem é do cliente → notifica a loja (uid = loja_id).
 * - Se a mensagem é da loja/colaborador → notifica o cliente (uid = cliente_id).
 *
 * Observação: colaboradores (lojista nível III) compartilham a mesma "caixa"
 * do dono (loja_id). A push chega no dispositivo do dono da loja.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const CHAT_FCM_ANDROID = {
    priority: "high",
    notification: {
        channelId: "high_importance_channel",
        sound: "default",
        defaultVibrateTimings: true,
        visibility: "public",
    },
};

const CHAT_FCM_APNS = {
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

function truncar(str, max) {
    if (!str || typeof str !== "string") return "";
    const t = str.trim();
    if (t.length <= max) return t;
    return `${t.slice(0, max - 1)}…`;
}

function descricaoConteudo(msg) {
    const texto = (msg && msg.texto ? String(msg.texto) : "").trim();
    if (texto) return truncar(texto, 140);
    const anexoTipo = (msg && msg.anexo_tipo ? String(msg.anexo_tipo) : "").toLowerCase();
    if (anexoTipo === "image") return "📷 Imagem";
    if (anexoTipo === "arquivo") return "📎 Arquivo";
    return "Nova mensagem";
}

async function enviarFcm(uidDestino, payload) {
    if (!uidDestino) return false;
    const snap = await admin.firestore().collection("users").doc(String(uidDestino)).get();
    if (!snap.exists) return false;
    const token = snap.data().fcm_token;
    if (!token) {
        console.log(`[chat_pedido] sem fcm_token uid=${uidDestino}`);
        return false;
    }
    try {
        await admin.messaging().send({ ...payload, token });
        return true;
    } catch (e) {
        console.error("[chat_pedido] erro FCM:", e.message || e);
        return false;
    }
}

exports.notificarChatMensagemPedido = functions.firestore
    .document("pedidos/{pedidoId}/mensagens/{msgId}")
    .onCreate(async (snap, context) => {
        const msg = snap.data() || {};
        const pedidoId = context.params.pedidoId;

        // Mensagens automáticas/sistema não disparam push para o outro lado.
        if (msg.sistema === true || msg.suporte_auto === true) return null;

        const pedidoRef = admin.firestore().collection("pedidos").doc(pedidoId);
        const pedidoSnap = await pedidoRef.get();
        if (!pedidoSnap.exists) return null;

        const pedido = pedidoSnap.data() || {};
        const status = String(pedido.status || "").trim().toLowerCase();
        // Se o pedido já foi encerrado (entregue/cancelado), não dispara —
        // as rules já impedem novos envios, mas garante robustez.
        if (status === "entregue" || status === "cancelado") return null;

        const clienteId = pedido.cliente_id != null ? String(pedido.cliente_id).trim() : "";
        const lojaId = pedido.loja_id != null ? String(pedido.loja_id).trim() : "";
        const remetente = msg.remetente_id != null ? String(msg.remetente_id).trim() : "";
        if (!remetente || (!clienteId && !lojaId)) return null;

        const enviadaPeloCliente = remetente === clienteId;
        // Qualquer mensagem que NÃO seja do cliente é tratada como "loja"
        // (colaboradores também caem aqui).
        const destinoUid = enviadaPeloCliente ? lojaId : clienteId;
        if (!destinoUid) return null;

        const corpo = descricaoConteudo(msg);
        const idCurto = pedidoId.length >= 5 ? pedidoId.slice(-5).toUpperCase() : pedidoId.toUpperCase();

        let titulo;
        let tipo;
        let segmento;
        if (enviadaPeloCliente) {
            const nomeCliente = truncar(pedido.cliente_nome || "Cliente", 60);
            titulo = `${nomeCliente} · Pedido #${idCurto}`;
            tipo = "chat_pedido_cliente_para_loja";
            segmento = "loja";
        } else {
            const nomeLoja = truncar(pedido.loja_nome || "Loja", 60);
            titulo = `${nomeLoja} · Pedido #${idCurto}`;
            tipo = "chat_pedido_loja_para_cliente";
            segmento = "cliente";
        }

        const payload = {
            notification: {
                title: titulo,
                body: corpo,
            },
            android: {
                ...CHAT_FCM_ANDROID,
                // Uma notificação por pedido/destino; mensagens seguintes
                // atualizam a mesma bolha em vez de empilhar.
                collapseKey: `chat_pedido_${pedidoId}_${segmento}`,
            },
            apns: CHAT_FCM_APNS,
            data: {
                type: "CHAT_PEDIDO",
                tipoNotificacao: tipo,
                segmento,
                evento: "chat_mensagem",
                pedido_id: String(pedidoId),
                order_id: String(pedidoId),
                loja_id: lojaId,
                cliente_id: clienteId,
                remetente_id: remetente,
            },
        };

        await enviarFcm(destinoUid, payload);
        return null;
    });
