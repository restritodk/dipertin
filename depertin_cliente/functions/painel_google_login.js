/**
 * Validação server-side após Firebase Auth com Google no painel web.
 * - Provedor Google obrigatório.
 * - Lojista **aprovado**: status_loja ∈ { aprovada, aprovado, ativo }.
 * - Se `users/{uid}` não bater, procura `users` pelo **mesmo e-mail** do token
 *   e funde no UID do Google (vincula perfil aprovado ao login atual).
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

/** Igual a saque_solicitar.js — muitos lojistas têm role "cliente" legado e tipoUsuario "lojista". */
function docIndicaLojista(u) {
    if (!u) return false;
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(u[k] || "").toLowerCase().trim() === "lojista") return true;
    }
    return false;
}

function normalizeEmail(e) {
    if (!e || typeof e !== "string") return "";
    return e.trim().toLowerCase();
}

/** Loja liberada para operar no painel / vitrine (alinhado ao painel master). */
function lojistaAprovadoParaPainelJs(d) {
    if (!docIndicaLojista(d)) return false;
    const sl = String(d.status_loja || "").toLowerCase().trim();
    return sl === "aprovada" || sl === "aprovado" || sl === "ativo";
}

/** Conta operacionalmente bloqueada (alinhado a lojistaDocumentoBloqueadoJs em index.js). */
function lojistaRecusaSoCadastroJs(d) {
    if (d.recusa_cadastro === true) return true;
    const sl = String(d.status_loja || "");
    if (sl !== "bloqueada" && sl !== "bloqueado") return false;
    if (Object.prototype.hasOwnProperty.call(d, "block_active")) return false;
    const motivo = String(d.motivo_recusa || "").trim();
    if (!motivo) return false;
    const s = motivo.toLowerCase();
    const keys = [
        "pagamento",
        "inadimpl",
        "financeir",
        "suspens",
        "falta de pagamento",
        "produtos suspens",
        "cobrança",
        "cobranca",
        "mensalidade",
        "plano",
        "pendência financeira",
        "pendencia financeira",
        "regulariz",
        "débito",
        "debito",
    ];
    if (keys.some((k) => s.includes(k))) return false;
    return true;
}

function lojistaDocumentoBloqueadoJs(d) {
    if (!d) return false;
    if (!docIndicaLojista(d)) return false;
    if (lojistaRecusaSoCadastroJs(d)) return false;

    const sl = String(d.status_loja || "");
    const temBlockActive = Object.prototype.hasOwnProperty.call(d, "block_active");

    if (sl === "bloqueado") return true;
    if (sl === "bloqueio_temporario" && d.block_end_at) {
        const end = d.block_end_at.toDate
            ? d.block_end_at.toDate()
            : new Date(d.block_end_at._seconds * 1000);
        if (Date.now() > end.getTime()) return false;
        return true;
    }
    if (sl === "bloqueada" || sl === "bloqueado") {
        if (!temBlockActive) return true;
    }
    if (!d.block_active) return false;
    if (d.block_type === "BLOCK_TEMPORARY" && d.block_end_at) {
        const end = d.block_end_at.toDate
            ? d.block_end_at.toDate()
            : new Date(d.block_end_at._seconds * 1000);
        if (Date.now() > end.getTime()) return false;
    }
    return true;
}

/**
 * Localiza documento de lojista **aprovado** com o mesmo e-mail (campo `email`).
 */
async function buscarLojistaAprovadoPorEmail(emailNorm) {
    const snap = await admin
        .firestore()
        .collection("users")
        .where("email", "==", emailNorm)
        .limit(10)
        .get();
    if (snap.empty) return null;
    let best = null;
    snap.forEach((doc) => {
        const d = doc.data();
        if (docIndicaLojista(d) && lojistaAprovadoParaPainelJs(d)) {
            best = { id: doc.id, data: d };
        }
    });
    return best;
}

/**
 * Remove o usuário do Firebase Auth quando o login Google no painel é recusado
 * e **não existe** documento em `users/{uid}` — evita acumular contas "órfãs"
 * de quem não é lojista. Nunca apaga se já houver perfil no Firestore (cliente, etc.).
 */
