/**
 * Triggers para sincronizar alterações em fiscal_integrations com
 * store_fiscal_settings (desnormalização).
 *
 * Quando o admin edita uma integração global (ex.: troca token da Focus NFe),
 * este trigger propaga os dados atualizados para TODOS os documentos
 * store_fiscal_settings que referenciam aquela integration_id.
 */

const admin = require("firebase-admin");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");

// ─── Campos relevantes a propagar ───
const CAMPOS_INTEGRACAO = [
  "provider",
  "provider_name",
  "environment",
  "base_url_sandbox",
  "base_url_production",
  "supported_documents",
  "credentials_encrypted",
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
    region: "southamerica-east1",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const integrationId = event.params.integrationId;
    const beforeData = event.data.before?.data();
    const afterData = event.data.after?.data();

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
          "updated_at": admin.firestore.FieldValue.serverTimestamp(),
        };

        if (isDelete) {
          // Integração foi removida → limpa dados, mas mantém o ID como referência
          updates["integration_data"] = null;
          updates["integration_removida_em"] =
            admin.firestore.FieldValue.serverTimestamp();
        } else if (integrationData) {
          // Integração foi criada/atualizada → propaga dados novos
          updates["integration_data"] = integrationData;
          updates["integration_removida_em"] = null;
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
