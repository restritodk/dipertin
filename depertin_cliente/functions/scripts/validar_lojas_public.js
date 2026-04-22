/**
 * Valida o conteúdo de `lojas_public` (Fase 3G.1):
 *  - Imprime os campos presentes em cada doc
 *  - Alerta se encontrar campos sensíveis que NÃO deviam estar lá
 *    (cpf, cnpj, email, saldo, fcm_token, documentos, block_*, senha etc.)
 *
 * Uso (na pasta functions):
 *   node scripts/validar_lojas_public.js
 */

const admin = require("firebase-admin");
const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";

const CAMPOS_SENSIVEIS_PROIBIDOS = [
    "cpf",
    "cnpj",
    "email",
    "senha",
    "password",
    "saldo",
    "fcm_token",
    "fcm_tokens",
    "documentos",
    "data_nascimento",
    "termos_aceitos",
    "lojista_owner_uid",
    "chaves_pix",
    "colaboradores",
    "tokens",
    "google_uid",
];

const PREFIXOS_SENSIVEIS = ["block_", "bloqueio_", "auth_", "password_"];

function ehSensivel(nomeCampo) {
    const k = nomeCampo.toLowerCase();
    if (CAMPOS_SENSIVEIS_PROIBIDOS.includes(k)) return true;
    return PREFIXOS_SENSIVEIS.some((p) => k.startsWith(p));
}

async function main() {
    if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
    const db = admin.firestore();

    const snap = await db.collection("lojas_public").get();
    console.log(`lojas_public: ${snap.size} docs\n`);

    let totalAlertas = 0;
    for (const doc of snap.docs) {
        const d = doc.data();
        const chaves = Object.keys(d).sort();
        const sensiveis = chaves.filter(ehSensivel);
        const nome =
            d.loja_nome ||
            d.nome_loja ||
            d.nome_fantasia ||
            d.nome ||
            "(sem nome)";
        const flag = sensiveis.length ? " ⚠️" : "";
        console.log(`${doc.id} — ${nome}${flag}`);
        console.log(`  campos (${chaves.length}): ${chaves.join(", ")}`);
        if (sensiveis.length) {
            totalAlertas++;
            console.log(`  CAMPOS SENSÍVEIS VAZANDO: ${sensiveis.join(", ")}`);
        }
        console.log("");
    }

    if (totalAlertas === 0) {
        console.log("OK — nenhum campo sensível vazando em lojas_public.");
    } else {
        console.log(`ALERTA — ${totalAlertas} doc(s) com campos sensíveis.`);
        process.exitCode = 1;
    }
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
