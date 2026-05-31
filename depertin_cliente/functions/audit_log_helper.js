"use strict";

/**
 * Grava eventos na coleção audit_logs (painel web → Centro de operações).
 * Somente Admin SDK / Cloud Functions (regra Firestore: write staff).
 */

const admin = require("firebase-admin");

const MAX_KEYS = 28;
const MAX_STRING = 900;

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {{
 *   acao: string,
 *   categoria?: string,
 *   origem?: string,
 *   detalhe?: unknown,
 *   atorUid?: string|null,
 *   atorEmail?: string|null,
 * }} payload
 */
async function registrarAuditLog(db, payload) {
    const acao = String(payload.acao || "evento").slice(0, 200);
    const origem = String(payload.origem || "cloud_functions").slice(0, 48);
    const categoria = String(payload.categoria || "sistema").slice(0, 60);
    const doc = {
        acao,
        origem,
        categoria,
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (payload.atorUid) doc.ator_uid = String(payload.atorUid);
    if (payload.atorEmail) doc.ator_email = String(payload.atorEmail).slice(0, 200);
    if (payload.detalhe !== undefined && payload.detalhe !== null) {
        doc.detalhe = sanitizarDetalheValor(payload.detalhe, 0);
    }
    await db.collection("audit_logs").add(doc);
}

function sanitizarDetalheValor(v, depth) {
    if (depth > 3) return "[…]";
    if (v === null || v === undefined) return null;
    if (typeof v === "boolean" || typeof v === "number") return v;
    if (typeof v === "string") return v.slice(0, MAX_STRING);
    if (v instanceof admin.firestore.Timestamp) {
        try {
            return v.toDate().toISOString();
        } catch {
            return String(v);
        }
    }
    if (Array.isArray(v)) {
        return v.slice(0, 16).map((x) => sanitizarDetalheValor(x, depth + 1));
    }
    if (typeof v === "object") {
        const o = {};
        const keys = Object.keys(v);
        for (let i = 0; i < keys.length && i < MAX_KEYS; i++) {
            const k = keys[i];
            o[String(k).slice(0, 64)] = sanitizarDetalheValor(v[k], depth + 1);
        }
        if (keys.length > MAX_KEYS) {
            o._omitido = `${keys.length - MAX_KEYS}`;
        }
        return o;
    }
    return String(v).slice(0, MAX_STRING);
}

module.exports = { registrarAuditLog, sanitizarDetalheValor };
