"use strict";

/**
 * Split financeiro completo — fonte de verdade no servidor.
 *
 * Bases independentes:
 *   subtotal_produtos → comissão lojista (planos_taxas publico=lojista)
 *   subtotal_frete    → comissão entregador (planos_taxas publico=entregador)
 *
 * Cupom:
 *   desconto_cupom reduz o valor pago pelo cliente.
 *   A comissão do lojista incide sobre o valor bruto dos produtos (antes do cupom).
 *   O custo do cupom é absorvido pela plataforma.
 *
 * Distribuição:
 *   valor_liquido_lojista     = valor_produto - taxa_plataforma
 *   valor_liquido_entregador  = valor_frete   - taxa_entregador
 *   valor_plataforma          = taxa_plataforma + taxa_entregador
 *   valor_total_pago_cliente  = valor_produto + valor_frete - desconto_cupom - desconto_saldo
 */

const admin = require("firebase-admin");

function roundMoney(v) {
    const n = Number(v);
    if (Number.isNaN(n)) return 0;
    return Math.round(n * 100) / 100;
}

function normalizarCidade(s) {
    return String(s || "")
        .trim()
        .toLowerCase();
}

function normalizarVeiculo(s) {
    return String(s || "")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .trim()
        .toLowerCase();
}

// ── Comissão genérica ──────────────────────────────────────────────

/**
 * @param {number} base  Valor base (produtos ou frete)
 * @param {{ tipo_cobranca?: string, valor?: number } | null} plano
 * @returns {number}
 */
function calcularComissao(base, plano) {
    if (!plano || base <= 0) return 0;
    const tipo = String(plano.tipo_cobranca || "").toLowerCase();
    const v = Number(plano.valor || 0);
    if (Number.isNaN(v)) return 0;
    if (tipo === "fixo") {
        return roundMoney(Math.min(base, Math.max(0, v)));
    }
    return roundMoney(base * (v / 100));
}

/** Alias retrocompatível (usada em código legado). */
function calcularTaxaPlataforma(valorProduto, plano) {
    return calcularComissao(valorProduto, plano);
}

// ── Carregamento de planos ─────────────────────────────────────────

/**
 * Busca plano de comissão por público e cidade.
 * Prioridade: cidade exata > "todas".
 */
async function carregarPlanoComissao(db, publico, cidadeLoja, opcoes = {}) {
    const cidadeBusca = normalizarCidade(cidadeLoja);
    const veiculoBusca = normalizarVeiculo(opcoes.veiculoEntregador);
    const snap = await db
        .collection("planos_taxas")
        .where("publico", "==", publico)
        .get();

    const lista = [];
    snap.forEach((doc) => {
        const d = doc.data();
        if (d.ativo === false) return;
        const pc = normalizarCidade(d.cidade);
        const isTodas = pc === "todas" || pc === "" || pc === "todas as cidades";
        let prioCidade = 0;
        if (pc === cidadeBusca && cidadeBusca) {
            prioCidade = 2;
        } else if (isTodas) {
            prioCidade = 1;
        } else {
            return;
        }

        let prioVeiculo = 0;
        if (publico === "entregador") {
            const pv = normalizarVeiculo(d.veiculo || "todos");
            const veiculoTodos = pv === "" || pv === "todos" || pv === "todas";
            if (veiculoBusca) {
                if (pv === veiculoBusca) {
                    prioVeiculo = 2;
                } else if (veiculoTodos) {
                    prioVeiculo = 1;
                } else {
                    return;
                }
            } else {
                prioVeiculo = veiculoTodos ? 1 : 0;
            }
        }

        lista.push({
            id: doc.id,
            data: d,
            prioCidade,
            prioVeiculo,
        });
    });
    lista.sort((a, b) => {
        if (b.prioCidade !== a.prioCidade) {
            return b.prioCidade - a.prioCidade;
        }
        return (b.prioVeiculo || 0) - (a.prioVeiculo || 0);
    });
    if (lista.length === 0) return null;
    return { id: lista[0].id, data: lista[0].data };
}

async function carregarPlanoComissaoLojista(db, cidadeLoja) {
    return carregarPlanoComissao(db, "lojista", cidadeLoja);
}

async function carregarPlanoComissaoEntregador(db, cidadeLoja, veiculoEntregador) {
    return carregarPlanoComissao(db, "entregador", cidadeLoja, {
        veiculoEntregador,
    });
}

// ── Cálculo principal ──────────────────────────────────────────────

/**
 * Calcula todos os campos financeiros do pedido.
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} pedido — snapshot do doc `pedidos`
 * @returns {Promise<object>}
 */
