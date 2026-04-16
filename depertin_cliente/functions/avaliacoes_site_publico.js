/**
 * GET público — lista avaliações 4–5★ para depoimentos no site institucional.
 * Comentário opcional no app: textos curtos ou ausentes viram frase padrão.
 * Usa Admin SDK (ignora App Check do cliente web).
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

const MAX = 10;
/** Texto mínimo vindo do app; abaixo disso usamos texto padrão (comentário é opcional no app). */
const COMENTARIO_MIN = 3;
const FETCH_NOTA_ALTA = 120;
const FETCH_FALLBACK = 200;

const ALLOWED_ORIGINS = new Set([
    "https://www.dipertin.com.br",
    "https://dipertin.com.br",
    "https://depertin-f940f.web.app",
    "http://localhost:5500",
    "http://127.0.0.1:5500",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
]);

function corsHeaders(origin) {
    const o = origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://www.dipertin.com.br";
    return {
        "Access-Control-Allow-Origin": o,
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Max-Age": "3600",
        "Content-Type": "application/json; charset=utf-8",
    };
}

function tsMillis(data) {
    if (!data) return 0;
    if (typeof data.toMillis === "function") return data.toMillis();
    if (data._seconds != null) return data._seconds * 1000;
    if (data.seconds != null) return data.seconds * 1000;
    return 0;
}

function docValido(d) {
    if (!d || !d.cliente_id || String(d.cliente_id).trim() === "") return false;
    const n = Number(d.nota);
    if (isNaN(n)) return false;
    const nr = Math.round(n);
    // Site: depoimentos "positivos" — 4 ou 5 estrelas (mesma escala inteira do app).
    if (nr < 4 || nr > 5) return false;
    return true;
}

function textoComentarioOuPadrao(d, nr) {
    let c = d.comentario != null ? String(d.comentario).trim() : "";
    if (c.length >= COMENTARIO_MIN) return c.slice(0, 800);
    if (nr === 5) return "Cliente avaliou com 5 estrelas no app DiPertin.";
    if (nr === 4) return "Cliente avaliou com 4 estrelas no app DiPertin.";
    return "";
}

function montarLista(docs) {
    const rows = [];
    docs.forEach((doc) => {
        const d = doc.data();
        if (!docValido(d)) return;
        const nr = Math.round(Number(d.nota));
        const comentario = textoComentarioOuPadrao(d, nr);
        if (!comentario) return;
        rows.push({
            dataMs: tsMillis(d.data),
            nota: nr,
            comentario,
            cliente_nome_exibicao:
                (d.cliente_nome_exibicao && String(d.cliente_nome_exibicao).trim().slice(0, 120)) || "",
            cliente_id: String(d.cliente_id).trim(),
        });
    });
    rows.sort((a, b) => b.dataMs - a.dataMs);
    return rows.slice(0, MAX);
}

/** Firestore getAll aceita no máx. 10 refs por chamada. */
async function enriquecerFotosClientes(db, rows) {
    const ids = [...new Set(rows.map((r) => r.cliente_id).filter(Boolean))];
    const map = new Map();
    const chunk = 10;
    for (let i = 0; i < ids.length; i += chunk) {
        const slice = ids.slice(i, i + chunk);
        const refs = slice.map((id) => db.collection("users").doc(id));
        const snaps = await db.getAll(...refs);
        snaps.forEach((s) => {
            if (!s.exists) return;
            const fp = s.data().foto_perfil;
            const u = fp != null ? String(fp).trim() : "";
            if (u.startsWith("https://")) {
                map.set(s.id, u.slice(0, 2000));
            }
        });
    }
    return rows.map((r) => {
        const { cliente_id: cid, ...pub } = r;
        const url = cid && map.has(cid) ? map.get(cid) : "";
        return { ...pub, cliente_foto_url: url || "" };
    });
}

exports.avaliacoesSitePublicas = functions.https.onRequest(async (req, res) => {
    const origin = req.get("Origin") || "";

    if (req.method === "OPTIONS") {
        res.set(corsHeaders(origin));
        return res.status(204).send("");
    }

    if (req.method !== "GET") {
        res.set(corsHeaders(origin));
        return res.status(405).json({ ok: false, error: "method" });
    }

    res.set(corsHeaders(origin));

    try {
        const db = admin.firestore();
        let snap = await db
            .collection("avaliacoes")
            .where("nota", "in", [4, 5])
            .limit(FETCH_NOTA_ALTA)
            .get();
        let avaliacoes = montarLista(snap.docs);
        if (avaliacoes.length === 0) {
            snap = await db.collection("avaliacoes").limit(FETCH_FALLBACK).get();
            avaliacoes = montarLista(snap.docs);
        }
        avaliacoes = await enriquecerFotosClientes(db, avaliacoes);
        return res.status(200).json({ ok: true, avaliacoes });
    } catch (e) {
        console.error("[avaliacoesSitePublicas]", e);
        return res.status(500).json({ ok: false, error: "server" });
    }
});
