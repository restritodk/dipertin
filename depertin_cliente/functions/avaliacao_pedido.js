/**
 * Nova avaliação (doc id = pedido_id) → atualiza rating_media e total_avaliacoes em users/{loja_id}.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

exports.atualizarRatingLojaAposAvaliacao = functions.firestore
    .document("avaliacoes/{pedidoId}")
    .onCreate(async (snap, context) => {
        const data = snap.data() || {};
        const lojaId = data.loja_id;
        const nota = Number(data.nota);
        if (!lojaId || Number.isNaN(nota) || nota < 1 || nota > 5) {
            console.log("[avaliacao] Ignorado: loja_id ou nota inválidos.");
            return null;
        }

        const db = admin.firestore();
        const lojaRef = db.collection("users").doc(String(lojaId));

        try {
            await db.runTransaction(async (t) => {
                const doc = await t.get(lojaRef);
                const d = doc.data() || {};
                const oldCount = Number(d.total_avaliacoes || 0);
                const oldMedia = Number(d.rating_media || 0);
                const newCount = oldCount + 1;
                const newMedia =
                    oldCount === 0
                        ? nota
                        : (oldMedia * oldCount + nota) / newCount;
                const rounded = Math.round(newMedia * 100) / 100;
                t.set(
                    lojaRef,
                    {
                        total_avaliacoes: newCount,
                        rating_media: rounded,
                    },
                    { merge: true },
                );
            });
            console.log(
                `[avaliacao] Loja ${lojaId} atualizada (nota=${nota}).`,
            );
        } catch (e) {
            console.error("[avaliacao] Erro ao atualizar loja:", e.message);
        }
        return null;
    });
