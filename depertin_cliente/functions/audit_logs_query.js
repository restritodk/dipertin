"use strict";

/**
 * Callables para a tela de Auditoria do painel web (`depertin_web`).
 *
 * - auditLogsPesquisarUsuarios: busca em `users` por nome/CPF/CNPJ/email/telefone/uid.
 *   Retorna apenas resumo (sem saldo, sem chaves pix). Apenas staff.
 * - auditLogsListarEventos: query paginada de `audit_logs` com filtros server-side.
 *   Aplica mascaramento de CPF/CNPJ/email antes de retornar.
 * - auditLogsExportar: gera CSV (mascarado) no Storage e retorna URL temporária (24h).
 *   Apenas master.
 *
 * Hospedagem: mesma região do pipeline base (`us-central1`).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const region = "us-central1";
const callableOpts = { region, enforceAppCheck: false };

/** Mascaramento ------------------------------------------------------- */

function apenasDigitos(s) {
    if (s === null || s === undefined) return "";
    return String(s).replace(/\D+/g, "");
}

function mascararCpf(cpf) {
    const d = apenasDigitos(cpf);
    if (d.length !== 11) return cpf ? String(cpf) : null;
    return `${d.slice(0, 3)}.***.***-${d.slice(-2)}`;
}

function mascararCnpj(cnpj) {
    const d = apenasDigitos(cnpj);
    if (d.length !== 14) return cnpj ? String(cnpj) : null;
    return `${d.slice(0, 2)}.***.***/****-${d.slice(-2)}`;
}

function mascararDocumentoAuto(doc) {
    if (!doc) return null;
    const d = apenasDigitos(doc);
    if (d.length === 11) return mascararCpf(d);
    if (d.length === 14) return mascararCnpj(d);
    return String(doc);
}

function mascararEmail(email) {
    if (!email) return null;
    const s = String(email);
    const at = s.indexOf("@");
    if (at < 1) return s;
    const local = s.slice(0, at);
    const domain = s.slice(at);
    if (local.length <= 1) return `${local[0] || "?"}***${domain}`;
    return `${local[0]}***${domain}`;
}

function mascararTelefone(tel) {
    if (!tel) return null;
    const d = apenasDigitos(tel);
    if (d.length < 8) return String(tel);
    if (d.length === 11) {
        return `(${d.slice(0, 2)}) ${d[2]}****-${d.slice(-4)}`;
    }
    if (d.length === 10) {
        return `(${d.slice(0, 2)}) ****-${d.slice(-4)}`;
    }
    return `****-${d.slice(-4)}`;
}

/** Aplica mascaramento aos campos sensíveis de um user doc */
function sanitizarUserResumo(data) {
    if (!data) return null;
    return {
        uid: data.uid || null,
        nome: data.nome || data.displayName || null,
        email_mascarado: mascararEmail(data.email || null),
        documento_mascarado: mascararDocumentoAuto(data.cnpj || data.cpf || null),
        telefone_mascarado: mascararTelefone(data.telefone || null),
        role: data.role || data.tipoUsuario || null,
        cidade: data.cidade || null,
        criado_em: data.criado_em || null,
        loja_nome: data.loja_nome || data.nome_fantasia || null,
        status: data.entregador_status || data.status_cadastro || data.status_loja || null,
    };
}

