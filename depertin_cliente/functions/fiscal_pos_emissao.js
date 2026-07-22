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
 * Integração de Saldo:
 * - Esta função atualiza SALDO via saldoHelper.processarWebhookAutorizacao
 * - Webhook e polling usam o MESMO helper (idempotente)
 * - Cancelamento fiscal NÃO estorna saldo (regras existentes)
 *
 * Para consulta automática, o frontend chama fiscalConsultarEAtualizarStatus
 * com retry progressivo (não usa loop infinito no backend).
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");
const securityGuard = require("./fiscal_security_guard");
const logger = require("./fiscal_logger");
const saldoHelper = require("./fiscal_saldo_helper");

// ─── Secret Manager: FISCAL_MASTER_KEY ───
const fiscalMasterKey = defineSecret("FISCAL_MASTER_KEY");

const CONFIG = {
  region: "us-east1",
  cpu: 1,
  memory: "512MiB",
  maxInstances: 10,
  timeoutSeconds: 120,
  // TODO: voltar para `enforceAppCheck: process.env.FUNCTIONS_EMULATOR ? false : true`
  // após corrigir a Secret Key do reCAPTCHA v3 no Firebase Console → App Check →
  // depertin_web. Mantido false (igual às functions do Mercado Pago) pois a Secret
  // Key inválida faz o exchangeRecaptchaV3Token retornar 400 e bloqueia o staff.
  // Proteção preservada: Firebase Auth + verificação de papel staff dentro da função.
  enforceAppCheck: false,
  secrets: [fiscalMasterKey],
};

// ═══════════════════════════════════════════════════════════════════════
// Helpers de criptografia (compartilhados com fiscal_nfe_proxy.js)
// Usam FISCAL_MASTER_KEY via process.env (injetado pelo Secret Manager)
// ═══════════════════════════════════════════════════════════════════════

const CRYPTO_PREFIX = "DIP_AES256_v2:";
const CRYPTO_PREFIX_LEGACY = "DIP_ENC_v1:";

/**
 * Chave mestra — lê de process.env.FISCAL_MASTER_KEY (injetado via Secret Manager).
 * Se ausente ou inválida, lança erro (SEM fallback hardcoded).
 */
function resolverChaveMestra() {
  const rawKey = process.env.FISCAL_MASTER_KEY;
  if (!rawKey || typeof rawKey !== "string" || rawKey.length < 32) {
    throw new Error("Configuração criptográfica fiscal indisponível.");
  }
  return crypto.createHash("sha256").update(rawKey, "utf8").digest();
}

let _masterKeyCache = null;
function obterChaveMestra() {
  if (!_masterKeyCache) {
    _masterKeyCache = resolverChaveMestra();
  }
  return _masterKeyCache;
}

function derivarChave256(seed) {
  return crypto.createHash("sha256").update(seed, "utf8").digest();
}

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

function decryptLegacy(encrypted, masterKey) {
  const encoded = encrypted.slice(CRYPTO_PREFIX_LEGACY.length);
  const buf = Buffer.from(encoded, "base64url");
  if (!buf || buf.length === 0 || !masterKey) return null;
  const key = masterKey;
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

  const masterKey = obterChaveMestra();

  if (apiKey.startsWith(CRYPTO_PREFIX)) {
    const decrypted = decryptAesGcm(apiKey, masterKey);
    if (decrypted) apiKey = decrypted;
  } else if (apiKey.startsWith(CRYPTO_PREFIX_LEGACY)) {
    apiKey = decryptLegacy(apiKey, masterKey);
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
 *
 * SEGURANÇA: Arquivos fiscais são mantidos PRIVADOS.
 * Não usa makePublic() — apenas Admin SDK e Cloud Functions podem acessar.
 * O caminho do arquivo é salvo no Firestore para recuperação via Cloud Function.
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
        // NÃO torna público — arquivo permanece privado no Storage
      },
    });

    // NÃO usa makePublic() — arquivo permanece privado
    // Retorna o caminho interno (não URL pública)
    console.log(`[salvarNoStorage] Salvo (privado): ${caminhoDestino}`);
    return caminhoDestino; // Retorna caminho interno, não URL pública
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

      // Salva XML no Storage (mantido privado)
      if (dados.xmlUrl) {
        const xmlPath = `fiscal/${store_id}/${documento_id}/nfe-${dados.numero || documento_id}.xml`;
        const xmlStoragePath = await salvarNoStorage(dados.xmlUrl, xmlPath, store_id, documento_id);
        // Salva caminho interno (não URL pública)
        // Se falhar, salva null (não expõe URL da Focus)
        updateData.xml_url = xmlStoragePath && !xmlStoragePath.startsWith("http")
          ? xmlStoragePath
          : null;
      }

      // Salva DANFE/PDF no Storage (mantido privado)
      if (dados.danfeUrl) {
        const danfePath = `fiscal/${store_id}/${documento_id}/danfe-${dados.numero || documento_id}.pdf`;
        const danfeStoragePath = await salvarNoStorage(dados.danfeUrl, danfePath, store_id, documento_id);
        // Salva caminho interno (não URL pública)
        updateData.pdf_url = danfeStoragePath && !danfeStoragePath.startsWith("http")
          ? danfeStoragePath
          : null;
      }
    }

    // Se rejeitada: salvar motivo
    if (statusNovo === "rejeitada") {
      updateData.rejection_reason = dados.erro || json.motivo || "Rejeitada pela SEFAZ";
      if (json.codigo) updateData.rejection_code = String(json.codigo);
    }

    // ═══ Atualizar documento ═══
    await db.collection("fiscal_documents").doc(documento_id).update(updateData);

    // ═══════════════════════════════════════════════════════════════════════
    // ATUALIZAR SALDO VIA HELPER TRANSACIONAL
    // ═══════════════════════════════════════════════════════════════════════
    // Buscar provider_ref para atualizar saldo
    const providerRef = docData.ref || null;
    if (providerRef) {
      try {
        const saldoResultado = await saldoHelper.processarPolling(
          db,
          providerRef,
          statusNovo,
          documento_id,
          { status: dados.status, message: dados.erro || null }
        );
        console.log(`[fiscalConsultarEAtualizarStatus] Saldo processado: provider_ref=${providerRef}, resultado=${saldoResultado.status}`);
      } catch (saldoErr) {
        // Erro no saldo helper não deve falhar a consulta
        console.warn(`[fiscalConsultarEAtualizarStatus] Erro ao processar saldo: ${saldoErr.message}`);
      }
    }

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

