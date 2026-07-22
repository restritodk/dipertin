/**
 * Proxy Fiscal — Focus NFe (backend seguro)
 *
 * Todas as chamadas à API da Focus NFe passam por estas Cloud Functions.
 * O token/api_key nunca transita no frontend — fica apenas no Firestore
 * (fiscal_integrations) e é descriptografado aqui no backend com Admin SDK.
 *
 * Homologação: https://homologacao.focusnfe.com.br/v2
 * Produção:    https://api.focusnfe.com.br/v2
 *
 * Autenticação: HTTP Basic Auth (RFC 7617).
 *   - usuário: token Focus NFe
 *   - senha: vazia
 *   - formato: Authorization: Basic base64(token:)
 *   - Documentação oficial: https://doc.focusnfe.com.br/reference/autenticacao
 *
 * Segurança:
 *   - FiscalSecurityGuard: valida vínculo loja × nota × usuário em todas as funções
 *   - FiscalPayloadValidator: valida payload completo antes de enviar à Focus
 *   - FiscalLogger: registra logs técnicos sem expor token
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { FieldValue: FirebaseFieldValue } = require("firebase-admin/firestore");

const crypto = require("crypto");
const securityGuard = require("./fiscal_security_guard");
const payloadValidator = require("./fiscal_payload_validator");
const logger = require("./fiscal_logger");
const saldoHelper = require("./fiscal_saldo_helper");
const fiscalCertificado = require("./fiscal_certificado");

// ─── Secret Manager: FISCAL_MASTER_KEY ───
const fiscalMasterKey = defineSecret("FISCAL_MASTER_KEY");

// ═══════════════════════════════════════════════════════════════════════
// Configuração das funções
// ═══════════════════════════════════════════════════════════════════════

const CONFIG = {
  region: "us-east1",
  cpu: 1,
  memory: "512MiB",
  maxInstances: 10,
  timeoutSeconds: 90,
  // TODO: voltar para `enforceAppCheck: process.env.FUNCTIONS_EMULATOR ? false : true`
  // após corrigir a Secret Key do reCAPTCHA v3 no Firebase Console → App Check →
  // depertin_web. Mantido false (igual às functions do Mercado Pago) pois a Secret
  // Key inválida faz o exchangeRecaptchaV3Token retornar 400 e bloqueia o staff.
  // Proteção preservada: Firebase Auth + verificação de papel staff dentro da função.
  enforceAppCheck: false,
  secrets: [fiscalMasterKey],
};

// ═══════════════════════════════════════════════════════════════════════
// Helpers de criptografia (compatível com FiscalCryptoUtil Dart)
// ═══════════════════════════════════════════════════════════════════════

const CRYPTO_PREFIX = "DIP_AES256_v2:";
const CRYPTO_PREFIX_LEGACY = "DIP_ENC_v1:";

/**
 * Chave mestra para criptografia das credenciais fiscais.
 *
 * OBRIGATÓRIA: a variável de ambiente FISCAL_MASTER_KEY deve estar
 * configurada com pelo menos 32 caracteres (recomendado: 64 hex chars).
 *
 * NÃO existe fallback hardcoded. Se a chave não estiver disponível,
 * a Function falha com erro controlado que não expõe detalhes.
 *
 * Gerar nova chave:
 *   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
 *
 * @returns {Buffer} Chave de 32 bytes derivada via SHA-256
 * @throws {Error} Se FISCAL_MASTER_KEY não estiver configurada
 */
function resolverChaveMestra() {
  const rawKey = process.env.FISCAL_MASTER_KEY;

  if (!rawKey || typeof rawKey !== "string" || rawKey.length < 32) {
    throw new Error("Configuração criptográfica fiscal indisponível.");
  }

  return crypto.createHash("sha256").update(rawKey, "utf8").digest();
}

/** Deriva chave de 32 bytes via SHA-256 (compatível com Dart). */
function derivarChave256(seed) {
  return crypto.createHash("sha256").update(seed, "utf8").digest();
}

/** Descriptografa credentials no formato AES-256-GCM (DIP_AES256_v2). */
function decryptAesGcm(encrypted, masterKey) {
  const payload = encrypted.slice(CRYPTO_PREFIX.length);
  const [ivB64, dataB64] = payload.split(".");
  if (!ivB64 || !dataB64) return null;

  const iv = Buffer.from(ivB64, "base64url");
  const full = Buffer.from(dataB64, "base64url");
  if (!masterKey) return null;
  const key = masterKey;

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

/**
 * Criptografa texto com AES-256-GCM no formato compatível com [decryptAesGcm].
 *
 * Formato de saída: DIP_AES256_v2:{iv_base64url}.{ciphertext+tag_base64url}
 *   - IV: 12 bytes aleatórios (CSRNG)
 *   - Ciphertext + 16-byte GCM auth tag
 *   - Tudo Base64URL (sem padding)
 *
 * Compatível com a implementação Dart em FiscalCryptoUtil.encryptAesGcm().
 *
 * @param {string} plaintext - Texto a criptografar (token, API key, etc.)
 * @param {Buffer} masterKey - Chave de 32 bytes derivada da FISCAL_MASTER_KEY
 * @returns {string} Texto cifrado no formato DIP_AES256_v2:{iv}.{data}
 */
function encryptAesGcm(plaintext, masterKey) {
  if (!plaintext || typeof plaintext !== "string") return null;
  if (!masterKey) return null;

  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", masterKey, iv);
  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  const ivB64 = iv.toString("base64url");
  const dataB64 = Buffer.concat([encrypted, tag]).toString("base64url");

  return `${CRYPTO_PREFIX}${ivB64}.${dataB64}`;
}

/** Descriptografa credentials no formato legado (XOR v1). */
function decryptLegacy(encrypted, masterKey) {
  const encoded = encrypted.slice(CRYPTO_PREFIX_LEGACY.length);
  const buf = Buffer.from(encoded, "base64url");
  if (!masterKey) return null;
  const key = masterKey;
  const decrypted = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) {
    decrypted[i] = buf[i] ^ key[i % key.length];
  }
  return decrypted.toString("utf8");
}

/**
 * Cache da chave mestra — computada uma vez no cold start para evitar
 * log repetitivo a cada descriptografia.
 */
let _masterKeyCache = null;
function obterChaveMestra() {
  if (!_masterKeyCache) {
    _masterKeyCache = resolverChaveMestra();
  }
  return _masterKeyCache;
}

/**
 * Obtém a API Key decriptografada a partir do doc fiscal_integrations.
 *
 * Lê o campo de credencial adequado baseado no environment da integração:
 *   - "sandbox" → credentials_sandbox
 *   - "production" → credentials_production
 *   - Fallback: credentials_encrypted (formato antigo único)
 *   - Fallback: api_key (texto puro — migração)
 *
 * Retorna null se não encontrar ou não conseguir descriptografar.
 */
async function obterApiKey(integrationId, environment) {
  if (!integrationId) return null;
  const db = admin.firestore();
  const snap = await db.collection("fiscal_integrations").doc(integrationId).get();
  if (!snap.exists) return null;

  const data = snap.data();

  // Determina qual campo de credencial ler baseado no environment
  let apiKey;
  const env = (environment || data.environment || "sandbox").toLowerCase().trim();

  if (env === "production") {
    apiKey = data.credentials_production || "";
  } else {
    apiKey = data.credentials_sandbox || "";
  }

  // Fallback para formato antigo (credentials_encrypted único)
  if (!apiKey) {
    apiKey = data.credentials_encrypted || "";
  }

  // Último fallback: texto puro legado (migração)
  if (!apiKey) {
    apiKey = data.api_key || "";
  }

  if (!apiKey) return null;

  const masterKey = obterChaveMestra();

  if (apiKey.startsWith(CRYPTO_PREFIX)) {
    const decrypted = decryptAesGcm(apiKey, masterKey);
    if (decrypted) return decrypted;
    // Se falhou com FISCAL_MASTER_KEY, tenta com a chave legada
    // (dados encriptados pelo frontend antigo com _appKey)
    const legacyFallbackKey = derivarChave256("DiPertin@2026!Fiscal#NF-e");
    const fallbackDecrypted = decryptAesGcm(apiKey, legacyFallbackKey);
    if (fallbackDecrypted) return fallbackDecrypted;
  } else if (apiKey.startsWith(CRYPTO_PREFIX_LEGACY)) {
    apiKey = decryptLegacy(apiKey, masterKey);
    if (apiKey) return apiKey;
  } else {
    // Plain text (novo fluxo: admin salva direto, backend encripta depois)
    return apiKey;
  }

  return apiKey;
}

/** Gera um ref único para a nota. */
function gerarRef(storeId) {
  const ts = Date.now().toString(36);
  const rand = crypto.randomBytes(4).toString("hex");
  return `DIP-${storeId.slice(0, 8)}-${ts}-${rand}`;
}

// ═══════════════════════════════════════════════════════════════════════
// CLASSIFICAÇÃO DE ERROS DE REDE
// ═══════════════════════════════════════════════════════════════════════

/**
 * Classifica um erro de rede/fetch em uma de três categorias:
 *
 * 1. "falha_antes_envio"  — Comprovadamente antes do POST (pode estornar saldo)
 *    Ex: URL inválida, credencial ausente, DNS não resolvido, conexão recusada
 *        sem conexão estabelecida, payload não serializável.
 *
 * 2. "aguardando_consulta" — Resultado ambíguo (NÃO estornar, NÃO reemitir)
 *    Ex: connection reset, socket hang up, fetch failed sem causa conclusiva,
 *        erro TLS durante comunicação, resposta interrompida, conexão fechada
 *        depois do envio, qualquer erro sem prova de que o provedor NÃO recebeu.
 *
 * 3. "timeout" — Timeout após POST (NÃO estornar, consultar depois)
 *
 * @param {Error|string} error - Erro capturado no catch do fetch
 * @returns {{ categoria: string, mensagem: string }}
 */
function classificarErroRede(error) {
  const msg = (error && (error.message || error.toString() || String(error))) || "";
  const msgLower = msg.toLowerCase();

  // ═══ 1. ANTES DO ENVIO (verificar PRIMEIRO) ═══
  // Erros comprovadamente antes do POST: DNS, conexão recusada, URL inválida
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
    /fetch\s+failed/i,                      // fetch Failed é ambíguo (sem prova conclusiva)
    /typeerror.*fetch/i,
  ];
  for (const p of padroesAmbiguos) {
    if (p.test(msgLower)) {
      return { categoria: "aguardando_consulta", mensagem: msg };
    }
  }

  // ═══ 4. FALLBACK: ambíguo ═══
  return { categoria: "aguardando_consulta", mensagem: msg };
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers de requisição HTTP (fetch)
// ═══════════════════════════════════════════════════════════════════════

/** Resolve a base URL da Focus NFe conforme ambiente. */
function resolverBaseUrl(integrationData, environment) {
  const rawEnv = environment || integrationData.environment || "sandbox";
  // Normaliza: "production" (inglês) → "producao" (português)
  const env = rawEnv === "production" ? "producao" : rawEnv;
  const sandboxUrl = integrationData.base_url_sandbox;
  const prodUrl = integrationData.base_url_production;

  if (env === "producao" && prodUrl) return prodUrl;
  if (env !== "producao" && sandboxUrl) return sandboxUrl;

  return env === "producao"
    ? "https://api.focusnfe.com.br/v2"
    : "https://homologacao.focusnfe.com.br/v2";
}

/**
 * Monta header Authorization para Focus NFe usando HTTP Basic Auth.
 *
 * A Focus NFe exige Basic Auth com:
 *   - usuário: token (api_key)
 *   - senha: vazia
 *   - formato: Basic base64(token:)
 *
 * @see https://doc.focusnfe.com.br/reference/autenticacao
 */
function montarBasicAuth(apiKey) {
  const credentials = `${apiKey}:`;
  const encoded = Buffer.from(credentials, "utf8").toString("base64");
  return `Basic ${encoded}`;
}

// ═══════════════════════════════════════════════════════════════════════
// Regra de obrigatoriedade de certificado A1 por provider/document_type/environment
// ═══════════════════════════════════════════════════════════════════════

/**
 * Mapa explícito de quando o certificado A1 é obrigatório.
 *
 * Estrutura: provider → document_type → environment → boolean
 *
 * "production" = produção; "sandbox" = homologação
 * null como environment = aplica-se a todos os ambientes
 *
 * ARQUITETURA REAL — Focus NFe:
 *   - A requisição HTTP de emissão NÃO envia o .pfx/certificado A1.
 *   - A Focus NFe gerencia o certificado no próprio painel/API.
 *   - O upload de certificado A1 no DiPertin é mantido para:
 *       a) validar titularidade/CNPJ do emitente;
 *       b) compatibilidade com providers que exigem assinatura local;
 *       c) emissão direta SEFAZ (futuro).
 *   - Certificate_managed_by_provider: true para Focus NFe.
 */
const REQUER_CERTIFICADO = {
  focus_nfe: {
    // Focus NFe: certificado gerenciado pelo provedor, NÃO enviado na requisição.
    // O A1 é útil para validação local de CNPJ/titularidade, mas NÃO é obrigatório.
    // certificate_managed_by_provider: true
    nfe: { production: false, sandbox: false },
    nfce: { production: false, sandbox: false },
  },
  // Providers futuros devem ser registrados aqui explicitamente
  // webmania: { nfe: true },
};

/**
 * Verifica se um certificado A1 é obrigatório para a operação.
 *
 * @param {string} provider - Nome do provedor (ex: "focus_nfe")
 * @param {string} documentType - Tipo de documento (ex: "nfe")
 * @param {string} environment - Ambiente (ex: "production", "sandbox")
 * @returns {boolean} true se o certificado é obrigatório
 */
function requiresCertificate(provider, documentType, environment) {
  const docReq = REQUER_CERTIFICADO[provider];
  if (!docReq) return false; // Provider desconhecido: não bloqueia (compatibilidade)

  const envReq = docReq[documentType];
  if (!envReq) return false; // Tipo de documento sem regra: não bloqueia

  const specific = envReq[environment];
  if (specific !== undefined) return specific; // Regra específica do ambiente

  // Fallback: se não tem regra específica, assume false
  return false;
}

