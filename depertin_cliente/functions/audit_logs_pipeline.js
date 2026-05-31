"use strict";

/**
 * Alimenta audit_logs para o painel (tempo real via snapshots no Flutter web).
 * Triggers: pedidos, support_tickets, saques_solicitacoes, users (campos críticos).
 * Callable: app autenticado reporta eventos pontuais (erros, marcos).
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { registrarAuditLog } = require("./audit_log_helper");

const region = "us-central1";
const fs = functions.region(region).firestore;

const USUARIO_CAMPOS_AUDITORIA = new Set([
    "role",
    "entregador_status",
    "status_loja",
    "block_active",
    "block_type",
    "block_end_at",
    "block_reason",
    "painel_colaborador_nivel",
]);

function assinaturaValor(v) {
    if (v === undefined) return "__undef__";
    if (v === null) return "__null__";
    if (v && typeof v.toMillis === "function") return `ts:${v.toMillis()}`;
    if (typeof v === "object") return JSON.stringify(v);
    return String(v);
}

function diffCamposAuditoria(antes, depois) {
    const mud = {};
    for (const k of USUARIO_CAMPOS_AUDITORIA) {
        const a = antes[k];
        const b = depois[k];
        if (assinaturaValor(a) !== assinaturaValor(b)) {
            mud[k] = { de: a ?? null, para: b ?? null };
        }
    }
    return mud;
}

/** Novo pedido (inclui rascunho aguardando pagamento). */
exports.auditLogPedidoOnCreate = fs.document("pedidos/{pedidoId}").onCreate(
    async (snap, context) => {
        const db = admin.firestore();
        const p = snap.data() || {};
        try {
            await registrarAuditLog(db, {
                acao: "pedido_criado",
                categoria: "pedido",
                origem: "cloud_functions",
                detalhe: {
                    pedido_id: context.params.pedidoId,
                    status: p.status || null,
                    loja_id: p.loja_id || p.lojista_id || null,
                    cliente_id: p.cliente_id || null,
                    cliente_nome: p.cliente_nome || null,
                    loja_nome: p.loja_nome || null,
                    total: p.total != null ? Number(p.total) : null,
                    forma_pagamento: p.forma_pagamento || null,
                    tipo_entrega: p.tipo_entrega || null,
                    checkout_grupo_id: p.checkout_grupo_id || null,
                },
            });
        } catch (e) {
            console.warn("[audit_logs] pedido onCreate:", e.message || e);
        }
        return null;
    },
);

/** Transição de status do pedido. */
exports.auditLogPedidoOnUpdate = fs.document("pedidos/{pedidoId}").onUpdate(
    async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const sa = String(antes.status || "");
        const sd = String(depois.status || "").trim();
        if (!sd || sa === sd) return null;
        const db = admin.firestore();
        try {
            await registrarAuditLog(db, {
                acao: "pedido_status_alterado",
                categoria: "pedido",
                origem: "cloud_functions",
                detalhe: {
                    pedido_id: context.params.pedidoId,
                    status_anterior: sa || null,
                    status_novo: sd,
                    loja_id: depois.loja_id || depois.lojista_id || null,
                    cliente_id: depois.cliente_id || null,
                    entregador_id: depois.entregador_id || null,
                },
            });
        } catch (e) {
            console.warn("[audit_logs] pedido onUpdate:", e.message || e);
        }
        return null;
    },
);

exports.auditLogSupportTicketOnCreate = fs
    .document("support_tickets/{ticketId}")
    .onCreate(async (snap, context) => {
        const db = admin.firestore();
        const t = snap.data() || {};
        try {
            await registrarAuditLog(db, {
                acao: "suporte_ticket_criado",
                categoria: "suporte",
                origem: "cloud_functions",
                detalhe: {
                    ticket_id: context.params.ticketId,
                    status: t.status || null,
                    uid: t.user_uid || t.user_id || null,
                    categoria: t.categoria_suporte || null,
                },
            });
        } catch (e) {
            console.warn("[audit_logs] ticket onCreate:", e.message || e);
        }
        return null;
    });

