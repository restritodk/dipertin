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

    // `loja_ids` é a lista COMPLETA de lojas únicas presentes no carrinho.
    // Para cupons de escopo "loja", essa lista define se podemos aceitar
    // o cupom (não pode haver outras lojas no carrinho além da do cupom).
    // Compat retroativa: se o app antigo não enviar `loja_ids`, usamos `loja_id`.
    let lojaIds = [];
    if (Array.isArray(data?.loja_ids)) {
        lojaIds = data.loja_ids
            .map((x) => String(x || "").trim())
            .filter((x) => x.length > 0);
    }
    if (lojaIds.length === 0 && lojaId) {
        lojaIds = [lojaId];
    }
    // Dedup final
    lojaIds = Array.from(new Set(lojaIds));

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

        // Conta CHECKOUTS únicos, não pedidos. Em multi-loja, 1 compra
        // gera N pedidos com o mesmo `checkout_grupo_id` mas representa
        // apenas 1 uso do cupom (mesma regra do contador global em
        // `processarFinanceiroPedidoOnCreate`). Pedidos cancelados/recusados
        // antes da entrega NÃO consomem uso (cliente pode tentar de novo).
        const checkoutsUnicos = new Set();
        pedidosSnap.docs.forEach((doc) => {
            const data = doc.data() || {};
            const st = String(data.status || "").toLowerCase();
            // Pedidos cancelados (PIX expirado, cliente desistiu, recusa)
            // não devem contar como uso consumido — libera o cupom de novo.
            if (st === "cancelado" || st === "recusado") return;
            const grupo = String(data.checkout_grupo_id || "").trim();
            const chave = grupo ? `g:${grupo}` : `p:${doc.id}`;
            checkoutsUnicos.add(chave);
        });

        if (checkoutsUnicos.size >= limitePorUsuario) {
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
        const lojaCupom = String(cupom.loja_id);

        // Cupom restrito a UMA loja: o carrinho não pode conter itens
        // de outras lojas — não há como aplicar parcial só nessa loja
        // sem distorcer o desconto (rateio iria para outras lojas que
        // não fazem parte do escopo do cupom). Regra: tudo ou nada.
        if (lojaIds.length > 1) {
            return {
                valid: false,
                mensagem:
                    "Este cupom é válido apenas para uma loja específica. " +
                    "Remova os produtos das outras lojas do carrinho para usá-lo.",
            };
        }
        if (lojaIds.length === 1 && lojaIds[0] !== lojaCupom) {
            return {
                valid: false,
                mensagem: "Este cupom não é válido para esta loja.",
            };
        }
        if (lojaIds.length === 0) {
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
