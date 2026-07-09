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
const admin = require("firebase-admin");

const crypto = require("crypto");
const securityGuard = require("./fiscal_security_guard");
const payloadValidator = require("./fiscal_payload_validator");
const logger = require("./fiscal_logger");

// ═══════════════════════════════════════════════════════════════════════
// Configuração das funções
// ═══════════════════════════════════════════════════════════════════════

const CONFIG = {
  region: "southamerica-east1",
  cpu: 1,
  memory: "512MiB",
  maxInstances: 10,
  timeoutSeconds: 90,
  enforceAppCheck: false,
};

// ═══════════════════════════════════════════════════════════════════════
// Helpers de criptografia (compatível com FiscalCryptoUtil Dart)
// ═══════════════════════════════════════════════════════════════════════

const CRYPTO_PREFIX = "DIP_AES256_v2:";
const CRYPTO_PREFIX_LEGACY = "DIP_ENC_v1:";
const APP_KEY = "DiPertin@2026!Fiscal#NF-e";

/** Deriva chave de 32 bytes via SHA-256 (compatível com Dart). */
function derivarChave256(seed) {
  return crypto.createHash("sha256").update(seed, "utf8").digest();
}

/** Descriptografa credentials no formato AES-256-GCM (DIP_AES256_v2). */
function decryptAesGcm(encrypted) {
  const payload = encrypted.slice(CRYPTO_PREFIX.length);
  const [ivB64, dataB64] = payload.split(".");
  if (!ivB64 || !dataB64) return null;

  const iv = Buffer.from(ivB64, "base64url");
  const full = Buffer.from(dataB64, "base64url");
  const key = derivarChave256(APP_KEY);

  const tag = full.subarray(-16);
  const ciphertext = full.subarray(0, -16);

  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);
  return decipher.update(ciphertext) + decipher.final("utf8");
}

/** Descriptografa credentials no formato legado (XOR v1). */
function decryptLegacy(encrypted) {
  const encoded = encrypted.slice(CRYPTO_PREFIX_LEGACY.length);
  const buf = Buffer.from(encoded, "base64url");
  const key = derivarChave256(APP_KEY);
  const decrypted = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) {
    decrypted[i] = buf[i] ^ key[i % key.length];
  }
  return decrypted.toString("utf8");
}

/**
 * Obtém a API Key decriptografada a partir do doc fiscal_integrations.
 * Retorna null se não encontrar.
 */
