"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const H = require("../cupom_helpers");

describe("cupom_helpers", () => {
    it("calcularDescontoProduto percentual", () => {
        const d = H.calcularDescontoProduto("porcentagem", 10, 100);
        assert.equal(d, 10);
    });

    it("calcularDescontoProduto fixo limitado ao subtotal", () => {
        const d = H.calcularDescontoProduto("fixo", 50, 30);
        assert.equal(d, 30);
    });

    it("cupomDentroDaVigencia rejeita antes do início", () => {
        const amanha = new Date(Date.now() + 86400000);
        const r = H.cupomDentroDaVigencia({ validade_inicio: amanha });
        assert.equal(r.ok, false);
    });

    it("cupomDentroDaVigencia aceita início no mesmo dia civil BR", () => {
        const inicio = new Date("2026-06-07T03:00:00.000Z");
        const agora = new Date("2026-06-07T12:00:00.000Z");
        const r = H.cupomDentroDaVigencia({ validade_inicio: inicio }, agora);
        assert.equal(r.ok, true);
    });

    it("cupomDentroDaVigencia rejeita início em dia civil futuro", () => {
        const inicio = new Date("2026-06-14T03:00:00.000Z");
        const agora = new Date("2026-06-07T12:00:00.000Z");
        const r = H.cupomDentroDaVigencia({ validade_inicio: inicio }, agora);
        assert.equal(r.ok, false);
        assert.match(r.mensagem, /ainda não está válido/);
    });

    it("cupomDentroDaVigencia aceita no último dia civil de vigência", () => {
        const fim = new Date("2026-07-07T03:00:00.000Z");
        const agora = new Date("2026-07-07T20:00:00.000Z");
        const r = H.cupomDentroDaVigencia({ validade: fim }, agora);
        assert.equal(r.ok, true);
    });

    it("validarFreteGratisRaio sem limite aplica taxa integral", () => {
        const r = H.validarFreteGratisRaio(
            { frete_gratis_modalidade: "sem_limite" },
            { taxa_entrega: 12.5, retirada_na_loja: false },
        );
        assert.equal(r.ok, true);
        assert.equal(r.descontoFrete, 12.5);
    });

    it("validarFreteGratisRaio rejeita retirada na loja", () => {
        const r = H.validarFreteGratisRaio(
            { frete_gratis_modalidade: "sem_limite" },
            { taxa_entrega: 10, retirada_na_loja: true },
        );
        assert.equal(r.ok, false);
    });

    it("validarFreteGratisRaio por raio aceita dentro do limite", () => {
        const r = H.validarFreteGratisRaio(
            {
                frete_gratis_modalidade: "raio_km",
                frete_gratis_raio_km: 5,
            },
            {
                taxa_entrega: 8,
                retirada_na_loja: false,
                distancia_entrega_km: 3.2,
            },
        );
        assert.equal(r.ok, true);
        assert.equal(r.descontoFrete, 8);
    });

    it("validarFreteGratisRaio por raio rejeita fora do limite", () => {
        const r = H.validarFreteGratisRaio(
            {
                frete_gratis_modalidade: "raio_km",
                frete_gratis_raio_km: 3,
            },
            {
                taxa_entrega: 8,
                retirada_na_loja: false,
                distancia_entrega_km: 5.1,
            },
        );
        assert.equal(r.ok, false);
        assert.match(r.mensagem, /5\.1 km/);
    });

    it("distanciaKm calcula aproximadamente", () => {
        const d = H.distanciaKm(-16.47, -54.62, -16.48, -54.63);
        assert.ok(d > 0 && d < 20);
    });
});
