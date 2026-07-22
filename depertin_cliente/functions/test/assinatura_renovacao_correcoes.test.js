"use strict";

/**
 * Testes unitários — correções assinatura (webhook export, plan_id, templates, avisos).
 * node --test test/assinatura_renovacao_correcoes.test.js
 */

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

describe("assinatura_cobrancas exports", () => {
    it("exporta processarPagamentoGestaoComercial como função", () => {
        const mod = require("../assinatura_cobrancas");
        assert.equal(typeof mod.processarPagamentoGestaoComercial, "function");
        assert.equal(typeof mod.processarPagamentoCobrancaAssinatura, "function");
        assert.equal(typeof mod.planIdDaAssinatura, "function");
        assert.ok(String(mod.ASSINATURA_MP_WEBHOOK_URL || "").includes("webhookMercadoPagoGestaoComercial"));
    });

    it("planIdDaAssinatura usa plan_id canônico e fallback plano_id", () => {
        const { planIdDaAssinatura } = require("../assinatura_cobrancas");
        assert.equal(planIdDaAssinatura({ plan_id: "abc" }), "abc");
        assert.equal(planIdDaAssinatura({ plano_id: "legado" }), "legado");
        assert.equal(planIdDaAssinatura({ plan_id: "novo", plano_id: "legado" }), "novo");
        assert.equal(planIdDaAssinatura({}), "");
    });

    it("processarPagamentoGestaoComercial rejeita payment inválido", async () => {
        const { processarPagamentoGestaoComercial } = require("../assinatura_cobrancas");
        const r1 = await processarPagamentoGestaoComercial(null);
        assert.equal(r1.ok, false);
        assert.equal(r1.reason, "payment_invalido");
        const r2 = await processarPagamentoGestaoComercial({ metadata: { tipo: "outro" } });
        assert.equal(r2.ok, false);
        assert.equal(r2.reason, "nao_eh_assinatura_cobranca");
    });
});

describe("assinatura_emails_templates", () => {
    const t = require("../assinatura_emails_templates");

    const base = {
        lojaNome: "Fran Artesanatos",
        planoNome: "Gestão Comercial",
        valor: 99.9,
        vencimento: "15/07/2026",
        situacao: "Pendente",
        fatura: "#FAT-2026-000001",
        formaPagamento: "PIX",
        diasToleranciaRestantes: "3 dia(s)",
        dataBloqueioEstimada: "23/07/2026",
    };

    it("gera templates com remetente DiPertin e sem dados sensíveis", () => {
        const mails = [
            t.templateVencimentoProximo(base),
            t.templateTentativa1(base),
            t.templateTentativa2(base),
            t.templateTentativa3(base),
            t.templatePagamentoAprovado(base),
            t.templatePlanoSuspenso(base),
            t.templatePlanoReativado(base),
        ];
        for (const m of mails) {
            assert.ok(m.subject && m.subject.length > 5);
            assert.ok(m.html.includes("DiPertin"));
            assert.ok(m.html.includes("Fran Artesanatos"));
            assert.ok(m.html.includes("Gestão Comercial") || m.html.includes("Gestao"));
            assert.ok(!m.html.toLowerCase().includes("cvv"));
            assert.ok(!m.html.toLowerCase().includes("access_token"));
            assert.ok(m.html.includes("#6A1B9A") || m.html.includes("6A1B9A"));
        }
        assert.match(mails[0].subject, /vence em breve/i);
        assert.match(mails[1].subject, /pendente/i);
        assert.match(mails[3].subject, /lembrete|suspens/i);
        assert.match(mails[4].subject, /confirmado|renovada/i);
        assert.match(mails[5].subject, /suspenso/i);
        assert.match(mails[6].subject, /restabelecido/i);
    });
});

describe("assinatura_avisos helpers", () => {
    it("exporta scheduled e helpers de tentativa", () => {
        const a = require("../assinatura_avisos");
        assert.equal(typeof a.assinaturaAvisosTentativasScheduled, "function");
        assert.equal(typeof a.registrarEEnviarTentativa, "function");
        assert.equal(typeof a.calcularDataBloqueioEstimada, "function");
    });

    it("calcularDataBloqueioEstimada respeita tolerancia + suspender_apos_dias", () => {
        const { calcularDataBloqueioEstimada } = require("../assinatura_avisos");
        const venc = new Date(2026, 6, 10); // 10 jul 2026
        const est = calcularDataBloqueioEstimada(
            { tolerancia_dias: 3, suspender_apos_dias: 5 },
            venc,
        );
        assert.ok(est instanceof Date);
        // 10 + 3 + 5 = 18 jul
        assert.equal(est.getDate(), 18);
        assert.equal(est.getMonth(), 6);
    });

    it("calcularDataBloqueioEstimada retorna null sem suspender_apos_dias", () => {
        const { calcularDataBloqueioEstimada } = require("../assinatura_avisos");
        assert.equal(
            calcularDataBloqueioEstimada({ tolerancia_dias: 3 }, new Date()),
            null,
        );
    });
});

describe("assinatura_pagamento webhook PIX direto", () => {
    it("exporta processarPagamentoPixAssinaturaDireto e notification URL", () => {
        const p = require("../assinatura_pagamento");
        assert.equal(typeof p.processarPagamentoPixAssinaturaDireto, "function");
        assert.ok(String(p.ASSINATURA_MP_WEBHOOK_URL || "").includes("webhookMercadoPagoGestaoComercial"));
    });
});
