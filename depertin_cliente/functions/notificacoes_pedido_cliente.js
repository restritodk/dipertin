"use strict";

/**
 * Notificações de status do pedido exclusivamente para o cliente (cliente_id).
 * Eventos: payment_confirmed, preparing, out_for_delivery (só ao ir ao cliente), delivered.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const dispatcher = require("./notification_dispatcher");

/** Só “a caminho do cliente” — não incluir `entregador_indo_loja` (aceite = indo à loja). */
const STATUS_SAIDA_PARA_CLIENTE = new Set([
    "saiu_entrega",
    "em_rota",
    "a_caminho",
]);

function nomeLojaDoPedido(dadosPedido = {}) {
    const candidatos = [
        dadosPedido.loja_nome,
        dadosPedido.nome_loja,
        dadosPedido.nome_fantasia,
        dadosPedido.nomeFantasia,
        dadosPedido.lojaNome,
        dadosPedido.store_name,
        dadosPedido.storeName,
    ];
    for (const c of candidatos) {
        const v = c != null ? String(c).trim() : "";
        if (v) return v;
    }
    return "";
}

async function resolverNomeLoja(db, dadosPedido = {}) {
    const lojaIdRaw =
        dadosPedido.loja_id ??
        dadosPedido.lojista_id ??
        dadosPedido.store_id ??
        dadosPedido.seller_id;
    const lojaId = lojaIdRaw != null ? String(lojaIdRaw).trim() : "";

    if (lojaId) {
        try {
            const lojaSnap = await db.collection("users").doc(lojaId).get();
            if (lojaSnap.exists) {
                const loja = lojaSnap.data() || {};
                const candidatosLoja = [
                    loja.loja_nome,
                    loja.nome_loja,
                    loja.nome_fantasia,
                    loja.nomeFantasia,
                    loja.store_name,
                    loja.razao_social,
                ];
                for (const c of candidatosLoja) {
                    const v = c != null ? String(c).trim() : "";
                    if (v) return v;
                }
            }
        } catch (e) {
            console.warn("[notif_cliente] Falha ao resolver nome da loja por loja_id:", e.message || e);
        }
    }

    const doPedido = nomeLojaDoPedido(dadosPedido);
    return doPedido || "Loja parceira";
}

exports.notificarClienteStatusPedido = functions.firestore
    .document("pedidos/{pedidoId}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data();
        const depois = change.after.data();
        const pedidoId = context.params.pedidoId;
        const clienteId = depois.cliente_id;
        if (!clienteId) return null;

        const db = admin.firestore();
        const sa = antes.status || "";
        const sd = depois.status || "";

        try {
            if (sa === "aguardando_pagamento" && sd === "pendente") {
                await dispatcher.enviarStatusPedidoParaCliente(
                    db,
                    clienteId,
                    pedidoId,
                    "payment_confirmed",
                    "Pagamento confirmado",
                    "Seu pedido foi enviado para a loja.",
                );
                return null;
            }

            const nomeLoja = await resolverNomeLoja(db, depois);

            if (sa === "pendente" && sd === "aceito") {
                await dispatcher.enviarStatusPedidoParaCliente(
                    db,
                    clienteId,
                    pedidoId,
                    "preparing",
                    `A ${nomeLoja} aceitou seu pedido`,
                    "Em breve seu pedido entra em preparo.",
                );
                return null;
            }

            if (sa === "pendente" && sd === "em_preparo") {
                await dispatcher.enviarStatusPedidoParaCliente(
                    db,
                    clienteId,
                    pedidoId,
                    "preparing",
                    "Pedido em preparo",
                    `A ${nomeLoja} está preparando seu pedido.`,
                );
                return null;
            }

            if (sa === "aceito" && sd === "em_preparo") {
                await dispatcher.enviarStatusPedidoParaCliente(
                    db,
                    clienteId,
                    pedidoId,
                    "preparing",
                    "Pedido em preparo",
                    `A ${nomeLoja} está preparando seu pedido.`,
                );
                return null;
            }

            if (
                !STATUS_SAIDA_PARA_CLIENTE.has(sa) &&
                STATUS_SAIDA_PARA_CLIENTE.has(sd)
            ) {
                await dispatcher.enviarStatusPedidoParaCliente(
                    db,
                    clienteId,
                    pedidoId,
                    "out_for_delivery",
                    "Saiu para entrega",
                    "Seu pedido está a caminho.",
                );
                return null;
            }

            if (sd === "entregue" && sa !== "entregue") {
                await dispatcher.enviarStatusPedidoParaCliente(
                    db,
                    clienteId,
                    pedidoId,
                    "delivered",
                    "Pedido entregue",
                    "Obrigado por comprar no DiPertin!",
                );
                return null;
            }
        } catch (e) {
            console.error(`[notif_cliente] pedido ${pedidoId}:`, e.message || e);
        }
        return null;
    });

/**
 * Cliente cancelou em andamento — confirmação por push (reembolso em breve).
 * Dispara só na transição para `cancelado` + motivo cliente_solicitou (uma vez por cancelamento).
 */
exports.notificarClienteConfirmacaoCancelamento = functions.firestore
    .document("pedidos/{pedidoId}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        if (antes.status === "cancelado" || depois.status !== "cancelado") {
            return null;
        }
        if (String(depois.cancelado_motivo || "") !== "cliente_solicitou") {
            return null;
        }
        const clienteId = depois.cliente_id;
        if (!clienteId) return null;

        const db = admin.firestore();
        const comMp = !!(depois.mp_payment_id || antes.mp_payment_id);
        try {
            await dispatcher.enviarClienteConfirmacaoCancelamentoReembolso(
                db,
                String(clienteId),
                context.params.pedidoId,
                comMp,
            );
        } catch (e) {
            console.error(
                `[notif_cliente] confirmacao cancel pedido ${context.params.pedidoId}:`,
                e.message || e,
            );
        }
        return null;
    });
