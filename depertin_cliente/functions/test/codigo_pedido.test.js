"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { gerarCodigoPedido } = require("../codigo_pedido");

test("gerarCodigoPedido formato PED- + 6 dígitos", () => {
    const codigo = gerarCodigoPedido("abc123xyz789FirestoreId");
    assert.match(codigo, /^PED-\d{6}$/);
});

test("gerarCodigoPedido é determinístico para o mesmo ID", () => {
    const id = "Kp9mN2xQwE7vR4sT1uY8";
    assert.equal(gerarCodigoPedido(id), gerarCodigoPedido(id));
});