/** Sanitiza um audit log para retorno (remove campos internos se houver) */
function sanitizarAuditLog(data) {
    if (!data) return null;
    return {
        id: data.id,
        acao: data.acao || null,
        categoria: data.categoria || null,
        origem: data.origem || null,
        criado_em: data.criado_em || null,
        ator_uid: data.ator_uid || null,
        // Email em claro: a auditoria é exclusiva para staff (master/master_city).
        // A regra do Firestore (`firestore.rules` -> match /audit_logs) garante que
        // apenas `isStaff()` lê esses dados. Não exibimos em outros módulos.
        ator_email: data.ator_email || null,
        ator_nome: data.ator_nome || null,
        ator_role: data.ator_role || null,
        ator_documento_mascarado: data.ator_documento_mascarado || null,
        ator_telefone_mascarado: data.ator_telefone_mascarado || null,
        modulo: data.modulo || (data.detalhe && data.detalhe.modulo) || null,
        tela: data.tela || (data.detalhe && data.detalhe.tela) || null,
        entity_type: data.entity_type || (data.detalhe && data.detalhe.entity_type) || null,
        entity_id: data.entity_id || (data.detalhe && data.detalhe.entity_id) || null,
        severidade: data.severidade || (data.detalhe && data.detalhe.severidade) || "info",
        resultado: data.resultado || (data.detalhe && data.detalhe.resultado) || "sucesso",
        codigo_erro: data.codigo_erro || (data.detalhe && data.detalhe.codigo_erro) || null,
        mensagem_erro: data.mensagem_erro || (data.detalhe && data.detalhe.mensagem_erro) || null,
        ip: data.ip || (data.detalhe && data.detalhe.ip) || null,
        user_agent: data.user_agent || (data.detalhe && data.detalhe.user_agent) || null,
        plataforma: data.plataforma || (data.detalhe && data.detalhe.plataforma) || null,
        diff: data.diff || (data.detalhe && data.detalhe.diff) || null,
        mudancas: data.mudancas || (data.detalhe && data.detalhe.mudancas) || null,
        // Resto do detalhe (sem campos sensíveis)
        detalhe_extras: (() => {
            if (!data.detalhe || typeof data.detalhe !== "object") return null;
            const blacklist = [
                "modulo", "tela", "entity_type", "entity_id",
                "severidade", "resultado", "codigo_erro", "mensagem_erro",
                "ip", "user_agent", "plataforma", "diff", "mudancas",
            ];
            const out = {};
            for (const k of Object.keys(data.detalhe)) {
                if (blacklist.includes(k)) continue;
                if (k.toLowerCase().includes("senha") || k.toLowerCase().includes("token")
                    || k.toLowerCase().includes("secret") || k.toLowerCase().includes("cartao")
                    || k.toLowerCase().includes("cvv") || k.toLowerCase().includes("certificado")) {
                    continue;
                }
                out[k] = data.detalhe[k];
            }
            return Object.keys(out).length > 0 ? out : null;
        })(),
    };
}

/** Verifica permissão staff ------------------------------------------- */

function assertStaff(context) {
    if (!context.auth || !context.auth.uid) {
        throw new HttpsError("unauthenticated", "Autenticação necessária.");
    }
    return context.auth.uid;
}

async function assertStaffAndRole(context) {
    const uid = assertStaff(context);
    const udoc = await admin.firestore().collection("users").doc(uid).get();
    if (!udoc.exists) {
        throw new HttpsError("not-found", "Usuário não encontrado.");
    }
    const role = String(udoc.data().role || udoc.data().tipoUsuario || "").toLowerCase();
    if (role !== "master" && role !== "master_city"
        && role !== "superadmin" && role !== "super_admin") {
        throw new HttpsError("permission-denied", "Acesso restrito a staff.");
    }
    return { uid, role, cidade: String(udoc.data().cidade || "").toLowerCase() };
}

async function assertMaster(context) {
    const { uid, role } = await assertStaffAndRole(context);
    if (role !== "master" && role !== "superadmin" && role !== "super_admin") {
        throw new HttpsError("permission-denied", "Apenas master.");
    }
    return uid;
}

/** 1) Pesquisar usuários (resumo) -------------------------------------- */