/** Retorna uma resposta padronizada de sucesso/erro para o frontend. */
function resultado(sucesso, dados = {}) {
  return {
    sucesso,
    chave_acesso: dados.chave_acesso || null,
    protocolo: dados.protocolo || null,
    numero: dados.numero || null,
    serie: dados.serie || null,
    xml_url: dados.xml_url || null,
    pdf_url: dados.pdf_url || null,
    status: dados.status || (sucesso ? "autorizada" : "erro"),
    mensagem: dados.mensagem || (sucesso ? "Operação realizada." : "Erro na operação."),
    erro: dados.erro || null,
    provider_response: dados.provider_response || null,
    documento_id: dados.documento_id || null,
    codigo_rejeicao: dados.codigo_rejeicao || null,
    ref: dados.ref || null,
    // ─── Campos estruturados de erro para o frontend ───
    message: dados.message || dados.mensagem || null,
    technicalMessage: dados.technicalMessage || dados.erro || null,
    focusStatusCode: dados.focusStatusCode || null,
    focusResponse: dados.focusResponse || null,
    sefazCode: dados.sefazCode || dados.codigo_rejeicao || null,
    sefazMessage: dados.sefazMessage || null,
    validationErrors: dados.validationErrors || [],
    xmlGerado: dados.xmlGerado || null,
  };
}

/** Parseia resposta da Focus NFe para formato padronizado. */
function parseFocusNFeResponse(json, body, acao) {
  const ref = json.ref || null;
  const status = json.status || "";
  const chave = json.chave_nfe || json.chave || null;
  const protocolo = json.protocolo_autorizacao || json.protocolo || null;
  const numero = (json.numero || json.numero_nfe || "").toString();
  const serie = (json.serie || "").toString();
  const xmlUrl = json.xml || null;
  const danfeUrl = json.danfe || json.danfe_url || null;

  if (
    json.erro ||
    json.error ||
    status === "rejeitada" ||
    status === "erro" ||
    (status && /rejei/i.test(status) && (json.motivo || json.mensagem_sefaz))
  ) {
    const motivo = json.motivo || json.mensagem_sefaz || json.message || json.error || json.erro || "NF-e rejeitada pela SEFAZ.";
    const codigo = json.codigo != null
      ? String(json.codigo)
      : (json.codigo_sefaz != null ? String(json.codigo_sefaz)
        : (json.status_sefaz != null ? String(json.status_sefaz) : null));
    const sefazMsg = json.mensagem_sefaz || json.motivo || motivo;
    return resultado(false, {
      chave_acesso: chave,
      protocolo,
      numero,
      serie,
      status: "rejeitada",
      mensagem: codigo ? `Rejeição SEFAZ ${codigo}: ${sefazMsg}` : sefazMsg,
      erro: sefazMsg,
      provider_response: body,
      codigo_rejeicao: codigo,
      sefazCode: codigo,
      sefazMessage: sefazMsg,
      validationErrors: codigo
        ? [`Rejeição SEFAZ ${codigo}: ${sefazMsg}`]
        : [sefazMsg],
      ref,
    });
  }

  if (status === "processando" || status === "pendente") {
    return resultado(true, {
      chave_acesso: chave,
      numero,
      serie,
      status: "processando",
      mensagem: `NF-e enviada, aguardando processamento. Ref: ${ref}`,
      provider_response: body,
      ref,
    });
  }

  const sucesso =
    status === "autorizado" || status === "aprovado" || status === "processado";

  return resultado(sucesso, {
    chave_acesso: chave,
    protocolo,
    numero,
    serie,
    xml_url: xmlUrl,
    pdf_url: danfeUrl,
    status: sucesso ? "autorizada" : "rejeitada",
    mensagem: sucesso ? "NF-e emitida com sucesso." : "NF-e rejeitada.",
    erro: sucesso ? null : json.motivo || "Rejeitada pela SEFAZ.",
    provider_response: body,
    ref,
  });
}

/** Valida CNPJ (14 dígitos). */
function cnpjValido(cnpj) {
  if (!cnpj || typeof cnpj !== "string") return false;
  const digitos = cnpj.replace(/\D/g, "");
  return digitos.length === 14;
}

/** Status de assinatura GC considerados ativos. */
function statusAssinaturaGcAtivo(status) {
  const s = String(status || "").toLowerCase();
  return s === "ativo" || s === "active";
}

/** Verifica se modulos_extras inclui módulo fiscal. */
function moduloFiscalContratadoEm(modulosExtras) {
  const lista = (modulosExtras || []).map((m) => String(m).toLowerCase());
  return (
    lista.includes("fiscal") ||
    lista.includes("modulo_fiscal") ||
    lista.includes("nfe") ||
    lista.includes("nfce") ||
    lista.includes("notas_fiscais")
  );
}

/**
 * Valida assinatura Gestão Comercial (`assinaturas_clientes`) para emissão.
 * Retorna { sucesso, assinatura?, ...erro } — sem fallback de integração admin.
 */
function validarDadosAssinaturaGc(assinatura, storeId) {
  const statusAssinatura = String(assinatura.status || "").toLowerCase();
  if (!statusAssinaturaGcAtivo(statusAssinatura)) {
    return {
      sucesso: false,
      status: "assinatura_inativa",
      mensagem: `Assinatura está ${assinatura.status || "inativa"}. Ative-a para emitir notas.`,
      erro: `Status da assinatura: ${assinatura.status}`,
      technicalMessage: `Assinatura store_id="${storeId}" com status="${assinatura.status}". Apenas "ativo" é permitido.`,
      validationErrors: [`Assinatura ${assinatura.status || "inativa"}.`],
    };
  }

  const mpStatus = String(assinatura.pagamento_mp_status || "").toLowerCase();
  if (mpStatus && mpStatus !== "approved" && mpStatus !== "authorized") {
    return {
      sucesso: false,
      status: "pagamento_nao_confirmado",
      mensagem: "Pagamento da assinatura não aprovado.",
      erro: `pagamento_mp_status=${mpStatus}`,
      technicalMessage: `Assinatura store_id="${storeId}" com pagamento_mp_status="${mpStatus}". Apenas "approved" ou "authorized" é permitido.`,
      validationErrors: ["Pagamento não aprovado. Aguarde aprovação ou entre em contato com o suporte."],
    };
  }

  const modulosExtras = assinatura.modulos_extras || [];
  if (!moduloFiscalContratadoEm(modulosExtras)) {
    return {
      sucesso: false,
      status: "modulo_fiscal_nao_contratado",
      mensagem: "Módulo fiscal não está incluído no seu plano.",
      erro: "modulo_fiscal não contratado",
      technicalMessage: `Assinatura store_id="${storeId}" não possui módulo fiscal em modulos_extras=${JSON.stringify(modulosExtras)}.`,
      validationErrors: ["Seu plano não inclui emissão fiscal. Contrate um plano com módulo fiscal."],
    };
  }

  const modulosLower = modulosExtras.map((m) => String(m).toLowerCase());
  if (assinatura.modulo_fiscal_suspenso === true || modulosLower.includes("fiscal_suspenso")) {
    return {
      sucesso: false,
      status: "modulo_fiscal_suspenso",
      mensagem: "Módulo fiscal está temporariamente suspenso.",
      erro: "modulo_fiscal_suspenso=true",
      technicalMessage: `Assinatura store_id="${storeId}" com módulo fiscal suspenso.`,
      validationErrors: ["Módulo fiscal suspenso. Entre em contato com o suporte."],
    };
  }

  if (assinatura.data_fim || assinatura.end_date) {
    const fimDate = assinatura.data_fim?.toDate
      ? assinatura.data_fim.toDate()
      : assinatura.end_date instanceof Date
        ? assinatura.end_date
        : new Date(assinatura.data_fim || assinatura.end_date);

    if (fimDate && fimDate < new Date()) {
      return {
        sucesso: false,
        status: "assinatura_vencida",
        mensagem: `Assinatura vencida em ${fimDate.toLocaleDateString("pt-BR")}.`,
        erro: `data_fim=${fimDate.toISOString()}`,
        technicalMessage: `Assinatura store_id="${storeId}" com data_fim="${fimDate.toISOString()}" (vencida).`,
        validationErrors: [`Assinatura vencida em ${fimDate.toLocaleDateString("pt-BR")}. Renove para continuar.`],
      };
    }
  }

  const saldoNotas = assinatura.saldo_notas;
  if (saldoNotas !== undefined && saldoNotas !== null && Number(saldoNotas) <= 0) {
    return {
      sucesso: false,
      status: "saldo_insuficiente",
      mensagem: "Saldo de notas fiscais esgotado.",
      erro: `saldo_notas=${saldoNotas}`,
      technicalMessage: `Assinatura store_id="${storeId}" com saldo_notas=${saldoNotas} (zerado ou negativo).`,
      validationErrors: ["Saldo de notas fiscais esgotado. Adquira mais notas ou aguarde a renovação do plano."],
    };
  }

  return { sucesso: true, assinatura };
}

/**
 * Busca integração fiscal ativa criada pelo painel admin (`lojista_integracao`).
 */
async function buscarIntegracaoFiscalAtiva(db, storeId) {
  const snap = await db
    .collection("lojista_integracao")
    .where("store_id", "==", storeId)
    .limit(1)
    .get();

  if (snap.empty) return null;

  const doc = snap.docs[0];
  const data = doc.data();
  if (String(data.status || "").toLowerCase() !== "ativa") {
    return {
      erro: {
        sucesso: false,
        status: "integracao_fiscal_inativa",
        mensagem: `Integração fiscal está ${data.status || "inativa"}.`,
        erro: `status=${data.status}`,
        technicalMessage: `lojista_integracao/${doc.id} com status="${data.status}".`,
        validationErrors: [`Integração fiscal ${data.status || "inativa"}. Contate o suporte.`],
      },
    };
  }

  const limite = Number(data.limite_mensal || 0);
  const emitidas = Number(data.notas_emitidas || 0);
  const reservadas = Math.max(0, Number(data.notas_reservadas || 0));
  if (limite > 0 && (emitidas + reservadas) >= limite) {
    return {
      erro: {
        sucesso: false,
        status: "saldo_insuficiente",
        mensagem: "Você atingiu o limite de emissões do seu plano. Aguarde a renovação do plano ou faça um upgrade para continuar emitindo NF-e.",
        erro: `notas_emitidas=${emitidas}, notas_reservadas=${reservadas}, limite_mensal=${limite}`,
        technicalMessage: `lojista_integracao/${doc.id} atingiu limite (${emitidas}+${reservadas}/${limite}).`,
        validationErrors: [
          "Você atingiu o limite de emissões do seu plano. Aguarde a renovação do plano ou faça um upgrade para continuar emitindo NF-e.",
        ],
      },
    };
  }

  const saldoRestante = limite > 0 ? Math.max(0, limite - emitidas - reservadas) : null;
  return {
    integracaoId: doc.id,
    assinatura: {
      _id: doc.id,
      store_id: storeId,
      status: "ativo",
      saldo_notas: saldoRestante,
      modulos_extras: ["fiscal"],
      plano_nome: data.plano_nome || "",
      limite_mensal: limite,
      notas_emitidas: emitidas,
      notas_reservadas: reservadas,
      _fonte: "lojista_integracao",
    },
  };
}

/**
 * Validação COMPLETA de assinatura para EMISSÃO de novos documentos fiscais.
 *
 * USAR APENAS em: fiscalEmitirNFe
 *
 * Ordem de validação:
 * 1. `assinaturas_clientes` ativa com módulo fiscal (Gestão Comercial)
 * 2. Fallback: `lojista_integracao` ativa (plano fiscal configurado pelo admin)
 *
 * @param {object} db - Instância do Firestore Admin
 * @param {string} storeId - ID da loja
 * @returns {object} Dados da assinatura validada
 */
async function validarAssinaturaParaEmissao(db, storeId) {
  const snap = await db
    .collection("assinaturas_clientes")
    .where("store_id", "==", storeId)
    .get();

  let ultimoErroGc = null;

  if (!snap.empty) {
    const docsAtivos = snap.docs.filter((d) =>
      statusAssinaturaGcAtivo(d.data().status)
    );
    const candidatos = docsAtivos.length > 0 ? docsAtivos : snap.docs;

    for (const doc of candidatos) {
      const assinatura = { ...doc.data(), _id: doc.id };
      const resultado = validarDadosAssinaturaGc(assinatura, storeId);
      if (resultado.sucesso) {
        return {
          sucesso: true,
          assinatura,
          fonteQuota: "assinaturas_clientes",
          assinaturaId: doc.id,
        };
      }
      ultimoErroGc = resultado;
    }
  }

  const integracao = await buscarIntegracaoFiscalAtiva(db, storeId);
  if (integracao?.integracaoId) {
    console.log(
      `[validarAssinaturaParaEmissao] Usando lojista_integracao/${integracao.integracaoId} ` +
      `(GC ${ultimoErroGc ? ultimoErroGc.status : "ausente"}) store_id=${storeId}`
    );
    return {
      sucesso: true,
      assinatura: integracao.assinatura,
      fonteQuota: "lojista_integracao",
      integracaoId: integracao.integracaoId,
      assinaturaId: integracao.integracaoId,
    };
  }

  if (integracao?.erro) {
    return integracao.erro;
  }

  if (ultimoErroGc) {
    return ultimoErroGc;
  }

  return {
    sucesso: false,
    status: "assinatura_nao_encontrada",
    mensagem: "Nenhuma assinatura ou integração fiscal ativa encontrada para esta loja.",
    erro: "Assinatura não localizada.",
    technicalMessage: `Nenhuma assinatura GC nem lojista_integracao ativa com store_id="${storeId}".`,
    validationErrors: ["Plano fiscal não encontrado. Contrate um plano ou solicite ativação ao suporte."],
  };
}