// ═══════════════════════════════════════════════════════════════════════
// Download autenticado de arquivos fiscais
// ═══════════════════════════════════════════════════════════════════════

/**
 * Cloud Function para download de arquivos fiscais (XML, DANFE, eventos).
 *
 * FLUXO SEGURO:
 * 1. Recebe documento_id e tipo (xml/danfe/evento)
 * 2. Valida autenticação do usuário
 * 3. Verifica vínculo do usuário com a loja do documento
 * 4. Busca caminho do arquivo no Firestore
 * 5. Gera URL assinada com validade curta (5 minutos)
 * 6. Retorna URL temporária para download
 *
 * NÃO aceita caminho de arquivo diretamente do frontend.
 */
exports.fiscalDownloadArquivo = onCall(CONFIG, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Autenticação necessária.");
  }

  const { documento_id, tipo } = request.data || {};
  const userId = request.auth.uid;

  if (!documento_id) {
    throw new HttpsError("invalid-argument", "documento_id é obrigatório.");
  }

  // Tipos permitidos
  const tiposPermitidos = ["xml", "danfe", "evento", "carta_correcao", "cancelamento"];
  const tipoNormalizado = String(tipo || "xml").toLowerCase();

  if (!tiposPermitidos.includes(tipoNormalizado)) {
    throw new HttpsError("invalid-argument", `Tipo "${tipo}" não permitido. Use: ${tiposPermitidos.join(", ")}`);
  }

  try {
    const db = admin.firestore();

    // 1. Buscar documento fiscal
    const docSnap = await db.collection("fiscal_documents").doc(documento_id).get();
    if (!docSnap.exists) {
      throw new HttpsError("not-found", "Documento fiscal não encontrado.");
    }

    const docData = docSnap.data();
    const storeId = docData.store_id;

    // 2. Validar vínculo do usuário com a loja
    await securityGuard.validateStoreAccess({
      userId,
      storeId: storeId,
      action: "download",
    });

    // 3. Determinar caminho do arquivo
    let caminhoArquivo = null;

    switch (tipoNormalizado) {
      case "xml":
        caminhoArquivo = docData.xml_url;
        break;
      case "danfe":
        caminhoArquivo = docData.pdf_url;
        break;
      case "evento":
      case "carta_correcao":
      case "cancelamento":
        // Eventos são salvos com padrão: fiscal/{store_id}/{doc_id}/evento-{id}.json
        caminhoArquivo = docData.evento_url || docData.cc_url || docData.cancelamento_url;
        break;
    }

    if (!caminhoArquivo || caminhoArquivo.startsWith("http")) {
      throw new HttpsError("not-found", "Arquivo não encontrado para este documento.");
    }

    // 4. Gerar URL assinada com validade de 5 minutos
    const bucket = admin.storage().bucket();
    const file = bucket.file(caminhoArquivo);

    // Verifica se arquivo existe
    const [exists] = await file.exists();
    if (!exists) {
      throw new HttpsError("not-found", "Arquivo não encontrado no Storage.");
    }

    // Gera URL assinada (válida por 5 minutos)
    const [signedUrl] = await file.getSignedUrl({
      version: "v4",
      action: "read",
      expires: Date.now() + 5 * 60 * 1000, // 5 minutos
    });

    // 5. Registrar download no log
    await logger.registrarLog({
      storeId: storeId,
      acao: "download_arquivo",
      status: "sucesso",
      usuarioUid: userId,
      documentoId: documento_id,
      mensagem: `Download de ${tipoNormalizado} autorizado para usuário ${userId}`,
      detalhes: {
        tipo: tipoNormalizado,
        caminho: caminhoArquivo,
      },
    });

    return {
      sucesso: true,
      url: signedUrl,
      tipo: tipoNormalizado,
      expira_em: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;

    console.error(`[fiscalDownloadArquivo] Erro: ${e.message}`);

    // Log do erro
    try {
      const docId = request.data?.documento_id || "unknown";
      const storeId = await getStoreIdFromDoc(docId).catch(() => "unknown");
      await logger.registrarLog({
        storeId: storeId,
        acao: "download_arquivo_erro",
        status: "erro",
        usuarioUid: userId,
        documentoId: documento_id,
        mensagem: `Erro no download: ${e.message}`,
      });
    } catch (_) {}

    throw new HttpsError("internal", "Erro ao gerar URL de download.");
  }
});

/**
 * Helper: obtém store_id de um documento fiscal.
 */
async function getStoreIdFromDoc(documentoId) {
  try {
    const db = admin.firestore();
    const snap = await db.collection("fiscal_documents").doc(documentoId).get();
    return snap.exists ? (snap.data().store_id || "unknown") : "unknown";
  } catch (_) {
    return "unknown";
  }
}
