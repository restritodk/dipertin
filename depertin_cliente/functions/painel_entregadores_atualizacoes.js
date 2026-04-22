/**
 * Painel web — aba "Atualizações" (Gestão de Entregadores).
 * Lista CNH/CRLV com status pendente para entregadores já aprovados.
 * Usa Admin SDK para evitar PERMISSION_DENIED em collectionGroup no cliente.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

/** Garante JSON puro no retorno do onCall (evita falha de serialização p.ex. com Timestamps aninhados). */
function dadoParaJson(val) {
    if (val == null) {
        return val;
    }
    if (val instanceof admin.firestore.Timestamp) {
        return val.toDate().toISOString();
    }
    if (val instanceof admin.firestore.DocumentReference) {
        return val.path;
    }
    if (val instanceof admin.firestore.GeoPoint) {
        return { latitude: val.latitude, longitude: val.longitude };
    }
    if (Array.isArray(val)) {
        return val.map((x) => dadoParaJson(x));
    }
    if (typeof val === "object") {
        if (typeof val.toDate === "function") {
            try {
                return val.toDate().toISOString();
            } catch (_) {
                // continua
            }
        }
        if (val._seconds != null) {
            return new admin.firestore.Timestamp(
                val._seconds,
                val._nanoseconds || 0
            )
                .toDate()
                .toISOString();
        }
        const o = {};
        for (const [k, v] of Object.entries(val)) {
            o[k] = dadoParaJson(v);
        }
        return o;
    }
    return val;
}

function normRole(d) {
    return String(d?.role || d?.tipoUsuario || d?.tipo || "")
        .trim()
        .toLowerCase();
}

function isStaffUser(d) {
    const r = normRole(d);
    return (
        r === "master" ||
        r === "superadmin" ||
        r === "super_admin" ||
        r === "master_city"
    );
}

function parseDocumentoPath(fullPath) {
    const parts = String(fullPath || "").split("/");
    // users/{uid}/documentos/cnh
    if (
        parts.length === 4 &&
        parts[0] === "users" &&
        parts[2] === "documentos" &&
        parts[3] === "cnh"
    ) {
        return { uid: parts[1], tipoDoc: "cnh", veiculoId: null };
    }
    // users/{uid}/veiculos/{vid}/documentos/crlv
    if (
        parts.length === 6 &&
        parts[0] === "users" &&
        parts[2] === "veiculos" &&
        parts[4] === "documentos" &&
        parts[5] === "crlv"
    ) {
        return {
            uid: parts[1],
            tipoDoc: "crlv",
            veiculoId: parts[3],
        };
    }
    return null;
}

exports.painelEntregadoresAtualizacoesPendentes = functions
    .runWith({
        timeoutSeconds: 120,
        memory: "512MB",
        // Painel web não usa reCAPTCHA/App Check; HTTP direto do Flutter não manda
        // X-Firebase-AppCheck. Explícito para o runtime não exigir token.
        enforceAppCheck: false,
    })
    .https.onCall(async (data, context) => {
        try {
            if (!context.auth) {
                throw new functions.https.HttpsError(
                    "unauthenticated",
                    "Autenticação necessária."
                );
            }
            const db = admin.firestore();
            const callerSnap = await db
                .collection("users")
                .doc(context.auth.uid)
                .get();
            if (!callerSnap.exists) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "Perfil não encontrado."
                );
            }
            const caller = callerSnap.data();
            if (!isStaffUser(caller)) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "Apenas equipe administrativa."
                );
            }
            const callerRole = normRole(caller);
            let cidadesGerente = [];
            if (callerRole === "master_city") {
                const raw = caller.cidades_gerenciadas;
                if (Array.isArray(raw)) {
                    cidadesGerente = raw
                        .map((x) => String(x || "").trim())
                        .filter(Boolean);
                }
            }

            // Exige índice de collection group `documentos` + `status` (ver firestore.indexes.json).
            const snap = await db
                .collectionGroup("documentos")
                .where("status", "==", "pendente")
                .limit(400)
                .get();
            const items = [];
            const seenPath = new Set();

            for (const doc of snap.docs) {
                const docId = doc.id;
                if (docId !== "cnh" && docId !== "crlv") continue;
                const parsed = parseDocumentoPath(doc.ref.path);
                if (!parsed) continue;

                const userSnap = await db
                    .collection("users")
                    .doc(parsed.uid)
                    .get();
                if (!userSnap.exists) continue;
                const u = userSnap.data() || {};
                if (String(u.role || "").trim().toLowerCase() !== "entregador") {
                    continue;
                }
                if (
                    String(u.entregador_status || "").trim().toLowerCase() !==
                    "aprovado"
                ) {
                    continue;
                }
                if (cidadesGerente.length > 0) {
                    const c = String(u.cidade || "").trim();
                    if (!cidadesGerente.includes(c)) continue;
                }

                const d = doc.data() || {};
                const row = {
                    documentPath: doc.ref.path,
                    uid: parsed.uid,
                    tipoDoc: parsed.tipoDoc,
                    veiculoId: parsed.veiculoId,
                    data: dadoParaJson(d),
                };
                if (!seenPath.has(row.documentPath)) {
                    seenPath.add(row.documentPath);
                    items.push(row);
                }
            }

            items.sort((a, b) => {
                const ta = a.data?.atualizado_em;
                const tb = b.data?.atualizado_em;
                if (typeof ta === "string" && typeof tb === "string") {
                    return tb.localeCompare(ta);
                }
                if (typeof ta === "string") return -1;
                if (typeof tb === "string") return 1;
                return 0;
            });

            return { ok: true, items };
        } catch (e) {
            if (e instanceof functions.https.HttpsError) {
                throw e;
            }
            const msg = (e && e.message) || String(e);
            console.error("painelEntregadoresAtualizacoesPendentes", e);
            if (
                /FAILED_PRECONDITION|index|requires an index|create_composite/i.test(
                    msg
                )
            ) {
                throw new functions.https.HttpsError(
                    "failed-precondition",
                    "Índice do Firestore ausente ou em construção para a " +
                        "busca de documentos. " +
                        "Implante as regras de índice (firebase deploy --only firestore:indexes) " +
                        "e aguarde o índice ativar, ou tente de novo em alguns minutos."
                );
            }
            throw new functions.https.HttpsError(
                "internal",
                "Falha ao listar atualizações: " + msg
            );
        }
    });