exports.auditLogsPesquisarUsuarios = onCall(callableOpts, async (request) => {
    const { uid, role, cidade } = await assertStaffAndRole(request);
    const termo = String((request.data && request.data.termo) || "").trim();
    const limite = Math.min(50, Math.max(1, Number((request.data && request.data.limite) || 20)));
    const categoria = String((request.data && request.data.categoria) || "").toLowerCase().trim();

    // Mapear categoria do ator para role de Firestore
    const roleFiltro = (() => {
        if (categoria === "cliente") return "cliente";
        if (categoria === "lojista") return "lojista";
        if (categoria === "entregador") return "entregador";
        if (categoria === "admin") return ["master", "master_city", "superadmin", "super_admin"];
        return null;
    })();

    const db = admin.firestore();
    let usersSnap;
    if (termo.length < 2) {
        // Sem termo: listar por role, ordenado por criado_em desc
        if (Array.isArray(roleFiltro)) {
            // Para admin: tentar listar master/master_city
            const snaps = await Promise.all(
                roleFiltro.map((r) => db.collection("users")
                    .where("role", "==", r).limit(limite).get())
            );
            const docs = [];
            snaps.forEach((s) => docs.push(...s.docs));
            docs.sort((a, b) => {
                const ta = a.data().criado_em || a.data().dataCadastro || null;
                const tb = b.data().criado_em || b.data().dataCadastro || null;
                if (!ta) return 1;
                if (!tb) return -1;
                return tb.toMillis() - ta.toMillis();
            });
            usersSnap = { docs: docs.slice(0, limite) };
        } else {
            usersSnap = await db.collection("users")
                .where("role", "==", roleFiltro || "cliente")
                .limit(limite)
                .get();
        }
    } else {
        // Busca por termo: usa 'in' em dígitos se for CPF/CNPJ; nome/email por
        // prefix-match limitado. Para simplificar, faz varredura por prefix
        // (limitada) e em paralelo consulta `users_cpf_index` (somente digits).
        const digits = apenasDigitos(termo);
        const results = new Map();
        // 1) uid exato
        if (termo.length >= 10) {
            const direct = await db.collection("users").doc(termo).get();
            if (direct.exists) {
                const d = direct.data();
                if (!Array.isArray(roleFiltro) || roleFiltro.includes(d.role)) {
                    results.set(direct.id, { id: direct.id, data: d });
                }
            }
        }
        // 2) email prefix
        const emailLike = termo.includes("@");
        if (emailLike) {
            const clean = termo.toLowerCase();
            const s = await db.collection("users")
                .where("email", ">=", clean)
                .where("email", "<=", clean + "")
                .limit(limite)
                .get();
            s.docs.forEach((d) => results.set(d.id, { id: d.id, data: d.data() }));
        } else {
            // 3) nome prefix
            const termoLower = termo.toLowerCase();
            let query = db.collection("users")
                .where("nome", ">=", termo)
                .where("nome", "<=", termo + "")
                .limit(limite);
            if (roleFiltro && !Array.isArray(roleFiltro)) {
                query = db.collection("users")
                    .where("role", "==", roleFiltro)
                    .where("nome", ">=", termo)
                    .where("nome", "<=", termo + "")
                    .limit(limite);
            }
            const s = await query.get();
            s.docs.forEach((d) => results.set(d.id, { id: d.id, data: d.data() }));
        }
        // 4) users_cpf_index (somente digits)
        if (digits.length >= 3) {
            try {
                const s = await db.collection("users_cpf_index")
                    .doc(digits).get();
                if (s.exists) {
                    const uidFromIndex = s.data().uid;
                    if (uidFromIndex) {
                        const userDoc = await db.collection("users").doc(uidFromIndex).get();
                        if (userDoc.exists) {
                            results.set(userDoc.id, { id: userDoc.id, data: userDoc.data() });
                        }
                    }
                }
            } catch (_) { /* ok */ }
        }
        // 5) telefone contém digits
        if (digits.length >= 4) {
            const s = await db.collection("users")
                .where("telefone", ">=", digits)
                .where("telefone", "<=", digits + "")
                .limit(limite)
                .get();
            s.docs.forEach((d) => results.set(d.id, { id: d.id, data: d.data() }));
        }
        usersSnap = { docs: Array.from(results.values()).slice(0, limite) };
    }

    const items = usersSnap.docs
        .map((d) => {
            const data = d.data();
            data.uid = d.id;
            return data;
        })
        // Filtrar por cidade se master_city
        .filter((d) => {
            if (role !== "master_city") return true;
            return (d.cidade || "").toLowerCase() === cidade;
        })
        // Filtrar por role (categoria)
        .filter((d) => {
            if (!roleFiltro) return true;
            const r = (d.role || "").toLowerCase();
            if (Array.isArray(roleFiltro)) return roleFiltro.includes(r);
            return r === roleFiltro;
        })
        .map((d) => sanitizarUserResumo(d))
        .filter(Boolean);

    return { items, total: items.length };
});

/** 2) Listar eventos com paginação por cursor ------------------------- */

