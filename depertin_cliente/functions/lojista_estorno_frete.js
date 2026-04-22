// Fase 3G.3 — callable de estorno do frete quando o cliente retira o pedido na
// loja (tipo_entrega originalmente "entrega", mas o cliente decidiu buscar).
//
// Motivo da callable: o app do lojista fazia `update` direto em
// `users/{cliente_id}.saldo`, o que exigia que a rule de `users` permitisse
// escrita entre autenticados. Isso é perigoso (qualquer lojista/cliente podia
// creditar saldo em qualquer conta). Agora a rule de `users` fica fechada a
// dono+staff+colaborador, e o estorno passa por esta função (Admin SDK).
//
// Regras de autorização:
//   - Caller precisa estar autenticado.
//   - Caller precisa ser o dono da loja do pedido (`auth.uid == loja_id`) OU
//     colaborador painel do dono (`users/{auth.uid}.lojista_owner_uid == loja_id`).
//   - Pedido não pode já estar finalizado (entregue/cancelado).
//   - Pedido precisa ser de entrega (não retirada original) com taxa > 0 pra
//     fazer sentido estornar.

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");

const STATUS_FINAIS = [
    "entregue",
    "cancelado",
    "cancelado_pelo_cliente",
    "cancelado_pela_loja",
    "cancelado_pelo_lojista",
    "estornado",
    "expirado",
];

async function resolverLojaDoCaller(uidCaller) {
    const snap = await admin
        .firestore()
        .collection("users")
        .doc(uidCaller)
        .get();
    if (!snap.exists) return uidCaller;
    const data = snap.data() || {};
    const owner = (data.lojista_owner_uid || "").toString().trim();
    return owner || uidCaller;
}

/**
 * Lojista confirma que o cliente retirou o pedido de entrega na loja, devolve
 * a taxa de entrega para a carteira do cliente e marca o pedido como entregue.
 *
 * Request: { pedidoId: string }
 * Response: { ok: true, taxaEstornada: number }
 */
exports.lojistaConfirmarRetiradaNaLojaComEstorno = functions.https.onCall(
    async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "Faça login para confirmar a retirada.",
            );
        }

        const pedidoId = (data && data.pedidoId ? data.pedidoId : "")
            .toString()
            .trim();
        if (!pedidoId) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "pedidoId é obrigatório.",
            );
        }

        const uidCaller = context.auth.uid;
        const lojaCaller = await resolverLojaDoCaller(uidCaller);
        const db = admin.firestore();
        const pedidoRef = db.collection("pedidos").doc(pedidoId);

        const resultado = await db.runTransaction(async (tx) => {
            const pedidoSnap = await tx.get(pedidoRef);
            if (!pedidoSnap.exists) {
                throw new functions.https.HttpsError(
                    "not-found",
                    "Pedido não encontrado.",
                );
            }
            const pedido = pedidoSnap.data() || {};
            const lojaIdPedido = (pedido.loja_id || "").toString();
            if (lojaIdPedido !== lojaCaller) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "Este pedido não pertence à sua loja.",
                );
            }
            const statusAtual = (pedido.status || "").toString();
            if (STATUS_FINAIS.includes(statusAtual)) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "O pedido já foi finalizado e não pode ser alterado.",
                );
            }

            const clienteId = (pedido.cliente_id || "").toString().trim();
            const taxaEntregaRaw = pedido.taxa_entrega;
            const taxaEntrega =
                typeof taxaEntregaRaw === "number"
                    ? taxaEntregaRaw
                    : parseFloat(taxaEntregaRaw) || 0;
            const jaEstornado = pedido.frete_estornado === true;

            if (taxaEntrega > 0 && clienteId && !jaEstornado) {
                const clienteRef = db.collection("users").doc(clienteId);
                tx.update(clienteRef, {
                    saldo: admin.firestore.FieldValue.increment(taxaEntrega),
                });
            }

            tx.update(pedidoRef, {
                status: "entregue",
                frete_estornado:
                    taxaEntrega > 0 && clienteId ? true : jaEstornado,
                data_entregue: admin.firestore.FieldValue.serverTimestamp(),
                observacao_loja:
                    "Cliente retirou na loja. Frete estornado para a carteira.",
            });

            return {
                ok: true,
                taxaEstornada:
                    taxaEntrega > 0 && clienteId && !jaEstornado
                        ? taxaEntrega
                        : 0,
            };
        });

        return resultado;
    },
);
