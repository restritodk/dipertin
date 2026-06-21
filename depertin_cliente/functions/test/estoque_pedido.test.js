"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const E = require("../estoque_pedido");

test("itemContaParaEstoque ignora encomenda", () => {
    assert.equal(E.itemContaParaEstoque({ tipo_venda: "encomenda" }), false);
    assert.equal(E.itemContaParaEstoque({ tipo_venda: "pronta_entrega" }), true);
    assert.equal(E.itemContaParaEstoque({}), true);
});

test("agregarQuantidadesPorProduto soma por id_produto", () => {
    const mapa = E.agregarQuantidadesPorProduto([
        { id_produto: "a", quantidade: 2, tipo_venda: "pronta_entrega" },
        { id_produto: "a", quantidade: 1 },
        { id_produto: "b", quantidade: 3, tipo_venda: "encomenda" },
    ]);
    assert.equal(mapa.get("a"), 3);
    assert.equal(mapa.has("b"), false);
});

test("statusIndicaVendaConfirmada", () => {
    assert.equal(E.statusIndicaVendaConfirmada("pendente"), true);
    assert.equal(E.statusIndicaVendaConfirmada("aguardando_pagamento"), false);
    assert.equal(E.statusIndicaVendaConfirmada("cancelado"), false);
    assert.equal(E.statusIndicaVendaConfirmada("encomenda_entrada_paga"), false);
});

test("statusEhCancelado", () => {
    assert.equal(E.statusEhCancelado("cancelado"), true);
    assert.equal(E.statusEhCancelado("recusado"), true);
    assert.equal(E.statusEhCancelado("pendente"), false);
});
