"use strict";
const { describe, it } = require("node:test");
const assert = require("node:assert");

/**
 * Simula a função de geração de UUID v4 igual à implementada no focus_nfe_provider.dart.
 * UUID v4: 16 bytes aleatórios, bytes[6] = 0x40|(bytes[6]&0x0f), bytes[8] = 0x80|(bytes[8]&0x3f)
 */
function gerarUuidV4() {
  const bytes = crypto.randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map(b => b.toString(16).padStart(2, "0"));
  return `${hex[0]}${hex[1]}${hex[2]}${hex[3]}-${hex[4]}${hex[5]}-${hex[6]}${hex[7]}-${hex[8]}${hex[9]}-${hex[10]}${hex[11]}${hex[12]}${hex[13]}${hex[14]}${hex[15]}`;
}

/**
 * Simula a lógica de request_id do FocusNFeProvider.emitirNota().
 * Para emissão com source_id (pedido/venda), usa source_id.
 * Para emissão avulsa, gera UUID uma vez e persiste em configuracoesExtras.
 */
function obterRequestId({ sourceId, configuracoesExtras }) {
  if (sourceId && sourceId.length > 0) {
    return { requestId: "", sourceId };
  }
  // Emissão avulsa: verificar se já existe request_id persistido
  if (configuracoesExtras && configuracoesExtras.request_id) {
    return { requestId: configuracoesExtras.request_id, sourceId: "" };
  }
  // Gerar novo UUID e persistir
  const uuid = gerarUuidV4();
  if (configuracoesExtras) {
    configuracoesExtras.request_id = uuid;
  }
  return { requestId: uuid, sourceId: "" };
}

const crypto = require("crypto");

describe("REQUEST_ID — Emissão avulsa com UUID", () => {

  it("01. Duas emissões avulsas distintas geram request_ids diferentes", () => {
    const extras1 = {};
    const extras2 = {};

    const r1 = obterRequestId({ sourceId: "", configuracoesExtras: extras1 });
    const r2 = obterRequestId({ sourceId: "", configuracoesExtras: extras2 });

    assert.notStrictEqual(r1.requestId, r2.requestId, "UUIDs devem ser diferentes");
    assert.strictEqual(r1.requestId.length >= 8, true, "request_id deve ter no mínimo 8 caracteres");
    assert.strictEqual(extras1.request_id, r1.requestId, "request_id deve ser persistido em configuracoesExtras");
  });

  it("02. Clique duplo na mesma emissão reutiliza mesmo request_id", () => {
    const extras = {};

    const primeiro = obterRequestId({ sourceId: "", configuracoesExtras: extras });
    const segundo = obterRequestId({ sourceId: "", configuracoesExtras: extras });

    assert.strictEqual(primeiro.requestId, segundo.requestId, "Mesmo request_id deve ser reutilizado");
    assert.strictEqual(extras.request_id, primeiro.requestId, "Deve persistir em configuracoesExtras");
  });

  it("03. Retry da mesma emissão reutiliza mesmo request_id", () => {
    const extras = {};

    obterRequestId({ sourceId: "", configuracoesExtras: extras }); // primeira chamada
    // Retry após falha
    const retry = obterRequestId({ sourceId: "", configuracoesExtras: extras });
    // Timeout (nova chamada)
    const aposTimeout = obterRequestId({ sourceId: "", configuracoesExtras: extras });

    assert.strictEqual(retry.requestId, aposTimeout.requestId, "Retry e pós-timeout devem usar mesmo request_id");
  });

  it("04. Reabertura da mesma operação (mesmo extras) reutiliza request_id", () => {
    const extras = { request_id: "uuid-da-operacao-anterior" };

    const resultado = obterRequestId({ sourceId: "", configuracoesExtras: extras });

    assert.strictEqual(resultado.requestId, "uuid-da-operacao-anterior",
      "Deve reutilizar o request_id existente em configuracoesExtras");
  });

  it("05. Número vazio não causa colisão entre emissões distintas", () => {
    // Duas emissões avulsas na mesma loja, mesmo docType, mesma série, número vazio
    // Mas com configuracoesExtras diferentes (objetos diferentes)
    const extrasA = {};
    const extrasB = {};

    const rA = obterRequestId({ sourceId: "", configuracoesExtras: extrasA });
    const rB = obterRequestId({ sourceId: "", configuracoesExtras: extrasB });

    assert.notStrictEqual(rA.requestId, rB.requestId,
      "Duas emissões avulsas com número vazio não devem colidir");
  });

  it("06. Mesma série, mesma loja: emissões diferentes geram UUIDs diferentes", () => {
    const extras1 = {};
    const extras2 = {};

    // Mesmas condições: storeId, docType, serie seriam iguais
    // Mas são emissões diferentes → objetos extras diferentes
    const r1 = obterRequestId({ sourceId: "", configuracoesExtras: extras1 });
    const r2 = obterRequestId({ sourceId: "", configuracoesExtras: extras2 });

    assert.notStrictEqual(r1.requestId, r2.requestId,
      "Mesma loja, docType e série mas emissões diferentes devem ter UUIDs diferentes");
  });

  it("07. Nova emissão após uma autorizada: UUID diferente", () => {
    // Primeira emissão
    const extrasAnterior = {};
    const primeira = obterRequestId({ sourceId: "", configuracoesExtras: extrasAnterior });

    // Após autorizada, o frontend cria novo modal com novo objeto extras
    const extrasNova = {};
    const nova = obterRequestId({ sourceId: "", configuracoesExtras: extrasNova });

    assert.notStrictEqual(primeira.requestId, nova.requestId,
      "Nova emissão após autorizada deve ter UUID diferente");
  });

  it("08. Formato UUID: 8-4-4-4-12, 36 caracteres", () => {
    const extras = {};
    const r = obterRequestId({ sourceId: "", configuracoesExtras: extras });

    assert.match(r.requestId, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
      "Deve ser UUID v4 válido");
    assert.strictEqual(r.requestId.length, 36, "UUID v4 tem 36 caracteres");
  });

  it("09. Emissão com source_id (vinculada a venda): request_id vazio, source_id enviado", () => {
    const extras = {};
    const r = obterRequestId({ sourceId: "pedido_12345", configuracoesExtras: extras });

    assert.strictEqual(r.requestId, "", "request_id deve ser vazio quando source_id está presente");
    assert.strictEqual(r.sourceId, "pedido_12345", "source_id deve ser enviado");
  });
});
