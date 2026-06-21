/**
 * Baixa e restauração de `estoque_qtd` em `produtos` conforme vendas em `pedidos`.
 *
 * Regras:
 * - Só itens de pronta-entrega (`tipo_venda` ≠ encomenda).
 * - PIX/cartão: baixa quando o status sai de `aguardando_pagamento` para confirmado.
 * - Saldo integral: baixa no onCreate com status `pendente`.
 * - Cancelamento após baixa: restaura quantidades (idempotente).
 * - Sem alteração no pipeline FCM.
 */

"use strict";

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const STATUS_AGUARDANDO_PAGAMENTO = "aguardando_pagamento";
const STATUS_VENDA_CONFIRMADA = new Set([
    "pendente",
    "aceito",
    "em_preparo",
    "aguardando_entregador",
    "entregador_indo_loja",
    "saiu_entrega",
    "a_caminho",
    "em_rota",
    "pronto",
    "entregue",
]);

const STATUS_CANCELADOS = new Set([
    "cancelado",
    "cancelado_pelo_cliente",
    "cancelado_pela_loja",
    "cancelado_pelo_lojista",
    "recusado",
    "estornado",
    "expirado",
]);

/**
 * @param {unknown} item
 * @returns {boolean}
 */
function itemContaParaEstoque(item) {
    if (!item || typeof item !== "object") return false;
    const tv = String(item.tipo_venda || "pronta_entrega").trim().toLowerCase();
    return tv !== "encomenda";
}

/**
 * @param {unknown} status
 * @returns {boolean}
 */
function statusIndicaVendaConfirmada(status) {
    const st = String(status || "").trim().toLowerCase();
    if (!st || st === STATUS_AGUARDANDO_PAGAMENTO) return false;
    if (st === "encomenda_entrada_paga") return false;
    if (STATUS_CANCELADOS.has(st)) return false;
    return STATUS_VENDA_CONFIRMADA.has(st);
}

/**
 * @param {unknown} status
 * @returns {boolean}
 */
function statusEhCancelado(status) {
    return STATUS_CANCELADOS.has(String(status || "").trim().toLowerCase());
}

/**
 * Agrega quantidades por `id_produto` (somente itens de estoque).
 *
 * @param {unknown} itens
 * @returns {Map<string, number>}
 */
function agregarQuantidadesPorProduto(itens) {
    const mapa = new Map();
    if (!Array.isArray(itens)) return mapa;

    for (const item of itens) {
        if (!itemContaParaEstoque(item)) continue;
        const id = String(item.id_produto || item.produto_id || "").trim();
        if (!id) continue;
        const qtdRaw = item.quantidade;
        const qtd = Number.isFinite(Number(qtdRaw)) ? Math.max(1, Math.floor(Number(qtdRaw))) : 1;
        mapa.set(id, (mapa.get(id) || 0) + qtd);
    }
    return mapa;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} pedidoId
 * @param {Record<string, unknown>} pedido
 */
