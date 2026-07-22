"use strict";

/**
 * Triggers adicionais de auditoria — eventos críticos faltantes no pipeline base.
 *
 * Cobre: estornos, planos de assinatura, integração fiscal, gateway de pagamento,
 * cupons, exclusão de usuários, status de cadastro, status de encomenda.
 *
 * Padrão: usar `registrarAuditLog` do helper central, anexar diffs de
 * antes/depois e marcar severidade (`info` | `atencao` | `critica`).
 *
 * Hospedagem: mesmo `region` do pipeline principal (`us-central1`).
 */

const functions = require("firebase-functions/v1");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { registrarAuditLog, buscarDadosUsuario } = require("./audit_log_helper");

const region = "us-central1";
const fs = functions.region(region).firestore;
const v2 = require("firebase-functions/v2/https");

/** Helpers locais ------------------------------------------------------- */

const USUARIO_STATUS_CAMPOS = new Set([
    "entregador_status",
    "status_cadastro",
    "status_loja",
    "acesso_app_mobile",
]);

function assinaturaValor(v) {
    if (v === undefined) return "__undef__";
    if (v === null) return "__null__";
    if (v && typeof v.toMillis === "function") return `ts:${v.toMillis()}`;
    if (typeof v === "object") return JSON.stringify(v);
    return String(v);
}

function diffPorCampos(antes, depois, campos) {
    const mud = {};
    for (const k of campos) {
        const a = antes[k];
        const b = depois[k];
        if (assinaturaValor(a) !== assinaturaValor(b)) {
            mud[k] = { de: a ?? null, para: b ?? null };
        }
    }
    return mud;
}

function severidadeEstorno(valor) {
    const v = Number(valor || 0);
    return v > 100 ? "critica" : "atencao";
}

function ipUaFromRequest(req) {
    if (!req) return { ip: null, userAgent: null };
    const ip =
        (req.rawRequest && req.rawRequest.ip) ||
        (req.headers && (req.headers["x-forwarded-for"] || req.headers["fastly-client-ip"])) ||
        null;
    const userAgent =
        (req.headers && (req.headers["user-agent"] || req.headers["User-Agent"])) ||
        null;
    return {
        ip: ip ? String(ip).split(",")[0].trim() : null,
        userAgent: userAgent ? String(userAgent).slice(0, 300) : null,
    };
}

/** Estornos (cancelamentos/devoluções) ---------------------------------- */

exports.auditLogEstornoOnCreate = fs
    .document("estornos/{id}")
    .onCreate(async (snap, context) => {
        const d = snap.data() || {};
        const valor = Number(d.valor || 0);
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "estorno_registrado",
                categoria: "financeiro",
                origem: "cloud_functions",
                atorUid: d.operador_uid || d.atendente_uid || null,
                atorEmail: d.operador_email || null,
                detalhe: {
                    estorno_id: context.params.id,
                    loja_id: d.loja_id || null,
                    pedido_id: d.pedido_id || null,
                    cliente_id: d.cliente_id || null,
                    valor,
                    tipo_operacao: d.tipo_operacao || null,
                    motivo: d.motivo || null,
                    severidade: severidadeEstorno(valor),
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] estorno onCreate:", e.message || e);
        }
        return null;
    });

/** Planos de assinatura (upgrade/downgrade/cancelamento) ----------------- */

exports.auditLogPlanoAssinaturaOnUpdate = fs
    .document("assinaturas_clientes/{id}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const campos = [
            "plano_id",
            "status",
            "data_fim",
            "proximo_vencimento",
            "forma_pagamento",
            "modulos_ativos",
        ];
        const mud = diffPorCampos(antes, depois, campos);
        if (Object.keys(mud).length === 0) return null;
        try {
            const statusDowngrade =
                String(depois.status || "") === "cancelada" ||
                String(depois.status || "") === "suspensa" ||
                (antes.plano_id && depois.plano_id && antes.plano_id !== depois.plano_id);
            await registrarAuditLog(admin.firestore(), {
                acao: "assinatura_plano_alterado",
                categoria: "assinatura",
                origem: "cloud_functions",
                atorUid: depois.atualizado_por_uid || depois.cadastrado_por_uid || null,
                detalhe: {
                    assinatura_id: context.params.id,
                    loja_id: depois.store_id || depois.loja_id || null,
                    mudancas: mud,
                    severidade: statusDowngrade ? "critica" : "atencao",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] assinatura onUpdate:", e.message || e);
        }
        return null;
    });