exports.auditLogsListarEventos = onCall(callableOpts, async (request) => {
    const { role } = await assertStaffAndRole(request);
    const data = request.data || {};
    const filtros = data.filtros || {};
    const cursorDocId = data.cursorDocId || null;
    const direction = data.direction === "prev" ? "prev" : "next";
    const pageSize = Math.min(100, Math.max(1, Number(data.pageSize) || 25));
    const db = admin.firestore();

    let q = db.collection("audit_logs");
    // Filtros
    if (filtros.ator_uid) {
        q = q.where("ator_uid", "==", String(filtros.ator_uid));
    }
    if (filtros.categoria) {
        q = q.where("categoria", "==", String(filtros.categoria));
    }
    if (filtros.modulo) {
        q = q.where("modulo", "==", String(filtros.modulo));
    }
    if (filtros.resultado) {
        q = q.where("resultado", "==", String(filtros.resultado));
    }
    if (filtros.severidade) {
        q = q.where("detalhe.severidade", "==", String(filtros.severidade));
    }
    if (filtros.acao) {
        q = q.where("acao", "==", String(filtros.acao));
    }
    if (filtros.origem) {
        q = q.where("origem", "==", String(filtros.origem));
    }
    // Período
    if (filtros.data_inicio_ms) {
        const ts = admin.firestore.Timestamp.fromMillis(Number(filtros.data_inicio_ms));
        q = q.where("criado_em", ">=", ts);
    }
    if (filtros.data_fim_ms) {
        const ts = admin.firestore.Timestamp.fromMillis(Number(filtros.data_fim_ms));
        q = q.where("criado_em", "<=", ts);
    }
    // Ordernar e paginar
    q = q.orderBy("criado_em", "desc").orderBy(admin.firestore.FieldPath.documentId(), "desc");
    if (cursorDocId) {
        try {
            const cursor = await db.collection("audit_logs").doc(cursorDocId).get();
            if (cursor.exists) {
                if (direction === "prev") {
                    q = q.startAt(cursor);
                } else {
                    q = q.startAfter(cursor);
                }
            }
        } catch (_) { /* ignore cursor */ }
    }
    const snap = await q.limit(pageSize + 1).get();
    const hasMore = snap.size > pageSize;
    const rawItems = snap.docs.slice(0, pageSize).map((d) => {
        const data = d.data();
        data.id = d.id;
        return data; // sem sanitizar ainda
    });

    // ── Resolver dados de usuário onde faltam ─────────────────────
    const uidsParaBuscar = new Set();
    for (const item of rawItems) {
        if (item.ator_uid && (!item.ator_nome || !item.ator_email)) {
            uidsParaBuscar.add(item.ator_uid);
        }
    }
    const usuariosCache = {};
    if (uidsParaBuscar.size > 0) {
        const promises = [];
        for (const uid of uidsParaBuscar) {
            promises.push(
                db.collection("users").doc(uid).get().then((s) => {
                    if (s.exists) {
                        const d = s.data() || {};
                        usuariosCache[uid] = d;
                    }
                }).catch(() => { /* ignora falha */ })
            );
        }
        await Promise.all(promises);
    }

    function roleLabel(r) {
        const rl = (r || "").toLowerCase();
        if (rl === "master") return "Administrador Master";
        if (rl === "master_city") return "Administrador da Cidade";
        if (rl === "superadmin" || rl === "super_admin") return "Super Administrador";
        if (rl === "lojista") return "Lojista";
        if (rl === "entregador") return "Entregador";
        if (rl === "cliente") return "Cliente";
        return r || null;
    }

    function resolverNome(uid, dadosLog, dadosUser) {
        if (dadosLog) return dadosLog;
        if (dadosUser) {
            return dadosUser.nome || dadosUser.displayName || dadosUser.nome_fantasia || dadosUser.loja_nome || null;
        }
        return null;
    }

    function resolverEmail(uid, dadosLog, dadosUser) {
        if (dadosLog) return dadosLog;
        if (dadosUser) return dadosUser.email || null;
        return null;
    }

    function resolverRole(uid, dadosLog, dadosUser) {
        if (dadosLog) return dadosLog;
        if (dadosUser) return roleLabel(dadosUser.role || dadosUser.tipoUsuario);
        return null;
    }

    const items = rawItems.map((item) => {
        const userData = item.ator_uid ? usuariosCache[item.ator_uid] : null;
        // Preencher campos que faltam com dados resolvidos
        if (!item.ator_nome && userData) {
            item.ator_nome = resolverNome(item.ator_uid, null, userData);
        }
        if (!item.ator_email && userData) {
            item.ator_email = resolverEmail(item.ator_uid, null, userData);
        }
        if (!item.ator_role && userData) {
            item.ator_role = resolverRole(item.ator_uid, null, userData);
        }
        // Se não achou nome, marca como não identificado (nunca mostra UID como nome)
        if (!item.ator_nome && item.ator_uid) {
            item.ator_nome = null; // não inventar
        }
        // Preencher modulo/tela ausentes com fallback pela ação
        if (!item.modulo) {
            item.modulo = deduzirModulo(item.acao || "");
        }
        if (!item.tela) {
            item.tela = deduzirTela(item.acao || "");
        }
        return sanitizarAuditLog(item);
    });

    const lastDocId = items.length > 0 ? items[items.length - 1].id : null;
    const firstDocId = items.length > 0 ? items[0].id : null;
    return {
        items,
        hasMore,
        lastDocId,
        firstDocId,
        total_retornado: items.length,
    };
});