async function removerContaAuthSeNaoHaDocUsers(uid, docExists) {
    if (docExists) return;
    try {
        await admin.auth().deleteUser(uid);
    } catch (e) {
        console.warn(
            "painelValidarPosLoginGoogle removerContaAuthSeNaoHaDocUsers",
            uid,
            e.message || e
        );
    }
}

const CAMPOS_PARA_VINCULAR = [
    "nome",
    "nome_loja",
    "role",
    "tipoUsuario",
    "cidade",
    "status_loja",
    "ativo",
    "loja_aberta",
    "telefone",
    "cpf",
    "cpf_cnpj",
    "primeiro_acesso",
    "saldo",
    "recusa_cadastro",
    "motivo_recusa",
    "block_active",
    "block_type",
    "block_end_at",
    "block_start_at",
    "block_reason",
    "motivo_bloqueio",
    "status_conta",
];

exports.painelValidarPosLoginGoogle = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Autenticação necessária."
        );
    }

    const token = context.auth.token || {};
    const firebaseMeta = token.firebase || {};
    const provider = firebaseMeta.sign_in_provider;
    if (provider !== "google.com") {
        throw new functions.https.HttpsError(
            "permission-denied",
            "Token inválido: o login deve ser feito com Google."
        );
    }

    const uid = context.auth.uid;

    const identities = firebaseMeta.identities || {};
    const googleIds = identities["google.com"];
    const googleUid =
        Array.isArray(googleIds) && googleIds.length ? String(googleIds[0]) : null;

    const docRef = admin.firestore().collection("users").doc(uid);
    let doc = await docRef.get();
    let d = doc.exists ? doc.data() : null;

    const emailNorm = normalizeEmail(token.email);
    if (!emailNorm) {
        await removerContaAuthSeNaoHaDocUsers(uid, doc.exists);
        return { ok: false, code: "NO_EMAIL" };
    }

    async function gravarGoogleUid(uidDoc) {
        if (!googleUid) return;
        try {
            await admin
                .firestore()
                .collection("users")
                .doc(uidDoc)
                .set(
                    {
                        google_uid: googleUid,
                        google_signin_ultimo: admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                );
        } catch (e) {
            console.warn("painelValidarPosLoginGoogle google_uid", e.message);
        }
    }

    function retornoSucesso(dados) {
        if (lojistaDocumentoBloqueadoJs(dados)) {
            return {
                ok: true,
                role: "lojista",
                primeiro_acesso: dados.primeiro_acesso === true,
                bloqueado_operacional: true,
            };
        }
        return {
            ok: true,
            role: "lojista",
            primeiro_acesso: dados.primeiro_acesso === true,
            bloqueado_operacional: false,
        };
    }

    // 1) users/{uid} já é lojista aprovado
    if (d && docIndicaLojista(d) && lojistaAprovadoParaPainelJs(d)) {
        await gravarGoogleUid(uid);
        return retornoSucesso(d);
    }

    // 2) users/{uid} é lojista mas ainda não aprovado (pendente, etc.)
    if (d && docIndicaLojista(d) && !lojistaAprovadoParaPainelJs(d)) {
        return { ok: false, code: "LOJISTA_NAO_APROVADO" };
    }

    // 3) Mesmo e-mail de um lojista aprovado noutro documento → fundir no UID atual (Google)
    const porEmail = await buscarLojistaAprovadoPorEmail(emailNorm);
    if (!porEmail) {
        await removerContaAuthSeNaoHaDocUsers(uid, doc.exists);
        return { ok: false, code: "NOT_LOJISTA" };
    }

    if (porEmail.id === uid) {
        await gravarGoogleUid(uid);
        return retornoSucesso(porEmail.data);
    }

    const src = porEmail.data;
    const mergeData = { email: emailNorm };
    for (const k of CAMPOS_PARA_VINCULAR) {
        if (src[k] !== undefined) mergeData[k] = src[k];
    }
    mergeData.painel_vinculado_por_email = true;
    mergeData.painel_vinculado_doc_origem = porEmail.id;
    mergeData.painel_vinculado_em = admin.firestore.FieldValue.serverTimestamp();

    await docRef.set(mergeData, { merge: true });
    doc = await docRef.get();
    d = doc.data();
    if (!d) {
        await removerContaAuthSeNaoHaDocUsers(uid, doc.exists);
        return { ok: false, code: "NO_PROFILE" };
    }
    await gravarGoogleUid(uid);
    return retornoSucesso(d);
});
