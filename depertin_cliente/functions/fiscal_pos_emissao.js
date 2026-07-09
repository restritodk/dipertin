/**
 * Fiscal Pós-Emissão — Consulta automática, Storage e processamento
 *
 * Após emitir uma nota na Focus NFe:
 * 1. Salva status inicial como "processando"
 * 2. Consulta a Focus NFe em intervalos (5s, 15s, 30s — máx 3 tentativas)
 * 3. Quando autorizada: captura URLs de XML/DANFE, salva no Storage
 * 4. Registra em fiscal_status_history e fiscal_logs
 * 5. Se rejeitada: salva motivo da rejeição
 *
 * Para consulta automática, o frontend chama fiscalConsultarEAtualizarStatus
 * com retry progressivo (não usa loop infinito no backend).
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const securityGuard = require("./fiscal_security_guard");
const logger = require("./fiscal_logger");

const CONFIG = {
  region: "southamerica-east1",
  cpu: 1,
  memory: "512MiB",
  maxInstances: 10,
  timeoutSeconds: 120,
  enforceAppCheck: false,
};

// ═══════════════════════════════════════════════════════════════════════
// Helpers de criptografia (reutilizados de fiscal_nfe_proxy)
// ═══════════════════════════════════════════════════════════════════════

const CRYPTO_PREFIX = "DIP_AES256_v2:";
const CRYPTO_PREFIX_LEGACY = "DIP_ENC_v1:";
const APP_KEY = "DiPertin@2026!Fiscal#NF-e";

function derivarChave256(seed) {
  return crypto.createHash("sha256").update(seed, "utf8").digest();
}

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

function resolverBaseUrl(integrationData, environment) {
  const rawEnv = environment || integrationData.environment || "sandbox";
  const env = rawEnv === "production" ? "producao" : rawEnv;
  const sandboxUrl = integrationData.base_url_sandbox;
  const prodUrl = integrationData.base_url_production;
  if (env === "producao" && prodUrl) return prodUrl;
  if (env !== "producao" && sandboxUrl) return sandboxUrl;
  return env === "producao"
    ? "https://api.focusnfe.com.br/v2"
    : "https://homologacao.focusnfe.com.br/v2";
}

function montarBasicAuth(apiKey) {
  const credentials = `${apiKey}:`;
  const encoded = Buffer.from(credentials, "utf8").toString("base64");
  return `Basic ${encoded}`;
}

/**
 * Parseia resposta da Focus NFe para extrair URLs e dados.
 */
function parseFocusResponse(json) {
  const status = json.status || "";
  const chave = json.chave_nfe || json.chave || null;
  const protocolo = json.protocolo_autorizacao || json.protocolo || null;
  const numero = (json.numero || json.numero_nfe || "").toString();
  const serie = (json.serie || "").toString();
  const xmlUrl = json.xml || null;
  const danfeUrl = json.danfe || json.danfe_url || null;
  const erro = json.erro || json.error || json.motivo || null;

  return { status, chave, protocolo, numero, serie, xmlUrl, danfeUrl, erro };
}

/**
 * Salva um arquivo (XML ou PDF) da Focus NFe para o Firebase Storage.
 * Se o download falhar, retorna a URL original como fallback.
 */
async function salvarNoStorage(url, caminhoDestino, storeId, documentoId) {
  if (!url) return null;

  try {
    const response = await fetch(url, { method: "GET" });
    if (!response.ok) {
      console.warn(`[salvarNoStorage] Download falhou HTTP ${response.status}: ${url}`);
      return url; // fallback: retorna URL original
    }

    const buffer = await response.arrayBuffer();
    const bucket = admin.storage().bucket();

    const file = bucket.file(caminhoDestino);
    await file.save(Buffer.from(buffer), {
      contentType: response.headers.get("content-type") || "application/octet-stream",
      metadata: {
        store_id: storeId,
        documento_id: documentoId,
        criado_em: new Date().toISOString(),
      },
    });

    // Torna público
    await file.makePublic();

    const publicUrl = `https://storage.googleapis.com/${bucket.name}/${caminhoDestino}`;
    console.log(`[salvarNoStorage] Salvo em: ${publicUrl}`);
    return publicUrl;
  } catch (e) {
    console.error(`[salvarNoStorage] Erro ao salvar: ${e.message}`);
    return url; // fallback
  }
}