async function baixarEstoqueDoPedido(db, pedidoId, pedido) {
    if (pedido.estoque_baixado === true) {
        return { ok: true, skipped: "ja_baixado" };
    }
    if (!statusIndicaVendaConfirmada(pedido.status)) {
        return { ok: true, skipped: "status_sem_baixa" };
    }

    const agg = agregarQuantidadesPorProduto(pedido.itens);
    const pedidoRef = db.collection("pedidos").doc(pedidoId);
    const lojaId = String(pedido.loja_id || pedido.lojista_id || "").trim();

    if (agg.size === 0) {
        await pedidoRef.set(
            {
                estoque_baixado: true,
                estoque_baixado_em: admin.firestore.FieldValue.serverTimestamp(),
                estoque_baixado_motivo: "sem_itens_pronta_entrega",
            },
            { merge: true },
        );
        return { ok: true, skipped: "sem_itens" };
    }

    const detalhe = {};

    await db.runTransaction(async (tx) => {
        const pedSnap = await tx.get(pedidoRef);
        if (!pedSnap.exists) return;
        const atual = pedSnap.data() || {};
        if (atual.estoque_baixado === true) return;

        for (const [produtoId, qtd] of agg.entries()) {
            const prodRef = db.collection("produtos").doc(produtoId);
            const prodSnap = await tx.get(prodRef);
            if (!prodSnap.exists) {
                detalhe[produtoId] = { ok: false, motivo: "produto_inexistente", qtd };
                continue;
            }
            const prod = prodSnap.data() || {};
            const lojaProd = String(prod.lojista_id || prod.loja_id || "").trim();
            if (lojaId && lojaProd && lojaProd !== lojaId) {
                detalhe[produtoId] = { ok: false, motivo: "loja_divergente", qtd };
                continue;
            }

            const atualQtd = Number(prod.estoque_qtd);
            const base = Number.isFinite(atualQtd) ? atualQtd : 0;
            const novo = Math.max(0, base - qtd);
            tx.update(prodRef, {
                estoque_qtd: novo,
                estoque_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            detalhe[produtoId] = { ok: true, antes: base, depois: novo, qtd };
        }

        tx.update(pedidoRef, {
            estoque_baixado: true,
            estoque_baixado_em: admin.firestore.FieldValue.serverTimestamp(),
            estoque_baixado_detalhe: detalhe,
        });
    });

    console.log(`[estoque] baixa pedido=${pedidoId} itens=${agg.size}`);
    return { ok: true, baixado: true };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} pedidoId
 * @param {Record<string, unknown>} pedido
 */
async function restaurarEstoqueDoPedido(db, pedidoId, pedido) {
    if (pedido.estoque_baixado !== true) {
        return { ok: true, skipped: "nunca_baixado" };
    }
    if (pedido.estoque_restaurado === true) {
        return { ok: true, skipped: "ja_restaurado" };
    }

    const agg = agregarQuantidadesPorProduto(pedido.itens);
    const pedidoRef = db.collection("pedidos").doc(pedidoId);
    const lojaId = String(pedido.loja_id || pedido.lojista_id || "").trim();

    if (agg.size === 0) {
        await pedidoRef.set(
            {
                estoque_restaurado: true,
                estoque_restaurado_em: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
        );
        return { ok: true, skipped: "sem_itens" };
    }

    const detalhe = {};

    await db.runTransaction(async (tx) => {
        const pedSnap = await tx.get(pedidoRef);
        if (!pedSnap.exists) return;
        const atual = pedSnap.data() || {};
        if (atual.estoque_baixado !== true || atual.estoque_restaurado === true) return;

        for (const [produtoId, qtd] of agg.entries()) {
            const prodRef = db.collection("produtos").doc(produtoId);
            const prodSnap = await tx.get(prodRef);
            if (!prodSnap.exists) {
                detalhe[produtoId] = { ok: false, motivo: "produto_inexistente", qtd };
                continue;
            }
            const prod = prodSnap.data() || {};
            const lojaProd = String(prod.lojista_id || prod.loja_id || "").trim();
            if (lojaId && lojaProd && lojaProd !== lojaId) {
                detalhe[produtoId] = { ok: false, motivo: "loja_divergente", qtd };
                continue;
            }

            const atualQtd = Number(prod.estoque_qtd);
            const base = Number.isFinite(atualQtd) ? atualQtd : 0;
            const novo = base + qtd;
            tx.update(prodRef, {
                estoque_qtd: novo,
                estoque_atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
            detalhe[produtoId] = { ok: true, antes: base, depois: novo, qtd };
        }

        tx.update(pedidoRef, {
            estoque_restaurado: true,
            estoque_restaurado_em: admin.firestore.FieldValue.serverTimestamp(),
            estoque_restaurado_detalhe: detalhe,
        });
    });

    console.log(`[estoque] restauração pedido=${pedidoId} itens=${agg.size}`);
    return { ok: true, restaurado: true };
}

exports.STATUS_VENDA_CONFIRMADA = STATUS_VENDA_CONFIRMADA;
exports.STATUS_CANCELADOS = STATUS_CANCELADOS;
exports.itemContaParaEstoque = itemContaParaEstoque;
exports.statusIndicaVendaConfirmada = statusIndicaVendaConfirmada;
exports.statusEhCancelado = statusEhCancelado;
exports.agregarQuantidadesPorProduto = agregarQuantidadesPorProduto;
exports.baixarEstoqueDoPedido = baixarEstoqueDoPedido;
exports.restaurarEstoqueDoPedido = restaurarEstoqueDoPedido;

exports.baixarEstoquePedidoOnCreate = functions.firestore
    .document("pedidos/{pedidoId}")
    .onCreate(async (snap, context) => {
        const pedido = snap.data() || {};
        if (!statusIndicaVendaConfirmada(pedido.status)) {
            return null;
        }
        try {
            const db = admin.firestore();
            await baixarEstoqueDoPedido(db, context.params.pedidoId, pedido);
        } catch (err) {
            console.error(
                `[estoque] erro onCreate pedido=${context.params.pedidoId}:`,
                err.message || err,
            );
        }
        return null;
    });

exports.sincronizarEstoquePedidoOnUpdate = functions.firestore
    .document("pedidos/{pedidoId}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const stAntes = String(antes.status || "").trim();
        const stDepois = String(depois.status || "").trim();
        const pedidoId = context.params.pedidoId;
        const db = admin.firestore();

        try {
            const pagamentoConfirmado =
                stAntes === STATUS_AGUARDANDO_PAGAMENTO &&
                statusIndicaVendaConfirmada(stDepois);

            if (pagamentoConfirmado) {
                await baixarEstoqueDoPedido(db, pedidoId, depois);
            }

            const cancelou =
                !statusEhCancelado(stAntes) &&
                statusEhCancelado(stDepois);

            if (cancelou) {
                await restaurarEstoqueDoPedido(db, pedidoId, depois);
            }
        } catch (err) {
            console.error(`[estoque] erro onUpdate pedido=${pedidoId}:`, err.message || err);
        }
        return null;
    });