exports.auditLogPlanoAssinaturaOnCreate = fs
    .document("assinaturas_clientes/{id}")
    .onCreate(async (snap, context) => {
        const d = snap.data() || {};
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "assinatura_plano_criada",
                categoria: "assinatura",
                origem: "cloud_functions",
                atorUid: d.cadastrado_por_uid || null,
                detalhe: {
                    assinatura_id: context.params.id,
                    loja_id: d.store_id || d.loja_id || null,
                    plano_id: d.plano_id || null,
                    status: d.status || null,
                    severidade: "info",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] assinatura onCreate:", e.message || e);
        }
        return null;
    });

/** Integração fiscal (token/certificado alterado) ----------------------- */

exports.auditLogFiscalIntegrationOnWrite = fs
    .document("fiscal_integrations/{id}")
    .onWrite(async (change, context) => {
        if (!change.after.exists) return null; // delete é tratado em outro lugar
        const antes = change.before.exists ? change.before.data() || {} : null;
        const depois = change.after.data() || {};
        if (!antes) {
            // criação
            try {
                await registrarAuditLog(admin.firestore(), {
                    acao: "fiscal_integracao_criada",
                    categoria: "fiscal",
                    origem: "cloud_functions",
                    detalhe: {
                        integration_id: context.params.id,
                        provedor: depois.provedor || null,
                        severidade: "critica",
                        resultado: "sucesso",
                    },
                });
            } catch (e) {
                console.warn("[audit_logs] fiscal integration onCreate:", e.message || e);
            }
            return null;
        }
        const mud = diffPorCampos(antes, depois, [
            "api_key",
            "api_token",
            "certificado_base64",
            "senha_certificado",
            "provedor",
            "ambiente",
        ]);
        if (Object.keys(mud).length === 0) return null;
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "fiscal_integracao_alterada",
                categoria: "fiscal",
                origem: "cloud_functions",
                detalhe: {
                    integration_id: context.params.id,
                    campos_alterados: Object.keys(mud),
                    severidade: "critica",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] fiscal integration onUpdate:", e.message || e);
        }
        return null;
    });

/** Gateway de pagamento (token alterado) -------------------------------- */

exports.auditLogGatewayPagamentoOnWrite = fs
    .document("gateways_pagamento/{id}")
    .onWrite(async (change, context) => {
        if (!change.after.exists) return null;
        const antes = change.before.exists ? change.before.data() || {} : null;
        const depois = change.after.data() || {};
        if (!antes) {
            try {
                await registrarAuditLog(admin.firestore(), {
                    acao: "gateway_pagamento_criado",
                    categoria: "financeiro",
                    origem: "cloud_functions",
                    detalhe: {
                        gateway_id: context.params.id,
                        tipo: depois.tipo || null,
                        severidade: "critica",
                        resultado: "sucesso",
                    },
                });
            } catch (e) {
                console.warn("[audit_logs] gateway onCreate:", e.message || e);
            }
            return null;
        }
        const mud = diffPorCampos(antes, depois, [
            "access_token",
            "public_key",
            "webhook_secret",
            "ativo",
        ]);
        if (Object.keys(mud).length === 0) return null;
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "gateway_pagamento_alterado",
                categoria: "financeiro",
                origem: "cloud_functions",
                detalhe: {
                    gateway_id: context.params.id,
                    campos_alterados: Object.keys(mud),
                    severidade: "critica",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] gateway onUpdate:", e.message || e);
        }
        return null;
    });

/** Cupons --------------------------------------------------------------- */

exports.auditLogCupomOnCreate = fs
    .document("cupons/{id}")
    .onCreate(async (snap, context) => {
        const d = snap.data() || {};
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "cupom_criado",
                categoria: "marketing",
                origem: "cloud_functions",
                atorUid: d.criado_por_uid || null,
                detalhe: {
                    cupom_id: context.params.id,
                    codigo: d.codigo || null,
                    loja_id: d.loja_id || null,
                    escopo: d.escopo || null,
                    severidade: "atencao",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] cupom onCreate:", e.message || e);
        }
        return null;
    });

exports.auditLogCupomOnUpdate = fs
    .document("cupons/{id}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const mud = diffPorCampos(antes, depois, [
            "ativo",
            "valor",
            "percentual",
            "validade",
            "usos_atual",
            "codigo",
        ]);
        if (Object.keys(mud).length === 0) return null;
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "cupom_alterado",
                categoria: "marketing",
                origem: "cloud_functions",
                atorUid: depois.atualizado_por_uid || null,
                detalhe: {
                    cupom_id: context.params.id,
                    codigo: depois.codigo || null,
                    loja_id: depois.loja_id || null,
                    mudancas: mud,
                    severidade: "atencao",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] cupom onUpdate:", e.message || e);
        }
        return null;
    });