/**
 * Validação LEVE de assinatura para OPERAÇÕES EM DOCUMENTOS JÁ EMITIDOS.
 *
 * USAR em: fiscalCancelarNFe, fiscalCartaCorrecaoNFe, fiscalInutilizarNFe,
 * fiscalConsultarNFe, fiscalDownloadArquivo
 *
 * Esta função NÃO bloqueia por:
 * - Assinatura vencida
 * - Pagamento pendente
 * - Saldo insuficiente
 *
 * Justificativa: Um lojista pode ter emitido notas com plano válido e depois
 * o plano venceu. Ele ainda precisa poder cancelar, fazer carta de correção,
 * inutilizar ou consultar notas que emitiu anteriormente.
 *
 * @param {object} db - Instância do Firestore Admin
 * @param {string} storeId - ID da loja
 * @returns {object} Dados da assinatura validada
 */
async function validarAssinaturaParaDocumentoExistente(db, storeId) {
  const snap = await db
    .collection("assinaturas_clientes")
    .where("store_id", "==", storeId)
    .limit(1)
    .get();

  if (snap.empty) {
    return {
      sucesso: false,
      status: "assinatura_nao_encontrada",
      mensagem: "Assinatura não encontrada para esta loja.",
      erro: "Assinatura não localizada.",
      technicalMessage: `Nenhuma assinatura em assinaturas_clientes com store_id="${storeId}".`,
      validationErrors: ["Assinatura não encontrada."],
    };
  }

  const assinatura = snap.docs[0].data();

  // Para operações em documentos existentes, permitimos que a assinatura
  // esteja inativa/vencida, pois o documento foi emitido quando estava válido.
  // Apenas verificamos que a assinatura PERTENCE a esta loja.

  return { sucesso: true, assinatura };
}