async function obterApiKey(integrationId) {
  if (!integrationId) return null;
  const db = admin.firestore();
  const snap = await db.collection("fiscal_integrations").doc(integrationId).get();
  if (!snap.exists) return null;

  const data = snap.data();
  let apiKey = data.credentials_encrypted || data.api_key || "";

  if (!apiKey) return null;

  if (apiKey.startsWith(CRYPTO_PREFIX)) {
    const decrypted = decryptAesGcm(apiKey);
    if (decrypted) apiKey = decrypted;
  } else if (apiKey.startsWith(CRYPTO_PREFIX_LEGACY)) {
    apiKey = decryptLegacy(apiKey);
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

  if (json.erro || json.error || (status === "rejeitada" && json.motivo)) {
    return resultado(false, {
      chave_acesso: chave,
      protocolo,
      numero,
      serie,
      status: "rejeitada",
      mensagem: json.motivo || json.error || json.erro || "NF-e rejeitada pela SEFAZ.",
      erro: json.motivo || json.error || json.erro || "Rejeitada",
      provider_response: body,
      codigo_rejeicao: json.codigo ? String(json.codigo) : null,
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

  try {
    const db = admin.firestore();
    const batch = db.batch();

    // ═══ 1. VALIDAÇÃO DE SEGURANÇA (vínculo loja × usuário) ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      action: "emitir",
    });

    // ═══ 2. VALIDAÇÃO DA INTEGRAÇÃO DO LOJISTA (lojista_integracao) ═══
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

    // ═══ 3. VALIDAÇÃO DE CERTIFICADO DIGITAL ═══
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

      // Verifica se o certificado está expirado
      if (certData.validade_fim) {
        const validadeFim = certData.validade_fim.toDate ? certData.validade_fim.toDate() : new Date(certData.validade_fim);
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

      // Verifica se o CNPJ do certificado corresponde ao CNPJ da loja
      const cnpjCert = (certData.cnpj || "").replace(/\D/g, "");
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
      console.log(`[fiscalEmitirNFe] Nenhum certificate_id informado — continuando sem validação de certificado.`);
    }

    // ═══ 4. VALIDAÇÃO DE PAYLOAD (dados obrigatórios) ═══
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

    // ═══ 5. BUSCAR INTEGRAÇÃO ADMIN E API KEY ═══
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
      throw new HttpsError("failed-precondition",
        "API Key da Focus NFe não configurada. Configure a integração admin primeiro.");
    }

    const environment = lojistaData.environment || integData.environment || "sandbox";
    const baseUrl = resolverBaseUrl(integData, environment);
    // Focus NFe v2: ref vai na URL como query param
    // O payload (flat) contém cnpj_emitente no corpo
    const ref = data.ref || gerarRef(store_id);
    const url = `${baseUrl}/nfe?ref=${ref}`;
    // ref NÃO vai no body (já está na URL)

    // ═══ LOG DO PAYLOAD (amostra segura) ═══
    const payloadPreview = JSON.stringify(nfe_payload).substring(0, 500);
    console.log(`[fiscalEmitirNFe] Payload (início): ${payloadPreview}`);

    // ═══ LOG TÉCNICO (sem expor token) ═══
    console.log(
      `[fiscalEmitirNFe] provider=focus_nfe | storeId=${store_id} | integrationId=${integration_id} | ` +
      `lojistaIntegrationId=${lojista_integration_id} | ambiente=${environment} | ` +
      `endpoint=${baseUrl}/nfe/*** | credencialAdmin=${apiKey ? "encontrada" : "ausente"} | ` +
      `certificado=${certificate_id ? "encontrado" : "ausente"}`
    );

    // ═══ 6. CHAMADA FOCUS NFe ═══
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
        body: JSON.stringify(nfe_payload),
      });
      body = await response.text();
    } catch (fetchError) {
      console.error("[fiscalEmitirNFe] Erro de rede ao chamar Focus NFe:", fetchError.message);
      const erroMsg = fetchError.message || "Erro de conexão com a Focus NFe";
      const isTimeout = /timeout|timed.?out/i.test(erroMsg);
      await logger.registrarLog({
        storeId: store_id, acao: "emitir_erro_rede", status: "erro",
        usuarioUid: userId, mensagem: `Erro de rede: ${erroMsg.slice(0, 300)}`,
        integrationId: integration_id,
      });
      return resultado(false, {
        status: "erro_comunicacao",
        mensagem: isTimeout
          ? "Tempo limite excedido ao comunicar com a Focus NFe. Tente novamente."
          : "Erro de conexão com a Focus NFe. Verifique sua internet e tente novamente.",
        erro: erroMsg,
        technicalMessage: `Falha na requisição HTTP para Focus NFe: ${erroMsg}`,
        focusStatusCode: 0,
        validationErrors: [`Erro de ${isTimeout ? "timeout" : "conexão"} com o servidor Focus NFe.`],
      });
    }

    let json;
    try {
      json = JSON.parse(body);
    } catch (_) {
      json = { erro: "Resposta inválida da Focus NFe", body: body };
    }

    // ═══ 7. TRATAR ERROS HTTP DA FOCUS NFe ═══
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
          mensagemAmigavel = "Conflito: já existe uma NF-e com esta referência. Tente novamente.";
          validationErrors.push("Código 409: Conflito de referência. Já existe uma nota com esta ref.");
          break;
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

    // ═══ 8. RESPOSTA DE SUCESSO / PROCESSAMENTO ═══
    const res = parseFocusNFeResponse(json, body, "emitir");
    res.ref = ref;

    // ═══ 9. SALVAR DOCUMENTO NO FIRESTORE ═══
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
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      issued_at: res.status === "autorizada"
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
    });

    await batch.commit();

    // ═══ 10. LOG ═══
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
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalEmitirNFe] Erro não tratado:", e.message, e.stack ? e.stack.slice(0, 300) : "");

    const erroMsg = e.message || "Erro interno no servidor";
    await logger.registrarLog({
      storeId: store_id || "unknown",
      acao: "emitir_erro_interno",
      status: "erro",
      usuarioUid: userId || "unknown",
      mensagem: `Erro interno: ${erroMsg.slice(0, 300)}`,
      erro: erroMsg,
      integrationId: integration_id || null,
    });

    return resultado(false, {
      status: "erro",
      mensagem: "Erro interno ao emitir NF-e. Tente novamente ou contate o suporte.",
      erro: erroMsg,
      technicalMessage: `Exceção não tratada: ${erroMsg}`,
      focusStatusCode: 0,
      validationErrors: [`Erro interno: ${erroMsg}`],
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
        cancelled_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      chaveAcesso: chave_acesso,
      action: "carta_correcao",
    });

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
    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      action: "inutilizar",
    });

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

  const { store_id, numero_nfe, serie } = request.data || {};
  const userId = request.auth.uid;

  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!numero_nfe) throw new HttpsError("invalid-argument", "numero_nfe é obrigatório.");

  try {
    const db = admin.firestore();

    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      action: "deletar_documento",
    });

    // Busca o documento
    const docsRef = db.collection("fiscal_documents");
    const q = serie
      ? docsRef.where("number", "==", numero_nfe)
          .where("store_id", "==", store_id)
          .where("series", "==", serie)
          .limit(1)
      : docsRef.where("number", "==", numero_nfe)
          .where("store_id", "==", store_id)
          .limit(1);

    const snap = await q.get();
    if (snap.empty) {
      throw new HttpsError("not-found",
        "Documento fiscal não encontrado. Pode já ter sido deletado.");
    }

    const docSnap = snap.docs[0];
    const docId = docSnap.id;

    await docsRef.doc(docId).delete();

    await logger.registrarLog({
      storeId: store_id,
      acao: "deletar_documento",
      status: "sucesso",
      usuarioUid: userId,
      documentoId: docId,
      mensagem: `Documento fiscal Nº ${numero_nfe} deletado.`,
    });

    return resultado(true, {
      mensagem: `Documento Nº ${numero_nfe} deletado permanentemente.`,
      status: "deletado",
      documento_id: docId,
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

  const { integration_id } = request.data || {};
  if (!integration_id) {
    throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
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
