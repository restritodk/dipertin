"use strict";

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

/**
 * validarCupom — onCall v1
 *
 * Valida cupom no servidor antes do checkout.
 * Checks: ativo, validade, limite_usos (global), limite_por_usuario, valor_minimo.
 * Retorna: { valid, cupom_id, tipo_desconto, valor_desconto, mensagem }
 */
exports.validarCupom = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Autenticação necessária.",
        );
    }

    const codigo = String(data?.codigo ?? "").trim().toUpperCase();
    const subtotalProdutos = Number(data?.subtotal_produtos ?? 0);
    const lojaId = String(data?.loja_id ?? "").trim();
    const clienteId = context.auth.uid;

    if (!codigo) {
        return { valid: false, mensagem: "Informe o código do cupom." };
    }

    const db = admin.firestore();

    const snap = await db
        .collection("cupons")
        .where("codigo", "==", codigo)
        .limit(1)
        .get();

    if (snap.empty) {
        return { valid: false, mensagem: "Cupom não encontrado." };
    }

    const doc = snap.docs[0];
    const cupom = doc.data();

    if (cupom.ativo !== true) {
        return { valid: false, mensagem: "Este cupom está desativado." };
    }

    if (cupom.validade) {
        const validade = cupom.validade.toDate
            ? cupom.validade.toDate()
            : new Date(cupom.validade);
        if (validade < new Date()) {
            return { valid: false, mensagem: "Este cupom expirou." };
        }
    }

    const limiteUsos = Number(cupom.limite_usos ?? 0);
    const usosAtual = Number(cupom.usos_atual ?? 0);
    if (limiteUsos > 0 && usosAtual >= limiteUsos) {
        return { valid: false, mensagem: "Este cupom atingiu o limite de usos." };
    }

    const limitePorUsuario = Number(cupom.limite_por_usuario ?? 0);
    if (limitePorUsuario > 0) {
        const pedidosSnap = await db
            .collection("pedidos")
            .where("cliente_id", "==", clienteId)
            .where("cupom_codigo", "==", codigo)
            .get();
        if (pedidosSnap.size >= limitePorUsuario) {
            return {
                valid: false,
                mensagem: "Você já utilizou este cupom o número máximo de vezes.",
            };
        }
    }

    const valorMinimo = Number(cupom.valor_minimo ?? 0);
    if (valorMinimo > 0 && subtotalProdutos < valorMinimo) {
        return {
            valid: false,
            mensagem: `Valor mínimo do pedido: R$ ${valorMinimo.toFixed(2)}.`,
        };
    }

    if (cupom.escopo === "loja" && cupom.loja_id) {
        if (lojaId !== String(cupom.loja_id)) {
            return {
                valid: false,
                mensagem: "Este cupom não é válido para esta loja.",
            };
        }
    }

    const tipo = String(cupom.tipo || "porcentagem").toLowerCase();
    const valor = Number(cupom.valor || 0);
    let desconto = 0;

    if (tipo === "porcentagem") {
        desconto = Math.round(subtotalProdutos * (valor / 100) * 100) / 100;
    } else {
        desconto = Math.round(Math.min(valor, subtotalProdutos) * 100) / 100;
    }

    desconto = Math.min(desconto, subtotalProdutos);
    desconto = Math.max(0, desconto);

    return {
        valid: true,
        cupom_id: doc.id,
        tipo_desconto: tipo,
        valor_desconto: desconto,
        percentual: tipo === "porcentagem" ? valor : null,
        mensagem:
            tipo === "porcentagem"
                ? `Cupom aplicado! ${valor}% de desconto.`
                : `Cupom aplicado! R$ ${desconto.toFixed(2)} de desconto.`,
    };
});
