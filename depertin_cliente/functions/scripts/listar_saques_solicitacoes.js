/**
 * Lista documentos em saques_solicitacoes (últimos N por id não é ordenado — só amostra).
 * Uso: node scripts/listar_saques_solicitacoes.js
 */
const admin = require("firebase-admin");
const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";

async function main() {
    if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
    const db = admin.firestore();
    const snap = await db.collection("saques_solicitacoes").limit(100).get();
    const rows = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    rows.sort((a, b) => {
        const ta = a.data_solicitacao?.toMillis?.() ?? 0;
        const tb = b.data_solicitacao?.toMillis?.() ?? 0;
        return tb - ta;
    });
    console.log("Total docs (amostra até 100):", rows.length);
    for (const r of rows) {
        const v = Number(r.valor ?? 0);
        const st = String(r.status ?? "—");
        const tipo = String(r.tipo_usuario ?? r.tipoUsuario ?? r.tipo ?? "—");
        const uid = String(r.user_id ?? "—");
        console.log(
            `${r.id} | R$ ${v.toFixed(2)} | ${st} | tipo=${tipo} | user=${uid.slice(0, 8)}…`,
        );
    }
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