// ═══════════════════════════════════════════════════════════════════════
// Emissão de NF-e
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalEmitirNFe = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const data = request.data;
  const {
    integration_id,
    store_id,
    nfe_payload,
    cnpj,
    document_type,
    lojista_integration_id,
    certificate_id,
  } = data || {};

  const userId = request.auth.uid;
  let docRefId = null;

  if (!integration_id) throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!cnpj || !cnpjValido(cnpj)) {
    throw new HttpsError("invalid-argument",
      "CNPJ inválido. Informe um CNPJ com 14 dígitos.");
  }
  if (!nfe_payload || typeof nfe_payload !== "object") {
    throw new HttpsError("invalid-argument", "nfe_payload inválido ou ausente.");
  }
  if (!document_type) {
    throw new HttpsError("invalid-argument", "document_type é obrigatório.");
  }

  // Variável para chave idempotente (declarada aqui para acesso no catch)
  let chaveIdempotente = null;
  let db = null;

  try {
    db = admin.firestore();
    const batch = db.batch();

    // ═══ 0.5. VALIDAR IDEMPOTENCY KEY (antes de qualquer outra coisa) ═══
    // Não permite emissão sem chave idempotente estável
    const validacaoKey = saldoHelper.validarIdempotencyKey(data);
    if (!validacaoKey.valida) {
      return resultado(false, {
        status: "idempotency_key_required",
        mensagem: "Identificador de operação não fornecido. Forneça pedido_id, request_id ou ref.",
        erro: validacaoKey.erro,
        technicalMessage: validacaoKey.mensagem,
        validationErrors: [validacaoKey.mensagem],
      });
    }
    const idempotencyKey = validacaoKey.chave;
    console.log(`[fiscalEmitirNFe] Idempotency key validada: tipo=${validacaoKey.tipo}, chave=${idempotencyKey.substring(0, 20)}***`);

    // ═══ 1. VALIDAÇÃO DE SEGURANÇA (vínculo loja × usuário) ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      action: "emitir",
    });

    // ═══ 2. VALIDAÇÃO DE ASSINATURA E MÓDULO FISCAL (EMISSÃO) ═══
    // Validação COMPLETA: só permite emitir se assinatura ativa, módulo contratado,
    // pagamento confirmado, não suspensa, não vencida, saldo disponível.
    const validacaoAssinatura = await validarAssinaturaParaEmissao(db, store_id);
    if (!validacaoAssinatura.sucesso) {
      return resultado(false, {
        status: validacaoAssinatura.status,
        mensagem: validacaoAssinatura.mensagem,
        erro: validacaoAssinatura.erro,
        technicalMessage: validacaoAssinatura.technicalMessage,
        validationErrors: validacaoAssinatura.validationErrors,
      });
    }

    console.log(
      `[fiscalEmitirNFe] Assinatura validada: store_id=${store_id}, ` +
      `status=${validacaoAssinatura.assinatura.status}, ` +
      `saldo=${validacaoAssinatura.assinatura.saldo_notas ?? "sem limite"}`
    );

    // ═══ 2.5. RESERVA TRANSACIONAL DE SALDO ═══
    // Valida idempotency key e reserva saldo ANTES de qualquer chamada externa.
    // Esta reserva é atômica e idempotente:
    // - Se já existe operação autorizada, retorna o documento existente
    // - Se já existe operação em andamento, reutiliza
    // - Se saldo insuficiente, bloqueia
    const assinaturaId = validacaoAssinatura.assinaturaId ||
      validacaoAssinatura.assinatura._id || "";

    console.log(`[fiscalEmitirNFe] Validando e reservando saldo: idempotency_key=${idempotencyKey.substring(0, 20)}***, fonte=${validacaoAssinatura.fonteQuota || "assinaturas_clientes"}`);

    // Chave para uso posterior (webhook, estorno, etc) — determinística, pode ser calculada antes
    chaveIdempotente = saldoHelper.gerarChaveIdempotente(store_id, document_type || "nfe", idempotencyKey);

    // ═══ provider_ref: gerar ANTES da reserva para persistir na operação ═══
    // Regras:
    // - Se operação já existe (retry), reutilizar provider_ref existente
    // - Se é nova operação, gerar ref única
    // - Persistir no documento da operação para ser recuperável após timeout
    const operacaoExistente = await saldoHelper.obterOperacao(db, chaveIdempotente);
    let ref = operacaoExistente?.provider_ref || gerarRef(store_id);

    const reservaResultado = await saldoHelper.validarEReservar(db, {
      storeId: store_id,
      assinaturaId: assinaturaId,
      documentType: document_type || "nfe",
      idempotencyKey: idempotencyKey,
      providerRef: ref,
      userId: userId,
      integrationId: integration_id,
      fonteQuota: validacaoAssinatura.fonteQuota || "assinaturas_clientes",
      integracaoId: validacaoAssinatura.integracaoId || null,
    });

    // Atualizar ref com o que foi persistido (pode vir do reuso)
    if (reservaResultado.provider_ref) {
      ref = reservaResultado.provider_ref;
    } else if (reservaResultado.operacao?.provider_ref) {
      ref = reservaResultado.operacao.provider_ref;
    }

    if (!reservaResultado.sucesso) {
      console.warn(`[fiscalEmitirNFe] Reserva falhou: ${reservaResultado.status}`);
      const msgLimite = reservaResultado.mensagem ||
        "Você atingiu o limite de emissões do seu plano. Aguarde a renovação do plano ou faça um upgrade para continuar emitindo NF-e.";
      return resultado(false, {
        status: reservaResultado.status,
        mensagem: reservaResultado.status === "saldo_insuficiente"
          ? msgLimite
          : "Não foi possível processar sua solicitação.",
        erro: reservaResultado.status,
        technicalMessage: `Reserva de saldo falhou: ${reservaResultado.status}`,
        validationErrors: [reservaResultado.status === "saldo_insuficiente"
          ? msgLimite
          : "Operação não disponível."],
      });
    }

    // Se a operação já estava autorizada, retornar o documento existente
    if (reservaResultado.status === "ja_autorizada" && reservaResultado.operacao?.fiscal_document_id) {
      console.log(`[fiscalEmitirNFe] Operação já autorizada, retornando documento existente: ${reservaResultado.operacao.fiscal_document_id}`);
      return resultado(true, {
        status: "ja_emitida",
        fiscal_document_id: reservaResultado.operacao.fiscal_document_id,
        mensagem: "Esta nota fiscal já foi emitida anteriormente.",
        reutilizada: true,
      });
    }

    // Se a operação foi reutilizada (processando), retornar status atual
    if (reservaResultado.status === "ja_existe") {
      console.log(`[fiscalEmitirNFe] Operação já existe, continuando: ${reservaResultado.status}`);
    } else {
      console.log(`[fiscalEmitirNFe] Saldo reservado com sucesso: ${reservaResultado.saldo_reservado ? "sim" : "não (ilimitado)"}`);
    }

    // ═══ 3. VALIDAÇÃO DA INTEGRAÇÃO DO LOJISTA (lojista_integracao) ═══
    console.log(`[fiscalEmitirNFe] Validando integração lojista: lojista_integration_id=${lojista_integration_id}, store_id=${store_id}`);

    if (!lojista_integration_id) {
      return resultado(false, {
        status: "erro_integracao",
        mensagem: "Nenhuma integração fiscal ativa encontrada para esta loja.",
        erro: "lojista_integration_id não informado.",
        technicalMessage: "O ID da integração do lojista é obrigatório. Verifique se a integração foi configurada corretamente.",
        validationErrors: ["Integração do lojista não informada."],
      });
    }

    const lojistaIntegSnap = await db.collection("lojista_integracao").doc(lojista_integration_id).get();
    if (!lojistaIntegSnap.exists) {
      return resultado(false, {
        status: "erro_integracao",
        mensagem: "Nenhuma integração fiscal ativa encontrada para esta loja.",
        erro: "Documento lojista_integracao não encontrado.",
        technicalMessage: `Integração ${lojista_integration_id} não encontrada no Firestore.`,
        validationErrors: ["Integração fiscal não encontrada no servidor."],
      });
    }

    const lojistaData = lojistaIntegSnap.data();

    // Valida store_id da integração pertence ao lojista
    if (lojistaData.store_id !== store_id) {
      return resultado(false, {
        status: "erro_integracao",
        mensagem: "A integração fiscal não pertence a esta loja.",
        erro: "store_id da integração não corresponde ao store_id informado.",
        technicalMessage: `Integração store_id="${lojistaData.store_id}" ≠ store informado="${store_id}".`,
        validationErrors: ["A integração fiscal selecionada não pertence à sua loja."],
      });
    }

    // Valida status ativo
    if (lojistaData.status !== "ativa") {
      return resultado(false, {
        status: "erro_integracao",
        mensagem: `A integração fiscal está ${lojistaData.status || "inativa"}. Ative-a antes de emitir.`,
        erro: `Status da integração: ${lojistaData.status}`,
        technicalMessage: `A integração do lojista está com status "${lojistaData.status}". Apenas integrações "ativa" podem emitir.`,
        validationErrors: [`Status da integração: ${lojistaData.status}. É necessário estar "ativa".`],
      });
    }

    // ═══ 4. VALIDAÇÃO DE CERTIFICADO DIGITAL ═══
    if (certificate_id) {
      console.log(`[fiscalEmitirNFe] Validando certificado: certificate_id=${certificate_id}`);
      const certSnap = await db.collection("fiscal_certificates").doc(certificate_id).get();
      if (!certSnap.exists) {
        return resultado(false, {
          status: "erro_certificado",
          mensagem: "Certificado digital do lojista não encontrado.",
          erro: "certificate_id não encontrado no Firestore.",
          technicalMessage: `Certificado ${certificate_id} não encontrado em fiscal_certificates.`,
          validationErrors: ["Certificado digital não encontrado. Verifique se ele foi anexado corretamente."],
        });
      }
      const certData = certSnap.data();

      // Verifica se o certificado pertence à loja correta
      if (certData.store_id && certData.store_id !== store_id) {
        return resultado(false, {
          status: "erro_certificado",
          mensagem: "Certificado digital não pertence a esta loja.",
          erro: "store_id do certificado não corresponde.",
          technicalMessage: `Certificado store_id="${certData.store_id}" ≠ loja="${store_id}".`,
          validationErrors: ["O certificado digital anexado não pertence à sua loja."],
        });
      }

      // Verifica se o certificado está expirado (suporta campo novo valid_until e legado validade_fim)
      const validUntilField = certData.valid_until || certData.validade_fim;
      if (validUntilField) {
        const validadeFim = validUntilField.toDate ? validUntilField.toDate() : new Date(validUntilField);
        if (validadeFim < new Date()) {
          return resultado(false, {
            status: "erro_certificado",
            mensagem: "Certificado digital do lojista está expirado.",
            erro: `Vencido em: ${validadeFim.toISOString().split("T")[0]}`,
            technicalMessage: `Certificado expirou em ${validadeFim.toISOString()}. Renove o certificado A1.`,
            validationErrors: ["Certificado digital expirado. Renove-o para emitir NF-e."],
          });
        }
      }

      // Verifica se o CNPJ do certificado corresponde ao CNPJ da loja (campo novo certificate_cnpj ou legado cnpj)
      const cnpjCert = ((certData.certificate_cnpj || certData.cnpj || "") + "").replace(/\D/g, "");
      if (cnpjCert && cnpjCert !== cnpj.replace(/\D/g, "")) {
        return resultado(false, {
          status: "erro_certificado",
          mensagem: "CNPJ do certificado digital não corresponde ao CNPJ da empresa.",
          erro: `CNPJ do certificado: ${cnpjCert} | CNPJ da loja: ${cnpj}`,
          technicalMessage: `O certificado digital está vinculado ao CNPJ ${cnpjCert}, mas a loja informou CNPJ ${cnpj}.`,
          validationErrors: ["O certificado digital não corresponde ao CNPJ da sua empresa."],
        });
      }

      console.log(`[fiscalEmitirNFe] Certificado válido: store=${certData.store_id}, cnpj=${cnpjCert}`);
    } else {
      // ═══ REGRA EXPLÍCITA DE OBRIGATORIEDADE DO CERTIFICADO ═══
      const providerCert = (lojistaData?.provider || "focus_nfe").toLowerCase();
      const envCert = (lojistaData?.environment || lojistaData?.ambiente || "sandbox").toLowerCase();
      const docTypeCert = (document_type || "nfe").toLowerCase();

      if (requiresCertificate(providerCert, docTypeCert, envCert)) {
        return resultado(false, {
          status: "erro_certificado_obrigatorio",
          mensagem: "Certificado digital A1 é obrigatório para emissão de NF-e em produção.",
          erro: "Nenhum certificate_id informado e certificado é obrigatório para este provedor/tipo/ambiente.",
          technicalMessage: `provider=${providerCert} docType=${docTypeCert} env=${envCert} → requiresCertificate=true, mas nenhum certificate_id foi fornecido.`,
          validationErrors: ["Configure um certificado digital A1 válido antes de emitir NF-e."],
        });
      }
      console.log(`[fiscalEmitirNFe] Nenhum certificate_id informado — certificado não obrigatório para provider=${providerCert} docType=${docTypeCert} env=${envCert}`);
    }

    // ═══ 5. CARREGAR CERTIFICADO DO STORAGE (se existir e for obrigatório) ═══
    // Carrega o PFX do Cloud Storage para uso na assinatura digital do XML.
    // O certificado completo NUNCA transita no frontend.
    let pfxCertBuffer = null;
    let pfxPassword = null;
    if (certificate_id) {
      try {
        console.log(`[fiscalEmitirNFe] Carregando certificado do Storage: certificate_id=${certificate_id}`);
        const loaded = await fiscalCertificado.carregarCertificadoParaEmissao(
          certificate_id,
          admin.firestore(),
          store_id,
        );
        pfxCertBuffer = loaded.pfxBuffer;
        pfxPassword = loaded.senha;
        console.log(`[fiscalEmitirNFe] Certificado carregado do Storage com sucesso (${pfxCertBuffer.length} bytes).`);
      } catch (certLoadErr) {
        console.error(`[fiscalEmitirNFe] Erro ao carregar certificado do Storage: ${certLoadErr.message}`);
        return resultado(false, {
          status: "erro_certificado",
          mensagem: "Erro ao carregar certificado digital. Verifique se o arquivo está íntegro.",
          erro: certLoadErr.message,
          technicalMessage: `Falha ao carregar certificado via carregarCertificadoParaEmissao: ${certLoadErr.message}`,
          validationErrors: ["Erro ao carregar certificado digital. Reenvie o certificado A1."],
        });
      }
    }

    // ═══ 5. VALIDAÇÃO DE PAYLOAD (dados obrigatórios) ═══
    const validacao = await payloadValidator.validate({
      storeId: store_id,
      integrationId: integration_id,
      nfePayload: nfe_payload,
    });

    if (!validacao.isValid) {
      const mensagemErro = validacao.errors.join(" | ");
      console.error(
        `[fiscalEmitirNFe] Payload INVÁLIDO: ${validacao.errors.length} erros. ` +
        `Campos ausentes: ${validacao.missingFields.join(", ")}`
      );

      await logger.registrarLog({
        storeId: store_id,
        acao: "emitir_payload_invalido",
        status: "erro_validacao",
        usuarioUid: userId,
        mensagem: mensagemErro.slice(0, 500),
        detalhes: { total_erros: validacao.errors.length, campos_ausentes: validacao.missingFields },
        integrationId: integration_id,
      });

      return resultado(false, {
        status: "erro_validacao",
        mensagem: "Não foi possível emitir a NF-e. Corrija os erros abaixo.",
        erro: mensagemErro,
        erros_validacao: validacao.errors,
        campos_ausentes: validacao.missingFields,
        validationErrors: validacao.errors,
      });
    }

    // ═══ 6. BUSCAR INTEGRAÇÃO ADMIN E API KEY ═══
    let integSnap = await db.collection("fiscal_integrations").doc(integration_id).get();

    // Fallback: se o ID não existe, tenta encontrar pela store_id + provider
    if (!integSnap.exists) {
      console.log(
        `[fiscalEmitirNFe] integration_id=${integration_id} não encontrado. ` +
        `Buscando fallback por store_id=${store_id}...`
      );
      const fallbackSnap = await db
        .collection("fiscal_integrations")
        .where("provider", "==", "focus_nfe")
        .where("status", "==", "active")
        .limit(1)
        .get();

      if (!fallbackSnap.empty) {
        integSnap = fallbackSnap.docs[0];
        console.log(
          `[fiscalEmitirNFe] Fallback: usando integration_id=${integSnap.id}`
        );
      } else {
        throw new HttpsError("not-found", "Integração fiscal admin não encontrada no servidor.");
      }
    }
    const integData = integSnap.data();
    const apiKey = await obterApiKey(integration_id);
    if (!apiKey) {
      // Estornar saldo antes de falhar
      await saldoHelper.estornarSaldo(db, chaveIdempotente, "api_key_nao_configurada", saldoHelper.STATUS.FALHA_ANTES_ENVIO);
      throw new HttpsError("failed-precondition",
        "API Key da Focus NFe não configurada. Configure a integração admin primeiro.");
    }

    const environment = lojistaData.environment || integData.environment || "sandbox";
    const baseUrl = resolverBaseUrl(integData, environment);
    // Focus NFe v2: ref vai na URL como query param
    // O payload (flat) contém cnpj_emitente no corpo
    // ref já foi gerada e persistida na etapa 2.5; reutilizar
    const url = `${baseUrl}/nfe?ref=${ref}`;
    // ref NÃO vai no body (já está na URL)

    // ═══ LOG DO PAYLOAD (amostra segura) ═══
    // Remove campos opcionais vazios (ex.: nome_fantasia) — NF-e não exige xFant
    const payloadFocus = { ...nfe_payload };
    if (!String(payloadFocus.nome_fantasia_emitente || "").trim()) {
      delete payloadFocus.nome_fantasia_emitente;
    }

    // IE: string vazia causa SEFAZ 209. Se isento/MEI → "ISENTO"; se numérica → mantém.
    {
      let ieEmit = String(payloadFocus.inscricao_estadual_emitente || "").trim();
      let ieIsentoPayload = payloadFocus.ie_isento === true ||
        String(ieEmit).toUpperCase() === "ISENTO";

      if (!ieIsentoPayload) {
        try {
          const settingsSnap = await db
            .collection("store_fiscal_settings")
            .where("store_id", "==", store_id)
            .limit(1)
            .get();
          if (!settingsSnap.empty) {
            const tax = settingsSnap.docs[0].data().company_tax_data || {};
            const regime = String(tax.regime_tributario || "").toLowerCase().replace(/\s+/g, "_");
            if (tax.ie_isento === true || (regime === "mei" && !String(tax.ie || "").trim())) {
              ieIsentoPayload = true;
            }
            if (!ieEmit && String(tax.ie || "").trim()) {
              ieEmit = String(tax.ie).trim();
            }
          }
        } catch (e) {
          console.warn(`[fiscalEmitirNFe] Falha ao ler IE de store_fiscal_settings: ${e.message}`);
        }
      }

      if (ieIsentoPayload || ieEmit.toUpperCase() === "ISENTO") {
        payloadFocus.inscricao_estadual_emitente = "ISENTO";
        console.log("[fiscalEmitirNFe] IE emitente → ISENTO (isento/MEI)");
      } else if (ieEmit) {
        payloadFocus.inscricao_estadual_emitente = ieEmit;
      } else {
        delete payloadFocus.inscricao_estadual_emitente;
        console.warn("[fiscalEmitirNFe] IE emitente ausente e não marcada como isenta");
      }
      delete payloadFocus.ie_isento;
      delete payloadFocus.ie;
    }

    const payloadPreview = JSON.stringify(payloadFocus).substring(0, 500);
    console.log(`[fiscalEmitirNFe] Payload (início): ${payloadPreview}`);

    // ═══ LOG TÉCNICO (sem expor token) ═══
    console.log(
      `[fiscalEmitirNFe] provider=focus_nfe | storeId=${store_id} | integrationId=${integration_id} | ` +
      `lojistaIntegrationId=${lojista_integration_id} | ambiente=${environment} | ` +
      `endpoint=${baseUrl}/nfe/*** | credencialAdmin=${apiKey ? "encontrada" : "ausente"} | ` +
      `certificado=${certificate_id ? "encontrado" : "ausente"}`
    );

    // ═══ 7. CHAMADA FOCUS NFe ═══
    console.log(`[fiscalEmitirNFe] ${environment} → POST nfe/${cnpj.slice(0, 3)}*** ref=${ref}`);

    let response;
    let body;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Authorization": montarBasicAuth(apiKey),
        },
        body: JSON.stringify(payloadFocus),
      });
      body = await response.text();
    } catch (fetchError) {
      console.error("[fiscalEmitirNFe] Erro de rede ao chamar Focus NFe:", fetchError.message);
      const erroMsg = fetchError.message || "Erro de conexão com a Focus NFe";

      // ═══ CLASSIFICAR ERRO USANDO FUNÇÃO EXPLÍCITA ═══
      const classificacao = classificarErroRede(fetchError);

      if (classificacao.categoria === "timeout") {
        // ⚠️ Timeout após POST: o provedor PODE ter recebido a requisição.
        // NÃO estornar saldo — manter RESERVADO para consulta posterior.
        // Marcar como AGUARDANDO_CONSULTA para que polling possa verificar.
        await saldoHelper.atualizarStatus(db, chaveIdempotente, saldoHelper.STATUS.AGUARDANDO_CONSULTA, { motivo: "timeout_apos_envio", provider_ref: ref });

        await logger.registrarLog({
          storeId: store_id, acao: "emitir_timeout", status: "erro",
          usuarioUid: userId, mensagem: "Timeout após POST: " + erroMsg.slice(0, 300),
          integrationId: integration_id,
        });
        return resultado(false, {
          status: "timeout_consultar",
          mensagem: "Tempo limite excedido. A nota pode ter sido enviada. Consulte o status antes de reemitir.",
          erro: erroMsg,
          technicalMessage: "Timeout na requisição Focus NFe: " + erroMsg,
          provider_ref: ref,
          focusStatusCode: 0,
          validationErrors: ["Tempo limite excedido. A nota pode ter sido processada — consulte o status."],
        });
      }

      if (classificacao.categoria === "aguardando_consulta") {
        // ⚠️ Resultado ambíguo: NÃO é possível provar que o provedor NÃO recebeu.
        // NÃO estornar saldo — manter RESERVADO.
        // Marcar como AGUARDANDO_CONSULTA, preservar provider_ref.
        await saldoHelper.atualizarStatus(db, chaveIdempotente, saldoHelper.STATUS.AGUARDANDO_CONSULTA, { motivo: "erro_ambiguo", provider_ref: ref });

        await logger.registrarLog({
          storeId: store_id, acao: "emitir_erro_rede_ambiguo", status: "erro",
          usuarioUid: userId, mensagem: "Erro ambíguo: " + erroMsg.slice(0, 300),
          integrationId: integration_id,
        });
        return resultado(false, {
          status: "erro_ambiguo_consultar",
          mensagem: "Ocorreu um erro de comunicação. O status da nota será consultado automaticamente.",
          erro: erroMsg,
          technicalMessage: "Erro ambíguo na requisição Focus NFe: " + erroMsg,
          provider_ref: ref,
          focusStatusCode: 0,
          validationErrors: ["Erro de comunicação sem confirmação de envio. Consultando status posteriormente."],
        });
      }

      // ─── Categoria: falha_antes_envio ───
      // Erro comprovadamente antes do POST: seguro estornar saldo.
      await saldoHelper.estornarSaldo(db, chaveIdempotente, "erro_rede_antes_envio: " + erroMsg, saldoHelper.STATUS.FALHA_ANTES_ENVIO);

      await logger.registrarLog({
        storeId: store_id, acao: "emitir_erro_rede_antes_envio", status: "erro",
        usuarioUid: userId, mensagem: "Erro antes do envio: " + erroMsg.slice(0, 300),
        integrationId: integration_id,
      });
      return resultado(false, {
        status: "erro_comunicacao",
        mensagem: "Erro de conexão com a Focus NFe. Verifique sua internet e tente novamente.",
        erro: erroMsg,
        technicalMessage: "Falha antes do envio para Focus NFe: " + erroMsg,
        focusStatusCode: 0,
        validationErrors: ["Erro de conexão com o servidor Focus NFe."],
      });
    }

    let json;
    try {
      json = JSON.parse(body);
    } catch (_) {
      json = { erro: "Resposta inválida da Focus NFe", body: body };
    }

    // ═══ 8. TRATAR ERROS HTTP DA FOCUS NFe ═══
    const focusStatusCode = response ? response.status : 0;

    if (!response.ok) {
      console.error(`[fiscalEmitirNFe] Focus NFe HTTP ${focusStatusCode}: ${(body || "").slice(0, 500)}`);

      // Sanitiza a resposta (remove possíveis tokens)
      let focusResponseSanitized = (body || "").length > 3000 ? (body || "").substring(0, 3000) + "..." : (body || "");
      try {
        const parsed = JSON.parse(body);
        const sanitized = { ...parsed };
        delete sanitized.token;
        delete sanitized.api_key;
        delete sanitized.credentials;
        focusResponseSanitized = JSON.stringify(sanitized, null, 2);
        if (focusResponseSanitized.length > 3000) {
          focusResponseSanitized = focusResponseSanitized.substring(0, 3000) + "...";
        }
      } catch (_) {}

      // Extrai campos de erro da Focus
      const focusMsg = json.message || json.error || json.erro || "";
      const focusErros = json.erros || [];
      const focusStatus = json.status || "";
      const focusCodigo = json.codigo ? String(json.codigo) : "";
      const focusMotivo = json.motivo || "";

      // Detecta código de rejeição SEFAZ
      let sefazCode = "";
      let sefazMessage = "";
      if (focusMotivo || focusCodigo) {
        sefazCode = focusCodigo;
        sefazMessage = focusMotivo;
      } else if (/rejei[cç][aã]o/i.test(focusMsg) || focusStatus === "rejeitada") {
        const match = focusMsg.match(/\b(\d{3})\b/);
        sefazCode = focusCodigo || (match ? match[1] : "");
        sefazMessage = focusMotivo || focusMsg;
      }

      // Constrói mensagens de erro amigáveis conforme HTTP status
      let mensagemAmigavel = "";
      const validationErrors = [];

      switch (focusStatusCode) {
        case 401:
          mensagemAmigavel = "Token Focus NFe inválido. Verifique as credenciais da integração.";
          validationErrors.push("Código 401: Token Focus NFe inválido. As credenciais da API admin estão incorretas.");
          break;
        case 403:
          mensagemAmigavel = "Acesso não autorizado na Focus NFe. Verifique as permissões da conta.";
          validationErrors.push("Código 403: Acesso não autorizado na Focus NFe.");
          break;
        case 404:
          mensagemAmigavel = "Empresa do lojista não encontrada/cadastrada na Focus NFe para este ambiente.";
          validationErrors.push("Código 404: Empresa não encontrada na Focus NFe. Verifique se o CNPJ está cadastrado neste ambiente.");
          break;
        case 422:
          mensagemAmigavel = "Dados fiscais inválidos enviados para a Focus NFe. Verifique os erros abaixo.";
          if (focusErros && Array.isArray(focusErros)) {
            for (const e of focusErros) {
              const campo = e.campo || e.erro || "";
              const desc = e.mensagem || e.descricao || "";
              validationErrors.push(campo && desc ? `${campo}: ${desc}` : (desc || campo || "Erro de validação"));
            }
          } else {
            validationErrors.push(`Dados inválidos: ${focusMsg || focusMotivo || "Erro de schema/payload"}`);
          }
          if (sefazCode) {
            validationErrors.push(`Rejeição SEFAZ ${sefazCode}: ${sefazMessage || "Falha no schema XML"}`);
          }
          break;
        case 409:
          mensagemAmigavel = "Conflito: já existe uma NF-e com esta referência. Consultando status...";
          validationErrors.push("Código 409: Conflito de referência. A nota pode já ter sido emitida.");
          // NÃO gerar nova ref - reutilizar existente
          // NÃO estornar saldo - a nota pode ter sido emitida
          // Marcar como aguardando consulta
          await saldoHelper.atualizarStatus(db, saldoHelper.gerarChaveIdempotente(store_id, document_type || "nfe", idempotencyKey), saldoHelper.STATUS.AGUARDANDO_CONSULTA, { provider_ref: ref });
          // Retornar indicando que deve consultar
          return resultado(false, {
            status: "conflito_consultar",
            mensagem: "Já existe uma nota com esta referência. Consultando status...",
            erro: "HTTP 409",
            provider_ref: ref,
            technicalMessage: "HTTP 409 Conflict - nota pode já existir, consultando status.",
            validationErrors: ["A nota com esta referência pode já ter sido emitida. Status sendo verificado."],
          });
        case 429:
          mensagemAmigavel = "Muitas requisições para a Focus NFe. Aguarde e tente novamente.";
          validationErrors.push("Código 429: Limite de requisições excedido.");
          break;
        default:
          mensagemAmigavel = focusMsg || focusMotivo || `Erro na Focus NFe (HTTP ${focusStatusCode})`;
          if (focusMsg) validationErrors.push(focusMsg);
          if (focusMotivo) validationErrors.push(focusMotivo);
          if (focusErros && Array.isArray(focusErros)) {
            for (const e of focusErros) {
              validationErrors.push(e.mensagem || e.erro || JSON.stringify(e));
            }
          }
          if (sefazCode) validationErrors.push(`Rejeição SEFAZ ${sefazCode}: ${sefazMessage}`);
          break;
      }

      await logger.registrarLog({
        storeId: store_id, acao: "emitir_erro_focus", status: "erro",
        usuarioUid: userId,
        mensagem: `Focus NFe HTTP ${focusStatusCode}: ${focusMsg || focusMotivo || "erro"}`,
        erro: focusMsg || focusMotivo || `HTTP ${focusStatusCode}`,
        codigoRejeicao: sefazCode || String(focusStatusCode),
        integrationId: integration_id,
        detalhes: { focus_status_code: focusStatusCode, sefaz_code: sefazCode, ambiente: environment },
      });

      return resultado(false, {
        status: "rejeitada",
        mensagem: mensagemAmigavel,
        erro: focusMsg || focusMotivo || `HTTP ${focusStatusCode}`,
        provider_response: (body || "").length > 5000 ? (body || "").substring(0, 5000) : (body || ""),
        codigo_rejeicao: sefazCode || String(focusStatusCode),
        message: mensagemAmigavel,
        technicalMessage: `Focus NFe HTTP ${focusStatusCode} | ${focusMsg || ""} | ${focusCodigo ? "Código: " + focusCodigo : ""}`.trim(),
        focusStatusCode,
        focusResponse: focusResponseSanitized,
        sefazCode,
        sefazMessage,
        validationErrors,
        ref,
      });
    }

    // ═══ 9. RESPOSTA DE SUCESSO / PROCESSAMENTO ═══
    const res = parseFocusNFeResponse(json, body, "emitir");
    res.ref = ref;

    // ═══ 10. CONFIRMAR OU ESTORNAR SALDO ═══
    // ⚠️ NUNCA confirmar saldo para "processando" ou "pendente":
    //    saldo permanece RESERVADO até autorização definitiva.
    //    Se a nota for rejeitada depois, o polling/webhook estorna.
    const ehAutorizada = res.sucesso && (res.status === "autorizada" || res.status === "aprovado" || res.status === "processado");
    const ehProcessando = res.sucesso && (res.status === "processando" || res.status === "pendente");

    if (ehAutorizada) {
      // Nota autorizada: confirmar consumo de saldo
      await saldoHelper.confirmarConsumo(db, chaveIdempotente, null, {
        status: res.status,
        message: res.erro || null,
      });
      console.log("[fiscalEmitirNFe] Saldo confirmado: operacao=" + chaveIdempotente);
    } else if (ehProcessando) {
      // Nota em processamento: saldo permanece RESERVADO.
      // O frontend deve consultar via fiscalConsultarEAtualizarStatus,
      // que chama saldoHelper.processarPolling() para confirmar ou estornar.
      console.log("[fiscalEmitirNFe] NF-e em processamento. Saldo mantido como RESERVADO. status=" + res.status);
    } else {
      // Nota rejeitada: estornar saldo
      await saldoHelper.estornarSaldo(db, chaveIdempotente, "rejeitada: " + (res.erro || "falha"), saldoHelper.STATUS.REJEITADO);
      console.log("[fiscalEmitirNFe] Saldo estornado (rejeitada): operacao=" + chaveIdempotente);
    }

    // ═══ 11. SALVAR DOCUMENTO NO FIRESTORE ═══
    const docRef = db.collection("fiscal_documents").doc();
    docRefId = docRef.id;
    batch.set(docRef, {
      store_id,
      document_type: document_type || "nfe",
      provider: "focus_nfe",
      provider_response: res.sucesso ? null : (body || "").substring(0, 5000),
      status: res.status,
      access_key: res.chave_acesso,
      protocol: res.protocolo,
      number: res.numero,
      series: res.serie || null,
      ref,
      xml_url: res.xml_url,
      pdf_url: res.pdf_url,
      rejection_reason: res.erro,
      rejection_code: res.codigo_rejeicao,
      integration_id,
      lojista_integration_id,
      created_at: FirebaseFieldValue.serverTimestamp(),
      updated_at: FirebaseFieldValue.serverTimestamp(),
      issued_at: res.status === "autorizada"
        ? FirebaseFieldValue.serverTimestamp()
        : null,
    });

    await batch.commit();

    // ═══ 11. LOG ═══
    await logger.registrarLog({
      storeId: store_id,
      acao: res.sucesso ? "emitir" : "emitir_rejeitada",
      status: res.sucesso ? "sucesso" : "erro",
      usuarioUid: userId,
      documentoId: docRef.id,
      chaveAcesso: res.chave_acesso,
      mensagem: res.sucesso
        ? `NF-e ${res.numero || ""} emitida. Ref: ${ref}`
        : `NF-e rejeitada: ${res.erro}`,
      erro: res.erro,
      codigoRejeicao: res.codigo_rejeicao,
      integrationId: integration_id,
    });

    // ═══ 11. HISTÓRICO DE STATUS ═══
    await logger.registrarStatusHistory({
      storeId: store_id,
      documentoId: docRef.id,
      chaveAcesso: res.chave_acesso,
      statusAnterior: "criada",
      statusNovo: res.status,
      usuarioUid: userId,
      origem: "api",
    });

    res.documento_id = docRef.id;
    return res;
  } catch (e) {
    if (e instanceof HttpsError) {
      // Estornar saldo em caso de erro de validação ANTES do POST
      if (chaveIdempotente) {
        await saldoHelper.estornarSaldo(db, chaveIdempotente, "https_error: " + e.message, saldoHelper.STATUS.FALHA_ANTES_ENVIO);
      }
      throw e;
    }
    console.error("[fiscalEmitirNFe] Erro não tratado:", e.message, e.stack ? e.stack.slice(0, 300) : "");

    const erroMsg = e.message || "Erro interno no servidor";

    // Estornar saldo em caso de exceção
    if (chaveIdempotente) {
      await saldoHelper.estornarSaldo(db, chaveIdempotente, "excecao_interna: " + erroMsg, saldoHelper.STATUS.FALHA_ANTES_ENVIO);
    }

    await logger.registrarLog({
      storeId: store_id || "unknown",
      acao: "emitir_erro_interno",
      status: "erro",
      usuarioUid: userId || "unknown",
      mensagem: "Erro interno: " + erroMsg.slice(0, 300),
      erro: erroMsg,
      integrationId: integration_id || null,
    });

    return resultado(false, {
      status: "erro",
      mensagem: "Erro interno ao emitir NF-e. Tente novamente ou contate o suporte.",
      erro: erroMsg,
      technicalMessage: "Exceção não tratada: " + erroMsg,
      focusStatusCode: 0,
      validationErrors: ["Erro interno: " + erroMsg],
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Cancelamento de NF-e
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalCancelarNFe = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const data = request.data;
  const { integration_id, chave_acesso, justificativa, numero_protocolo, store_id } = data || {};
  const userId = request.auth.uid;

  if (!integration_id) throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
  if (!chave_acesso) throw new HttpsError("invalid-argument", "chave_acesso é obrigatória.");
  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!justificativa || justificativa.length < 15) {
    throw new HttpsError("invalid-argument", "Justificativa deve ter no mínimo 15 caracteres.");
  }

  try {
    const db = admin.firestore();

    // ═══ SEGURANÇA: validar vínculo loja × nota ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      chaveAcesso: chave_acesso,
      action: "cancelar",
    });

    // ═══ VALIDAÇÃO DE ASSINATURA (DOCUMENTO EXISTENTE) ═══
    // Validação LEVE: só verifica que assinatura existe e pertence à loja.
    // NÃO bloqueia por vencimento/suspensão, pois o documento foi emitido antes.
    const validacaoAssinatura = await validarAssinaturaParaDocumentoExistente(db, store_id);
    if (!validacaoAssinatura.sucesso) {
      return resultado(false, {
        status: validacaoAssinatura.status,
        mensagem: validacaoAssinatura.mensagem,
        erro: validacaoAssinatura.erro,
        technicalMessage: validacaoAssinatura.technicalMessage,
        validationErrors: validacaoAssinatura.validationErrors,
      });
    }

    const integSnap = await db.collection("fiscal_integrations").doc(integration_id).get();
    if (!integSnap.exists) {
      throw new HttpsError("not-found", "Integração fiscal não encontrada.");
    }
    const integData = integSnap.data();
    const apiKey = await obterApiKey(integration_id);
    if (!apiKey) {
      throw new HttpsError("failed-prerequisite", "API Key não configurada.");
    }

    // ═══ VERIFICAR SE NOTA ESTÁ AUTORIZADA ANTES DE CANCELAR ═══
    const docsSnap = await db.collection("fiscal_documents")
      .where("access_key", "==", chave_acesso)
      .where("store_id", "==", store_id)
      .limit(1)
      .get();

    if (!docsSnap.empty) {
      const docData = docsSnap.docs[0].data();
      const statusAtual = docData.status || "";
      if (statusAtual !== "autorizada") {
        return resultado(false, {
          erro: `Nota fiscal não pode ser cancelada. Status atual: ${statusAtual}. Apenas notas autorizadas podem ser canceladas.`,
          status: "erro",
        });
      }
    }

    const baseUrl = resolverBaseUrl(integData, integData.environment);
    const url = `${baseUrl}/nfe/cancelamento`;

    const bodyPayload = {
      chave: chave_acesso,
      justificativa,
    };
    if (numero_protocolo) bodyPayload.protocolo = numero_protocolo;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": montarBasicAuth(apiKey),
      },
      body: JSON.stringify(bodyPayload),
    });

    const body = await response.text();
    let json;
    try {
      json = JSON.parse(body);
    } catch (_) {
      json = {};
    }

    if (json.erro || json.error) {
      await logger.registrarLog({
        storeId: store_id,
        acao: "cancelar_erro",
        status: "erro",
        usuarioUid: userId,
        chaveAcesso: chave_acesso,
        mensagem: `Erro no cancelamento: ${json.error || json.erro}`,
        erro: json.error || json.erro,
        integrationId: integration_id,
      });

      return resultado(false, {
        erro: json.error || json.erro || "Erro no cancelamento.",
        provider_response: body,
        codigo_rejeicao: json.codigo ? String(json.codigo) : null,
        status: "erro",
      });
    }

    const res = resultado(true, {
      chave_acesso,
      protocolo: json.protocolo_cancelamento || json.protocolo || null,
      numero: json.numero ? String(json.numero) : null,
      status: "cancelada",
      mensagem: "Cancelamento realizado com sucesso.",
      provider_response: body,
    });

    // Atualiza documento no Firestore
    if (!docsSnap.empty) {
      await docsSnap.docs[0].ref.update({
        status: "cancelada",
        cancellation_protocol: res.protocolo,
        cancellation_justification: justificativa,
        cancelled_at: FirebaseFieldValue.serverTimestamp(),
        updated_at: FirebaseFieldValue.serverTimestamp(),
      });

      // Histórico de status
      await logger.registrarStatusHistory({
        storeId: store_id,
        documentoId: docsSnap.docs[0].id,
        chaveAcesso: chave_acesso,
        statusAnterior: "autorizada",
        statusNovo: "cancelada",
        motivo: justificativa,
        usuarioUid: userId,
        origem: "api",
      });
    }

    // Log
    await logger.registrarLog({
      storeId: store_id,
      acao: "cancelar",
      status: "sucesso",
      usuarioUid: userId,
      chaveAcesso: chave_acesso,
      documentoId: docsSnap.empty ? null : docsSnap.docs[0].id,
      mensagem: `NF-e ${chave_acesso} cancelada.`,
      integrationId: integration_id,
    });

    return res;
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalCancelarNFe] Erro:", e.message);
    return resultado(false, {
      erro: `Erro ao cancelar NF-e: ${e.message}`,
      provider_response: e.message,
      status: "erro",
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Consulta de NF-e
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalConsultarNFe = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { integration_id, chave_acesso, store_id } = request.data || {};
  const userId = request.auth.uid;

  if (!integration_id) throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
  if (!chave_acesso) throw new HttpsError("invalid-argument", "chave_acesso é obrigatória.");
  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");

  const db = admin.firestore();

  try {
    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      chaveAcesso: chave_acesso,
      action: "consultar",
    });

    const apiKey = await obterApiKey(integration_id);
    if (!apiKey) {
      throw new HttpsError("failed-prerequisite", "API Key não configurada.");
    }

    const integSnap = await admin.firestore()
      .collection("fiscal_integrations").doc(integration_id).get();
    const integData = integSnap.data() || {};
    const baseUrl = resolverBaseUrl(integData, integData.environment);
    const url = `${baseUrl}/nfe/${chave_acesso}`;

    const response = await fetch(url, {
      headers: {
        "Accept": "application/json",
        "Authorization": montarBasicAuth(apiKey),
      },
    });

    const body = await response.text();
    let json;
    try {
      json = JSON.parse(body);
    } catch (_) {
      json = {};
    }

    const res = parseFocusNFeResponse(json, body, "consultar");

    // ═══════════════════════════════════════════════════════════════════════
    // ATUALIZAR SALDO VIA HELPER (polling)
    // ═══════════════════════════════════════════════════════════════════════
    // Buscar provider_ref pela chave de acesso
    const db = admin.firestore();
    try {
      const docSnap = await db.collection("fiscal_documents")
        .where("access_key", "==", chave_acesso)
        .limit(1)
        .get();

      if (!docSnap.empty) {
        const docData = docSnap.docs[0].data();
        const providerRef = docData.ref || docData.provider_ref || null;

        if (providerRef) {
          const saldoResultado = await saldoHelper.processarPolling(
            db,
            providerRef,
            res.status,
            docSnap.docs[0].id,
            { status: res.status, message: res.erro }
          );
          console.log(`[fiscalConsultarNFe] Saldo atualizado: provider_ref=${providerRef}, resultado=${saldoResultado.status}`);
        }
      }
    } catch (saldoErr) {
      // Erro no saldo helper não deve falhar a consulta
      console.warn(`[fiscalConsultarNFe] Erro ao processar saldo: ${saldoErr.message}`);
    }

    // Log
    await logger.registrarLog({
      storeId: store_id,
      acao: "consultar",
      status: res.sucesso ? "sucesso" : "erro",
      usuarioUid: userId,
      chaveAcesso: chave_acesso,
      mensagem: res.sucesso ? `NF-e consultada: status ${res.status}` : `Erro na consulta: ${res.erro}`,
      integrationId: integration_id,
    });

    return res;
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalConsultarNFe] Erro:", e.message);
    return resultado(false, {
      erro: `Erro ao consultar NF-e: ${e.message}`,
      status: "erro",
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Carta de Correção (CC-e)
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalCartaCorrecaoNFe = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { integration_id, chave_acesso, texto_correcao, sequencia, store_id } = request.data || {};
  const userId = request.auth.uid;

  if (!integration_id) throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
  if (!chave_acesso) throw new HttpsError("invalid-argument", "chave_acesso é obrigatória.");
  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!texto_correcao || texto_correcao.length < 15) {
    throw new HttpsError("invalid-argument", "Texto da correção deve ter no mínimo 15 caracteres.");
  }

  try {
    const db = admin.firestore();

    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      chaveAcesso: chave_acesso,
      action: "carta_correcao",
    });

    // ═══ VALIDAÇÃO DE ASSINATURA (DOCUMENTO EXISTENTE) ═══
    // Validação LEVE: só verifica que assinatura existe e pertence à loja.
    // NÃO bloqueia por vencimento/suspensão, pois o documento foi emitido antes.
    const validacaoAssinatura = await validarAssinaturaParaDocumentoExistente(db, store_id);
    if (!validacaoAssinatura.sucesso) {
      return resultado(false, {
        status: validacaoAssinatura.status,
        mensagem: validacaoAssinatura.mensagem,
        erro: validacaoAssinatura.erro,
        technicalMessage: validacaoAssinatura.technicalMessage,
        validationErrors: validacaoAssinatura.validationErrors,
      });
    }

    const apiKey = await obterApiKey(integration_id);
    if (!apiKey) {
      throw new HttpsError("failed-prerequisite", "API Key não configurada.");
    }

    const integSnap = await admin.firestore()
      .collection("fiscal_integrations").doc(integration_id).get();
    const integData = integSnap.data() || {};
    const baseUrl = resolverBaseUrl(integData, integData.environment);
    const url = `${baseUrl}/nfe/${chave_acesso}/carta_correcao`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": montarBasicAuth(apiKey),
      },
      body: JSON.stringify({
        correcao: texto_correcao,
        sequencia: sequencia || 1,
      }),
    });

    const body = await response.text();
    let json;
    try {
      json = JSON.parse(body);
    } catch (_) {
      json = {};
    }

    if (json.erro || json.error) {
      return resultado(false, {
        erro: json.error || json.erro || "Erro na carta de correção.",
        provider_response: body,
        codigo_rejeicao: json.codigo ? String(json.codigo) : null,
        status: "erro",
      });
    }

    return resultado(true, {
      chave_acesso,
      protocolo: json.protocolo || null,
      status: "carta_correcao_enviada",
      mensagem: `Carta de Correção #${sequencia || 1} enviada com sucesso.`,
      provider_response: body,
    });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalCartaCorrecaoNFe] Erro:", e.message);
    return resultado(false, {
      erro: `Erro ao enviar CC-e: ${e.message}`,
      status: "erro",
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Inutilização de numeração
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalInutilizarNFe = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { integration_id, store_id, serie, numero_inicial, numero_final, justificativa } =
    request.data || {};
  const userId = request.auth.uid;

  if (!integration_id) throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!serie) throw new HttpsError("invalid-argument", "serie é obrigatória.");
  if (!numero_inicial || !numero_final) {
    throw new HttpsError("invalid-argument",
      "numero_inicial e numero_final são obrigatórios.");
  }
  if (!justificativa || justificativa.length < 15) {
    throw new HttpsError("invalid-argument", "Justificativa deve ter no mínimo 15 caracteres.");
  }

  try {
    const db = admin.firestore();

    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      action: "inutilizar",
    });

    // ═══ VALIDAÇÃO DE ASSINATURA (DOCUMENTO EXISTENTE) ═══
    // Validação LEVE: só verifica que assinatura existe e pertence à loja.
    // NÃO bloqueia por vencimento/suspensão, pois o documento foi emitido antes.
    const validacaoAssinatura = await validarAssinaturaParaDocumentoExistente(db, store_id);
    if (!validacaoAssinatura.sucesso) {
      return resultado(false, {
        status: validacaoAssinatura.status,
        mensagem: validacaoAssinatura.mensagem,
        erro: validacaoAssinatura.erro,
        technicalMessage: validacaoAssinatura.technicalMessage,
        validationErrors: validacaoAssinatura.validationErrors,
      });
    }

    const apiKey = await obterApiKey(integration_id);
    if (!apiKey) {
      throw new HttpsError("failed-prerequisite", "API Key não configurada.");
    }

    const integSnap = await admin.firestore()
      .collection("fiscal_integrations").doc(integration_id).get();
    const integData = integSnap.data() || {};

    const cnpj = integData.cnpj_emitente || "";
    if (!cnpjValido(cnpj)) {
      throw new HttpsError("failed-prerequisite",
        "CNPJ do emitente não configurado na integração. Configure antes de inutilizar.");
    }

    const baseUrl = resolverBaseUrl(integData, integData.environment);
    const url = `${baseUrl}/nfe/${cnpj}/inutilizacao`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": montarBasicAuth(apiKey),
      },
      body: JSON.stringify({
        serie,
        numero_inicial,
        numero_final,
        justificativa,
      }),
    });

    const body = await response.text();
    let json;
    try {
      json = JSON.parse(body);
    } catch (_) {
      json = {};
    }

    if (json.erro || json.error) {
      return resultado(false, {
        erro: json.error || json.erro || "Erro na inutilização.",
        provider_response: body,
        codigo_rejeicao: json.codigo ? String(json.codigo) : null,
        status: "erro",
      });
    }

    return resultado(true, {
      protocolo: json.protocolo || null,
      status: "numeracao_inutilizada",
      mensagem: `Numeração Série ${serie}: ${numero_inicial}-${numero_final} inutilizada.`,
      provider_response: body,
    });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalInutilizarNFe] Erro:", e.message);
    return resultado(false, {
      erro: `Erro ao inutilizar numeração: ${e.message}`,
      status: "erro",
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Deletar documento fiscal
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalDeletarDocumento = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const {
    store_id,
    numero_nfe,
    serie,
    documento_id,
    ref: refNota,
    fiscal_document_id,
  } = request.data || {};
  const userId = request.auth.uid;

  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!documento_id && !numero_nfe && !fiscal_document_id && !refNota) {
    throw new HttpsError(
      "invalid-argument",
      "Informe documento_id, numero_nfe, fiscal_document_id ou ref para deletar."
    );
  }

  try {
    const db = admin.firestore();

    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      action: "deletar_documento",
    });

    const deletados = [];
    let rotulo = numero_nfe || documento_id || fiscal_document_id || refNota || "—";

    // 1) Documento da UI: users/{storeId}/notas_fiscais/{documento_id}
    //    Notas rejeitadas/aguardando frequentemente NÃO têm numero_nfe.
    if (documento_id) {
      const notaRef = db
        .collection("users")
        .doc(store_id)
        .collection("notas_fiscais")
        .doc(documento_id);
      const notaSnap = await notaRef.get();
      if (notaSnap.exists) {
        const notaData = notaSnap.data() || {};
        const sit = String(notaData.situacao || notaData.status || "").toLowerCase();
        // Bloqueia apagar nota já autorizada/emitida sem cancelamento prévio
        if (["autorizada", "autorizado", "emitida", "aprovada"].includes(sit)) {
          throw new HttpsError(
            "failed-precondition",
            "Não é possível deletar uma NF-e autorizada/emitida. Cancele a nota na SEFAZ antes."
          );
        }
        if (notaData.numero_nfe) rotulo = String(notaData.numero_nfe);
        await notaRef.delete();
        deletados.push(`notas_fiscais/${documento_id}`);
      }
    }

    // 2) fiscal_documents (Admin) — por id, número, ou ref Focus
    const docsRef = db.collection("fiscal_documents");
    let fiscalSnap = null;

    if (fiscal_document_id) {
      const s = await docsRef.doc(fiscal_document_id).get();
      if (s.exists && s.data()?.store_id === store_id) fiscalSnap = s;
    }

    if (!fiscalSnap && numero_nfe) {
      let q = docsRef
        .where("store_id", "==", store_id)
        .where("number", "==", String(numero_nfe))
        .limit(1);
      if (serie) {
        q = docsRef
          .where("store_id", "==", store_id)
          .where("number", "==", String(numero_nfe))
          .where("series", "==", String(serie))
          .limit(1);
      }
      const qs = await q.get();
      if (!qs.empty) fiscalSnap = qs.docs[0];
    }

    if (!fiscalSnap && refNota) {
      const qs = await docsRef
        .where("store_id", "==", store_id)
        .where("ref", "==", String(refNota))
        .limit(1)
        .get();
      if (!qs.empty) fiscalSnap = qs.docs[0];
    }

    if (fiscalSnap) {
      const fData = fiscalSnap.data() || {};
      const fStatus = String(fData.status || "").toLowerCase();
      if (["autorizada", "autorizado", "aprovado", "processado"].includes(fStatus)) {
        throw new HttpsError(
          "failed-precondition",
          "Não é possível deletar um documento fiscal autorizado. Cancele a NF-e na SEFAZ antes."
        );
      }
      if (fData.number) rotulo = String(fData.number);
      await docsRef.doc(fiscalSnap.id).delete();
      deletados.push(`fiscal_documents/${fiscalSnap.id}`);
    }

    if (deletados.length === 0) {
      throw new HttpsError(
        "not-found",
        "Documento fiscal não encontrado. Pode já ter sido deletado."
      );
    }

    await logger.registrarLog({
      storeId: store_id,
      acao: "deletar_documento",
      status: "sucesso",
      usuarioUid: userId,
      documentoId: documento_id || fiscalSnap?.id || null,
      mensagem: `Documento fiscal (${rotulo}) deletado: ${deletados.join(", ")}.`,
    });

    return resultado(true, {
      mensagem: `Documento ${rotulo !== "—" ? `Nº ${rotulo}` : ""} deletado permanentemente.`.replace("  ", " ").trim(),
      status: "deletado",
      documento_id: documento_id || null,
      deletados,
    });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalDeletarDocumento] Erro:", e.message);
    return resultado(false, {
      erro: `Erro ao deletar documento: ${e.message}`,
      status: "erro",
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Listar notas fiscais da loja (com segurança)
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalListarNotas = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { store_id, limit: maxLimit, status_filtro, data_inicio, data_fim } = request.data || {};
  const userId = request.auth.uid;

  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");

  try {
    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      action: "listar_notas",
    });

    const db = admin.firestore();
    let query = db.collection("fiscal_documents")
      .where("store_id", "==", store_id)
      .orderBy("created_at", "desc");

    if (status_filtro) {
      query = query.where("status", "==", status_filtro);
    }

    if (data_inicio) {
      const inicio = new Date(data_inicio);
      query = query.where("created_at", ">=", inicio);
    }

    const limite = Math.min(maxLimit || 50, 200);
    const snap = await query.limit(limite).get();

    const docs = snap.docs
      .map((d) => {
        const data = d.data();
        return {
          id: d.id,
          store_id: data.store_id,
          document_type: data.document_type,
          status: data.status,
          access_key: data.access_key,
          number: data.number,
          series: data.series,
          ref: data.ref,
          xml_url: data.xml_url,
          pdf_url: data.pdf_url,
          rejection_reason: data.rejection_reason,
          rejection_code: data.rejection_code,
          created_at: data.created_at?.toDate?.()?.toISOString() || null,
          updated_at: data.updated_at?.toDate?.()?.toISOString() || null,
          issued_at: data.issued_at?.toDate?.()?.toISOString() || null,
          // NUNCA expõe token/integration_id completo
        };
      });

    // Filtro por data_fim (client-side após paginação)
    let resultados = docs;
    if (data_fim) {
      const fim = new Date(data_fim).getTime();
      resultados = docs.filter((d) => {
        if (!d.created_at) return true;
        return new Date(d.created_at).getTime() <= fim;
      });
    }

    return {
      sucesso: true,
      documentos: resultados,
      total: resultados.length,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalListarNotas] Erro:", e.message);
    return { sucesso: false, documentos: [], total: 0, erro: e.message };
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Baixar XML da nota
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalBaixarXml = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { store_id, documento_id } = request.data || {};
  const userId = request.auth.uid;

  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!documento_id) throw new HttpsError("invalid-argument", "documento_id é obrigatório.");

  try {
    // ═══ SEGURANÇA (valida que o doc pertence à loja) ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      docId: documento_id,
      action: "baixar_xml",
    });

    const db = admin.firestore();
    const docSnap = await db.collection("fiscal_documents").doc(documento_id).get();
    if (!docSnap.exists) {
      throw new HttpsError("not-found", "Documento fiscal não encontrado.");
    }

    const docData = docSnap.data();
    const xmlUrl = docData.xml_url || "";

    // Log
    await logger.registrarLog({
      storeId: store_id,
      acao: "baixar_xml",
      status: "sucesso",
      usuarioUid: userId,
      documentoId: documento_id,
      chaveAcesso: docData.access_key,
    });

    return resultado(true, {
      xml_url: xmlUrl,
      documento_id,
      chave_acesso: docData.access_key,
      mensagem: xmlUrl ? "XML disponível para download." : "XML não disponível para esta nota.",
    });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalBaixarXml] Erro:", e.message);
    return resultado(false, {
      erro: `Erro ao baixar XML: ${e.message}`,
      status: "erro",
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Baixar DANFE/PDF da nota
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalBaixarDanfe = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { store_id, documento_id } = request.data || {};
  const userId = request.auth.uid;

  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!documento_id) throw new HttpsError("invalid-argument", "documento_id é obrigatório.");

  try {
    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      docId: documento_id,
      action: "baixar_danfe",
    });

    const db = admin.firestore();
    const docSnap = await db.collection("fiscal_documents").doc(documento_id).get();
    if (!docSnap.exists) {
      throw new HttpsError("not-found", "Documento fiscal não encontrado.");
    }

    const docData = docSnap.data();
    const pdfUrl = docData.pdf_url || "";

    await logger.registrarLog({
      storeId: store_id,
      acao: "baixar_danfe",
      status: "sucesso",
      usuarioUid: userId,
      documentoId: documento_id,
      chaveAcesso: docData.access_key,
    });

    return resultado(true, {
      pdf_url: pdfUrl,
      documento_id,
      chave_acesso: docData.access_key,
      mensagem: pdfUrl ? "DANFE disponível para download." : "DANFE não disponível para esta nota.",
    });
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalBaixarDanfe] Erro:", e.message);
    return resultado(false, {
      erro: `Erro ao baixar DANFE: ${e.message}`,
      status: "erro",
    });
  }
});