exports.auditLogCupomOnDelete = fs
    .document("cupons/{id}")
    .onDelete(async (snap, context) => {
        const d = snap.data() || {};
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "cupom_excluido",
                categoria: "marketing",
                origem: "cloud_functions",
                detalhe: {
                    cupom_id: context.params.id,
                    codigo: d.codigo || null,
                    loja_id: d.loja_id || null,
                    severidade: "critica",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] cupom onDelete:", e.message || e);
        }
        return null;
    });

/** Exclusão de usuário -------------------------------------------------- */

exports.auditLogUserDeleted = fs
    .document("users/{uid}")
    .onDelete(async (snap, context) => {
        const d = snap.data() || {};
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "usuario_excluido",
                categoria: "conta",
                origem: "cloud_functions",
                atorUid: d.excluido_por_uid || null,
                detalhe: {
                    uid: context.params.uid,
                    nome: d.nome || d.displayName || null,
                    email: d.email || null,
                    role: d.role || d.tipoUsuario || null,
                    severidade: "critica",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] users onDelete:", e.message || e);
        }
        return null;
    });

/** Status de cadastro (entregador/lojista) ------------------------------ */

exports.auditLogUserStatusOnUpdate = fs
    .document("users/{uid}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const mud = diffPorCampos(antes, depois, Array.from(USUARIO_STATUS_CAMPOS));
        if (Object.keys(mud).length === 0) return null;
        const ehBloqueio =
            mud.block_active && mud.block_active.para === true;
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: ehBloqueio
                    ? "usuario_bloqueado"
                    : "usuario_status_cadastro_alterado",
                categoria: "conta",
                origem: "cloud_functions",
                atorUid: depois.atualizado_por_uid || context.params.uid,
                detalhe: {
                    uid: context.params.uid,
                    nome: depois.nome || antes.nome || null,
                    role: depois.role || antes.role || null,
                    mudancas: mud,
                    severidade: ehBloqueio ? "critica" : "atencao",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] users status onUpdate:", e.message || e);
        }
        return null;
    });

/** Encomendas - status de negociação ----------------------------------- */

exports.auditLogEncomendaStatusOnUpdate = fs
    .document("encomendas/{id}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};
        const sa = String(antes.status_negociacao || "");
        const sd = String(depois.status_negociacao || "");
        if (sa === sd) return null;
        try {
            await registrarAuditLog(admin.firestore(), {
                acao: "encomenda_status_alterado",
                categoria: "pedido",
                origem: "cloud_functions",
                atorUid: depois.ultimo_atendente_uid || depois.cliente_id || null,
                detalhe: {
                    encomenda_id: context.params.id,
                    cliente_id: depois.cliente_id || null,
                    loja_id: depois.loja_id || depois.lojista_id || null,
                    status_anterior: sa || null,
                    status_novo: sd,
                    severidade: sd.includes("cancelada") || sd.includes("recusada")
                        ? "atencao"
                        : "info",
                    resultado: "sucesso",
                },
            });
        } catch (e) {
            console.warn("[audit_logs] encomenda onUpdate:", e.message || e);
        }
        return null;
    });

/** Login/logout via callable (usado pelo app/painel) -------------------- */

const loginOpts = {
    region,
    enforceAppCheck: false,
};

