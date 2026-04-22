/**
 * Backfill da coleção `lojas_public` (Fase 3G.1).
 *
 * Para cada doc em `users` cujo `role/tipoUsuario/tipo == 'lojista'`, cria/atualiza
 * o espelho em `lojas_public/{uid}` usando a MESMA allowlist que o trigger
 * `sincronizarLojaPublicOnWrite` em `../sincronizar_lojas_public.js`.
 *
 * Também opcionalmente remove espelhos "órfãos" (docs em `lojas_public` cujo
 * `users/{uid}` não existe mais ou deixou de ser lojista).
 *
 * Uso (pasta functions):
 *   node scripts/backfill_lojas_public.js            # dry-run: imprime o que faria
 *   node scripts/backfill_lojas_public.js --confirm  # aplica de fato
 *   node scripts/backfill_lojas_public.js --confirm --limpar-orfaos
 *
 * Credenciais:
 *   - GOOGLE_APPLICATION_CREDENTIALS=path/para/sa.json, OU
 *   - gcloud auth application-default login
 */

const admin = require("firebase-admin");
const {
    ehLojista,
    extrairCamposPublicos,
} = require("../sincronizar_lojas_public");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";
const CONFIRMAR = process.argv.includes("--confirm");
const LIMPAR_ORFAOS = process.argv.includes("--limpar-orfaos");
const BATCH_SIZE = 400;

function init() {
    if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
    return admin.firestore();
}

async function sincronizarLojistas(db) {
    console.log("[backfill] Lendo users...");
    const snap = await db.collection("users").get();
    console.log(`[backfill] Total users: ${snap.size}`);

    let lojistas = 0;
    let naoLojistas = 0;
    let batch = db.batch();
    let opsNoBatch = 0;
    let aplicados = 0;

    for (const doc of snap.docs) {
        const data = doc.data();
        if (!ehLojista(data)) {
            naoLojistas++;
            continue;
        }
        lojistas++;
        const patch = extrairCamposPublicos(data);
        const ref = db.collection("lojas_public").doc(doc.id);

        if (!CONFIRMAR) {
            console.log(
                `[dry-run] set lojas_public/${doc.id} (${String(
                    data.loja_nome ||
                        data.nome_loja ||
                        data.nome_fantasia ||
                        data.nome ||
                        "(sem nome)",
                )}) — ${Object.keys(patch).length} campos`,
            );
            continue;
        }

        batch.set(ref, patch, { merge: true });
        opsNoBatch++;
        aplicados++;
        if (opsNoBatch >= BATCH_SIZE) {
            await batch.commit();
            console.log(`[backfill] commit parcial: ${aplicados} docs`);
            batch = db.batch();
            opsNoBatch = 0;
        }
    }

    if (CONFIRMAR && opsNoBatch > 0) {
        await batch.commit();
        console.log(`[backfill] commit final: ${aplicados} docs`);
    }

    console.log("");
    console.log(`[backfill] Lojistas encontrados: ${lojistas}`);
    console.log(`[backfill] Não-lojistas ignorados: ${naoLojistas}`);
    if (CONFIRMAR) {
        console.log(`[backfill] Espelhos criados/atualizados: ${aplicados}`);
    } else {
        console.log("[backfill] DRY-RUN — rode de novo com --confirm pra aplicar.");
    }
}

async function limparOrfaos(db) {
    if (!LIMPAR_ORFAOS) return;
    console.log("");
    console.log("[backfill] Procurando órfãos em lojas_public...");
    const publicSnap = await db.collection("lojas_public").get();
    console.log(`[backfill] Total lojas_public: ${publicSnap.size}`);

    let batch = db.batch();
    let opsNoBatch = 0;
    let apagados = 0;

    for (const doc of publicSnap.docs) {
        const uid = doc.id;
        const userSnap = await db.collection("users").doc(uid).get();
        const continuaLojista = userSnap.exists && ehLojista(userSnap.data());
        if (continuaLojista) continue;

        if (!CONFIRMAR) {
            console.log(
                `[dry-run] delete lojas_public/${uid} (órfão — user não é mais lojista)`,
            );
            continue;
        }
        batch.delete(doc.ref);
        opsNoBatch++;
        apagados++;
        if (opsNoBatch >= BATCH_SIZE) {
            await batch.commit();
            console.log(`[backfill] commit órfãos parcial: ${apagados}`);
            batch = db.batch();
            opsNoBatch = 0;
        }
    }

    if (CONFIRMAR && opsNoBatch > 0) {
        await batch.commit();
    }
    console.log(`[backfill] Órfãos apagados: ${apagados}`);
}

async function main() {
    const db = init();
    await sincronizarLojistas(db);
    await limparOrfaos(db);
}

main().catch((e) => {
    console.error("[backfill] ERRO:", e);
    process.exit(1);
});
