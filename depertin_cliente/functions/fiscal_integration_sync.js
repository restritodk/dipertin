/**
 * Triggers para sincronizar alterações em fiscal_integrations com
 * store_fiscal_settings (desnormalização).
 *
 * SEGURANÇA: Apenas campos públicos/operacionais são propagados.
 * credentials_encrypted NUNCA é copiado — o token fica exclusivamente
 * em fiscal_integrations (staff-only) e é descriptografado apenas no
 * backend via Admin SDK.
 *
 * Quando o admin edita uma integração global (ex.: troca ambiente),
 * este trigger propaga os dados atualizados para TODOS os documentos
 * store_fiscal_settings que referenciam aquela integration_id.
 */

const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");

// ─── Campos públicos a propagar (NUNCA incluir credentials_encrypted) ───
const CAMPOS_INTEGRACAO = [
  "provider",
  "provider_name",
  "environment",
  "base_url_sandbox",
  "base_url_production",
  "supported_documents",
  "status",
];

/**
 * Extrai do documento fiscal_integrations apenas os campos
 * que devem ser propagados para store_fiscal_settings.integration_data.
 */
function extrairIntegrationData(data) {
  if (!data) return null;
  const result = {};
  for (const campo of CAMPOS_INTEGRACAO) {
    if (data[campo] !== undefined) result[campo] = data[campo];
  }
  return Object.keys(result).length > 0 ? result : null;
}

/**
 * Trigger onDocumentWritten em fiscal_integrations/{integrationId}.
 *
 * - onCreate / onUpdate: propaga integration_data atualizado para
 *   todos os store_fiscal_settings que apontam para esta integration_id.
 * - onDelete: remove integration_data dos store_fiscal_settings
 *   (mas mantém o integration_id para indicar qual foi removido).
 */
exports.onFiscalIntegrationWrite = onDocumentWritten(
  {
    document: "fiscal_integrations/{integrationId}",
    region: "us-east1",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const integrationId = event.params.integrationId;
    const beforeData = event.data.before?.data();
    const afterData = event.data.after?.data();

    // ═══ SEGURANÇA: detecta api_key em texto puro ═══
    // Se um documento foi salvo com api_key não vazia, significa que o
    // frontend escreveu diretamente sem passar pelo callable fiscalSalvarIntegracao.
    // O token deve estar criptografado em credentials_encrypted.
    const rawApiKey = (afterData?.api_key || "").trim();
    if (rawApiKey && rawApiKey.length > 0) {
      console.warn(
        `[onFiscalIntegrationWrite] ⚠️ SEGURANÇA: api_key em texto puro detectada ` +
        `em integration_id=${integrationId} (${rawApiKey.substring(0, 4)}...). ` +
        `Sempre usar fiscalSalvarIntegracao para salvar tokens criptografados.`
      );
    }

    const db = admin.firestore();
    const integrationData = extrairIntegrationData(afterData);
    const isDelete = afterData === undefined;

    try {
      // Busca todos os store_fiscal_settings que referenciam esta integração
      const settingsSnap = await db
        .collection("store_fiscal_settings")
        .where("integration_id", "==", integrationId)
        .get();

      if (settingsSnap.empty) {
        console.log(
          `[onFiscalIntegrationWrite] Nenhum store_fiscal_settings referencia integration_id=${integrationId}`
        );
        return;
      }

      console.log(
        `[onFiscalIntegrationWrite] Atualizando ${settingsSnap.size} store(s) ` +
          `para integration_id=${integrationId} | delete=${isDelete}`
      );

      const batch = db.batch();
      for (const doc of settingsSnap.docs) {
        const updates = {
          "updated_at": FieldValue.serverTimestamp(),
        };

        if (isDelete) {
          // Integração foi removida → limpa dados, mas mantém o ID como referência
          updates["integration_data"] = null;
          updates["integration_removida_em"] = FieldValue.serverTimestamp();
        } else if (integrationData) {
          // Integração foi criada/atualizada → propaga dados novos
          updates["integration_data"] = integrationData;
          // Remove o campo integration_removida_em (não apenas seta null)
          updates["integration_removida_em"] = FieldValue.delete();
        }

        batch.update(doc.ref, updates);
      }

      await batch.commit();
      console.log(
        `[onFiscalIntegrationWrite] Sincronização concluída para ${settingsSnap.size} store(s).`
      );
    } catch (err) {
      console.error(
        `[onFiscalIntegrationWrite] Erro ao sincronizar integration_id=${integrationId}:`,
        err.message
      );
    }
  }
);
