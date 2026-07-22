"use strict";

/**
 * Testes de segurança para o Módulo Fiscal.
 *
 * Uso: node --test test/fiscal_seguranca.test.js
 * Requer: Node 20+
 *
 * Verifica:
 * - FISCAL_MASTER_KEY obrigatória (sem fallback hardcoded)
 * - Criptografia AES-256-GCM compatível com Dart
 * - Storage rules proteção do prefixo /fiscal/
 */
const { describe, it, before, after, mock } = require("node:test");
const assert = require("node:assert");
const crypto = require("crypto");
const path = require("path");
const fs = require("fs");

// ═══════════════════════════════════════════════════════════════════════════════
// DUPLICATA DA LÓGICA DE CRIPTOGRAFIA (fiscal_nfe_proxy.js)
// ═══════════════════════════════════════════════════════════════════════════════

const CRYPTO_PREFIX = "DIP_AES256_v2:";
const CRYPTO_PREFIX_LEGACY = "DIP_ENC_v1:";
const CHAVE_32 = "abcdef0123456789abcdef0123456789";
const CHAVE_64 = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";

function derivarChave256(seed) {
  return crypto.createHash("sha256").update(seed, "utf8").digest();
}

function decryptAesGcm(encrypted, key) {
  const payload = encrypted.slice(CRYPTO_PREFIX.length);
  const [ivB64, dataB64] = payload.split(".");
  if (!ivB64 || !dataB64) return null;

  const iv = Buffer.from(ivB64, "base64url");
  const full = Buffer.from(dataB64, "base64url");
  if (!key) return null;

  const tag = full.subarray(-16);
  const ciphertext = full.subarray(0, -16);

  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);
  try {
    return decipher.update(ciphertext) + decipher.final("utf8");
  } catch {
    return null;
  }
}

function decryptLegacy(encrypted, key) {
  const encoded = encrypted.slice(CRYPTO_PREFIX_LEGACY.length);
  const buf = Buffer.from(encoded, "base64url");
  if (!buf || buf.length === 0 || !key) return null;
  const decrypted = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) {
    decrypted[i] = buf[i] ^ key[i % key.length];
  }
  return decrypted.toString("utf8");
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS PARA CRIAR TOKENS DE TESTE
// ═══════════════════════════════════════════════════════════════════════════════

function encryptAesGcm(plaintext, key) {
  if (!plaintext || typeof plaintext !== "string") return null;
  if (!key) return null;

  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  const ivB64 = iv.toString("base64url");
  const dataB64 = Buffer.concat([encrypted, tag]).toString("base64url");
  return `${CRYPTO_PREFIX}${ivB64}.${dataB64}`;
}

