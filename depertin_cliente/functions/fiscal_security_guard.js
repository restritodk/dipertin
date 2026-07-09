/**
 * FiscalSecurityGuard — Validação de segurança por loja
 *
 * Garante que nenhum lojista acesse, consulte, cancele ou baixe
 * documentos fiscais de outra loja.
 *
 * Uso:
 *   const guard = require('./fiscal_security_guard');
 *   await guard.validateStoreAccess({ userId, storeId, docId, action });
 *
 * Regras:
 * - Usuário autenticado deve pertencer à loja
 * - Documento fiscal deve pertencer à mesma loja
 * - Qualquer divergência → HTTP 403 + log de tentativa suspeita
 * - Token Focus NFe nunca é exposto
 */
const admin = require("firebase-admin");

/**
 * Valida acesso de um usuário a um recurso fiscal de uma loja.
 *
 * @param {Object} params
 * @param {string} params.userId - UID do usuário autenticado
 * @param {string} params.storeId - ID da loja sendo acessada
 * @param {string} [params.docId] - ID do documento fiscal (opcional)
 * @param {string} [params.chaveAcesso] - Chave de acesso da nota (opcional)
 * @param {string} params.action - Nome da ação (ex: "emitir", "consultar", "cancelar")
 * @param {boolean} [params.allowStaff] - Se true, staff (master) pode acessar qualquer loja
 * @returns {Promise<{ permitido: boolean, lojaId: string, lojaNome: string, userId: string, isStaff: boolean }>}
 * @throws {HttpsError} Se o acesso for negado
 */
async function validateStoreAccess({
  userId,
  storeId,
  docId,
  chaveAcesso,
  action,
  allowStaff = true,
}) {
  if (!userId) {
    throwDenied("Usuário não autenticado.", action, storeId);
  }
  if (!storeId) {
    throwDenied("storeId é obrigatório.", action, storeId);
  }

  const db = admin.firestore();

  // ─── 1. Buscar dados do usuário ───
  const userSnap = await db.collection("users").doc(userId).get();
  if (!userSnap.exists) {
    throwDenied("Usuário não encontrado.", action, storeId);
  }

  const userData = userSnap.data();
  const role = (userData.role || userData.tipo || "").toLowerCase().trim();
  const isStaff =
    role === "master" || role === "master_city" || role === "superadmin";

  // Staff pode acessar qualquer loja (se allowStaff = true)
  if (isStaff && allowStaff) {
    return {
      permitido: true,
      lojaId: storeId,
      lojaNome: userData.nome_loja || userData.nome || storeId,
      userId,
      isStaff: true,
    };
  }

  // ─── 2. Verificar vínculo do usuário com a loja ───
  let usuarioStoreId = userData.loja_id || userData.store_id || "";
  const lojistaOwnerUid = userData.lojista_owner_uid || "";

  // Se for colaborador, usa o owner_uid como storeId efetivo
  if (lojistaOwnerUid && lojistaOwnerUid.length > 0) {
    usuarioStoreId = lojistaOwnerUid;
  }

  // Fallback: se o uid do usuário é o mesmo que storeId
  if (!usuarioStoreId) {
    usuarioStoreId = userId;
  }

  // Verifica se o storeId informado corresponde ao storeId do usuário
  if (usuarioStoreId !== storeId) {
    await registrarTentativaSuspeita({
      userId,
      storeId,
      usuarioStoreId,
      action,
      motivo: "Usuário não pertence à loja informada",
    });
    throwDenied(
      "Você não tem permissão para acessar esta loja.",
      action,
      storeId
    );
  }

  // ─── 3. Se tem docId, verificar se o documento pertence à loja ───
  if (docId) {
    const docSnap = await db.collection("fiscal_documents").doc(docId).get();
    if (docSnap.exists) {
      const docData = docSnap.data();
      const docStoreId = docData.store_id || "";

      if (docStoreId !== storeId) {
        await registrarTentativaSuspeita({
          userId,
          storeId: docStoreId,
          usuarioStoreId,
          docId,
          action,
          motivo: "Documento fiscal não pertence à loja do usuário",
        });
        throwDenied(
          "Você não tem permissão para acessar esta nota fiscal.",
          action,
          storeId
        );
      }
    }
  }

  // ─── 4. Se tem chaveAcesso, verificar se o documento pertence à loja ───
  if (chaveAcesso && !docId) {
    const docSnap = await db
      .collection("fiscal_documents")
      .where("access_key", "==", chaveAcesso)
      .limit(1)
      .get();

    if (!docSnap.empty) {
      const docData = docSnap.docs[0].data();
      const docStoreId = docData.store_id || "";

      if (docStoreId !== storeId) {
        await registrarTentativaSuspeita({
          userId,
          chaveAcesso,
          usuarioStoreId,
          docStoreId,
          action,
          motivo: "Chave de acesso não pertence à loja do usuário",
        });
        throwDenied(
          "Você não tem permissão para acessar esta nota fiscal.",
          action,
          storeId
        );
      }
    }
  }

  return {
    permitido: true,
    lojaId: storeId,
    lojaNome: userData.nome_loja || userData.nome_fantasia || storeId,
    userId,
    isStaff: false,
  };
}

/**
 * Lança HttpsError com mensagem de permissão negada e registra log.
 */
function throwDenied(mensagem, action, storeId) {
  const logMsg = `[FiscalSecurityGuard] ACESSO NEGADO: action=${action} storeId=${storeId} motivo="${mensagem}"`;
  console.warn(logMsg);

  const { HttpsError } = require("firebase-functions/v2/https");
  throw new HttpsError(
    "permission-denied",
    "Você não tem permissão para acessar esta nota fiscal."
  );
}

/**
 * Registra tentativa suspeita de acesso cruzado em fiscal_logs.
 */
async function registrarTentativaSuspeita({
  userId,
  storeId,
  usuarioStoreId,
  docId,
  chaveAcesso,
  action,
  motivo,
}) {
  try {
    const db = admin.firestore();
    await db.collection("fiscal_logs").add({
      tipo: "tentativa_acesso_negado",
      acao: action,
      usuario_uid: userId,
      store_id_solicitada: storeId,
      store_id_usuario: usuarioStoreId || null,
      documento_id: docId || null,
      chave_acesso: chaveAcesso || null,
      motivo,
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("[FiscalSecurityGuard] Erro ao registrar log suspeito:", e.message);
  }
}

module.exports = {
  validateStoreAccess,
};
