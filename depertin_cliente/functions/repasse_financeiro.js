"use strict";

/**
 * Split financeiro completo — fonte de verdade no servidor.
 *
 * Bases independentes:
 *   subtotal_produtos → comissão lojista (planos_taxas publico=lojista)
 *   subtotal_frete    → comissão entregador (planos_taxas publico=entregador)
 *
 * Cupom:
 *   desconto_cupom_produto / desconto_cupom_frete reduzem o valor pago pelo cliente.
 *   Comissão da plataforma sobre produtos incide após desconto de produtos (base líquida).
 *   Frete grátis: cliente não paga frete; entregador e comissão sobre frete usam taxa integral;
 *   subsídio do frete é debitado do líquido do lojista.
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
    const v = Number(plano.valor ?? 0);
    if (Number.isNaN(v) || v <= 0) return 0;
    if (tipo === "fixo") {
        return roundMoney(Math.min(base, v));
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

/**
 * Plano atribuído à loja no painel (`users.plano_taxa_id`).
 * Tem prioridade sobre busca por cidade.
 */
async function carregarPlanoComissaoPorId(db, planoId, publicoEsperado) {
    const id = String(planoId || "").trim();
    if (!id) return null;
    const snap = await db.collection("planos_taxas").doc(id).get();
    if (!snap.exists) return null;
    const d = snap.data() || {};
    if (d.ativo === false) return null;
    if (publicoEsperado && String(d.publico || "") !== publicoEsperado) {
        return null;
    }
    return { id: snap.id, data: d };
}

async function carregarPlanoComissaoLojista(db, cidadeLoja, planoIdLoja) {
    const porId = await carregarPlanoComissaoPorId(db, planoIdLoja, "lojista");
    if (porId) return porId;
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
    let descontoCupomProduto = roundMoney(
        Number(pedido.desconto_cupom_produto ?? 0),
    );
    let descontoCupomFrete = roundMoney(
        Number(pedido.desconto_cupom_frete ?? 0),
    );
    const descontoCupomLegado = roundMoney(Number(pedido.desconto_cupom ?? 0));
    if (
        descontoCupomProduto === 0 &&
        descontoCupomFrete === 0 &&
        descontoCupomLegado > 0
    ) {
        descontoCupomProduto = descontoCupomLegado;
    }
    const descontoCupom = roundMoney(
        descontoCupomProduto + descontoCupomFrete,
    );
    const cupomId = pedido.cupom_id || null;
    const cupomCodigo = pedido.cupom_codigo || null;

    const valorTotalPagoCliente = roundMoney(
        Math.max(
            0,
            valorProduto +
                valorFrete -
                descontoCupomProduto -
                descontoCupomFrete -
                descontoSaldo,
        ),
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
                u.plano_taxa_id,
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

    const isEncomendaSaldoFinal =
        pedido.tipo_compra === "encomenda" &&
        pedido.encomenda_fase_financeira === "saldo_final";

    const valorTotalProdutoNegociado = roundMoney(
        Number(
            pedido.valor_total_produto != null && pedido.valor_total_produto !== ""
                ? pedido.valor_total_produto
                : pedido.valor_total_encomenda_referencia ?? valorProduto,
        ),
    );
    const valorEntradaProduto = roundMoney(
        Number(
            pedido.valor_entrada_produto != null &&
            pedido.valor_entrada_produto !== ""
                ? pedido.valor_entrada_produto
                : pedido.valor_entrada_acordado ?? 0,
        ),
    );
    const valorRestanteProduto = roundMoney(
        Number(
            pedido.valor_restante_produto != null &&
            pedido.valor_restante_produto !== ""
                ? pedido.valor_restante_produto
                : valorProduto,
        ),
    );
    const valorTotalFreteRegistro = roundMoney(
        Number(
            pedido.valor_total_frete != null && pedido.valor_total_frete !== ""
                ? pedido.valor_total_frete
                : pedido.valor_frete_encomenda ?? valorFrete,
        ),
    );

    // Comissão lojista sobre produtos após desconto de cupom (custo do cupom = lojista)
    const baseComissaoProduto = roundMoney(
        Math.max(0, valorProduto - descontoCupomProduto),
    );
    const planoLojista = planoLojistaWrap ? planoLojistaWrap.data : null;
    const taxaPlataformaProduto = calcularComissao(
        baseComissaoProduto,
        planoLojista,
    );
    let valorLiquidoLojista = roundMoney(
        Math.max(
            0,
            baseComissaoProduto -
                taxaPlataformaProduto -
                descontoCupomFrete,
        ),
    );

    // Encomenda saldo: entrada já paga sem taxa — soma no crédito do lojista na entrega.
    if (isEncomendaSaldoFinal && valorEntradaProduto > 0) {
        valorLiquidoLojista = roundMoney(
            valorLiquidoLojista + valorEntradaProduto,
        );
    }

    // Comissão entregador (incide sobre o frete)
    const planoEntregador = planoEntregadorWrap
        ? planoEntregadorWrap.data
        : null;
    const taxaPlataformaFrete = calcularComissao(valorFrete, planoEntregador);
    const valorLiquidoEntregador = roundMoney(
        Math.max(0, valorFrete - taxaPlataformaFrete),
    );

    const taxaPlataforma = roundMoney(
        taxaPlataformaProduto + taxaPlataformaFrete,
    );

    // Receita da plataforma = soma das comissões
    const valorPlataforma = taxaPlataforma;

    const out = {
        valor_produto: valorProduto,
        valor_frete: valorFrete,
        desconto_cupom: descontoCupom,
        desconto_cupom_produto: descontoCupomProduto,
        desconto_cupom_frete: descontoCupomFrete,
        cupom_tipo: pedido.cupom_tipo || null,
        cupom_id: cupomId,
        cupom_codigo: cupomCodigo,
        taxa_plataforma: taxaPlataforma,
        taxa_entregador: taxaPlataformaFrete,
        taxa_plataforma_produto: taxaPlataformaProduto,
        taxa_plataforma_frete: taxaPlataformaFrete,
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

    if (isEncomendaSaldoFinal) {
        out.valor_total_produto = valorTotalProdutoNegociado;
        out.valor_entrada_produto = valorEntradaProduto;
        out.valor_restante_produto = valorRestanteProduto;
        out.valor_total_frete = valorTotalFreteRegistro;
    }

    return out;
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
    carregarPlanoComissaoPorId,
    carregarPlanoComissaoLojista,
    carregarPlanoComissaoEntregador,
    calcularCamposFinanceirosPedido,
    calcularRepassePedido: calcularCamposFinanceirosPedido,
    obterValorLiquidoParaCredito,
    obterValorLiquidoEntregadorParaCredito,
};