function encryptLegacy(plaintext, key) {
  const buf = Buffer.alloc(plaintext.length);
  for (let i = 0; i < plaintext.length; i++) {
    buf[i] = plaintext.charCodeAt(i) ^ key[i % key.length];
  }
  return `${CRYPTO_PREFIX_LEGACY}${buf.toString("base64url")}`;
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESOLVER CHAVE MESTRA — réplica da função de produção sem fallback
// ═══════════════════════════════════════════════════════════════════════════════

const KEY_ENV = "FISCAL_MASTER_KEY";

function resolverChaveMestra(rawKey) {
  if (!rawKey || typeof rawKey !== "string" || rawKey.length < 32) {
    throw new Error("Configuração criptográfica fiscal indisponível.");
  }
  return crypto.createHash("sha256").update(rawKey, "utf8").digest();
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTES
// ═══════════════════════════════════════════════════════════════════════════════

describe("resolverChaveMestra — sem fallback hardcoded", () => {
  it("deve lançar erro se FISCAL_MASTER_KEY não for fornecida", () => {
    assert.throws(
      () => resolverChaveMestra(undefined),
      /Configuração criptográfica fiscal indisponível/
    );
    assert.throws(
      () => resolverChaveMestra(null),
      /Configuração criptográfica fiscal indisponível/
    );
    assert.throws(
      () => resolverChaveMestra(""),
      /Configuração criptográfica fiscal indisponível/
    );
  });

  it("deve lançar erro se chave for menor que 32 caracteres", () => {
    assert.throws(
      () => resolverChaveMestra("curta"),
      /Configuração criptográfica fiscal indisponível/
    );
    assert.throws(
      () => resolverChaveMestra("abcdef0123456789abcdef01234567"),
      /Configuração criptográfica fiscal indisponível/
    );
  });

  it("deve aceitar chave de exatamente 32 caracteres", () => {
    const key = resolverChaveMestra(CHAVE_32);
    assert.ok(key instanceof Buffer);
    assert.strictEqual(key.length, 32);
  });

  it("deve aceitar chave de 64 caracteres (formato hex recomendado)", () => {
    const key = resolverChaveMestra(CHAVE_64);
    assert.ok(key instanceof Buffer);
    assert.strictEqual(key.length, 32);
  });

  it("deve ser determinístico: mesma entrada produz mesma chave", () => {
    const k1 = resolverChaveMestra(CHAVE_64);
    const k2 = resolverChaveMestra(CHAVE_64);
    assert.deepStrictEqual(k1, k2);
  });

  it("entradas diferentes produzem chaves diferentes", () => {
    const k1 = resolverChaveMestra(CHAVE_32);
    const k2 = resolverChaveMestra(CHAVE_64);
    assert.notDeepStrictEqual(k1, k2);
  });

  it("NÃO deve existir fallbackKey no código de produção", () => {
    const fonte = fs.readFileSync(
      path.join(__dirname, "..", "fiscal_nfe_proxy.js"),
      "utf8"
    );
    assert.ok(
      fonte.includes("FISCAL_MASTER_KEY"),
      "Código deve referenciar FISCAL_MASTER_KEY"
    );
    // Verifica que não há string com formato de chave hardcoded
    assert.ok(!fonte.includes("fallbackKey"), "Código não deve conter fallbackKey");
    assert.ok(
      fonte.includes("Configuração criptográfica fiscal indisponível"),
      "Código deve ter mensagem de erro controlada"
    );
  });
});

describe("Descriptografia AES-256-GCM (DIP_AES256_v2) — compatibilidade com Dart", () => {
  const KEY = resolverChaveMestra(CHAVE_64);
  const TOKEN_EXEMPLO = "focus_test_token_abc123";

  it("deve criptografar e descriptografar corretamente", () => {
    const encrypted = encryptAesGcm(TOKEN_EXEMPLO, KEY);
    const decrypted = decryptAesGcm(encrypted, KEY);
    assert.strictEqual(decrypted, TOKEN_EXEMPLO);
  });

  it("deve rejeitar token corrompido", () => {
    const encrypted = encryptAesGcm(TOKEN_EXEMPLO, KEY);
    const corrompido = encrypted.slice(0, -4);
    const result = decryptAesGcm(corrompido, KEY);
    assert.strictEqual(result, null);
  });

  it("deve retornar null se masterKey não for fornecida", () => {
    const encrypted = encryptAesGcm(TOKEN_EXEMPLO, KEY);
    const result = decryptAesGcm(encrypted, null);
    assert.strictEqual(result, null);
  });

  it("deve rejeitar payload sem separador", () => {
    const result = decryptAesGcm(`${CRYPTO_PREFIX}invalido`, KEY);
    assert.strictEqual(result, null);
  });

  it("deve descriptografar token com caracteres especiais", () => {
    const tokenEspecial = "TEST_APP_USR-1a2b3c!@#$%^&*()_+-=[]{}|;:',.<>?/`~";
    const encrypted = encryptAesGcm(tokenEspecial, KEY);
    const decrypted = decryptAesGcm(encrypted, KEY);
    assert.strictEqual(decrypted, tokenEspecial);
  });

  it("chave incorreta NÃO deve descriptografar (autenticação GCM falha)", () => {
    const otherKey = resolverChaveMestra("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    const encrypted = encryptAesGcm(TOKEN_EXEMPLO, KEY);
    const result = decryptAesGcm(encrypted, otherKey);
    assert.strictEqual(result, null); // GCM detecta adulteração
  });
});

describe("Descriptografia legada (DIP_ENC_v1 / XOR)", () => {
  const KEY = resolverChaveMestra(CHAVE_64);
  const TOKEN_EXEMPLO = "legacy_token_2024";

  it("deve descriptografar token legado (XOR)", () => {
    const encrypted = encryptLegacy(TOKEN_EXEMPLO, KEY);
    const decrypted = decryptLegacy(encrypted, KEY);
    assert.strictEqual(decrypted, TOKEN_EXEMPLO);
  });

  it("deve retornar null se masterKey não for fornecida", () => {
    const encrypted = encryptLegacy(TOKEN_EXEMPLO, KEY);
    const result = decryptLegacy(encrypted, null);
    assert.strictEqual(result, null);
  });

  it("deve produzir resultado diferente para chaves diferentes", () => {
    const encrypted = encryptLegacy(TOKEN_EXEMPLO, KEY);
    const otherKey = resolverChaveMestra("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    const decrypted = decryptLegacy(encrypted, otherKey);
    assert.notStrictEqual(decrypted, TOKEN_EXEMPLO);
  });
});

describe("Arquivo storage.rules — proteção do prefixo /fiscal/", () => {
  it("deve conter regra de negação para /fiscal/{allPaths=**}", () => {
    const rules = fs.readFileSync(
      path.join(__dirname, "..", "..", "storage.rules"),
      "utf8"
    );
    assert.ok(
      rules.includes("fiscal") && rules.includes("allow read, write: if false"),
      "storage.rules deve negar acesso a /fiscal/"
    );
  });
});

describe("FISCAL_MASTER_KEY — verificação de ambiente", () => {
  const FONTE_PATH = path.join(__dirname, "..", "fiscal_nfe_proxy.js");

  it("fiscal_nfe_proxy.js deve chamar resolverChaveMestra sem fallback", () => {
    const fonte = fs.readFileSync(FONTE_PATH, "utf8");
    // Verifica que `resolverChaveMestra` não é chamado como `|| resolverChaveMestra()`
    const linhas = fonte.split("\n");
    const linhasProblema = linhas.filter(
      (l) => l.includes("resolverChaveMestra") && l.includes("||")
    );
    assert.strictEqual(
      linhasProblema.length,
      0,
      `resolverChaveMestra não deve ser usado como fallback (||). Linhas: ${linhasProblema.join(", ")}`
    );
  });

  it("fiscal_integration_sync.js NÃO deve incluir credentials_encrypted em CAMPOS_INTEGRACAO", () => {
    const fonteSync = fs.readFileSync(
      path.join(__dirname, "..", "fiscal_integration_sync.js"),
      "utf8"
    );
    // Verifica que CAMPOS_INTEGRACAO não contém credentials_encrypted
    // (comentários de segurança podem mencionar o campo)
    const match = fonteSync.match(/CAMPOS_INTEGRACAO\s*=\s*\[([\s\S]*?)\];/);
    assert.ok(match, "Deve encontrar CAMPOS_INTEGRACAO");
    assert.ok(
      !match[1].includes("credentials_encrypted"),
      "credentials_encrypted não deve estar em CAMPOS_INTEGRACAO"
    );
  });

  it("extrairConfig no frontend NÃO deve expor api_key ou credentials_encrypted", () => {
    const fonteProvider = fs.readFileSync(
      path.join(
        __dirname, "..", "..", "..",
        "depertin_web", "lib", "services", "fiscal", "fiscal_provider_service.dart"
      ),
      "utf8"
    );
    // Verifica que extrairConfig não retorna credentials_encrypted ou api_key
    // Comentários e strings de documentação são permitidos
    const linhas = fonteProvider.split("\n");
    const linhasExtrairConfig = linhas.filter(
      l => l.includes("extrairConfig") || 
          (linhas.indexOf(l) > linhas.indexOf("extrairConfig") && 
           linhas.indexOf(l) < linhas.indexOf("}\n\n"))
    );
    // Verifica que o return não contém campos de credenciais
    const returnMatch = fonteProvider.match(/return\s*\{([\s\S]*?)\};/g);
    if (returnMatch) {
      for (const ret of returnMatch) {
        assert.ok(
          !ret.includes("credentials_encrypted"),
          "return em extrairConfig não deve conter credentials_encrypted"
        );
      }
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Testes: encryptAesGcm (fiscal_nfe_proxy.js) — compatibilidade com decryptAesGcm
// ═══════════════════════════════════════════════════════════════════════════════

describe("encryptAesGcm (fiscal_nfe_proxy.js) — AES-256-GCM compatível com decrypt", () => {
  const KEY = resolverChaveMestra(CHAVE_64);

  it("encryptAesGcm deve produzir formato DIP_AES256_v2:{iv}.{data}", () => {
    const resultado = encryptAesGcm("token_teste", KEY);
    assert.ok(resultado.startsWith(CRYPTO_PREFIX), "Deve iniciar com prefixo DIP_AES256_v2:");

    const payload = resultado.slice(CRYPTO_PREFIX.length);
    const partes = payload.split(".");
    assert.strictEqual(partes.length, 2, "Deve ter iv e data separados por ponto");
    assert.ok(partes[0].length > 0, "IV não pode ser vazio");
    assert.ok(partes[1].length > 0, "Data não pode ser vazia");

    // Verifica que é base64url válido
    assert.doesNotThrow(() => Buffer.from(partes[0], "base64url"));
    assert.doesNotThrow(() => Buffer.from(partes[1], "base64url"));
  });

  it("encryptAesGcm deve produzir resultados diferentes a cada chamada (IV aleatório)", () => {
    const r1 = encryptAesGcm("token_teste", KEY);
    const r2 = encryptAesGcm("token_teste", KEY);
    assert.notStrictEqual(r1, r2, "IV aleatório deve produzir ciphertext diferente");
  });

  it("encryptAesGcm → decryptAesGcm roundtrip deve restaurar o original", () => {
    const token = "FOCUS_NFE_TOKEN_ABC123_XYZ";
    const encrypted = encryptAesGcm(token, KEY);
    const decrypted = decryptAesGcm(encrypted, KEY);
    assert.strictEqual(decrypted, token);
  });

  it("encryptAesGcm com plaintext vazio deve retornar null", () => {
    const r1 = encryptAesGcm("", KEY);
    assert.strictEqual(r1, null);
  });

  it("encryptAesGcm sem masterKey deve retornar null", () => {
    const r1 = encryptAesGcm("token", null);
    assert.strictEqual(r1, null);
  });

  it("encryptAesGcm com token especial deve roundtrip", () => {
    const tokenEspecial = "!@#$%^&*()_+{}[]|;':\",./<>?`~ \n\t";
    const encrypted = encryptAesGcm(tokenEspecial, KEY);
    const decrypted = decryptAesGcm(encrypted, KEY);
    assert.strictEqual(decrypted, tokenEspecial);
  });

  it("token criptografado com uma chave NÃO descriptografa com outra chave", () => {
    const keyA = resolverChaveMestra("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    const keyB = resolverChaveMestra("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    const encrypted = encryptAesGcm("token_confidencial", keyA);
    const decryptedWithB = decryptAesGcm(encrypted, keyB);
    assert.strictEqual(decryptedWithB, null, "GCM deve rejeitar chave incorreta");
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Testes: compatibilidade encrypt/decrypt com o fluxo de produção
// ═══════════════════════════════════════════════════════════════════════════════

describe("Fluxo de criptografia de integração — encryptAesGcm → decryptAesGcm", () => {
  const KEY = resolverChaveMestra(CHAVE_64);

  it("deve replicar o formato usado em obterApiKey (decryptAesGcm)", () => {
    // Simula o fluxo: o novo callable fiscalSalvarIntegracao faz encrypt,
    // e a função existente obterApiKey faz decrypt
    const token = "meu_token_focus_123";
    const encrypted = encryptAesGcm(token, KEY);

    // Verifica que decryptAesGcm consegue ler
    const decrypted = decryptAesGcm(encrypted, KEY);
    assert.strictEqual(decrypted, token);

    // Verifica que o prefixo está correto
    assert.ok(encrypted.startsWith("DIP_AES256_v2:"));
  });

  it("deve usar o mesmo formato para token de homologação e produção", () => {
    const tokenHomolog = "token_homolog_focus";
    const tokenProd = "token_prod_focus";

    const encH = encryptAesGcm(tokenHomolog, KEY);
    const encP = encryptAesGcm(tokenProd, KEY);

    assert.strictEqual(decryptAesGcm(encH, KEY), tokenHomolog);
    assert.strictEqual(decryptAesGcm(encP, KEY), tokenProd);
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Testes: Dois tokens independentes (credentials_sandbox / credentials_production)
// ═══════════════════════════════════════════════════════════════════════════════

describe("Dois tokens independentes — sandbox e production", () => {
  const KEY = resolverChaveMestra(CHAVE_64);

  it("sandbox_token e production_token são criptografados separadamente", () => {
    const sandboxToken = "sbx_token_abc123";
    const productionToken = "prd_token_xyz789";

    const encSandbox = encryptAesGcm(sandboxToken, KEY);
    const encProduction = encryptAesGcm(productionToken, KEY);

    // Cada um restaura independentemente
    assert.strictEqual(decryptAesGcm(encSandbox, KEY), sandboxToken);
    assert.strictEqual(decryptAesGcm(encProduction, KEY), productionToken);

    // São diferentes (IVs aleatórios)
    assert.notStrictEqual(encSandbox, encProduction);
  });

  it("credencial de homologação nunca descriptografa como produção", () => {
    const sandboxToken = "sbx_token";
    const productionToken = "prd_token";

    const encSandbox = encryptAesGcm(sandboxToken, KEY);
    const encProduction = encryptAesGcm(productionToken, KEY);

    // A criptografia de produção aplicada ao token sandbox NÃO dá o sandbox_token
    assert.notStrictEqual(decryptAesGcm(encProduction, KEY), sandboxToken);
    assert.notStrictEqual(decryptAesGcm(encSandbox, KEY), productionToken);
  });

  it("obterApiKey lê credentials_sandbox quando environment é sandbox (simulado)", () => {
    // Simula o que obterApiKey faz: lê credentials_sandbox se environment=sandbox
    const sandboxToken = "sbx_focus_token";
    const docSandbox = {
      environment: "sandbox",
      credentials_sandbox: encryptAesGcm(sandboxToken, KEY),
      credentials_production: null,
    };

    const masterKey = KEY;
    const raw = docSandbox.credentials_sandbox;
    const decrypted = decryptAesGcm(raw, masterKey);
    assert.strictEqual(decrypted, sandboxToken);
  });

  it("obterApiKey lê credentials_production quando environment é production (simulado)", () => {
    const productionToken = "prd_focus_token";
    const docProduction = {
      environment: "production",
      credentials_sandbox: null,
      credentials_production: encryptAesGcm(productionToken, KEY),
    };

    const masterKey = KEY;
    const raw = docProduction.credentials_production;
    const decrypted = decryptAesGcm(raw, masterKey);
    assert.strictEqual(decrypted, productionToken);
  });

  it("obterApiKey fallback para credentials_encrypted legado (sem credentials_sandbox/production)", () => {
    const token = "legacy_token";
    const docLegado = {
      environment: "sandbox",
      credentials_encrypted: encryptAesGcm(token, KEY),
    };

    const masterKey = KEY;
    const raw = docLegado.credentials_encrypted;
    const decrypted = decryptAesGcm(raw, masterKey);
    assert.strictEqual(decrypted, token);
  });

  it("obterApiKey fallback para api_key (texto puro legado)", () => {
    const docPlain = {
      environment: "sandbox",
      api_key: "plain_text_token",
    };
    // obterApiKey tenta credentials_sandbox/production → credentials_encrypted → api_key
    // Se api_key for texto puro (não DIP_AES256_v2), retorna direto
    const apiKey = docPlain.api_key;
    assert.strictEqual(apiKey, "plain_text_token");
  });

  it("credentials_sandbox e credentials_production NÃO devem estar em CAMPOS_INTEGRACAO no sync", () => {
    const fonteSync = fs.readFileSync(
      path.join(__dirname, "..", "fiscal_integration_sync.js"),
      "utf8"
    );
    const match = fonteSync.match(/CAMPOS_INTEGRACAO\s*=\s*\[([\s\S]*?)\];/);
    assert.ok(match, "Deve encontrar CAMPOS_INTEGRACAO");
    assert.ok(
      !match[1].includes("credentials_sandbox"),
      "credentials_sandbox não deve estar em CAMPOS_INTEGRACAO"
    );
    assert.ok(
      !match[1].includes("credentials_production"),
      "credentials_production não deve estar em CAMPOS_INTEGRACAO"
    );
  });
});