// ═══════════════════════════════════════════════════════════════════════
// Teste de conexão Focus NFe (já existente, mantido)
// ═══════════════════════════════════════════════════════════════════════

exports.fiscalTestarConexaoFocus = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { integration_id, store_id } = request.data || {};
  if (!integration_id) {
    throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
  }

  // Validação de loja: staff pode testar qualquer integração;
  // lojista só pode testar a integração vinculada à sua própria loja.
  if (store_id) {
    try {
      await securityGuard.validateStoreAccess({
        userId: request.auth.uid,
        storeId: store_id,
        action: "testar_conexao",
        allowStaff: true,
      });

      // Verifica se a integração está vinculada à loja
      const db = admin.firestore();
      const settingsSnap = await db
        .collection("store_fiscal_settings")
        .where("store_id", "==", store_id)
        .limit(1)
        .get();

      if (!settingsSnap.empty) {
        const settingsData = settingsSnap.docs[0].data();
        const linkedIntegrationId = settingsData.integration_id || "";
        if (linkedIntegrationId && linkedIntegrationId !== integration_id) {
          throw new HttpsError(
            "permission-denied",
            "Esta integração não está vinculada à sua loja."
          );
        }
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      throw new HttpsError(
        "permission-denied",
        "Você não tem permissão para testar esta integração."
      );
    }
  } else {
    // Sem store_id: apenas staff pode testar
    const userSnap = await admin.firestore().collection("users").doc(request.auth.uid).get();
    if (!userSnap.exists) {
      throw new HttpsError("permission-denied", "Usuário não encontrado.");
    }
    const userData = userSnap.data();
    const role = (userData.role || userData.tipo || "").toLowerCase().trim();
    const isStaff = role === "master" || role === "master_city" || role === "superadmin";
    if (!isStaff) {
      throw new HttpsError(
        "permission-denied",
        "Informe store_id para testar a integração da sua loja."
      );
    }
  }

  const logData = {
    ambiente: "",
    url_chamada: "",
    status_http: 0,
    mensagem_focus: "",
    data_teste: new Date().toISOString(),
  };

  try {
    const db = admin.firestore();
    const integSnap = await db.collection("fiscal_integrations").doc(integration_id).get();
    if (!integSnap.exists) {
      throw new HttpsError("not-found", "Integração fiscal não encontrada.");
    }

    const integData = integSnap.data();
    const apiKey = await obterApiKey(integration_id);
    if (!apiKey || apiKey.trim().length === 0) {
      return {
        sucesso: false,
        mensagem: "Token Focus NFe vazio. Informe um token válido.",
        ambiente: integData.environment || "sandbox",
        validado: false,
      };
    }

    const environment = integData.environment || "sandbox";
    const baseUrl = resolverBaseUrl(integData, environment);
    // Usa /nfe/{ref_teste} em vez de /empresas porque o endpoint de
    // empresas só existe em produção. Com /nfe/{ref}:
    //   - HTTP 404 → token válido (ref não encontrada, esperado)
    //   - HTTP 401/403 → token inválido
    const refTeste = `teste_conexao_${Date.now()}`;
    const url = `${baseUrl}/nfe/${refTeste}`;

    logData.ambiente = environment;
    logData.url_chamada = url;

    console.log(`[fiscalTestarConexaoFocus] Ambiente: ${environment}`);
    console.log(`[fiscalTestarConexaoFocus] URL: ${url}`);
    console.log(`[fiscalTestarConexaoFocus] Auth: Basic (token oculto)`);

    const response = await fetch(url, {
      method: "GET",
      headers: {
        "Accept": "application/json",
        "Authorization": montarBasicAuth(apiKey),
      },
    });

    logData.status_http = response.status;

    const body = await response.text();
    let json;
    try {
      json = JSON.parse(body);
    } catch (_) {
      json = {};
    }

    logData.mensagem_focus = json.error || json.erro || json.mensagem || (response.ok ? "" : body.slice(0, 200));

    console.log(`[fiscalTestarConexaoFocus] HTTP ${response.status}`);

    // 404 = ref teste não encontrada, mas credenciais VÁLIDAS
    if (response.status === 404) {
      console.log("[fiscalTestarConexaoFocus] Token Focus NFe VÁLIDO ✓ (ref nao encontrada = esperado)");
      return {
        sucesso: true, validado: true,
        mensagem: `Credenciais validadas com sucesso no ambiente ${["producao","production"].includes(environment) ? "Produ\u00e7\u00e3o" : "Homologa\u00e7\u00e3o"}.`,
        ambiente: environment, status_http: response.status,
      };
    }

    if (response.status === 200 || response.status === 201 || response.status === 202) {
      console.log("[fiscalTestarConexaoFocus] Token Focus NFe VÁLIDO ✓");
      return {
        sucesso: true, validado: true,
        mensagem: `Credenciais validadas com sucesso no ambiente ${["producao","production"].includes(environment) ? "Produ\u00e7\u00e3o" : "Homologa\u00e7\u00e3o"}.`,
        ambiente: environment, status_http: response.status,
      };
    }

    if (response.status === 401 || response.status === 403) {
      console.log("[fiscalTestarConexaoFocus] Token INVÁLIDO ✗");
      return {
        sucesso: false, validado: false,
        mensagem: "Token Focus NFe inv\u00e1lido ou sem permiss\u00e3o para este ambiente.",
        ambiente: environment, status_http: response.status,
        erro_detalhado: json.error || json.erro || "Token n\u00e3o autorizado",
      };
    }

    return {
      sucesso: false, validado: false,
      mensagem: `Focus NFe retornou HTTP ${response.status}. Tente novamente.`,
      ambiente: environment, status_http: response.status,
      erro_detalhado: json.error || json.erro || `HTTP ${response.status}`,
    };
  } catch (e) {
    const msg = e.message || String(e);
    console.error(`[fiscalTestarConexaoFocus] Erro: ${msg}`);

    if (e instanceof HttpsError) throw e;

    if (msg.includes("Timeout") || msg.includes("timed out")) {
      return {
        sucesso: false, validado: false,
        mensagem: "Não foi possível conectar à Focus NFe no momento (timeout).",
        ambiente: logData.ambiente || "desconhecido", status_http: 0,
        erro_detalhado: "Timeout na conexão",
      };
    }

    if (msg.includes("fetch") || msg.includes("ENOTFOUND") || msg.includes("DNS")) {
      return {
        sucesso: false, validado: false,
        mensagem: "Não foi possível conectar à Focus NFe no momento (DNS/rede).",
        ambiente: logData.ambiente || "desconhecido", status_http: 0,
        erro_detalhado: msg.slice(0, 200),
      };
    }

    if (msg.includes("certificate") || msg.includes("SSL") || msg.includes("TLS")) {
      return {
        sucesso: false, validado: false,
        mensagem: "Erro de SSL/TLS ao conectar na Focus NFe. Verifique a rede.",
        ambiente: logData.ambiente || "desconhecido", status_http: 0,
        erro_detalhado: "Erro de certificado SSL",
      };
    }

    return {
      sucesso: false, validado: false,
      mensagem: "Não foi possível conectar à Focus NFe no momento.",
      ambiente: logData.ambiente || "desconhecido", status_http: 0,
      erro_detalhado: msg.slice(0, 300),
    };
  }
});