/** Deduz módulo a partir do código da ação (fallback para registros antigos) */
function deduzirModulo(acao) {
    if (acao.includes("pedido") || acao.includes("entrega") || acao.includes("encomenda")) return "Pedidos";
    if (acao.includes("login") || acao.includes("sessao") || acao.includes("logout")) return "Autenticação";
    if (acao.includes("cupom") || acao.includes("marketing")) return "Marketing";
    if (acao.includes("fiscal") || acao.includes("nfe")) return "Fiscal";
    if (acao.includes("assinatura") || acao.includes("plano")) return "Assinaturas";
    if (acao.includes("gateway") || acao.includes("estorno") || acao.includes("saque")) return "Financeiro";
    if (acao.includes("suporte") || acao.includes("ticket")) return "Suporte";
    if (acao.includes("auditoria") || acao.includes("exportacao")) return "Auditoria";
    if (acao.includes("usuario") || acao.includes("conta") || acao.includes("bloqueio")) return "Usuários";
    return null;
}

/** Deduz tela a partir do código da ação (fallback) */
function deduzirTela(acao) {
    if (acao.includes("login_sessao_painel")) return "Login do Painel Administrativo";
    if (acao.includes("login")) return "Autenticação";
    if (acao.includes("auditoria_acesso")) return "Auditoria do Sistema";
    if (acao.includes("auditoria_exportacao")) return "Auditoria do Sistema";
    if (acao.includes("pedido_criado")) return "Gestão de Pedidos";
    if (acao.includes("pedido_status")) return "Gestão de Pedidos";
    if (acao.includes("suporte_ticket")) return "Central de Atendimento";
    if (acao.includes("cupom")) return "Gerenciamento de Cupons";
    return null;
}

/** 3) Exportar CSV no Storage ----------------------------------------- */

