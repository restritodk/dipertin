/**
 * Fase B — carimbos de status no pedido (investigação / monitor).
 * Grava mapa `operacao_status_em.{status}` na primeira vez que o pedido entra em cada status.
 * Não envia FCM nem usa notification_dispatcher.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

function jaTemCarimbo(map, status) {
    if (!map || typeof map !== "object") return false;
    const v = map[status];
    return v != null;
}

exports.gravarOperacaoStatusEmPedidoOnCreate = functions.firestore
    .document("pedidos/{pedidoId}")
    .onCreate(async (snap) => {
        const p = snap.data() || {};
        const st = String(p.status || "").trim();
        if (!st) return null;
        if (jaTemCarimbo(p.operacao_status_em, st)) return null;
        const patch = {};
        patch[`operacao_status_em.${st}`] =
            admin.firestore.FieldValue.serverTimestamp();
        try {
            await snap.ref.update(patch);
        } catch (e) {
            console.error(
                "[operacao_status_em] onCreate falhou:",
                snap.id,
                e.message || e,
            );
        }
        return null;
    });

exports.gravarOperacaoStatusEmPedidoOnUpdate = functions.firestore
    .document("pedidos/{pedidoId}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const sa = String(antes.status || "");
        const sd = String(depois.status || "").trim();
        if (!sd || sa === sd) return null;
        if (jaTemCarimbo(depois.operacao_status_em, sd)) return null;
        const patch = {};
        patch[`operacao_status_em.${sd}`] =
            admin.firestore.FieldValue.serverTimestamp();
        try {
            await change.after.ref.update(patch);
        } catch (e) {
            console.error(
                "[operacao_status_em] onUpdate falhou:",
                context.params.pedidoId,
                e.message || e,
            );
        }
        return null;
    });