// ─── Campos públicos a propagar para store_fiscal_settings ───
// (em sincronia com fiscal_integration_sync.js)
const CAMPOS_INTEGRACAO_PUBLICOS = [
  "provider",
  "provider_name",
  "environment",
  "base_url_sandbox",
  "base_url_production",
  "supported_documents",
  "status",
];

/**
 * Sincroniza os dados públicos de uma integração fiscal para TODAS as
 * lojas vinculadas em store_fiscal_settings.
 *
 * Pode ser chamado:
 * - Por fiscalSalvarIntegracao (após criar/atualizar uma integração)
 * - Por fiscalVincularIntegracaoLoja (após vincular uma loja)
 * - Por fiscalRepararVinculoIntegracao (rotina de reparo)
 *
 * SEGURANÇA: Apenas campos públicos da whitelist são propagados.
 * credentials_encrypted NUNCA é copiado.
 */
async function _sincronizarLojasVinculadas(db, integrationId, integrationData) {
  const settingsSnap = await db
    .collection("store_fiscal_settings")
    .where("integration_id", "==", integrationId)
    .get();

  if (settingsSnap.empty) {
    console.log(
      `[_sincronizarLojasVinculadas] Nenhum store_fiscal_settings referencia integration_id=${integrationId}`
    );
    return;
  }

  console.log(
    `[_sincronizarLojasVinculadas] Sincronizando ${settingsSnap.size} store(s) p/ integration_id=${integrationId}`
  );

  const batch = db.batch();
  for (const doc of settingsSnap.docs) {
    batch.update(doc.ref, {
      integration_data: integrationData,
      integration_removida_em: admin.firestore.FieldValue.delete(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log(
    `[_sincronizarLojasVinculadas] Sincronização concluída para ${settingsSnap.size} store(s).`
  );
}

/**
 * Extrai dos dados da integração apenas os campos públicos
 * que podem ser propagados para store_fiscal_settings.integration_data.
 */
function extrairDadosPublicosIntegracao(data) {
  if (!data) return null;
  const result = {};
  for (const campo of CAMPOS_INTEGRACAO_PUBLICOS) {
    if (data[campo] !== undefined) result[campo] = data[campo];
  }
  return Object.keys(result).length > 0 ? result : null;
}

// ═══════════════════════════════════════════════════════════════════════
// Callable: fiscalSalvarIntegracao — Cria/Atualiza integração fiscal
// com criptografia INDEPENDENTE dos tokens de sandbox e produção.
//
// SEGURANÇA:
//   - Os tokens NUNCA são salvos em texto puro no Firestore.
//   - A criptografia ocorre EXCLUSIVAMENTE no backend com FISCAL_MASTER_KEY.
//   - Cada ambiente tem seu próprio campo criptografado:
//       credentials_sandbox    → token de homologação
//       credentials_production → token de produção
//   - Alterar um ambiente NÃO afeta o token do outro.
//   - O campo api_key é sempre esvaziado (segurança).
//
// Edição:
//   - Se sandbox_token vier vazio/ausente → preserva credentials_sandbox existente
//   - Se production_token vier vazio/ausente → preserva credentials_production existente
//   - Assim, o admin pode alterar apenas um ambiente sem perder o outro.
//
// Leitura (emissão):
//   - obterApiKey() lê do campo correto baseado em environment do documento.
// ═══════════════════════════════════════════════════════════════════════
exports.fiscalSalvarIntegracao = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const {
    integration_id,      // Opcional: se presente, atualiza existente
    provider,
    provider_name,
    environment,         // sandbox | production (ambiente ativo da integração)
    sandbox_token,       // Token de homologação (opcional na edição)
    production_token,    // Token de produção (opcional na edição)
    nome_integracao,
    status,
    supported_documents,
    base_url_sandbox,
    base_url_production,
  } = request.data || {};

  if (!provider) {
    throw new HttpsError("invalid-argument", "provider é obrigatório.");
  }

  // Normaliza o ambiente: só aceita valores canônicos; qualquer outro vira null
  // (null = não altera na edição / usa default "sandbox" na criação).
  const environmentNormalizado =
    environment === "production" || environment === "sandbox"
      ? environment
      : null;

  // Validação de permissão: apenas staff pode salvar integrações
  const db = admin.firestore();
  const userSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("permission-denied", "Usuário não encontrado.");
  }
  const userData = userSnap.data();
  const role = (userData.role || userData.tipo || "").toLowerCase().trim();
  const isStaff = role === "master" || role === "master_city" || role === "superadmin";
  if (!isStaff) {
    throw new HttpsError(
      "permission-denied",
      "Apenas administradores podem gerenciar integrações fiscais."
    );
  }

  const masterKey = obterChaveMestra();

  // ─── Criptografa tokens fornecidos ───────────────
  // Se o token veio vazio ou ausente, deixa como null para
  // preservar o valor existente (apenas na edição).

  let encryptedSandbox = null;
  if (sandbox_token && typeof sandbox_token === "string" && sandbox_token.trim().length > 0) {
    try {
      encryptedSandbox = encryptAesGcm(sandbox_token.trim(), masterKey);
    } catch (err) {
      console.error("[fiscalSalvarIntegracao] Erro ao criptografar token sandbox:", err.message);
      throw new HttpsError("internal", "Erro ao proteger credenciais de homologação.");
    }
    if (!encryptedSandbox) {
      throw new HttpsError("internal", "Falha ao criptografar token de homologação.");
    }
  }

  let encryptedProduction = null;
  if (production_token && typeof production_token === "string" && production_token.trim().length > 0) {
    try {
      encryptedProduction = encryptAesGcm(production_token.trim(), masterKey);
    } catch (err) {
      console.error("[fiscalSalvarIntegracao] Erro ao criptografar token production:", err.message);
      throw new HttpsError("internal", "Erro ao proteger credenciais de produção.");
    }
    if (!encryptedProduction) {
      throw new HttpsError("internal", "Falha ao criptografar token de produção.");
    }
  }

  // Valida: pelo menos um token foi fornecido ou é edição com token existente
  if (!encryptedSandbox && !encryptedProduction && !integration_id) {
    throw new HttpsError(
      "invalid-argument",
      "Informe ao menos o token de homologação para criar a integração."
    );
  }

  // ─── Monta os updates ────────────────────────────
  // Só altera o que foi fornecido. Preserva o que veio vazio.
  const docData = {
    provider,
    provider_name: provider_name || provider,
    api_key: "", // Sempre esvaziado por segurança
    nome_integracao: nome_integracao || null,
    status: status || "active",
    supported_documents: supported_documents || ["nfe"],
    base_url_sandbox: base_url_sandbox || "",
    base_url_production: base_url_production || "",
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Só inclui campos criptografados se foram fornecidos (preserva na edição)
  if (encryptedSandbox !== null) {
    docData.credentials_sandbox = encryptedSandbox;
  }
  if (encryptedProduction !== null) {
    docData.credentials_production = encryptedProduction;
  }

  // Ambiente ativo (sandbox|production). Usado por fiscalTestarConexaoFocus,
  // obterApiKey e resolverBaseUrl. Na edição, só sobrescreve se fornecido
  // (preserva o valor atual); na criação, default "sandbox".
  if (environmentNormalizado !== null) {
    docData.environment = environmentNormalizado;
  } else if (!integration_id) {
    docData.environment = "sandbox";
  }

  // ─── Cria ou atualiza ────────────────────────────
  let docRef;
  if (integration_id) {
    docRef = db.collection("fiscal_integrations").doc(integration_id);
    const existente = await docRef.get();
    if (!existente.exists) {
      throw new HttpsError("not-found", "Integração não encontrada.");
    }

    // Tokens sandbox e production coexistem no mesmo documento; o campo
    // environment define qual está ativo. Se o frontend enviar environment,
    // ele é atualizado; senão, o valor atual é preservado (não incluído em docData).
    await docRef.update(docData);

    console.log(
      `[fiscalSalvarIntegracao] Integração ${integration_id} atualizada: ` +
      `provider=${provider}, sandbox=${encryptedSandbox !== null ? "atualizado" : "preservado"}, ` +
      `production=${encryptedProduction !== null ? "atualizado" : "preservado"}`
    );
  } else {
    docData.created_at = admin.firestore.FieldValue.serverTimestamp();
    docRef = await db.collection("fiscal_integrations").add(docData);
    console.log(
      `[fiscalSalvarIntegracao] Integração ${docRef.id} criada: provider=${provider}, ` +
      `sandbox=${encryptedSandbox !== null ? "configurado" : "vazio"}, ` +
      `production=${encryptedProduction !== null ? "configurado" : "vazio"}`
    );
  }

  // Log sanitizado (sem tokens, sem chaves)
  console.log(
    `[fiscalSalvarIntegracao] OK: integration_id=${docRef.id || integration_id}, ` +
    `provider=${provider}`
  );

  // ─── Sincroniza lojas vinculadas (imediato, não depende só do trigger) ───
  // O trigger onFiscalIntegrationWrite também propaga, mas esta chamada
  // garante que lojas vinculadas ANTES ou DEPOIS da criação/atualização
  // recebam os dados públicos imediatamente.
  try {
    const integrationDocSnap = await docRef.get();
    const integrationDocData = integrationDocSnap.data();
    const dadosPublicos = extrairDadosPublicosIntegracao(integrationDocData);
    if (dadosPublicos) {
      await _sincronizarLojasVinculadas(db, docRef.id || integration_id, dadosPublicos);
    }
  } catch (syncErr) {
    console.error(
      `[fiscalSalvarIntegracao] Erro ao sincronizar lojas vinculadas:`,
      syncErr.message
    );
    // Não quebra a operação principal — o trigger fará a sync em até 120s
  }

  return {
    integration_id: docRef.id || integration_id,
    sucesso: true,
  };
});

// ═══════════════════════════════════════════════════════════════════════
// Callable: fiscalVincularIntegracaoLoja — Vincula loja a integração
//
// SEGURANÇA:
//   - Apenas staff (master/superadmin/master_city) pode vincular
//   - Valida que fiscal_integrations/{integrationId} existe e está active
//   - Preenche integration_data com whitelist pública (sem tokens/credenciais)
//   - Remove integration_removida_em com FieldValue.delete()
//   - Preserva company_tax_data, certificado, flags e configurações fiscais
//
// NUNCA lê credentials_encrypted nem propaga para store_fiscal_settings.
// ═══════════════════════════════════════════════════════════════════════
exports.fiscalVincularIntegracaoLoja = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { storeId, integrationId } = request.data || {};
  if (!storeId || !integrationId) {
    throw new HttpsError(
      "invalid-argument",
      "storeId e integrationId são obrigatórios."
    );
  }

  const db = admin.firestore();

  // ─── Valida permissão: apenas staff ───
  const userSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("permission-denied", "Usuário não encontrado.");
  }
  const userData = userSnap.data();
  const role = (userData.role || userData.tipo || "").toLowerCase().trim();
  const isStaff = role === "master" || role === "master_city" || role === "superadmin";
  if (!isStaff) {
    throw new HttpsError(
      "permission-denied",
      "Apenas administradores podem vincular lojas a integrações fiscais."
    );
  }

  // ─── Valida que a integração existe e está ativa ───
  const integrationRef = db.collection("fiscal_integrations").doc(integrationId);
  const integrationSnap = await integrationRef.get();
  if (!integrationSnap.exists) {
    throw new HttpsError("not-found", "Integração fiscal não encontrada.");
  }

  const integrationData = integrationSnap.data();
  const integracaoStatus = (integrationData.status || "").toLowerCase().trim();
  if (integracaoStatus !== "active") {
    throw new HttpsError(
      "failed-precondition",
      `Integração não está ativa (status="${integracaoStatus}"). Ative a integração antes de vincular lojas.`
    );
  }

  // ─── Busca store_fiscal_settings pelo store_id ───
  const settingsQuery = await db
    .collection("store_fiscal_settings")
    .where("store_id", "==", storeId)
    .limit(1)
    .get();

  const dadosPublicos = extrairDadosPublicosIntegracao(integrationData);

  if (settingsQuery.empty) {
    // Cria novo documento
    await db.collection("store_fiscal_settings").add({
      store_id: storeId,
      integration_id: integrationId,
      integration_data: dadosPublicos,
      enable_nfe: true,
      enable_nfce: false,
      enable_nfse: false,
      status: "active",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(
      `[fiscalVincularIntegracaoLoja] Settings CRIADO para storeId=${storeId}, ` +
      `integrationId=${integrationId}`
    );
  } else {
    // Atualiza documento existente — preserva company_tax_data, certificado, flags
    const settingsDoc = settingsQuery.docs[0];
    const updates = {
      integration_id: integrationId,
      integration_data: dadosPublicos,
      integration_removida_em: admin.firestore.FieldValue.delete(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };

    await settingsDoc.ref.update(updates);
    console.log(
      `[fiscalVincularIntegracaoLoja] Settings ATUALIZADO para storeId=${storeId}, ` +
      `integrationId=${integrationId}, integration_removida_em removido`
    );
  }

  return {
    sucesso: true,
    store_id: storeId,
    integration_id: integrationId,
  };
});

// ═══════════════════════════════════════════════════════════════════════
// Callable: fiscalRepararVinculoIntegracao — Repara vínculo de loja específica
//
// Útil para corrigir documentos store_fiscal_settings que ficaram com
// integration_removida_em preenchido e/ou integration_data = null/ausente
// mesmo estando vinculadas a uma integração existente e ativa.
//
// Idempotente: pode ser executado múltiplas vezes sem efeitos colaterais.
// ═══════════════════════════════════════════════════════════════════════
exports.fiscalRepararVinculoIntegracao = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { storeId, integrationId, settingsDocId } = request.data || {};
  if (!storeId) {
    throw new HttpsError("invalid-argument", "storeId é obrigatório.");
  }

  const db = admin.firestore();

  // ─── Valida permissão: apenas staff ───
  const userSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("permission-denied", "Usuário não encontrado.");
  }
  const userData = userSnap.data();
  const role = (userData.role || userData.tipo || "").toLowerCase().trim();
  const isStaff = role === "master" || role === "master_city" || role === "superadmin";
  if (!isStaff) {
    throw new HttpsError(
      "permission-denied",
      "Apenas administradores podem reparar vínculos fiscais."
    );
  }

  // ─── Busca store_fiscal_settings ───
  let settingsDoc;
  if (settingsDocId) {
    const ref = db.collection("store_fiscal_settings").doc(settingsDocId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", `store_fiscal_settings/${settingsDocId} não encontrado.`);
    }
    settingsDoc = { ref, data: snap.data(), id: settingsDocId };
  } else {
    const query = await db
      .collection("store_fiscal_settings")
      .where("store_id", "==", storeId)
      .limit(1)
      .get();
    if (query.empty) {
      throw new HttpsError("not-found", `Nenhum store_fiscal_settings encontrado para storeId=${storeId}.`);
    }
    settingsDoc = { ref: query.docs[0].ref, data: query.docs[0].data(), id: query.docs[0].id };
  }

  const currentData = settingsDoc.data;
  const currentIntegrationId = integrationId || currentData.integration_id || "";
  if (!currentIntegrationId) {
    throw new HttpsError(
      "failed-precondition",
      "store_fiscal_settings não tem integration_id. Use fiscalVincularIntegracaoLoja primeiro."
    );
  }

  // ─── Valida integration_data atual ───
  const hasIntegrationData = currentData.integration_data != null &&
    typeof currentData.integration_data === "object" &&
    Object.keys(currentData.integration_data).length > 0;
  const hasRemovidaEm = currentData.integration_removida_em != null;

  const diagnostic = {
    settings_id: settingsDoc.id,
    store_id: storeId,
    integration_id: currentIntegrationId,
    integration_data_presente: !!currentData.integration_data,
    integration_data_tem_chaves: hasIntegrationData,
    integration_removida_em_presente: hasRemovidaEm,
    integration_removida_em_valor: currentData.integration_removida_em
      ? String(currentData.integration_removida_em)
      : null,
  };
  console.log("[fiscalRepararVinculoIntegracao] Diagnóstico:", JSON.stringify(diagnostic));

  // ─── Busca dados atuais da integração ───
  const integrationRef = db.collection("fiscal_integrations").doc(currentIntegrationId);
  const integrationSnap = await integrationRef.get();
  if (!integrationSnap.exists) {
    throw new HttpsError("not-found",
      `fiscal_integrations/${currentIntegrationId} não encontrado. Crie a integração primeiro.`);
  }

  const integrationRawData = integrationSnap.data();
  const dadosPublicos = extrairDadosPublicosIntegracao(integrationRawData);

  // ─── Monta updates ───
  const updates = {
    integration_id: currentIntegrationId,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  // integration_data: sempre repopula com dados frescos da integração
  if (dadosPublicos) {
    updates.integration_data = dadosPublicos;
  }

  // integration_removida_em: sempre remove
  updates.integration_removida_em = admin.firestore.FieldValue.delete();

  await settingsDoc.ref.update(updates);
  console.log(
    `[fiscalRepararVinculoIntegracao] Reparo concluído para settings_id=${settingsDoc.id}, ` +
    `storeId=${storeId}, integrationId=${currentIntegrationId}, ` +
    `integration_data=${dadosPublicos ? "preenchido" : "nulo"}, ` +
    `integration_removida_em=removido`
  );

  return {
    sucesso: true,
    diagnostico: diagnostic,
    reparo_executado: true,
    integration_data_preenchido: dadosPublicos != null,
    integration_removida_em_removido: true,
  };
});
