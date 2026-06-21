"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const R = require("../repasse_financeiro");

test("calcularComissao 0% não cobra do lojista", () => {
    assert.equal(R.calcularComissao(100, { tipo_cobranca: "porcentagem", valor: 0 }), 0);
    assert.equal(R.calcularComissao(250.5, { tipo_cobranca: "porcentagem", valor: 0 }), 0);
});

test("calcularComissao percentual aplica só sobre a base de produtos", () => {
    assert.equal(
        R.calcularComissao(100, { tipo_cobranca: "porcentagem", valor: 12 }),
        12,
    );
    assert.equal(
        R.calcularComissao(50, { tipo_cobranca: "porcentagem", valor: 12 }),
        6,
    );
});

test("calcularComissao fixo respeita teto da base", () => {
    assert.equal(
        R.calcularComissao(80, { tipo_cobranca: "fixo", valor: 5 }),
        5,
    );
    assert.equal(
        R.calcularComissao(3, { tipo_cobranca: "fixo", valor: 5 }),
        3,
    );
});

test("calcularComissao sem plano ou base zero retorna zero", () => {
    assert.equal(R.calcularComissao(100, null), 0);
    assert.equal(R.calcularComissao(0, { tipo_cobranca: "porcentagem", valor: 12 }), 0);
});
