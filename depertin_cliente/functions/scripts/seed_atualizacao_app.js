/**
 * Cria/atualiza configuracoes/atualizacao_app (versão mínima obrigatória no app).
 *
 * cd depertin_cliente/functions
 * npm run seed:atualizacao-app
 *
 * Requer credenciais Admin (uma opção):
 * - $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 * - ou `gcloud auth application-default login` com projeto depertin-f940f
 */

const admin = require("firebase-admin");

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: "depertin-f940f" });
  }

  const db = admin.firestore();
  const ref = db.collection("configuracoes").doc("atualizacao_app");

  await ref.set(
    {
      versao_minima_android: "1.0.0",
      versao_minima_ios: "1.0.0",
      mensagem: "",
      url_loja_android: "",
      url_loja_ios: "",
      atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const snap = await ref.get();
  console.log("OK: configuracoes/atualizacao_app");
  console.log(JSON.stringify(snap.data(), null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
