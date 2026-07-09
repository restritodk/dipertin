/**
 * FiscalLogger — Log técnico de operações fiscais
 *
 * Salva registros de auditoria em 3 coleções:
 * - fiscal_logs: log detalhado de cada operação
 * - fiscal_webhooks: log específico de webhooks recebidos
 * - fiscal_status_history: histórico de mudanças de status dos documentos
 *
 * Nunca salva token completo nos logs.
 */
const admin = require("firebase-admin");

const SENSITIVE_FIELDS = [
  "api_key",
  "token",
  "credentials_encrypted",
  "access_token",
  "secret",
  "password",
  "authorization",
];

/**
 * Sanitiza um objeto removendo campos sensíveis para log seguro.
 */
function sanitizar(obj) {
  if (!obj || typeof obj !== "object") return obj;
  const sanitized = { ...obj };
  for (const key of Object.keys(sanitized)) {
    const keyLower = key.toLowerCase();
    if (SENSITIVE_FIELDS.some((s) => keyLower.includes(s))) {
      sanitized[key] = "***";
    } else if (typeof sanitized[key] === "object" && sanitized[key] !== null) {
      sanitized[key] = sanitizar(sanitized[key]);
    }
  }
  return sanitized;
}

/**
 * Registra um log de operação fiscal.
 *
 * @param {Object} params
 * @param {string} params.storeId - ID da loja
 * @param {string} params.acao - Nome da ação (emitir, consultar, cancelar, etc.)
 * @param {string} params.status - Status da operação (sucesso, erro, negado, etc.)
 * @param {string} params.usuarioUid - UID do usuário que executou
 * @param {string} [params.documentoId] - ID do documento fiscal
 * @param {string} [params.chaveAcesso] - Chave de acesso da nota
 * @param {string} [params.mensagem] - Mensagem descritiva
 * @param {string} [params.erro] - Mensagem de erro (se houver)
 * @param {string} [params.codigoRejeicao] - Código de rejeição SEFAZ
 * @param {Object} [params.detalhes] - Detalhes adicionais (sanitizados)
 * @param {string} [params.integrationId] - ID da integração usada
 */
async function registrarLog({
  storeId,
  acao,
  status,
  usuarioUid,
  documentoId,
  chaveAcesso,
  mensagem,
  erro,
  codigoRejeicao,
  detalhes,
  integrationId,
}) {
  try {
    const db = admin.firestore();
    const logData = {
      store_id: storeId || null,
      acao,
      status,
      usuario_uid: usuarioUid || null,
      documento_id: documentoId || null,
      chave_acesso: chaveAcesso || null,
      mensagem: mensagem || null,
      erro: erro || null,
      codigo_rejeicao: codigoRejeicao || null,
      integration_id: integrationId || null,
      // Sanitiza detalhes para não vazar token
      detalhes_sanitizados: detalhes ? sanitizar(detalhes) : null,
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("fiscal_logs").add(logData);
  } catch (e) {
    console.error("[FiscalLogger] Erro ao registrar log:", e.message);
  }
}

/**
 * Registra um webhook recebido.
 *
 * @param {Object} params
 * @param {string} params.provider - Nome do provedor (focus_nfe, etc.)
 * @param {string} [params.chaveAcesso] - Chave de acesso
 * @param {string} [params.documentoId] - ID do documento no Firestore
 * @param {string} params.statusOriginal - Status recebido do provedor
 * @param {string} params.statusMapeado - Status mapeado para o sistema
 * @param {number} [params.codigoRejeicao] - Código de rejeição
 * @param {string} [params.motivoRejeicao] - Motivo da rejeição
 * @param {Object} [params.payload] - Payload completo do webhook (NUNCA salva token)
 */
async function registrarWebhook({
  provider,
  chaveAcesso,
  documentoId,
  statusOriginal,
  statusMapeado,
  codigoRejeicao,
  motivoRejeicao,
  payload,
}) {
  try {
    const db = admin.firestore();
    const logData = {
      provider,
      chave_acesso: chaveAcesso || null,
      documento_id: documentoId || null,
      status_original: statusOriginal,
      status_mapeado: statusMapeado,
      codigo_rejeicao: codigoRejeicao || null,
      motivo_rejeicao: motivoRejeicao || null,
      // Payload sanitizado (NUNCA token)
      payload: payload ? sanitizar(payload) : null,
      recebido_em: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("fiscal_webhooks").add(logData);
  } catch (e) {
    console.error("[FiscalLogger] Erro ao registrar webhook:", e.message);
  }
}

/**
 * Registra mudança de status de um documento fiscal.
 *
 * @param {Object} params
 * @param {string} params.storeId - ID da loja
 * @param {string} params.documentoId - ID do documento fiscal
 * @param {string} [params.chaveAcesso] - Chave de acesso
 * @param {string} params.statusAnterior - Status antes da mudança
 * @param {string} params.statusNovo - Status depois da mudança
 * @param {string} [params.motivo] - Motivo da mudança
 * @param {string} [params.usuarioUid] - UID do usuário (se aplicável)
 * @param {string} [params.origem] - Origem da mudança (api, webhook, painel)
 */
async function registrarStatusHistory({
  storeId,
  documentoId,
  chaveAcesso,
  statusAnterior,
  statusNovo,
  motivo,
  usuarioUid,
  origem = "api",
}) {
  try {
    const db = admin.firestore();
    const logData = {
      store_id: storeId,
      documento_id: documentoId,
      chave_acesso: chaveAcesso || null,
      status_anterior: statusAnterior,
      status_novo: statusNovo,
      motivo: motivo || null,
      usuario_uid: usuarioUid || null,
      origem,
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("fiscal_status_history").add(logData);
  } catch (e) {
    console.error("[FiscalLogger] Erro ao registrar status history:", e.message);
  }
}

module.exports = {
  registrarLog,
  registrarWebhook,
  registrarStatusHistory,
  sanitizar,
};
