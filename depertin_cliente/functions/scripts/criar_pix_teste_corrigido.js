/**
 * Script para criar cobrança PIX real usando a abordagem CORRIGIDA (Payments API).
 *
 * Esta é a MESMA abordagem usada pelo marketplace DiPertin (mpCriarPagamentoPix):
 *   POST /v1/payments (simples) em vez de POST /v1/orders (complexa).
 *
 * Uso: node scripts/criar_pix_teste_corrigido.js
 */

const https = require("https");
const fs = require("fs");

const MP_API = "https://api.mercadopago.com";
const ACCESS_TOKEN = "APP_USR-7983903692218431-040415-fdba61b56071bf470a4c4c8c75846467-3307972251";

function httpRequest(url, options, body) {
    return new Promise((resolve, reject) => {
        const urlObj = new URL(url);
        const transport = urlObj.protocol === "https:" ? https : http;
        const req = transport.request(
            url,
            {
                method: options.method || "GET",
                headers: options.headers || { "Content-Type": "application/json" },
            },
            (res) => {
                let data = "";
                res.on("data", (chunk) => (data += chunk));
                res.on("end", () => {
                    let parsed;
                    try {
                        parsed = JSON.parse(data);
                    } catch (_) {
                        parsed = data;
                    }
                    resolve({
                        ok: res.statusCode >= 200 && res.statusCode < 300,
                        status: res.statusCode,
                        data: parsed,
                        text: data,
                    });
                });
            }
        );
        req.on("error", reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

async function criarPixCorrigido() {
    const cobrancaId = "test_corr_" + Date.now() + "_" + Math.random().toString(36).substring(2, 6);
    const externalRef = "pdv_test_" + cobrancaId + "_" + Date.now();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();
    const valor = 0.10;

    // ════════════════════════════════════════════════════════════════
    // PAYLOAD IGUAL AO MARKETPLACE (POST /v1/payments)
    // NADA de Orders API (/v1/orders), POS, external_pos_id, etc.
    // ════════════════════════════════════════════════════════════════
    const payload = {
        transaction_amount: valor,
        description: "Teste PIX Gestao Comercial - CORRIGIDO " + new Date().toISOString(),
        payment_method_id: "pix",
        installments: 1,
        payer: {
            email: "pgto@dipertin.com.br",
            first_name: "Teste PDV",
        },
        date_of_expiration: expiresAt,
        external_reference: externalRef,
        metadata: {
            origem: "teste_auditoria",
            cobrancaId: cobrancaId,
            versao: "payments_api_corrigido",
        },
    };

    console.log("\n" + "=".repeat(80));
    console.log(">>> CRIANDO PIX REAL CORRIGIDO (Payments API, R$ 0,10)");
    console.log("=".repeat(80));

    console.log("\n[1] PAYLOAD ENVIADO (POST /v1/payments):");
    console.log(JSON.stringify(payload, null, 4));

    const resp = await httpRequest(MP_API + "/v1/payments", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + ACCESS_TOKEN,
            "Content-Type": "application/json",
            "X-Idempotency-Key": cobrancaId,
        },
    }, payload);

    console.log("\n[2] HTTP STATUS:", resp.status);

    if (!resp.ok) {
        console.log("\n[ERRO] MP retornou erro:");
        console.log(JSON.stringify(resp.data, null, 4));
        process.exit(1);
    }

    console.log("\n[3] JSON BRUTO RETORNADO PELO MP:");
    console.log(JSON.stringify(resp.data, null, 4));

    const d = resp.data;
    const txData = d.point_of_interaction?.transaction_data || {};

    console.log("\n" + "-".repeat(80));
    console.log(">>> CAMPOS EXTRAIDOS (NOVO PIX CORRIGIDO)");
    console.log("-".repeat(80));
    console.log("  id (payment_id):        ", d.id);
    console.log("  status:                 ", d.status);
    console.log("  status_detail:          ", d.status_detail);
    console.log("  external_reference:     ", d.external_reference);
    console.log("  date_of_expiration:     ", d.date_of_expiration);
    console.log("  date_created:           ", d.date_created);
    console.log("  live_mode:              ", d.live_mode);
    console.log("\n  qr_code (copia e cola): ");
    console.log("    " + (txData.qr_code || "(vazio)"));
    console.log("\n  qr_code_base64 presente:", !!txData.qr_code_base64);
    console.log("  qr_code_base64 length:  ", (txData.qr_code_base64 || "").length);
    console.log("  ticket_url:             ", txData.ticket_url || "(vazio)");

    // Salva referencia
    const ref = {
        payment_id: d.id,
        external_reference: externalRef,
        cobranca_id: cobrancaId,
        created_at: new Date().toISOString(),
        expires_at: expiresAt,
        status: d.status,
        status_detail: d.status_detail,
        qr_code: txData.qr_code,
        qr_code_base64: txData.qr_code_base64 || "",
        qr_code_base64_length: (txData.qr_code_base64 || "").length,
        versao: "payments_api_corrigido",
    };
    fs.writeFileSync("pix_teste_corrigido_referencia.json", JSON.stringify(ref, null, 4));

    console.log("\n" + "-".repeat(80));
    console.log(">>> REFERENCIA SALVA EM pix_teste_corrigido_referencia.json");
    console.log("-".repeat(80));
    console.log("\n*** PAGUE O QR CODE ACIMA PARA VERIFICAR O STATUS approved!");
    console.log("*** O QR code agora e gerado via Payments API (como o marketplace).\n");

    return ref;
}

criarPixCorrigido().catch((err) => {
    console.error("ERRO:", err.message || err);
    process.exit(1);
});