async function calcularCamposFinanceirosPedido(db, pedido, opcoes = {}) {
    const valorProduto = roundMoney(
        Number(
            pedido.total_produtos != null && pedido.total_produtos !== ""
                ? pedido.total_produtos
                : pedido.subtotal ?? 0,
        ),
    );
    const valorFrete = roundMoney(Number(pedido.taxa_entrega ?? 0));
    const descontoSaldo = roundMoney(Number(pedido.desconto_saldo ?? 0));
    const descontoCupom = roundMoney(Number(pedido.desconto_cupom ?? 0));
    const cupomId = pedido.cupom_id || null;
    const cupomCodigo = pedido.cupom_codigo || null;

    const valorTotalPagoCliente = roundMoney(
        Math.max(0, valorProduto + valorFrete - descontoCupom - descontoSaldo),
    );

    const lojaId = pedido.loja_id || pedido.lojista_id;
    let planoLojistaWrap = null;
    let planoEntregadorWrap = null;
    let cidadeLoja = "";

    if (lojaId) {
        const lojaSnap = await db.collection("users").doc(String(lojaId)).get();
        if (lojaSnap.exists) {
            const u = lojaSnap.data();
            cidadeLoja =
                u.cidade_normalizada || u.cidade || u.endereco_cidade || "";
            planoLojistaWrap = await carregarPlanoComissaoLojista(
                db,
                String(cidadeLoja),
            );
        }
    }

    if (valorFrete > 0) {
        planoEntregadorWrap = await carregarPlanoComissaoEntregador(
            db,
            String(cidadeLoja),
            opcoes.veiculoEntregador,
        );
    }

    // Comissão lojista (incide sobre bruto dos produtos, antes do cupom)
    const planoLojista = planoLojistaWrap ? planoLojistaWrap.data : null;
    const taxaPlataforma = calcularComissao(valorProduto, planoLojista);
    const valorLiquidoLojista = roundMoney(
        Math.max(0, valorProduto - taxaPlataforma),
    );

    // Comissão entregador (incide sobre o frete)
    const planoEntregador = planoEntregadorWrap
        ? planoEntregadorWrap.data
        : null;
    const taxaEntregador = calcularComissao(valorFrete, planoEntregador);
    const valorLiquidoEntregador = roundMoney(
        Math.max(0, valorFrete - taxaEntregador),
    );

    // Receita da plataforma = soma das comissões
    const valorPlataforma = roundMoney(taxaPlataforma + taxaEntregador);

    return {
        valor_produto: valorProduto,
        valor_frete: valorFrete,
        desconto_cupom: descontoCupom,
        cupom_id: cupomId,
        cupom_codigo: cupomCodigo,
        taxa_plataforma: taxaPlataforma,
        taxa_entregador: taxaEntregador,
        valor_liquido_lojista: valorLiquidoLojista,
        valor_liquido_entregador: valorLiquidoEntregador,
        valor_plataforma: valorPlataforma,
        valor_total_pago_cliente: valorTotalPagoCliente,
        plano_taxa_plataforma_id: planoLojistaWrap
            ? planoLojistaWrap.id
            : null,
        plano_taxa_entregador_id: planoEntregadorWrap
            ? planoEntregadorWrap.id
            : null,
    };
}

/**
 * Valor a creditar na carteira do lojista na entrega.
 */
async function obterValorLiquidoParaCredito(db, pedidoData) {
    if (
        pedidoData.financeiro_servidor_ok === true &&
        pedidoData.valor_liquido_lojista != null &&
        pedidoData.valor_liquido_lojista !== ""
    ) {
        return roundMoney(Number(pedidoData.valor_liquido_lojista));
    }
    const c = await calcularCamposFinanceirosPedido(db, pedidoData);
    return roundMoney(Number(c.valor_liquido_lojista));
}

/**
 * Valor a creditar na carteira do entregador na entrega.
 */
async function obterValorLiquidoEntregadorParaCredito(db, pedidoData) {
    if (
        pedidoData.financeiro_servidor_ok === true &&
        pedidoData.valor_liquido_entregador != null &&
        pedidoData.valor_liquido_entregador !== ""
    ) {
        return roundMoney(Number(pedidoData.valor_liquido_entregador));
    }
    const c = await calcularCamposFinanceirosPedido(db, pedidoData);
    return roundMoney(Number(c.valor_liquido_entregador));
}

module.exports = {
    roundMoney,
    normalizarCidade,
    calcularComissao,
    calcularTaxaPlataforma,
    carregarPlanoComissao,
    carregarPlanoComissaoLojista,
    carregarPlanoComissaoEntregador,
    calcularCamposFinanceirosPedido,
    calcularRepassePedido: calcularCamposFinanceirosPedido,
    obterValorLiquidoParaCredito,
    obterValorLiquidoEntregadorParaCredito,
};
