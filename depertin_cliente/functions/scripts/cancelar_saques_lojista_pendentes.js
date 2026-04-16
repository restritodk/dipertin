/**
 * Cancela todas as solicitações de saque PENDENTES feitas por lojistas:
 * - marca o documento em saques_solicitacoes como recusado
 * - devolve o valor a users/{uid}.saldo (o saque original debitou ao pedir)
 *
 * Uso (na pasta functions):
 *   node scripts/cancelar_saques_lojista_pendentes.js           # só lista (dry-run)
 *   node scripts/cancelar_saques_lojista_pendentes.js --confirm # aplica
 *
 * Credenciais: GOOGLE_APPLICATION_CREDENTIALS ou gcloud auth application-default login
 */

const admin = require("firebase-admin");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "depertin-f940f";

function tipoNoDoc(d) {
    return String(d.tipo_usuario || d.tipoUsuario || d.tipo || "")
        .toLowerCase()
        .trim();
}

function docPareceLojista(d) {
    const t = tipoNoDoc(d);
    if (t === "lojista" || t === "loja" || t === "lojas") return true;
    if (t === "entregador") return false;
    return null;
}

async function usuarioELojista(db, uid) {
    if (!uid) return false;
    const u = await db.collection("users").doc(String(uid)).get();
    if (!u.exists) return false;
    const ud = u.data();
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(ud[k] || "").toLowerCase().trim() === "lojista") return true;
    }
    return false;
}

async function main() {
    const confirmar = process.argv.includes("--confirm");

    if (!admin.apps.length) {
        admin.initializeApp({ projectId: PROJECT_ID });
    }
    const db = admin.firestore();

    const snap = await db
        .collection("saques_solicitacoes")
        .where("status", "==", "pendente")
        .get();

    const candidatos = [];
    for (const doc of snap.docs) {
        const d = doc.data();
        let lojista = docPareceLojista(d);
        if (lojista === null) {
            lojista = await usuarioELojista(db, d.user_id);
        }
        if (lojista) {
            candidatos.push({ id: doc.id, data: d });
        }
    }

    console.log(
        `Encontrados ${candidatos.length} saque(s) pendente(s) de lojista (de ${snap.size} pendente(s) no total).`,
    );

    if (candidatos.length === 0) {
        process.exit(0);
    }

    for (const { id, data } of candidatos) {
        const v = Number(data.valor ?? 0);
        const uid = String(data.user_id || "");
        console.log(
            `  - ${id} | uid=${uid} | R$ ${v.toFixed(2)} | tipo doc=${tipoNoDoc(data) || "—"}`,
        );
    }

    if (!confirmar) {
        console.log("\nDry-run. Para aplicar, executa com: --confirm");
        process.exit(0);
    }

    let ok = 0;
    let err = 0;
    for (const { id, data } of candidatos) {
        const saqueRef = db.collection("saques_solicitacoes").doc(id);
        const uid = String(data.user_id || "");
        const v = Number(data.valor ?? 0);
        if (!uid || Number.isNaN(v) || v <= 0) {
            console.error("Ignorado (uid/valor inválido):", id);
            err++;
            continue;
        }
        const userRef = db.collection("users").doc(uid);
        try {
            await db.runTransaction(async (t) => {
                const s = await t.get(saqueRef);
                if (!s.exists) return;
                const cur = s.data();
                if (String(cur.status || "") !== "pendente") return;
                t.update(userRef, {
                    saldo: admin.firestore.FieldValue.increment(v),
                });
                t.update(saqueRef, {
                    status: "recusado",
                    data_recusa: admin.firestore.FieldValue.serverTimestamp(),
                    recusa_motivo_script: "cancelar_saques_lojista_pendentes.js",
                });
            });
            ok++;
            console.log("OK:", id);
        } catch (e) {
            err++;
            console.error("Erro", id, e.message || e);
        }
    }

    console.log(`\nConcluído: ${ok} cancelado(s) com estorno de saldo, ${err} erro(s).`);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
