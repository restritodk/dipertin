"use strict";

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const H = require("./cupom_helpers");

/**
 * validarCupom — onCall v1
 *
 * Tipos: porcentagem, fixo, frete_gratis.
 * Cupom de loja: escopo=loja + loja_id.
 * Frete grátis: custo do frete para o lojista; entregador/plataforma sobre frete integral.
 */
exports.validarCupom = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Autenticação necessária.",
        );
    }

    const codigo = String(data?.codigo ?? "").trim().toUpperCase();
    const subtotalProdutos = H.roundMoney(Number(data?.subtotal_produtos ?? 0));
    const taxaEntrega = H.roundMoney(Number(data?.taxa_entrega ?? 0));
    const lojaId = String(data?.loja_id ?? "").trim();
    const retiradaNaLoja = data?.retirada_na_loja === true;

    let lojaIds = [];
    if (Array.isArray(data?.loja_ids)) {
        lojaIds = data.loja_ids
            .map((x) => String(x || "").trim())
            .filter((x) => x.length > 0);
    }
    if (lojaIds.length === 0 && lojaId) {
        lojaIds = [lojaId];
    }
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

    const vigencia = H.cupomDentroDaVigencia(cupom);
    if (!vigencia.ok) {
        return { valid: false, mensagem: vigencia.mensagem };
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

        const checkoutsUnicos = new Set();
        pedidosSnap.docs.forEach((pDoc) => {
            const pData = pDoc.data() || {};
            const st = String(pData.status || "").toLowerCase();
            if (st === "cancelado" || st === "recusado") return;
            const grupo = String(pData.checkout_grupo_id || "").trim();
            const chave = grupo ? `g:${grupo}` : `p:${pDoc.id}`;
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

    const tipo = String(cupom.tipo || H.TIPOS_CUPOM.PORCENTAGEM).toLowerCase();
    const valor = Number(cupom.valor || 0);

    if (tipo === H.TIPOS_CUPOM.FRETE_GRATIS) {
        const freteCheck = H.validarFreteGratisRaio(cupom, {
            retirada_na_loja: retiradaNaLoja,
            taxa_entrega: taxaEntrega,
            distancia_entrega_km: data?.distancia_entrega_km,
            loja_latitude: data?.loja_latitude,
            loja_longitude: data?.loja_longitude,
            entrega_latitude: data?.entrega_latitude,
            entrega_longitude: data?.entrega_longitude,
        });
        if (!freteCheck.ok) {
            return { valid: false, mensagem: freteCheck.mensagem };
        }
        const descontoFrete = H.roundMoney(freteCheck.descontoFrete);
        return {
            valid: true,
            cupom_id: doc.id,
            tipo_desconto: H.TIPOS_CUPOM.FRETE_GRATIS,
            valor_desconto: descontoFrete,
            desconto_cupom_produto: 0,
            desconto_cupom_frete: descontoFrete,
            percentual: null,
            mensagem: `Frete grátis aplicado! Você economiza R$ ${descontoFrete.toFixed(2)} na entrega.`,
        };
    }

    const descontoProduto = H.calcularDescontoProduto(
        tipo,
        valor,
        subtotalProdutos,
    );

    return {
        valid: true,
        cupom_id: doc.id,
        tipo_desconto: tipo,
        valor_desconto: descontoProduto,
        desconto_cupom_produto: descontoProduto,
        desconto_cupom_frete: 0,
        percentual: tipo === H.TIPOS_CUPOM.PORCENTAGEM ? valor : null,
        mensagem:
            tipo === H.TIPOS_CUPOM.PORCENTAGEM
                ? `Cupom aplicado! ${valor}% de desconto nos produtos.`
                : `Cupom aplicado! R$ ${descontoProduto.toFixed(2)} de desconto nos produtos.`,
    };
});