exports.auditLogsExportar = onCall({ ...callableOpts, timeoutSeconds: 120, memory: "512MB" }, async (request) => {
    const uidMaster = await assertMaster(request);
    const data = request.data || {};
    const filtros = data.filtros || {};
    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    let q = db.collection("audit_logs");
    if (filtros.ator_uid) q = q.where("ator_uid", "==", String(filtros.ator_uid));
    if (filtros.categoria) q = q.where("categoria", "==", String(filtros.categoria));
    if (filtros.modulo) q = q.where("modulo", "==", String(filtros.modulo));
    if (filtros.resultado) q = q.where("resultado", "==", String(filtros.resultado));
    if (filtros.severidade) q = q.where("detalhe.severidade", "==", String(filtros.severidade));
    if (filtros.acao) q = q.where("acao", "==", String(filtros.acao));
    if (filtros.data_inicio_ms) {
        q = q.where("criado_em", ">=", admin.firestore.Timestamp.fromMillis(Number(filtros.data_inicio_ms)));
    }
    if (filtros.data_fim_ms) {
        q = q.where("criado_em", "<=", admin.firestore.Timestamp.fromMillis(Number(filtros.data_fim_ms)));
    }
    q = q.orderBy("criado_em", "desc").limit(5000); // limite seguro por export

    const snap = await q.get();
    const linhas = [];
    linhas.push([
        "id", "criado_em_iso", "acao", "categoria", "origem",
        "ator_uid", "ator_email_mascarado", "ator_nome", "ator_role",
        "modulo", "tela", "entity_type", "entity_id",
        "severidade", "resultado", "codigo_erro", "mensagem_erro",
        "ip", "user_agent", "plataforma",
    ].join(","));
    snap.docs.forEach((d) => {
        const item = sanitizarAuditLog(d.data());
        const criadoEmIso = item.criado_em && item.criado_em.toDate
            ? item.criado_em.toDate().toISOString()
            : "";
        const csv = [
            item.id,
            criadoEmIso,
            item.acao,
            item.categoria,
            item.origem,
            item.ator_uid,
            item.ator_email_mascarado,
            item.ator_nome,
            item.ator_role,
            item.modulo,
            item.tela,
            item.entity_type,
            item.entity_id,
            item.severidade,
            item.resultado,
            item.codigo_erro,
            item.mensagem_erro,
            item.ip,
            item.user_agent,
            item.plataforma,
        ].map((v) => {
            if (v === null || v === undefined) return "";
            const s = String(v).replace(/"/g, '""').replace(/[\r\n]+/g, " ");
            if (s.includes(",") || s.includes("\"")) return `"${s}"`;
            return s;
        }).join(",");
        linhas.push(csv);
    });
    const conteudo = linhas.join("\n");
    const dataStr = new Date().toISOString().replace(/[:.]/g, "-");
    const path = `auditoria_exports/${uidMaster}/${dataStr}.csv`;
    const file = bucket.file(path);
    await file.save(conteudo, {
        contentType: "text/csv; charset=utf-8",
        metadata: { metadata: { gerado_por_uid: uidMaster } },
    });
    const [url] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 24 * 60 * 60 * 1000, // 24h
    });
    return {
        ok: true,
        url,
        path,
        total_registros: snap.size,
        expira_em_iso: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    };
});

/** 4) Estatísticas para KPI cards ------------------------------------- */

exports.auditLogsEstatisticas = onCall(callableOpts, async (request) => {
    const { role, cidade } = await assertStaffAndRole(request);
    const data = request.data || {};
    const filtros = data.filtros || {};
    const db = admin.firestore();

    const inicio = filtros.data_inicio_ms
        ? admin.firestore.Timestamp.fromMillis(Number(filtros.data_inicio_ms))
        : admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const fim = filtros.data_fim_ms
        ? admin.firestore.Timestamp.fromMillis(Number(filtros.data_fim_ms))
        : admin.firestore.Timestamp.fromMillis(Date.now());

    let q = db.collection("audit_logs")
        .where("criado_em", ">=", inicio)
        .where("criado_em", "<=", fim);
    if (filtros.ator_uid) q = q.where("ator_uid", "==", String(filtros.ator_uid));
    if (filtros.categoria) q = q.where("categoria", "==", String(filtros.categoria));
    if (filtros.modulo) q = q.where("modulo", "==", String(filtros.modulo));

    const snap = await q.limit(2000).get();
    const kpi = {
        total: 0,
        hoje: 0,
        sucesso: 0,
        erro: 0,
        alerta: 0,
        info: 0,
        critica: 0,
        atencao: 0,
        tentativas_login: 0,
        usuarios_unicos: 0,
        administrativas: 0,
    };
    const inicioHoje = new Date();
    inicioHoje.setHours(0, 0, 0, 0);
    const usuariosSet = new Set();
    snap.docs.forEach((d) => {
        const data = d.data();
        kpi.total++;
        if (data.criado_em && data.criado_em.toMillis() >= inicioHoje.getTime()) kpi.hoje++;
        const cat = (data.categoria || "").toString();
        if (cat === "admin") kpi.administrativas++;
        const sev = data.severidade || (data.detalhe && data.detalhe.severidade) || "info";
        if (sev === "info") kpi.info++;
        else if (sev === "atencao") kpi.atencao++;
        else if (sev === "critica") kpi.critica++;
        const res = data.resultado || (data.detalhe && data.detalhe.resultado) || "sucesso";
        if (res === "sucesso") kpi.sucesso++;
        else if (res === "erro") kpi.erro++;
        else if (res === "alerta") kpi.alerta++;
        if (cat === "sessao" && String(data.acao || "").includes("login")) kpi.tentativas_login++;
        if (data.ator_uid) usuariosSet.add(data.ator_uid);
    });
    kpi.usuarios_unicos = usuariosSet.size;
    return kpi;
});
