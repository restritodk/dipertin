"use strict";

/**
 * Testes — renovação PIX: só approved confirma pagamento.
 * node --test test/assinatura_renovar_pix_status.test.js
 */

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

const { mpStatusEhAprovado } = require("../assinatura_pagamento");

describe("mpStatusEhAprovado — regra estrita PIX", () => {
    it("aceita somente approved (case-insensitive)", () => {
        assert.equal(mpStatusEhAprovado("approved"), true);
        assert.equal(mpStatusEhAprovado("Approved"), true);
        assert.equal(mpStatusEhAprovado(" APPROVED "), true);
    });

    it("rejeita authorized e demais status do MP", () => {
        for (const st of [
            "authorized",
            "pending",
            "in_process",
            "in_mediation",
            "rejected",
            "cancelled",
            "refunded",
            "charged_back",
            "expired",
            "",
            null,
            undefined,
            "success",
            "created",
            "active",
            "completed",
            "true",
            "200",
        ]) {
            assert.equal(
                mpStatusEhAprovado(st),
                false,
                "não deveria aprovar status=" + String(st),
            );
        }
    });
});

describe("contrato de resposta renovação (documentação executável)", () => {
    function respostaConsulta({ payment_status, approved, success = true }) {
        return {
            success,
            payment_status,
            approved,
            pago: approved === true,
            status: approved ? "ativo" : "renovacao_pendente",
        };
    }

    it("pending: success true NÃO implica approved", () => {
        const r = respostaConsulta({ payment_status: "pending", approved: false });
        assert.equal(r.success, true);
        assert.equal(r.approved, false);
        assert.equal(r.pago, false);
        assert.notEqual(r.payment_status, "approved");
    });

    it("approved real: approved e payment_status alinhados", () => {
        const r = respostaConsulta({ payment_status: "approved", approved: true });
        assert.equal(r.success, true);
        assert.equal(r.approved, true);
        assert.equal(r.payment_status, "approved");
    });

    it("frontend só confirma com approved && payment_status===approved", () => {
        function frontendConfirma(status) {
            return status.approved === true
                && String(status.payment_status || "").toLowerCase() === "approved";
        }
        assert.equal(frontendConfirma({ success: true, approved: false, payment_status: "pending" }), false);
        assert.equal(frontendConfirma({ success: true, status: "ativo", pago: true }), false);
        assert.equal(frontendConfirma({ success: true, approved: true, payment_status: "pending" }), false);
        assert.equal(frontendConfirma({ success: true, approved: true, payment_status: "approved" }), true);
        assert.equal(frontendConfirma({ success: true, approved: false, payment_status: "approved" }), false);
    });
});