exports.auditLogSupportTicketOnUpdate = fs
    .document("support_tickets/{ticketId}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const stA = String(antes.status || "");
        const stB = String(depois.status || "");
        const catA = String(antes.categoria_suporte || "");
        const catB = String(depois.categoria_suporte || "");
        if (stA === stB && catA === catB) return null;
        const db = admin.firestore();
        try {
            await registrarAuditLog(db, {
                acao: "suporte_ticket_atualizado",
                categoria: "suporte",
                origem: "cloud_functions",
                detalhe: {
                    ticket_id: context.params.ticketId,
                    status: { de: stA || null, para: stB || null },
                    categoria_suporte: { de: catA || null, para: catB || null },
                },
            });
        } catch (e) {
            console.warn("[audit_logs] ticket onUpdate:", e.message || e);
        }
        return null;
    });

exports.auditLogSaqueOnUpdate = fs
    .document("saques_solicitacoes/{id}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const sa = String(antes.status || "");
        const sd = String(depois.status || "");
        if (sa === sd) return null;
        const db = admin.firestore();
        try {
            await registrarAuditLog(db, {
                acao: "saque_status_alterado",
                categoria: "financeiro",
                origem: "cloud_functions",
                detalhe: {
                    solicitacao_id: context.params.id,
                    usuario_id: depois.user_id || depois.usuario_id || depois.uid || null,
                    status: { de: sa || null, para: sd || null },
                    valor: depois.valor != null ? Number(depois.valor) : null,
                },
            });
        } catch (e) {
            console.warn("[audit_logs] saque onUpdate:", e.message || e);
        }
        return null;
    });

exports.auditLogSaqueOnCreate = fs
    .document("saques_solicitacoes/{id}")
    .onCreate(async (snap, context) => {
        const db = admin.firestore();
        const s = snap.data() || {};
        try {
            await registrarAuditLog(db, {
                acao: "saque_solicitado",
                categoria: "financeiro",
                origem: "cloud_functions",
                detalhe: {
                    solicitacao_id: context.params.id,
                    usuario_id: s.user_id || s.usuario_id || s.uid || null,
                    valor: s.valor != null ? Number(s.valor) : null,
                    status: s.status || null,
                    tipo_usuario: s.tipo_usuario || null,
                },
            });
        } catch (e) {
            console.warn("[audit_logs] saque onCreate:", e.message || e);
        }
        return null;
    });

exports.auditLogUsuarioCriticoOnUpdate = fs
    .document("users/{uid}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const mud = diffCamposAuditoria(antes, depois);
        if (Object.keys(mud).length === 0) return null;
        const db = admin.firestore();
        const uid = context.params.uid;
        try {
            const email =
                depois.email ||
                depois.email_login ||
                antes.email ||
                null;
            await registrarAuditLog(db, {
                acao: "usuario_campo_critico_alterado",
                categoria: "conta",
                origem: "cloud_functions",
                atorUid: uid,
                atorEmail: email ? String(email) : null,
                detalhe: {
                    uid,
                    mudancas: mud,
                },
            });
        } catch (e) {
            console.warn("[audit_logs] users onUpdate:", e.message || e);
        }
        return null;
    });

