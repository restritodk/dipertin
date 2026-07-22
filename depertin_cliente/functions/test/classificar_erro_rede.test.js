"use strict";
const { describe, it } = require("node:test");
const assert = require("node:assert");

// ─── Cópia da função classificarErroRede de fiscal_nfe_proxy.js ───
// Mantida em sync manualmente. Testa o comportamento da classificação.
function classificarErroRede(error) {
  const msg = (error && (error.message || error.toString() || String(error))) || "";
  const msgLower = msg.toLowerCase();

  // ═══ 1. ANTES DO ENVIO (verificar PRIMEIRO) ═══
  const padroesAntesEnvio = [
    /getaddrinfo\s+enotfound/i,
    /dns\s+(not\s+found|resolution)/i,
    /econnrefused/i,
    /ENOTFOUND/i,
    /ECONNREFUSED/i,
    /invalid\s+url/i,
    /scheme\s+is\s+not\s+http/i,
    /self[- ]?signed\s+certificate/i,
  ];
  for (const p of padroesAntesEnvio) {
    if (p.test(msgLower)) {
      return { categoria: "falha_antes_envio", mensagem: msg };
    }
  }

  // ═══ 2. TIMEOUT ═══
  if (/timeout|timed.?out|time.?out/i.test(msgLower)) {
    return { categoria: "timeout", mensagem: msg };
  }

  // ═══ 3. RESULTADO AMBÍGUO ═══
  const padroesAmbiguos = [
    /connection\s+reset/i,
    /socket\s+hang.?up/i,
    /econnreset/i,
    /EPIPE/i,
    /esocket/i,
    /tls/i,
    /ssl/i,
    /certificate\s+verify/i,
    /handshake/i,
    /response\s+interrupted/i,
    /abort/i,
    /corpo\s+da\s+resposta.*fechado/i,
    /body\s+closed/i,
    /write\s+after\s+end/i,
    /stream\s+destroyed/i,
    /socket\s+closed/i,
    /connection\s+lost/i,
    /network\s+error/i,
    /fetch\s+failed/i,
    /typeerror.*fetch/i,
  ];
  for (const p of padroesAmbiguos) {
    if (p.test(msgLower)) {
      return { categoria: "aguardando_consulta", mensagem: msg };
    }
  }

  return { categoria: "aguardando_consulta", mensagem: msg };
}

describe("CLASSIFICAR_ERRO_REDE", () => {

  // ─── Timeout ───
  it("timeout: timeout explícito", () => {
    const e = new Error("timeout of 90000ms exceeded");
    assert.strictEqual(classificarErroRede(e).categoria, "timeout");
  });
  it("timeout: timed out", () => {
    assert.strictEqual(classificarErroRede({ message: "timed out" }).categoria, "timeout");
  });
  it("timeout: connection timed out", () => {
    assert.strictEqual(classificarErroRede(new Error("connection timed out")).categoria, "timeout");
  });

  // ─── Falha antes do envio ───
  it("falha_antes_envio: DNS não resolvido (ENOTFOUND)", () => {
    const e = new Error("getaddrinfo ENOTFOUND api.focusnfe.com.br");
    assert.strictEqual(classificarErroRede(e).categoria, "falha_antes_envio");
  });
  it("falha_antes_envio: DNS not found", () => {
    assert.strictEqual(classificarErroRede({ message: "dns not found" }).categoria, "falha_antes_envio");
  });
  it("falha_antes_envio: conexão recusada (ECONNREFUSED)", () => {
    assert.strictEqual(classificarErroRede(new Error("connect ECONNREFUSED 127.0.0.1:8080")).categoria, "falha_antes_envio");
  });
  it("falha_antes_envio: URL inválida", () => {
    assert.strictEqual(classificarErroRede(new Error("Invalid URL: httpx://foo")).categoria, "falha_antes_envio");
  });
  it("falha_antes_envio: self-signed certificate", () => {
    assert.strictEqual(classificarErroRede({ message: "self signed certificate" }).categoria, "falha_antes_envio");
  });
  it("falha_antes_envio: scheme is not http", () => {
    assert.strictEqual(classificarErroRede(new Error("scheme is not http")).categoria, "falha_antes_envio");
  });

  // ─── Resultado ambíguo ───
  it("aguardando_consulta: connection reset", () => {
    assert.strictEqual(classificarErroRede(new Error("connection reset by peer")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: socket hang up", () => {
    assert.strictEqual(classificarErroRede({ message: "socket hang up" }).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: ECONNRESET", () => {
    assert.strictEqual(classificarErroRede(new Error("read ECONNRESET")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: EPIPE", () => {
    assert.strictEqual(classificarErroRede({ message: "broken pipe EPIPE" }).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: erro TLS", () => {
    assert.strictEqual(classificarErroRede(new Error("TLS handshake failed")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: SSL certificate verify", () => {
    assert.strictEqual(classificarErroRede({ message: "SSL certificate verify failed" }).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: response interrupted", () => {
    assert.strictEqual(classificarErroRede(new Error("response interrupted")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: abort", () => {
    assert.strictEqual(classificarErroRede({ message: "The user aborted a request" }).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: stream destroyed", () => {
    assert.strictEqual(classificarErroRede(new Error("stream destroyed")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: network error", () => {
    assert.strictEqual(classificarErroRede({ message: "network error" }).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: fetch failed", () => {
    assert.strictEqual(classificarErroRede(new Error("fetch failed")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: fetch failed with reason", () => {
    assert.strictEqual(classificarErroRede({ message: "fetch failed: reason: connection lost" }).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: TypeError fetch", () => {
    assert.strictEqual(classificarErroRede(new TypeError("Failed to fetch")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: erro genérico sem padrão conhecido", () => {
    assert.strictEqual(classificarErroRede(new Error("Unknown error occurred")).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: mensagem vazia", () => {
    assert.strictEqual(classificarErroRede({ message: "" }).categoria, "aguardando_consulta");
  });
  it("aguardando_consulta: erro nulo", () => {
    assert.strictEqual(classificarErroRede(null).categoria, "aguardando_consulta");
  });
});

describe("CLASSIFICAR_ERRO — INTEGRAÇÃO COM TIMEOUT", () => {

  it("Fronteira: timeout vs falha_antes_envio (DNS tem precedência)", () => {
    // Mensagem contém "timeout" e "ENOTFOUND" — ENOTFOUND tem precedência como falha_antes_envio
    const e = new Error("getaddrinfo ENOTFOUND api.focusnfe.com.br:443 timeout");
    const result = classificarErroRede(e);
    // DNS não resolvido é comprovadamente antes do envio, mesmo com timeout no nome
    assert.strictEqual(result.categoria, "falha_antes_envio",
      "DNS não resolvido deve ser falha_antes_envio, mesmo que msg contenha 'timeout'");
  });

  it("Fronteira: connection refused não é ambíguo", () => {
    const e = new Error("connect ECONNREFUSED 192.168.1.1:443");
    assert.strictEqual(classificarErroRede(e).categoria, "falha_antes_envio");
  });

  it("Fronteira: TLS durante handshake = ambíguo", () => {
    const e = new Error("TLS handshake failed: certificate verify failed");
    assert.strictEqual(classificarErroRede(e).categoria, "aguardando_consulta");
  });
});