// ═══════════════════════════════════════════════════════════════════════
// fiscalConsultarEAtualizarStatus — Consulta Focus NFe e atualiza Firestore
// ═══════════════════════════════════════════════════════════════════════

/**
 * Consulta o status de uma nota na Focus NFe e atualiza o documento no Firestore.
 *
 * @param {string} integration_id - ID da integração Fiscal
 * @param {string} store_id - ID da loja
 * @param {string} chave_acesso - Chave de 44 dígitos da nota
 * @param {string} documento_id - ID do documento no Firestore
 */
exports.fiscalConsultarEAtualizarStatus = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { integration_id, store_id, chave_acesso, documento_id } = request.data || {};
  const userId = request.auth.uid;

  if (!integration_id) throw new HttpsError("invalid-argument", "integration_id é obrigatório.");
  if (!store_id) throw new HttpsError("invalid-argument", "store_id é obrigatório.");
  if (!chave_acesso) throw new HttpsError("invalid-argument", "chave_acesso é obrigatória.");
  if (!documento_id) throw new HttpsError("invalid-argument", "documento_id é obrigatório.");

  try {
    const db = admin.firestore();

    // ═══ SEGURANÇA ═══
    await securityGuard.validateStoreAccess({
      userId,
      storeId: store_id,
      docId: documento_id,
      action: "consultar_status",
    });

    // ═══ Buscar documento atual ═══
    const docSnap = await db.collection("fiscal_documents").doc(documento_id).get();
    if (!docSnap.exists) {
      throw new HttpsError("not-found", "Documento fiscal não encontrado.");
    }
    const docData = docSnap.data();
    const statusAtual = docData.status || "";

    // Se já está em estado final, não consulta novamente
    if (["autorizada", "rejeitada", "cancelada", "cancelamento_homologado", "erro"].includes(statusAtual)) {
      return {
        sucesso: true,
        status: statusAtual,
        mensagem: `Nota já está em estado final: ${statusAtual}.`,
        jaFinal: true,
        documento_id,
        chave_acesso,
      };
    }

    // ═══ Buscar API Key ═══
    const integSnap = await db.collection("fiscal_integrations").doc(integration_id).get();
    if (!integSnap.exists) {
      throw new HttpsError("not-found", "Integração fiscal não encontrada.");
    }
    const integData = integSnap.data();
    const apiKey = await obterApiKey(integration_id);
    if (!apiKey) {
      throw new HttpsError("failed-precondition", "API Key não configurada.");
    }

    // ═══ Consultar Focus NFe ═══
    const baseUrl = resolverBaseUrl(integData, integData.environment);
    const url = `${baseUrl}/nfe/${chave_acesso}`;

    console.log(`[fiscalConsultarEAtualizarStatus] Consultando: ${url.replace(chave_acesso, "***")}`);

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

    if (!response.ok) {
      const erroMsg = json.error || json.erro || `HTTP ${response.status}`;

      await logger.registrarLog({
        storeId: store_id,
        acao: "consultar_status_erro",
        status: "erro",
        usuarioUid: userId,
        documentoId: documento_id,
        chaveAcesso: chave_acesso,
        mensagem: `Erro na consulta Focus NFe: ${erroMsg}`,
        integrationId: integration_id,
      });

      return {
        sucesso: false,
        status: "erro_consulta",
        mensagem: `Erro ao consultar Focus NFe: ${erroMsg}`,
        documento_id,
        chave_acesso,
        status_anterior: statusAtual,
      };
    }

    // ═══ Parsear resposta ═══
    const dados = parseFocusResponse(json);
    const statusNovo = mapearStatusFinal(dados.status);

    console.log(`[fiscalConsultarEAtualizarStatus] Status: ${statusAtual} → ${statusNovo}`);

    if (statusNovo === statusAtual) {
      // Status não mudou
      return {
        sucesso: true,
        status: statusNovo,
        mensagem: `Status permanece: ${statusNovo}.`,
        documento_id,
        chave_acesso,
        status_anterior: statusAtual,
      };
    }

    // ═══ Status mudou: atualizar Firestore ═══
    const updateData = {
      status: statusNovo,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (dados.chave) updateData.access_key = dados.chave;
    if (dados.protocolo) updateData.protocol = dados.protocolo;
    if (dados.numero) updateData.number = dados.numero;
    if (dados.serie) updateData.series = dados.serie;

    const bucket = admin.storage().bucket();

    // Se autorizada: salvar XML e DANFE no Storage
    if (statusNovo === "autorizada") {
      updateData.issued_at = admin.firestore.FieldValue.serverTimestamp();

      // Salva XML no Storage
      if (dados.xmlUrl) {
        const xmlPath = `fiscal/${store_id}/${documento_id}/nfe-${dados.numero || documento_id}.xml`;
        const xmlStorageUrl = await salvarNoStorage(dados.xmlUrl, xmlPath, store_id, documento_id);
        updateData.xml_url = xmlStorageUrl || dados.xmlUrl;
      }

      // Salva DANFE/PDF no Storage
      if (dados.danfeUrl) {
        const danfePath = `fiscal/${store_id}/${documento_id}/danfe-${dados.numero || documento_id}.pdf`;
        const danfeStorageUrl = await salvarNoStorage(dados.danfeUrl, danfePath, store_id, documento_id);
        updateData.pdf_url = danfeStorageUrl || dados.danfeUrl;
      }
    }

    // Se rejeitada: salvar motivo
    if (statusNovo === "rejeitada") {
      updateData.rejection_reason = dados.erro || json.motivo || "Rejeitada pela SEFAZ";
      if (json.codigo) updateData.rejection_code = String(json.codigo);
    }

    // ═══ Atualizar documento ═══
    await db.collection("fiscal_documents").doc(documento_id).update(updateData);

    // ═══ Histórico de status ═══
    await logger.registrarStatusHistory({
      storeId: store_id,
      documentoId: documento_id,
      chaveAcesso: chave_acesso,
      statusAnterior: statusAtual,
      statusNovo,
      motivo: statusNovo === "rejeitada" ? (dados.erro || null) : `Atualizado via consulta`,
      usuarioUid: userId,
      origem: "consulta",
    });

    // ═══ Log ═══
    await logger.registrarLog({
      storeId: store_id,
      acao: "consultar_status",
      status: statusNovo === "autorizada" ? "sucesso" : statusNovo,
      usuarioUid: userId,
      documentoId: documento_id,
      chaveAcesso: chave_acesso,
      mensagem: `Status atualizado: ${statusAtual} → ${statusNovo}`,
      integrationId: integration_id,
    });

    return {
      sucesso: statusNovo !== "rejeitada" && statusNovo !== "erro",
      status: statusNovo,
      mensagem: statusNovo === "autorizada"
        ? "NF-e autorizada! XML e DANFE salvos."
        : statusNovo === "rejeitada"
          ? `NF-e rejeitada: ${dados.erro || json.motivo || "Rejeitada pela SEFAZ"}`
          : `Status atualizado para: ${statusNovo}.`,
      documento_id,
      chave_acesso,
      numero: dados.numero,
      protocolo: dados.protocolo,
      xml_url: updateData.xml_url,
      pdf_url: updateData.pdf_url,
      erro: dados.erro,
      status_anterior: statusAtual,
      storage_salvo: statusNovo === "autorizada",
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[fiscalConsultarEAtualizarStatus] Erro:", e.message);
    return {
      sucesso: false,
      status: "erro",
      mensagem: `Erro na consulta: ${e.message}`,
      documento_id: (request.data || {}).documento_id,
      chave_acesso: (request.data || {}).chave_acesso,
    };
  }
});

/**
 * Mapeia status da Focus NFe para o status interno do sistema.
 */
function mapearStatusFinal(statusProvedor) {
  const s = String(statusProvedor || "").toLowerCase().trim();

  if (["autorizado", "aprovado", "aprovada", "authorized", "approved",
       "autorizada", "concluido", "concluída", "completed", "processed",
       "processado", "emitido", "emitida", "issued", "success",
       "sucesso", "ok", "homologado"].includes(s)) {
    return "autorizada";
  }

  if (["processando", "processing", "pendente", "pending", "enviado",
       "sent", "fila", "queue", "na_fila"].includes(s)) {
    return "processando";
  }

  if (["rejeitado", "rejeitada", "rejected", "recusado", "recusada",
       "refused", "denied", "erro", "error", "falhou", "failed",
       "invalid", "invalido", "inválida"].includes(s)) {
    return "rejeitada";
  }

  if (["cancelado", "cancelada", "cancelled", "canceled", "cancelamento",
       "cancellation", "cancelado_homologado", "cancelamento_homologado"].includes(s)) {
    return "cancelada";
  }

  // Mantém original se não reconhecido
  return s;
}
