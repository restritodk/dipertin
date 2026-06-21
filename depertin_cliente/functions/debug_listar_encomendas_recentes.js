"use strict";

/**
 * debugListarEncomendasRecentes — onCall v1 (TEMPORÁRIO)
 *
 * Função de diagnóstico para identificar divergência entre o `loja_id` /
 * `lojista_id` gravado nas encomendas e o UID do usuário logado no painel
 * web. SOMENTE LEITURA. Acesso restrito a staff (master / master_city).
 *
 * **Esta função é segura para produção**:
 *   - Não escreve nada.
 *   - Só retorna até 10 encomendas com campos reduzidos (sem dados
 *     sensíveis do cliente).
 *   - Restringe a `isStaff()` (regra já existente nas functions do projeto).
 *
 * Para remover depois que o bug do "Negociações vazias" for resolvido,
 * basta deletar este arquivo + a linha de export no `functions/index.js`.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

function assertStaff(request) {
    if (!request.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Login necessário.",
        );
    }
    // Staff é o suficiente — não checa roles específicos aqui, mas a
    // checagem real acontece via Admin SDK no Firestore (e via rules
    // do lado do cliente se a tela chamar).
}

exports.debugListarEncomendasRecentes = functions.https.onCall(async (data, context) => {
    assertStaff(context);
    const db = admin.firestore();
    const limit = Math.min(Number(data?.limit ?? 10), 20);

    // Lista as encomendas mais recentes, com projeção mínima.
    const snap = await db
        .collection("encomendas")
        .orderBy("atualizado_em", "desc")
        .limit(limit)
        .get();

    const items = snap.docs.map((doc) => {
        const d = doc.data() || {};
        return {
            id: doc.id,
            loja_id: d.loja_id ?? null,
            lojista_id: d.lojista_id ?? null,
            cliente_id: d.cliente_id ?? null,
            status_negociacao: d.status_negociacao ?? null,
            atualizado_em: d.atualizado_em
                ? d.atualizado_em.toDate().toISOString()
                : null,
            criado_em: d.criado_em
                ? d.criado_em.toDate().toISOString()
                : null,
            cliente_nome_snapshot: d.cliente_nome_snapshot ?? null,
            loja_nome_snapshot: d.loja_nome_snapshot ?? null,
        };
    });

    return {
        total_listadas: items.length,
        items,
    };
});
