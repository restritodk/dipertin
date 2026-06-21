/**
 * Avaliação por produto.
 *
 * Documento: avaliacoes_produto/{pedidoId}_{produtoId}
 *   - pedido_id, produto_id, loja_id, cliente_id
 *   - nota (1..5), comentario?, cliente_nome_exibicao?, produto_nome?
 *   - data (serverTimestamp)
 *
 * Agrega de forma incremental em produtos/{produto_id}:
 *   - total_avaliacoes (contagem)
 *   - rating_soma (soma das notas — campo interno p/ recálculo robusto)
 *   - rating_media (rating_soma / total_avaliacoes, 2 casas)
 *
 * Tratamos onCreate/onUpdate/onDelete para evitar inconsistência quando o
 * cliente edita ou remove a avaliação (diferente do rating de loja, que só
 * agregava no onCreate).
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

function notaValida(n) {
    const v = Number(n);
    return Number.isFinite(v) && v >= 1 && v <= 5;
}

async function aplicarDeltaRatingProduto(produtoId, deltaSoma, deltaCount) {
    if (!produtoId) return;
    const db = admin.firestore();
    const ref = db.collection("produtos").doc(String(produtoId));
    try {
        await db.runTransaction(async (t) => {
            const doc = await t.get(ref);
            if (!doc.exists) return;
            const d = doc.data() || {};
            const oldCount = Number(d.total_avaliacoes || 0);
            const oldSoma = Number(
                d.rating_soma != null
                    ? d.rating_soma
                    : Number(d.rating_media || 0) * oldCount,
            );
            let newCount = oldCount + deltaCount;
            let newSoma = oldSoma + deltaSoma;
            if (newCount < 0) newCount = 0;
            if (newSoma < 0) newSoma = 0;
            const media =
                newCount > 0
                    ? Math.round((newSoma / newCount) * 100) / 100
                    : 0;
            t.set(
                ref,
                {
                    total_avaliacoes: newCount,
                    rating_soma: newSoma,
                    rating_media: media,
                },
                { merge: true },
            );
        });
    } catch (e) {
        console.error(
            `[avaliacao_produto] Erro ao agregar produto ${produtoId}:`,
            e.message,
        );
    }
}

exports.atualizarRatingProdutoOnCreate = functions.firestore
    .document("avaliacoes_produto/{avalId}")
    .onCreate(async (snap) => {
        const data = snap.data() || {};
        const produtoId = data.produto_id;
        const nota = Number(data.nota);
        if (!produtoId || !notaValida(nota)) {
            console.log("[avaliacao_produto] Ignorado create: dados inválidos.");
            return null;
        }
        await aplicarDeltaRatingProduto(produtoId, nota, 1);
        return null;
    });

exports.atualizarRatingProdutoOnUpdate = functions.firestore
    .document("avaliacoes_produto/{avalId}")
    .onUpdate(async (change) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const produtoId = depois.produto_id || antes.produto_id;
        const notaAntes = Number(antes.nota);
        const notaDepois = Number(depois.nota);
        if (!produtoId) return null;

        // Só a nota afeta a agregação.
        const valAntes = notaValida(notaAntes) ? notaAntes : 0;
        const valDepois = notaValida(notaDepois) ? notaDepois : 0;
        const deltaSoma = valDepois - valAntes;
        if (deltaSoma === 0) return null;
        await aplicarDeltaRatingProduto(produtoId, deltaSoma, 0);
        return null;
    });

exports.atualizarRatingProdutoOnDelete = functions.firestore
    .document("avaliacoes_produto/{avalId}")
    .onDelete(async (snap) => {
        const data = snap.data() || {};
        const produtoId = data.produto_id;
        const nota = Number(data.nota);
        if (!produtoId || !notaValida(nota)) return null;
        await aplicarDeltaRatingProduto(produtoId, -nota, -1);
        return null;
    });