exports.auditLogRegistrarLogin = onCall(loginOpts, async (request) => {
    if (!request.auth || !request.auth.uid) {
        throw new HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const raw = request.data || {};
    const tipo = String(raw.tipo || "login").slice(0, 30);
    const sucesso = raw.sucesso !== false;
    const origem = String(raw.origem || "app").slice(0, 32);
    const { ip, userAgent } = ipUaFromRequest(request);
    const db = admin.firestore();
    let perfil = {};
    try {
        const udoc = await db.collection("users").doc(request.auth.uid).get();
        if (udoc.exists) {
            const udat = udoc.data() || {};
            perfil = {
                role: udat.role || udat.tipoUsuario || "",
                nome: udat.nome || "",
                email: udat.email || "",
            };
        }
    } catch (_) { /* ignore */ }
    const roleLabel = (() => {
        const r = (perfil.role || "").toLowerCase();
        if (r === "master") return "Administrador Master";
        if (r === "master_city") return "Administrador da Cidade";
        if (r === "lojista") return "Lojista";
        if (r === "entregador") return "Entregador";
        if (r === "cliente") return "Cliente";
        return r || null;
    })();
    try {
        await registrarAuditLog(db, {
            acao: sucesso ? `${tipo}_sucesso` : `${tipo}_falha`,
            categoria: "sessao",
            origem: `app:${origem}`,
            atorUid: request.auth.uid,
            atorEmail: (perfil.email || null),
            atorNome: (perfil.nome || null),
            atorRole: roleLabel,
            detalhe: {
                uid: request.auth.uid,
                ip,
                user_agent: userAgent,
                plataforma: origem,
                severidade: sucesso ? "info" : "atencao",
                resultado: sucesso ? "sucesso" : "erro",
                codigo_erro: raw.codigo_erro || null,
                mensagem_erro: raw.mensagem_erro || null,
                perfil_snapshot: perfil,
            },
        });
    } catch (e) {
        console.error("[audit_logs] registrarLogin:", e);
        throw new HttpsError("internal", "Falha ao registrar login.");
    }
    return { ok: true };
});

/** Acesso à própria tela de auditoria (severidade crítica) ------------- */

exports.auditLogAcessoTelaAuditoria = onCall(loginOpts, async (request) => {
    if (!request.auth || !request.auth.uid) {
        throw new HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const { ip, userAgent } = ipUaFromRequest(request);
    const db = admin.firestore();
    // Resolver dados do caller para gravar com o log
    const perfil = await buscarDadosUsuario(db, request.auth.uid);
    const role = (perfil.role || "").toLowerCase();
    let perfilLabel = "Administrador";
    if (role === "master") perfilLabel = "Administrador Master";
    else if (role === "master_city") perfilLabel = "Administrador da Cidade";
    try {
        await registrarAuditLog(db, {
            acao: "auditoria_acesso",
            categoria: "admin",
            origem: "painel_web",
            atorUid: request.auth.uid,
            atorNome: perfil.nome || null,
            atorEmail: perfil.email || null,
            atorRole: perfilLabel,
            modulo: "Auditoria",
            tela: "Auditoria do Sistema",
            detalhe: {
                ip,
                user_agent: userAgent,
                severidade: "critica",
                resultado: "sucesso",
            },
        });
    } catch (e) {
        console.error("[audit_logs] auditoria_acesso:", e);
    }
    return { ok: true };
});

/** Exportação de auditoria (CSV) - log adicional crítica --------------- */

exports.auditLogExportacao = onCall(loginOpts, async (request) => {
    if (!request.auth || !request.auth.uid) {
        throw new HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const db = admin.firestore();
    const udoc = await db.collection("users").doc(request.auth.uid).get();
    if (!udoc.exists) {
        throw new HttpsError("not-found", "Usuário não encontrado.");
    }
    const role = String(udoc.data().role || udoc.data().tipoUsuario || "").toLowerCase();
    if (role !== "master" && role !== "superadmin" && role !== "super_admin") {
        throw new HttpsError("permission-denied", "Apenas master pode exportar.");
    }
    const raw = request.data || {};
    const { ip, userAgent } = ipUaFromRequest(request);
    try {
        await registrarAuditLog(db, {
            acao: "auditoria_exportacao",
            categoria: "admin",
            origem: "painel_web",
            atorUid: request.auth.uid,
            detalhe: {
                ip,
                user_agent: userAgent,
                formato: raw.formato || "csv",
                periodo: raw.periodo || null,
                categoria: raw.categoria || null,
                total_registros: raw.total_registros || null,
                severidade: "critica",
                resultado: "sucesso",
            },
        });
    } catch (e) {
        console.error("[audit_logs] auditoria_exportacao:", e);
    }
    return { ok: true };
});

/** TTL/purge de logs antigos (scheduled, executa diariamente) ----------- */

exports.auditLogPurgarAntigos = functions.pubsub
    .schedule("every day 05:00")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
        const db = admin.firestore();
        const ttlDias = 365;
        const limiteMs = Date.now() - ttlDias * 24 * 60 * 60 * 1000;
        const limiteTs = admin.firestore.Timestamp.fromMillis(limiteMs);
        const colRef = db.collection("audit_logs");
        let apagados = 0;
        let lastDoc = null;
        // Paginação em chunks para não estourar memória
        while (true) {
            let q = colRef
                .where("criado_em", "<", limiteTs)
                .orderBy("criado_em", "asc")
                .limit(400);
            if (lastDoc) q = q.startAfter(lastDoc);
            const snap = await q.get();
            if (snap.empty) break;
            const batch = db.batch();
            snap.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            apagados += snap.size;
            lastDoc = snap.docs[snap.docs.length - 1];
            if (snap.size < 400) break;
        }
        if (apagados > 0) {
            console.log(`[audit_logs] purge TTL ${ttlDias}d: ${apagados} removidos`);
        }
        return null;
    });
