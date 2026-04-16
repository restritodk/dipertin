/**
 * Credita saldo em users/{uid}.saldo (lojista) por nome exato em `users.nome`.
 *
 * Requer credenciais Admin (uma das opções):
 *   PowerShell:
 *     $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\serviceAccount.json"
 *     cd depertin_cliente/functions
 *     node scripts/creditar_saldo_lojista.js "Eurico dos Santos Mota" 50
 *
 *   Ou: gcloud auth application-default login (conta com permissão no projeto)
 *
 * Uso:
 *   node scripts/creditar_saldo_lojista.js "<nome exato>" [valor]
 */

const admin = require("firebase-admin");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";

async function main() {
    const nome = process.argv[2];
    const valor = Number(process.argv[3] ?? "50");

    if (!nome || !nome.trim()) {
        console.error("Uso: node scripts/creditar_saldo_lojista.js \"Nome completo\" [valor]");
        process.exit(1);
    }
    if (Number.isNaN(valor) || valor <= 0) {
        console.error("Valor inválido.");
        process.exit(1);
    }

    if (!admin.apps.length) {
        admin.initializeApp({ projectId: PROJECT_ID });
    }

    const db = admin.firestore();
    const snap = await db
        .collection("users")
        .where("nome", "==", nome.trim())
        .limit(25)
        .get();

    if (snap.empty) {
        console.error("Nenhum documento em users com nome exato:", nome.trim());
        process.exit(2);
    }

    const candidatos = snap.docs.filter((d) => {
        const r = String(d.data().role || d.data().tipoUsuario || "").toLowerCase();
        return r === "lojista";
    });

    const doc = candidatos[0] || snap.docs[0];
    const data = doc.data();
    const role = String(data.role || data.tipoUsuario || "");

    if (candidatos.length === 0) {
        console.warn(
            "Aviso: nenhum user com role lojista nesse nome; usando primeiro match:",
            doc.id,
            "role=",
            role,
        );
    }

    const antes = Number(data.saldo ?? 0);
    await doc.ref.update({
        saldo: admin.firestore.FieldValue.increment(valor),
    });

    console.log("OK");
    console.log("  uid:", doc.id);
    console.log("  nome:", data.nome);
    console.log("  role:", role);
    console.log("  saldo antes:", antes);
    console.log("  crédito: +", valor);
    console.log("  saldo depois (esperado):", antes + valor);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
