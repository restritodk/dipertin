/**
 * Script para criar uma cobrança PIX real de teste no Mercado Pago.
 * Uso: node scripts/criar_pix_teste.js
 *
 * ATENÇÃO: Gera cobrança real no ambiente de produção do MP.
 * O PIX gerado pode ser pago por qualquer pessoa.
 */

const https = require("https");
const http = require("http");

const MP_API = "https://api.mercadopago.com";
const ACCESS_TOKEN = "APP_USR-7983903692218431-040415-fdba61b56071bf470a4c4c8c75846467-3307972251";

function criarIdempotencyKey() {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        const r = (Math.random() * 16) | 0;
        return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
    });
}

function criarExternalRef() {
    return "test_audit_gc_" + Date.now() + "_" + Math.random().toString(36).substring(2, 6);
}

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

async function criarPix() {
    const externalRef = criarExternalRef();
    const idempotencyKey = criarIdempotencyKey();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();

    const payload = {
        transaction_amount: 0.10,
        description: "Teste auditoria PIX Gestao Comercial - " + new Date().toISOString(),
        payment_method_id: "pix",
        payer: {
            email: "auditoria@dipertin.com.br",
            first_name: "Auditoria",
        },
        date_of_expiration: expiresAt,
        external_reference: externalRef,
    };

    console.log("\n" + "=".repeat(80));
    console.log(">>> CRIANDO COBRANCA PIX REAL DE TESTE (R$ 0,10)");
    console.log("=".repeat(80));
    console.log("\n[1] PAYLOAD ENVIADO PARA POST /v1/payments:");
    console.log(JSON.stringify(payload, null, 4));
    console.log("\n[2] X-Idempotency-Key:", idempotencyKey);

    const resp = await httpRequest(MP_API + "/v1/payments", {
        method: "POST",
        headers: {
            Authorization: "Bearer " + ACCESS_TOKEN,
            "Content-Type": "application/json",
            "X-Idempotency-Key": idempotencyKey,
        },
    }, payload);

    console.log("\n[3] HTTP STATUS:", resp.status);
    console.log("\n[4] JSON BRUTO RETORNADO PELO MP:");
    console.log(JSON.stringify(resp.data, null, 4));

    const d = resp.data;

    console.log("\n" + "-".repeat(80));
    console.log(">>> CAMPOS EXTRAIDOS");
    console.log("-".repeat(80));
    console.log("  id (payment_id):        ", d.id);
    console.log("  status:                 ", d.status);
    console.log("  status_detail:          ", d.status_detail);
    console.log("  external_reference:     ", d.external_reference);
    console.log("  date_of_expiration:     ", d.date_of_expiration);
    console.log("  date_created:           ", d.date_created);

    const txData = d.point_of_interaction?.transaction_data || {};
    console.log("\n  qr_code (copia e cola): ");
    console.log("    " + (txData.qr_code || "(vazio)"));
    console.log("\n  qr_code_base64 (presente):", !!txData.qr_code_base64);
    console.log("  qr_code_base64 (length):", (txData.qr_code_base64 || "").length);
    console.log("  ticket_url:             ", txData.ticket_url || "(vazio - normal p/ PIX)");

    console.log("\n" + "-".repeat(80));
    console.log(">>> SALVANDO REFERENCIA PARA CONSULTA POSTERIOR");
    console.log("-".repeat(80));
    console.log("\nArquivo de referencia: payment_id=" + d.id + ", external_ref=" + externalRef);
    console.log("Data expiracao:", expiresAt);
    console.log("\n*** IMPORTANTE: Pague o PIX acima para ver o status approved!");
    console.log("*** O QR Code copia-e-cola esta no campo qr_code acima.");
    console.log("*** Use seu app bancario para pagar em ate 5 minutos.\n");

    // Salva referencia em arquivo
    const fs = require("fs");
    const ref = {
        payment_id: d.id,
        external_reference: externalRef,
        created_at: new Date().toISOString(),
        expires_at: expiresAt,
        status: d.status,
        status_detail: d.status_detail,
        qr_code: txData.qr_code,
        qr_code_base64_length: (txData.qr_code_base64 || "").length,
        raw_response_summary: {
            id: d.id,
            status: d.status,
            status_detail: d.status_detail,
            date_of_expiration: d.date_of_expiration,
            external_reference: d.external_reference,
        },
    };
    fs.writeFileSync("pix_teste_referencia.json", JSON.stringify(ref, null, 4));
    console.log("Referencia salva em pix_teste_referencia.json\n");

    return { paymentId: d.id, externalRef };
}

criarPix().catch((err) => {
    console.error("ERRO:", err.message || err);
    process.exit(1);
});