exports.auditLogNotificacaoUsuarioItemOnCreate = fs
    .document("notificacoes_usuario/{uid}/items/{itemId}")
    .onCreate(async (snap, context) => {
        const db = admin.firestore();
        const uid = context.params.uid;
        const d = snap.data() || {};
        try {
            const titulo = String(d.titulo || "").trim();
            const corpo = String(d.corpo || "").trim();
            const tipoRaw = (
                d.tipo_notificacao || d.type || ""
            ).toString().trim();
            const dados = typeof d.dados === "object" && d.dados !== null
                ? d.dados
                : {};
            const keysDados = Object.keys(dados);
            await registrarAuditLog(db, {
                acao: "notificacao_fcm_registrada_no_app",
                categoria: "notificacao",
                origem: "cloud_functions",
                atorUid: uid,
                detalhe: {
                    usuario_destino_uid: uid,
                    item_id: context.params.itemId,
                    titulo: titulo || null,
                    corpo_preview: corpo.length > 200
                        ? corpo.slice(0, 200) + "…"
                        : corpo || null,
                    tipo_notificacao: tipoRaw || null,
                    segmento: String(d.segmento || "").trim() || null,
                    origem_pipeline: String(d.origem || "").trim() || null,
                    fcm_message_id: String(d.fcm_message_id || "").trim() || null,
                    lida: d.lida === true,
                    dados_chaves_amostra: keysDados.slice(0, 18),
                    dados_tamanho: keysDados.length,
                },
            });
        } catch (e) {
            console.warn(
                "[audit_logs] notificacoes_usuario item onCreate:",
                e.message || e,
            );
        }
        return null;
    });

const registrarEventoOpts = {
    region,
    enforceAppCheck: false,
};

/**
 * App / painel autenticados: registra marco ou erro (não substitui logs nativos do Cloud Logging).
 * Payload: { evento: string, detalhe?: object|string, plataforma?: string }
 */
exports.registrarEventoAuditoriaApp = onCall(registrarEventoOpts, async (request) => {
    if (!request.auth || !request.auth.uid) {
        throw new HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const raw = request.data || {};
    const evento = String(raw.evento || "").trim().slice(0, 120);
    if (evento.length < 2) {
        throw new HttpsError("invalid-argument", "Campo evento inválido.");
    }
    let categoriaCli = String(raw.categoria || "").trim().slice(0, 60);
    let categoria = categoriaCli;
    if (!categoria) {
        if (/login_sessao/i.test(evento)) categoria = "sessao";
        else if (/notificacao|notification/i.test(evento)) categoria = "notificacao";
        else if (/flutter_erro|erro_/i.test(evento)) categoria = "erro_app";
        else categoria = "app";
    }
    let detalhe = raw.detalhe;
    if (detalhe !== undefined && detalhe !== null) {
        const s = typeof detalhe === "string"
            ? detalhe
            : JSON.stringify(detalhe);
        if (s.length > 3500) {
            detalhe = { _truncado: true, texto: s.slice(0, 3500) };
        }
    }
    const plataforma = String(raw.plataforma || "app").slice(0, 32);

    let origemTipo = `app:${plataforma}`;
    if (plataforma === "painel_web") origemTipo = "painel_web";

    const db = admin.firestore();

    /** Enriquecer com papel no Firestore (cliente / lojista / entregador / staff). */
    let perfil = {};
    try {
        const udoc = await db.collection("users").doc(request.auth.uid).get();
        if (udoc.exists) {
            const udat = udoc.data() || {};
            perfil = {
                role: udat.role || udat.tipoUsuario || "",
                tipoUsuario: udat.tipoUsuario || "",
                cidade: String(udat.cidade || "").slice(0, 80),
            };
        }
    } catch (_) {
        /* ignore */
    }

    if (
        typeof detalhe === "object" &&
        detalhe !== null &&
        !Array.isArray(detalhe)
    ) {
        detalhe = Object.assign({}, detalhe, { perfilFirestore: perfil });
    } else {
        detalhe = {
            entrada: detalhe,
            perfilFirestore: perfil,
        };
    }

    let email = null;
    try {
        const u = await admin.auth().getUser(request.auth.uid);
        email = u.email || null;
    } catch {
        /* ignore */
    }
    try {
        await registrarAuditLog(db, {
            acao: evento,
            categoria,
            origem: origemTipo,
            atorUid: request.auth.uid,
            atorEmail: email,
            detalhe,
        });
    } catch (e) {
        console.error("[audit_logs] registrarEventoAuditoriaApp:", e);
        throw new HttpsError("internal", "Falha ao registrar evento.");
    }
    return { ok: true };
});
