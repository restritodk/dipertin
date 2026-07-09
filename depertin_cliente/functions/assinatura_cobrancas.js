"use strict";

/**
 * Cobranças de Assinaturas (Gestão de Assinaturas — painel admin).
 *
 * Coleção: `assinaturas_cobrancas/{id}`
 * Origem real dos dados: `assinaturas_clientes` (assinaturas contratadas).
 *
 * Callables v2 (região us-central1, apenas staff):
 * - adminGerarCobrancasAssinaturas  → gera/atualiza cobranças a partir das assinaturas
 * - adminCriarCobrancaAvulsa        → cria uma cobrança manual para uma assinatura
 * - adminAtualizarCobranca          → ações (marcar paga, cancelar, reembolsar, enviar, excluir, reabrir)
 *
 * Escrita nesta coleção é EXCLUSIVA do Admin SDK (rules: write=false).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const COLECAO = "assinaturas_cobrancas";
const COLECAO_ASSINATURAS = "assinaturas_clientes";
const COLECAO_BILLING_SETTINGS = "billing_settings";
const CONTADOR_REF = "contadores/assinaturas_cobrancas";

const STATUS_VALIDOS = [
    "em_aberto",
    "vencida",
    "paga",
    "cancelada",
    "reembolsada",
];

const MODULOS_VALIDOS = [
    "gestao_comercial",
    "pdv",
    "gestao_entregas",
    "financeiro",
    "marketing",
];

// ── helpers ───────────────────────────────────────────────

function isStaffRole(role) {
    const r = String(role || "").toLowerCase();
    return r === "master" || r === "master_city" || r === "staff";
}

async function assertCallerStaff(auth) {
    if (!auth) {
        throw new HttpsError("unauthenticated", "Autenticação necessária.");
    }
    const snap = await admin.firestore().collection("users").doc(auth.uid).get();
    if (!snap.exists) {
        throw new HttpsError("failed-precondition", "Perfil não encontrado.");
    }
    const d = snap.data() || {};
    const role = d.role || d.tipoUsuario || "";
    if (!isStaffRole(role)) {
        throw new HttpsError(
            "permission-denied",
            "Apenas administradores podem gerenciar cobranças.",
        );
    }
    return {
        uid: auth.uid,
        email: auth.token && auth.token.email ? String(auth.token.email) : "",
    };
}

function tsParaDate(v) {
    if (!v) return null;
    if (v instanceof admin.firestore.Timestamp) return v.toDate();
    if (v instanceof Date) return v;
    if (typeof v === "object" && typeof v._seconds === "number") {
        return new Date(v._seconds * 1000);
    }
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
}

function cicloDe(date) {
    const d = date || new Date();
    return `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}`;
}

/** Deriva o módulo da assinatura (default: Gestão Comercial). */
function derivarModulo(assinatura) {
    const alvo = `${assinatura.plan_name || ""} ${(assinatura.modulos_extras || []).join(" ")}`
        .toLowerCase();
    if (alvo.includes("pdv")) return "pdv";
    if (alvo.includes("entrega")) return "gestao_entregas";
    if (alvo.includes("financeiro")) return "financeiro";
    if (alvo.includes("marketing")) return "marketing";
    return "gestao_comercial";
}

function statusPorVencimento(vencimentoDate) {
    if (!vencimentoDate) return "em_aberto";
    const hoje = new Date();
    const h = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate());
    const v = new Date(
        vencimentoDate.getFullYear(),
        vencimentoDate.getMonth(),
        vencimentoDate.getDate(),
    );
    return v.getTime() < h.getTime() ? "vencida" : "em_aberto";
}

function baseCobrancaDeAssinatura(assinatura, assinaturaId) {
    return {
        assinatura_id: assinaturaId,
        store_id: assinatura.store_id || "",
        store_name: assinatura.store_name || "Loja",
        owner_name: assinatura.owner_name || "",
        email: assinatura.email || "",
        modulo: derivarModulo(assinatura),
        plan_name: assinatura.plan_name || "",
        valor: Number(assinatura.monthly_amount) || 0,
    };
}

// ── adminGerarCobrancasAssinaturas ────────────────────────

exports.adminGerarCobrancasAssinaturas = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 120 },
    async (request) => {
        await assertCallerStaff(request.auth);
        const db = admin.firestore();

        const assinaturasSnap = await db.collection(COLECAO_ASSINATURAS).get();

        let criadas = 0;
        let atualizadas = 0;

        for (const doc of assinaturasSnap.docs) {
            const a = doc.data() || {};
            const status = String(a.status || "");
            if (status === "cancelado" || status === "pagamento_pendente") continue;

            const base = baseCobrancaDeAssinatura(a, doc.id);
            if (base.valor <= 0) continue;

            const proxVenc = tsParaDate(a.next_billing_date);
            const ultPagto = tsParaDate(a.last_payment_date);

            const resultado = await _gerarParaAssinatura(db, doc.id, base, proxVenc, ultPagto);
            criadas += resultado.criadas;
            atualizadas += resultado.atualizadas;
        }

        return { ok: true, criadas, atualizadas };
    },
);

async function _gerarParaAssinatura(db, assinaturaId, base, proxVenc, ultPagto) {
    let criadas = 0;
    let atualizadas = 0;

    // Ciclo em aberto
    if (proxVenc) {
        const ciclo = cicloDe(proxVenc);
        const id = `${assinaturaId}_${ciclo}`;
        const ref = db.collection(COLECAO).doc(id);
        const r = await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const novoStatus = statusPorVencimento(proxVenc);
            if (snap.exists) {
                const d = snap.data() || {};
                // Não mexe em cobranças já pagas/canceladas/reembolsadas.
                if (["paga", "cancelada", "reembolsada"].includes(d.status)) {
                    return { criada: false, atualizada: false };
                }
                if (d.status !== novoStatus) {
                    tx.update(ref, {
                        status: novoStatus,
                        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    return { criada: false, atualizada: true };
                }
                return { criada: false, atualizada: false };
            }
            const contador = db.doc(CONTADOR_REF);
            const csnap = await tx.get(contador);
            const seq = (csnap.exists ? Number(csnap.data().ultimo_seq || 0) : 0) + 1;
            const numero = `#FAT-${proxVenc.getFullYear()}-${String(seq).padStart(6, "0")}`;
            tx.set(contador, {
                ultimo_seq: seq,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            tx.set(ref, {
                ...base,
                fatura: numero,
                fatura_seq: seq,
                ciclo,
                vencimento: admin.firestore.Timestamp.fromDate(proxVenc),
                status: novoStatus,
                origem: "assinatura",
                criado_em: admin.firestore.FieldValue.serverTimestamp(),
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                historico: [{
                    tipo: "geracao",
                    descricao: "Cobrança gerada a partir da assinatura.",
                    data_em: admin.firestore.Timestamp.now(),
                }],
            });
            return { criada: true, atualizada: false };
        });
        if (r.criada) criadas++;
        if (r.atualizada) atualizadas++;
    }

    // Ciclo pago (último pagamento) — só cria se não colidir com o ciclo em aberto.
    if (ultPagto) {
        const ciclo = cicloDe(ultPagto);
        const cicloAberto = proxVenc ? cicloDe(proxVenc) : null;
        if (ciclo !== cicloAberto) {
            const id = `${assinaturaId}_${ciclo}`;
            const ref = db.collection(COLECAO).doc(id);
            const r = await db.runTransaction(async (tx) => {
                const snap = await tx.get(ref);
                if (snap.exists) return { criada: false };
                const contador = db.doc(CONTADOR_REF);
                const csnap = await tx.get(contador);
                const seq = (csnap.exists ? Number(csnap.data().ultimo_seq || 0) : 0) + 1;
                const numero = `#FAT-${ultPagto.getFullYear()}-${String(seq).padStart(6, "0")}`;
                tx.set(contador, {
                    ultimo_seq: seq,
                    atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });

                tx.set(ref, {
                    ...base,
                    fatura: numero,
                    fatura_seq: seq,
                    ciclo,
                    vencimento: admin.firestore.Timestamp.fromDate(ultPagto),
                    status: "paga",
                    pago_em: admin.firestore.Timestamp.fromDate(ultPagto),
                    origem: "assinatura",
                    criado_em: admin.firestore.FieldValue.serverTimestamp(),
                    atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    historico: [{
                        tipo: "pagamento",
                        descricao: "Pagamento confirmado da assinatura.",
                        data_em: admin.firestore.Timestamp.fromDate(ultPagto),
                    }],
                });
                return { criada: true };
            });
            if (r.criada) criadas++;
        }
    }

    return { criadas, atualizadas };
}

// ── adminCriarCobrancaAvulsa ──────────────────────────────

exports.adminCriarCobrancaAvulsa = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        const adminInfo = await assertCallerStaff(request.auth);
        const db = admin.firestore();
        const data = request.data || {};

        const assinaturaId = String(data.assinaturaId || "").trim();
        if (!assinaturaId) {
            throw new HttpsError("invalid-argument", "Selecione a assinatura.");
        }

        const valor = Number(data.valor);
        if (!Number.isFinite(valor) || valor <= 0) {
            throw new HttpsError("invalid-argument", "Informe um valor válido.");
        }

        const vencimentoDate = tsParaDate(data.vencimento);
        if (!vencimentoDate) {
            throw new HttpsError("invalid-argument", "Informe a data de vencimento.");
        }

        let modulo = String(data.modulo || "").trim();

        const aSnap = await db.collection(COLECAO_ASSINATURAS).doc(assinaturaId).get();
        if (!aSnap.exists) {
            throw new HttpsError("not-found", "Assinatura não encontrada.");
        }
        const a = aSnap.data() || {};
        const base = baseCobrancaDeAssinatura(a, assinaturaId);
        if (!MODULOS_VALIDOS.includes(modulo)) modulo = base.modulo;

        const ref = db.collection(COLECAO).doc();
        const novoId = await db.runTransaction(async (tx) => {
            const contador = db.doc(CONTADOR_REF);
            const csnap = await tx.get(contador);
            const seq = (csnap.exists ? Number(csnap.data().ultimo_seq || 0) : 0) + 1;
            const numero = `#FAT-${vencimentoDate.getFullYear()}-${String(seq).padStart(6, "0")}`;
            tx.set(contador, {
                ultimo_seq: seq,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            tx.set(ref, {
                ...base,
                modulo,
                valor,
                fatura: numero,
                fatura_seq: seq,
                ciclo: cicloDe(vencimentoDate),
                vencimento: admin.firestore.Timestamp.fromDate(vencimentoDate),
                status: statusPorVencimento(vencimentoDate),
                origem: "manual",
                criado_por_uid: adminInfo.uid,
                criado_em: admin.firestore.FieldValue.serverTimestamp(),
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                historico: [{
                    tipo: "criacao",
                    descricao: "Cobrança criada manualmente pelo administrador.",
                    data_em: admin.firestore.Timestamp.now(),
                    por_uid: adminInfo.uid,
                }],
            });
            return ref.id;
        });

        return { ok: true, cobrancaId: novoId };
    },
);

// ── adminAtualizarCobranca ────────────────────────────────

exports.adminAtualizarCobranca = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        const adminInfo = await assertCallerStaff(request.auth);
        const db = admin.firestore();
        const data = request.data || {};

        const cobrancaId = String(data.cobrancaId || "").trim();
        const acao = String(data.acao || "").trim();
        if (!cobrancaId) {
            throw new HttpsError("invalid-argument", "cobrancaId é obrigatório.");
        }

        const ref = db.collection(COLECAO).doc(cobrancaId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new HttpsError("not-found", "Cobrança não encontrada.");
        }
        const c = snap.data() || {};
        const now = admin.firestore.Timestamp.now();

        function hist(tipo, descricao, extra) {
            return admin.firestore.FieldValue.arrayUnion({
                tipo,
                descricao,
                data_em: now,
                por_uid: adminInfo.uid,
                ...(extra || {}),
            });
        }

        let patch = { atualizado_em: now };

        switch (acao) {
            case "marcar_paga":
                if (c.status === "paga") {
                    throw new HttpsError("failed-precondition", "Cobrança já está paga.");
                }
                patch.status = "paga";
                patch.pago_em = now;
                patch.historico = hist("pagamento", "Marcada como paga pelo administrador.");
                break;

            case "reabrir": {
                const venc = tsParaDate(c.vencimento);
                patch.status = statusPorVencimento(venc);
                patch.pago_em = admin.firestore.FieldValue.delete();
                patch.historico = hist("reabertura", "Cobrança reaberta pelo administrador.");
                break;
            }

            case "cancelar":
                if (c.status === "cancelada") {
                    throw new HttpsError("failed-precondition", "Cobrança já cancelada.");
                }
                patch.status = "cancelada";
                patch.cancelado_em = now;
                patch.historico = hist("cancelamento", "Cobrança cancelada pelo administrador.");
                break;

            case "reembolsar":
                if (c.status !== "paga") {
                    throw new HttpsError(
                        "failed-precondition",
                        "Só é possível reembolsar cobranças pagas.",
                    );
                }
                patch.status = "reembolsada";
                patch.reembolsado_em = now;
                patch.historico = hist("reembolso", "Cobrança reembolsada pelo administrador.");
                break;

            case "registrar_envio": {
                const canal = String(data.canal || "email");
                const canalLabel = canal === "whatsapp"
                    ? "WhatsApp"
                    : (canal === "link" ? "Link de pagamento" : "E-mail");
                patch.ultimo_envio_em = now;
                patch.historico = hist("envio", `Cobrança enviada via ${canalLabel}.`, { canal });
                break;
            }

            case "segunda_via":
                patch.segunda_via_em = now;
                patch.historico = hist("segunda_via", "Segunda via gerada pelo administrador.");
                break;

            case "excluir":
                await ref.delete();
                await _audit(db, adminInfo, "assinatura_cobranca_excluida", cobrancaId, c);
                return { ok: true, excluida: true };

            default:
                throw new HttpsError("invalid-argument", "Ação inválida.");
        }

        await ref.update(patch);
        await _audit(db, adminInfo, `assinatura_cobranca_${acao}`, cobrancaId, c);

        return { ok: true, cobrancaId, status: patch.status || c.status };
    },
);

async function _audit(db, adminInfo, acao, cobrancaId, c) {
    try {
        await db.collection("audit_logs").add({
            acao,
            categoria: "assinaturas_cobrancas",
            origem: "callable",
            criado_em: admin.firestore.Timestamp.now(),
            ator_uid: adminInfo.uid,
            ator_email: adminInfo.email || null,
            detalhe: {
                cobranca_id: cobrancaId,
                store_id: c.store_id || "",
                fatura: c.fatura || "",
            },
        });
    } catch (e) {
        console.warn("[assinatura-cobrancas] audit log:", e.message);
    }
}

// ── adminEnviarReciboEmail (nova) ──────────────────────────

const smtp = require("./smtp_transport");

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function formatarDataPtBr(date) {
    if (!date) return "—";
    const d = date instanceof Date ? date : new Date(date);
    if (Number.isNaN(d.getTime())) return "—";
    return d.toLocaleDateString("pt-BR");
}

function formatarDataHoraPtBr(date) {
    if (!date) return "—";
    const d = date instanceof Date ? date : new Date(date);
    if (Number.isNaN(d.getTime())) return "—";
    return d.toLocaleString("pt-BR");
}

function formatarMoeda(valor) {
    const n = Number(valor) || 0;
    return n.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

function templateHtmlRecibo(dados) {
    const lojista = escapeHtml(dados.clienteNome || "Lojista");
    const email = escapeHtml(dados.clienteEmail || "");
    const fatura = escapeHtml(dados.fatura || "—");
    const plano = escapeHtml(dados.planoNome || "—");
    const modulo = escapeHtml(dados.modulo || "—");
    const valor = dados.valorExibicao || "—";
    const vencimento = escapeHtml(dados.vencimento || "—");
    const status = escapeHtml(dados.statusRotulo || "—");
    const dataEmissao = formatarDataHoraPtBr(dados.dataEmissao ? new Date(dados.dataEmissao) : new Date());
    const dataPagamento = dados.dataPagamento ? formatarDataPtBr(new Date(dados.dataPagamento)) : null;
    const formaPagamento = escapeHtml(dados.formaPagamento || "—");
    const reciboNumero = escapeHtml(dados.reciboNumero || fatura);
    const empresaNome = "DiPertin";
    const empresaSite = "www.dipertin.com.br";
    const empresaEmail = "contato@dipertin.com.br";
    const statusCor = status.toLowerCase().includes("pag") || status.toLowerCase().includes("pago")
        ? "#16A34A" : (status.toLowerCase().includes("venc") ? "#F04438" : "#FF8F00");

    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Recibo de Cobrança — DiPertin</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:600px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <!-- Header DiPertin -->
          <tr>
            <td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 55%,#7B1FA2 100%);padding:40px 32px 28px;text-align:center;">
              <p style="margin:0 0 4px;color:rgba(255,255,255,0.90);font-size:12px;font-weight:700;letter-spacing:2.5px;text-transform:uppercase;">DiPertin</p>
              <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:800;letter-spacing:-0.4px;">Gestão Comercial</h1>
              <p style="margin:18px 0 0;color:#ffffff;font-size:13px;font-weight:600;letter-spacing:0.5px;text-transform:uppercase;">Recibo de Cobrança</p>
            </td>
          </tr>
          <!-- Corpo -->
          <tr>
            <td style="padding:32px 32px 24px;">
              <p style="margin:0 0 20px;font-size:16px;line-height:1.55;">
                Olá, <strong style="color:#6A1B9A;">${lojista}</strong>!
              </p>
              <p style="margin:0 0 22px;font-size:14.5px;line-height:1.65;color:#555;">
                Segue em anexo o recibo da sua cobrança referente ao plano de assinatura do
                <strong>Gestão Comercial</strong>. Abaixo estão os detalhes completos:
              </p>

              <!-- Card Dados do Recibo -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Recibo</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Nº Recibo</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${reciboNumero}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Fatura</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${fatura}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Data de emissão</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${dataEmissao}</td></tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Card Plano Contratado -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Plano Contratado</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Plano</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${plano}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Módulo</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${modulo}</td></tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Card Financeiro -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Financeiro</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Valor</td><td style="padding:4px 0;font-size:18px;font-weight:800;color:#6A1B9A;">${valor}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Vencimento</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${vencimento}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Forma de pagamento</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${formaPagamento}</td></tr>`
    + (dataPagamento
        ? `<tr><td style="padding:4px 0;font-size:14px;color:#555;">Data do pagamento</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${dataPagamento}</td></tr>`
        : "")
    + `<tr><td style="padding:8px 0 0;font-size:14px;color:#555;">Status</td>
        <td style="padding:8px 0 0;"><span style="display:inline-block;padding:4px 12px;border-radius:8px;font-size:13px;font-weight:700;color:#ffffff;background:${statusCor};">${status}</span></td></tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Total destacado -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#f5f0ff;border-radius:14px;border:1px solid #e0d0f0;">
                <tr>
                  <td style="padding:20px;text-align:center;">
                    <p style="margin:0 0 4px;font-size:13px;font-weight:600;color:#6A1B9A;letter-spacing:0.5px;">TOTAL</p>
                    <p style="margin:0;font-size:28px;font-weight:800;color:#6A1B9A;letter-spacing:-0.5px;">${valor}</p>
                  </td>
                </tr>
              </table>

              <!-- Dados empresa emissora -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#f8f7fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:18px 20px;">
                    <p style="margin:0 0 10px;font-size:12px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Empresa Emissora</p>
                    <p style="margin:0 0 4px;font-size:13px;color:#555;"><strong>${empresaNome}</strong></p>
                    <p style="margin:0 0 4px;font-size:12px;color:#888;">${empresaSite}</p>
                    <p style="margin:0;font-size:12px;color:#888;">${empresaEmail}</p>
                  </td>
                </tr>
              </table>

              <p style="margin:0 0 4px;font-size:14px;line-height:1.55;color:#444;">
                O arquivo PDF com o recibo completo está anexado a este e-mail para sua conferência.
              </p>
              <p style="margin:0 0 4px;font-size:14px;line-height:1.55;color:#444;">
                Em caso de dúvidas, entre em contato com o suporte DiPertin.
              </p>
            </td>
          </tr>
          <!-- Rodapé -->
          <tr>
            <td style="padding:0 32px 32px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 22px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">
                Este e-mail foi enviado automaticamente pelo sistema DiPertin.<br/>
                Por favor, não responda a esta mensagem.<br/>
                <span style="color:#aaa;">&copy; ${new Date().getFullYear()} DiPertin — Gestão Comercial</span>
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

exports.assinaturaEnviarReciboEmail = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        const adminInfo = await assertCallerStaff(request.auth);
        const db = admin.firestore();
        const data = request.data || {};

        const cobrancaId = String(data.cobrancaId || "").trim();
        const clienteEmail = String(data.clienteEmail || "").trim();
        if (!cobrancaId) throw new HttpsError("invalid-argument", "cobrancaId é obrigatório.");
        if (!clienteEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clienteEmail)) {
            throw new HttpsError("invalid-argument", "E-mail do cliente inválido.");
        }

        const clienteNome = String(data.clienteNome || "Lojista").trim();
        const fatura = String(data.fatura || "—").trim();
        const planoNome = String(data.planoNome || "").trim();
        const modulo = String(data.modulo || "").trim();
        const valorExibicao = String(data.valorExibicao || "").trim();
        const vencimento = String(data.vencimento || "").trim();
        const statusRotulo = String(data.statusRotulo || "").trim();
        const formaPagamento = String(data.formaPagamento || "—").trim();
        const dataPagamento = data.dataPagamento || null;
        const dataEmissao = data.dataEmissao || new Date().toISOString();
        const reciboNumero = String(data.reciboNumero || fatura).trim();
        const pdfBase64 = String(data.pdfBase64 || "").trim();

        if (!pdfBase64) {
            throw new HttpsError("invalid-argument", "PDF do recibo não encontrado.");
        }

        const pdfBuffer = Buffer.from(pdfBase64, "base64");
        if (pdfBuffer.length === 0) {
            throw new HttpsError("invalid-argument", "PDF inválido.");
        }

        const now = admin.firestore.Timestamp.now();
        const subject = `Recibo de Cobrança — ${fatura} — DiPertin Gestão Comercial`;

        // Monta dados para o template
        const dadosTemplate = {
            clienteNome,
            clienteEmail,
            fatura,
            planoNome,
            modulo,
            valorExibicao,
            vencimento,
            statusRotulo,
            formaPagamento,
            dataPagamento,
            dataEmissao,
            reciboNumero,
        };

        // Envia e-mail via SMTP (naoresponder@dipertin.com.br)
        let emailResult;
        try {
            const transport = smtp.criarTransport("padrao");
            await transport.sendMail({
                from: smtp.from("padrao"),
                to: clienteEmail,
                subject,
                text: `Olá ${clienteNome},\n\nSegue em anexo o recibo da cobrança ${fatura}.\n\nValor: ${valorExibicao}\nVencimento: ${vencimento}\n\n— DiPertin Gestão Comercial`,
                html: templateHtmlRecibo(dadosTemplate),
                attachments: [{
                    filename: `recibo_${fatura.replace(/[^A-Za-z0-9]/g, "_")}.pdf`,
                    content: pdfBuffer,
                    contentType: "application/pdf",
                }],
            });
            emailResult = { ok: true };
        } catch (e) {
            console.warn("[assinatura-cobrancas] falha envio recibo e-mail:", e.message || e);
            emailResult = { ok: false, motivo: e.message || "smtp_erro" };
        }

        // Atualiza cobrança com histórico de emissão de recibo
        try {
            const ref = db.collection(COLECAO).doc(cobrancaId);
            const snap = await ref.get();
            if (snap.exists) {
                await ref.update({
                    ultimo_recibo_em: now,
                    atualizado_em: now,
                    historico: admin.firestore.FieldValue.arrayUnion({
                        tipo: "recibo_emitido",
                        descricao: "Recibo emitido e enviado por e-mail.",
                        data_em: now,
                        por_uid: adminInfo.uid,
                        por_email: adminInfo.email || null,
                        email_destino: clienteEmail,
                        email_ok: emailResult.ok === true,
                    }),
                });
            }
        } catch (e) {
            console.warn("[assinatura-cobrancas] erro ao atualizar histórico:", e.message);
        }

        // Auditoria
        try {
            await db.collection("audit_logs").add({
                acao: "assinatura_recibo_email_enviado",
                categoria: "assinaturas_cobrancas",
                origem: "callable",
                criado_em: now,
                ator_uid: adminInfo.uid,
                ator_email: adminInfo.email || null,
                detalhe: {
                    cobranca_id: cobrancaId,
                    fatura,
                    email_destino: clienteEmail,
                    email_ok: emailResult.ok === true,
                },
            });
        } catch (e) {
            console.warn("[assinatura-cobrancas] audit log recibo:", e.message);
        }

        if (!emailResult.ok) {
            throw new HttpsError("internal", "Falha ao enviar e-mail: " + (emailResult.motivo || "erro SMTP"));
        }

        return {
            ok: true,
            cobrancaId,
            fatura,
            emailDestino: clienteEmail,
        };
    },
);

// ── assinaturaEnviarCobrancaEmail ──────────────────────────

/**
 * Template HTML premium para e-mail de cobrança.
 * Inclui botão "Efetuar pagamento" apontando para o painel do lojista.
 * A rota /lojista/sua-loja/cobrancas será construída posteriormente.
 */
function templateHtmlCobranca(dados) {
    const lojista = escapeHtml(dados.clienteNome || "Lojista");
    const email = escapeHtml(dados.clienteEmail || "");
    const fatura = escapeHtml(dados.fatura || "—");
    const plano = escapeHtml(dados.planoNome || "—");
    const modulo = escapeHtml(dados.modulo || "—");
    const valor = dados.valorExibicao || "—";
    const vencimento = escapeHtml(dados.vencimento || "—");
    const status = escapeHtml(dados.statusRotulo || "—");
    const mensagem = dados.mensagemPersonalizada
        ? escapeHtml(dados.mensagemPersonalizada)
        : null;
    const statusCor = status.toLowerCase().includes("pag") || status.toLowerCase().includes("pago")
        ? "#16A34A" : (status.toLowerCase().includes("venc") ? "#F04438" : "#FF8F00");
    const empresaNome = "DiPertin";
    const empresaSite = "www.dipertin.com.br";
    const empresaEmail = "naoresponder@dipertin.com.br";

    // Rota para o painel do lojista — menu "Sua Loja" > Cobranças
    // TODO: Quando a rota /lojista/sua-loja/cobrancas for implementada,
    // substituir o href abaixo pela URL real do painel.
    const linkPagamento = "https://www.dipertin.com.br/sistema/#/lojista/sua-loja/cobrancas";

    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Cobrança — ${fatura} — DiPertin</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:600px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <!-- Header DiPertin -->
          <tr>
            <td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 55%,#7B1FA2 100%);padding:40px 32px 20px;text-align:center;">
              <p style="margin:0 0 2px;color:rgba(255,255,255,0.85);font-size:11px;font-weight:700;letter-spacing:3px;text-transform:uppercase;">DiPertin</p>
              <h1 style="margin:0;color:#ffffff;font-size:20px;font-weight:800;letter-spacing:-0.3px;">Gestão de Assinaturas</h1>
              <p style="margin:14px 0 0;color:#ffffff;font-size:13px;font-weight:600;letter-spacing:0.5px;text-transform:uppercase;">Cobrança</p>
            </td>
          </tr>
          <!-- Corpo -->
          <tr>
            <td style="padding:32px 32px 24px;">
              <p style="margin:0 0 20px;font-size:16px;line-height:1.55;">
                Olá, <strong style="color:#6A1B9A;">${lojista}</strong>!
              </p>
              <p style="margin:0 0 22px;font-size:14.5px;line-height:1.65;color:#555;">
                Sua cobrança do plano <strong>${plano}</strong> foi gerada. Veja os detalhes abaixo e efetue o pagamento até o vencimento para manter seus serviços ativos.
              </p>

              <!-- Card Fatura -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Fatura</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Nº Fatura</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${fatura}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Plano</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${plano}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Módulo</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${modulo}</td></tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Card Valores -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Valores</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Valor total</td><td style="padding:4px 0;font-size:18px;font-weight:800;color:#6A1B9A;">${valor}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Vencimento</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${vencimento}</td></tr>
                      <tr><td style="padding:8px 0 0;font-size:14px;color:#555;">Status</td>
                        <td style="padding:8px 0 0;"><span style="display:inline-block;padding:4px 12px;border-radius:8px;font-size:13px;font-weight:700;color:#ffffff;background:${statusCor};">${status}</span></td></tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Mensagem personalizada (opcional) -->
              ${mensagem ? `
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#fefcf5;border-radius:14px;border:1px solid #f0e8d0;">
                <tr>
                  <td style="padding:18px 20px;">
                    <p style="margin:0 0 8px;font-size:12px;font-weight:700;color:#b8860b;letter-spacing:0.3px;text-transform:uppercase;">Mensagem do Administrador</p>
                    <p style="margin:0;font-size:14px;line-height:1.55;color:#555;">${mensagem}</p>
                  </td>
                </tr>
              </table>
              ` : ""}

              <!-- Total destacado -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#f5f0ff;border-radius:14px;border:1px solid #e0d0f0;">
                <tr>
                  <td style="padding:20px;text-align:center;">
                    <p style="margin:0 0 4px;font-size:13px;font-weight:600;color:#6A1B9A;letter-spacing:0.5px;">VALOR A PAGAR</p>
                    <p style="margin:0;font-size:28px;font-weight:800;color:#6A1B9A;letter-spacing:-0.5px;">${valor}</p>
                  </td>
                </tr>
              </table>

              <!-- Botão Efetuar pagamento -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:24px 0;">
                <tr>
                  <td align="center">
                    <a href="${linkPagamento}" target="_blank"
                       style="display:inline-block;padding:16px 40px;border-radius:12px;
                              background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 100%);
                              color:#ffffff;font-size:16px;font-weight:700;text-decoration:none;
                              letter-spacing:0.3px;box-shadow:0 6px 20px rgba(106,27,154,0.35);">
                      Efetuar pagamento
                    </a>
                  </td>
                </tr>
              </table>

              <p style="margin:16px 0 4px;font-size:13px;line-height:1.5;color:#888;text-align:center;">
                Se o botão acima não funcionar, copie e cole o link abaixo no seu navegador:
              </p>
              <p style="margin:0 0 4px;font-size:12px;line-height:1.5;color:#aaa;text-align:center;word-break:break-all;">
                ${linkPagamento}
              </p>
            </td>
          </tr>
          <!-- Dados empresa emissora -->
          <tr>
            <td style="padding:0 32px 8px;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f8f7fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:18px 20px;">
                    <p style="margin:0 0 10px;font-size:12px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Empresa Emissora</p>
                    <p style="margin:0 0 4px;font-size:13px;color:#555;"><strong>${empresaNome}</strong></p>
                    <p style="margin:0 0 4px;font-size:12px;color:#888;">${empresaSite}</p>
                    <p style="margin:0;font-size:12px;color:#888;">${empresaEmail}</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <!-- Rodapé -->
          <tr>
            <td style="padding:0 32px 32px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:16px 0 20px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">
                Este e-mail foi enviado automaticamente pelo sistema DiPertin.<br/>
                Por favor, não responda a esta mensagem.<br/>
                Em caso de dúvidas, entre em contato com o suporte.<br/>
                <span style="color:#aaa;">&copy; ${new Date().getFullYear()} DiPertin — Gestão de Assinaturas</span>
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

exports.assinaturaEnviarCobrancaEmail = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        const adminInfo = await assertCallerStaff(request.auth);
        const db = admin.firestore();
        const data = request.data || {};

        const cobrancaId = String(data.cobrancaId || "").trim();
        const clienteEmail = String(data.clienteEmail || "").trim();
        if (!cobrancaId) throw new HttpsError("invalid-argument", "cobrancaId é obrigatório.");
        if (!clienteEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clienteEmail)) {
            throw new HttpsError("invalid-argument", "E-mail do cliente inválido.");
        }

        const clienteNome = String(data.clienteNome || "Lojista").trim();
        const fatura = String(data.fatura || "—").trim();
        const planoNome = String(data.planoNome || "").trim();
        const modulo = String(data.modulo || "").trim();
        const valorExibicao = String(data.valorExibicao || "").trim();
        const vencimento = String(data.vencimento || "").trim();
        const statusRotulo = String(data.statusRotulo || "").trim();
        const mensagemPersonalizada = String(data.mensagemPersonalizada || "").trim() || null;

        const now = admin.firestore.Timestamp.now();
        const subject = `Cobrança ${fatura} — DiPertin Gestão de Assinaturas`;

        // Monta dados para o template
        const dadosTemplate = {
            clienteNome,
            clienteEmail,
            fatura,
            planoNome,
            modulo,
            valorExibicao,
            vencimento,
            statusRotulo,
            mensagemPersonalizada,
        };

        // Envia e-mail via SMTP (naoresponder@dipertin.com.br)
        let emailResult;
        try {
            const transport = smtp.criarTransport("padrao");
            await transport.sendMail({
                from: smtp.from("padrao"),
                to: clienteEmail,
                subject,
                text: `Olá ${clienteNome},\n\nSua cobrança ${fatura} no valor de ${valorExibicao} vence em ${vencimento}.\n\nAcesse o painel DiPertin para efetuar o pagamento.\n\n— DiPertin Gestão de Assinaturas`,
                html: templateHtmlCobranca(dadosTemplate),
            });
            emailResult = { ok: true };
        } catch (e) {
            console.warn("[assinatura-cobrancas] falha envio e-mail cobranca:", e.message || e);
            emailResult = { ok: false, motivo: e.message || "smtp_erro" };
        }

        // Atualiza cobrança com histórico de envio
        try {
            const ref = db.collection(COLECAO).doc(cobrancaId);
            const snap = await ref.get();
            if (snap.exists) {
                await ref.update({
                    ultimo_envio_em: now,
                    atualizado_em: now,
                    historico: admin.firestore.FieldValue.arrayUnion({
                        tipo: "envio_cobranca",
                        descricao: "Cobrança enviada por e-mail.",
                        data_em: now,
                        por_uid: adminInfo.uid,
                        por_email: adminInfo.email || null,
                        email_destino: clienteEmail,
                        email_ok: emailResult.ok === true,
                    }),
                });
            }
        } catch (e) {
            console.warn("[assinatura-cobrancas] erro ao atualizar histórico de envio:", e.message);
        }

        // Auditoria
        try {
            await db.collection("audit_logs").add({
                acao: "assinatura_cobranca_email_enviado",
                categoria: "assinaturas_cobrancas",
                origem: "callable",
                criado_em: now,
                ator_uid: adminInfo.uid,
                ator_email: adminInfo.email || null,
                detalhe: {
                    cobranca_id: cobrancaId,
                    fatura,
                    email_destino: clienteEmail,
                    email_ok: emailResult.ok === true,
                },
            });
        } catch (e) {
            console.warn("[assinatura-cobrancas] audit log:", e.message);
        }

        if (!emailResult.ok) {
            throw new HttpsError("internal", "Falha ao enviar e-mail: " + (emailResult.motivo || "erro SMTP"));
        }

        return {
            ok: true,
            cobrancaId,
            fatura,
            emailDestino: clienteEmail,
        };
    },
);

// ── Templates HTML ──────────────────────────────────────────

function templateHtmlPagamentoConfirmado(dados) {
    const lojista = escapeHtml(dados.clienteNome || "Lojista");
    const fatura = escapeHtml(dados.fatura || "—");
    const plano = escapeHtml(dados.planoNome || "—");
    const modulo = escapeHtml(dados.modulo || "—");
    const valor = dados.valorExibicao || "—";
    const dataPagamento = escapeHtml(dados.dataPagamento || "—");
    const linkPagamento = "https://www.dipertin.com.br/sistema/#/lojista/sua-loja/cobrancas";
    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Pagamento Confirmado — ${fatura} — DiPertin</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:600px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <tr>
            <td style="background:linear-gradient(135deg,#16A34A 0%,#22C55E 100%);padding:40px 32px 20px;text-align:center;">
              <span style="display:inline-block;width:56px;height:56px;line-height:56px;border-radius:50%;background:rgba(255,255,255,0.2);font-size:28px;margin-bottom:12px;">&#10004;</span>
              <h1 style="margin:0;color:#ffffff;font-size:20px;font-weight:800;letter-spacing:-0.3px;">Pagamento Confirmado!</h1>
              <p style="margin:8px 0 0;color:rgba(255,255,255,0.9);font-size:13px;">Sua cobrança foi paga com sucesso.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:32px 32px 24px;">
              <p style="margin:0 0 20px;font-size:16px;line-height:1.55;">Olá, <strong style="color:#6A1B9A;">${lojista}</strong>!</p>
              <p style="margin:0 0 22px;font-size:14.5px;line-height:1.65;color:#555;">O pagamento da sua fatura foi confirmado. Confira os detalhes abaixo.</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Fatura</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Nº Fatura</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${fatura}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Plano</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${plano}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Módulo</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${modulo}</td></tr>
                    </table>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#16A34A;letter-spacing:0.3px;text-transform:uppercase;">Pagamento</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Valor pago</td><td style="padding:4px 0;font-size:18px;font-weight:800;color:#16A34A;">${valor}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Data do pagamento</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${dataPagamento}</td></tr>
                      <tr><td style="padding:8px 0 0;font-size:14px;color:#555;">Status</td>
                        <td style="padding:8px 0 0;"><span style="display:inline-block;padding:4px 12px;border-radius:8px;font-size:13px;font-weight:700;color:#ffffff;background:#16A34A;">Pagamento confirmado</span></td></tr>
                    </table>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#f5f0ff;border-radius:14px;border:1px solid #e0d0f0;">
                <tr>
                  <td style="padding:20px;text-align:center;">
                    <p style="margin:0 0 4px;font-size:13px;font-weight:600;color:#6A1B9A;letter-spacing:0.5px;">TOTAL PAGO</p>
                    <p style="margin:0;font-size:28px;font-weight:800;color:#16A34A;letter-spacing:-0.5px;">${valor}</p>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:24px 0;">
                <tr>
                  <td align="center">
                    <a href="${linkPagamento}" target="_blank"
                       style="display:inline-block;padding:16px 40px;border-radius:12px;
                              background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 100%);
                              color:#ffffff;font-size:16px;font-weight:700;text-decoration:none;
                              letter-spacing:0.3px;box-shadow:0 6px 20px rgba(106,27,154,0.35);">
                      Acessar painel
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 32px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 20px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">Este e-mail foi enviado automaticamente pelo sistema DiPertin.<br/>&copy; ${new Date().getFullYear()} DiPertin — Gestão de Assinaturas</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function templateHtmlCobrancaAtraso(dados) {
    const lojista = escapeHtml(dados.clienteNome || "Lojista");
    const fatura = escapeHtml(dados.fatura || "—");
    const plano = escapeHtml(dados.planoNome || "—");
    const modulo = escapeHtml(dados.modulo || "—");
    const valor = dados.valorExibicao || "—";
    const vencimento = escapeHtml(dados.vencimento || "—");
    const diasAtraso = dados.diasAtraso || "—";
    const linkPagamento = "https://www.dipertin.com.br/sistema/#/lojista/sua-loja/cobrancas";
    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Cobrança em Atraso — ${fatura} — DiPertin</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:600px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <tr>
            <td style="background:linear-gradient(135deg,#DC2626 0%,#F04438 100%);padding:40px 32px 20px;text-align:center;">
              <span style="display:inline-block;width:56px;height:56px;line-height:56px;border-radius:50%;background:rgba(255,255,255,0.2);font-size:28px;margin-bottom:12px;">&#9888;</span>
              <h1 style="margin:0;color:#ffffff;font-size:20px;font-weight:800;letter-spacing:-0.3px;">Cobrança em Atraso</h1>
              <p style="margin:8px 0 0;color:rgba(255,255,255,0.9);font-size:13px;">${diasAtraso} dia(s) após o vencimento.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:32px 32px 24px;">
              <p style="margin:0 0 20px;font-size:16px;line-height:1.55;">Olá, <strong style="color:#6A1B9A;">${lojista}</strong>!</p>
              <p style="margin:0 0 22px;font-size:14.5px;line-height:1.65;color:#555;">Identificamos que a sua fatura abaixo está vencida. Regularize o quanto antes para evitar a suspensão dos serviços.</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#fef2f2;border-radius:14px;border:1px solid #fecaca;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 14px;font-size:13px;font-weight:700;color:#DC2626;letter-spacing:0.3px;text-transform:uppercase;">Fatura Vencida</p>
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;width:120px;">Nº Fatura</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${fatura}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Plano</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${plano}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Módulo</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${modulo}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Valor</td><td style="padding:4px 0;font-size:18px;font-weight:800;color:#DC2626;">${valor}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Vencimento</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#1a1a2e;">${vencimento}</td></tr>
                      <tr><td style="padding:4px 0;font-size:14px;color:#555;">Dias em atraso</td><td style="padding:4px 0;font-size:14px;font-weight:700;color:#DC2626;">${diasAtraso} dia(s)</td></tr>
                    </table>
                  </td>
                </tr>
              </table>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:24px 0;">
                <tr>
                  <td align="center">
                    <a href="${linkPagamento}" target="_blank"
                       style="display:inline-block;padding:16px 40px;border-radius:12px;
                              background:linear-gradient(135deg,#DC2626 0%,#F04438 100%);
                              color:#ffffff;font-size:16px;font-weight:700;text-decoration:none;
                              letter-spacing:0.3px;box-shadow:0 6px 20px rgba(220,38,38,0.35);">
                      Efetuar pagamento
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 32px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 20px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">Este e-mail foi enviado automaticamente pelo sistema DiPertin.<br/>&copy; ${new Date().getFullYear()} DiPertin — Gestão de Assinaturas</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

// ── adminSalvarBillingSettings ──────────────────────────────

exports.adminSalvarBillingSettings = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 30 },
    async (request) => {
        await assertCallerStaff(request.auth);
        const db = admin.firestore();
        const data = request.data || {};
        const ref = db.collection(COLECAO_BILLING_SETTINGS).doc("global");
        const now = admin.firestore.Timestamp.now();

        const settings = {
            auto_cobranca_ativo: data.auto_cobranca_ativo === true,
            all_plans: data.all_plans !== false,
            selected_plan_ids: Array.isArray(data.selected_plan_ids) ? data.selected_plan_ids.map(String) : [],
            selected_plans_snapshot: Array.isArray(data.selected_plans_snapshot) ? data.selected_plans_snapshot.map((p) => ({
                id: String(p.id || ""),
                nome: String(p.nome || ""),
                valor: Number(p.valor) || 0,
                ativo: p.ativo !== false,
            })) : [],
            dia_geracao: Math.max(1, Math.min(28, Number(data.dia_geracao) || 1)),
            dias_antes_vencimento: Math.max(0, Number(data.dias_antes_vencimento) || 5),
            auto_enviar_email: data.auto_enviar_email !== false,
            remetente: String(data.remetente || "naoresponder@dipertin.com.br"),
            pagamento_confirmado_ativo: data.pagamento_confirmado_ativo === true,
            pagamento_confirmado_email: data.pagamento_confirmado_email !== false,
            atraso_ativo: data.atraso_ativo === true,
            atraso_regras: Array.isArray(data.atraso_regras) ? data.atraso_regras.map((r) => ({
                dias_apos_vencimento: Math.max(1, Number(r.dias_apos_vencimento) || 1),
                ativo: r.ativo !== false,
            })) : [],
            cobranca_template_ativo: data.cobranca_template_ativo !== false,
            pagamento_template_ativo: data.pagamento_template_ativo !== false,
            atraso_template_ativo: data.atraso_template_ativo !== false,
            updated_at: now,
            updated_by: String(data.updated_by || "unknown"),
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
        };

        await ref.set(settings, { merge: true });
        return { ok: true };
    },
);

// ── adminGerarCobrancasPorConfig ────────────────────────────

async function _gerarCobrancaUnica(db, assinatura, assinaturaId, settings) {
    const status = String(assinatura.status || "");
    if (status === "cancelado" || status === "pagamento_pendente") return null;
    const valor = Number(assinatura.monthly_amount) || 0;
    if (valor <= 0) return null;

    const base = baseCobrancaDeAssinatura(assinatura, assinaturaId);
    const modulo = derivarModulo(assinatura);

    // Se configurado para filtrar por módulo/plano
    const settingsAllPlans = settings.all_plans !== false;
    if (!settingsAllPlans) {
        const planIds = Array.isArray(settings.selected_plan_ids) ? settings.selected_plan_ids : [];
        if (planIds.length > 0 && !planIds.includes(assinaturaId) && !planIds.includes(String(assinatura.plano_id || ""))) {
            return null;
        }
    }

    // Gera data de vencimento para o mês atual
    const hoje = new Date();
    const dia = settings.dia_geracao || 1;
    const vencimentoDate = new Date(hoje.getFullYear(), hoje.getMonth(), dia);
    if (vencimentoDate.getTime() < hoje.getTime()) {
        // Se já passou, avança para o próximo mês
        vencimentoDate.setMonth(vencimentoDate.getMonth() + 1);
    }

    const ciclo = cicloDe(vencimentoDate);
    const id = `${assinaturaId}_${ciclo}`;
    const ref = db.collection(COLECAO).doc(id);

    return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (snap.exists) {
            // Já existe cobrança para este ciclo
            return null;
        }

        const contador = db.doc(CONTADOR_REF);
        const csnap = await tx.get(contador);
        const seq = (csnap.exists ? Number(csnap.data().ultimo_seq || 0) : 0) + 1;
        const numero = `#FAT-${vencimentoDate.getFullYear()}-${String(seq).padStart(6, "0")}`;
        tx.set(contador, {
            ultimo_seq: seq,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        const statusCobranca = dia === hoje.getDate() ? "em_aberto" : statusPorVencimento(vencimentoDate);

        tx.set(ref, {
            ...base,
            modulo,
            fatura: numero,
            fatura_seq: seq,
            ciclo,
            vencimento: admin.firestore.Timestamp.fromDate(vencimentoDate),
            status: statusCobranca,
            origem: "auto",
            criado_em: admin.firestore.FieldValue.serverTimestamp(),
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            historico: [{
                tipo: "geracao_auto",
                descricao: "Cobrança gerada automaticamente pelo sistema.",
                data_em: admin.firestore.Timestamp.now(),
            }],
        });

        return { cobrancaId: id, fatura: numero };
    });
}

exports.adminGerarCobrancasPorConfig = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 120 },
    async (request) => {
        await assertCallerStaff(request.auth);
        const db = admin.firestore();

        // Carrega configurações
        const configSnap = await db.collection(COLECAO_BILLING_SETTINGS).doc("global").get();
        if (!configSnap.exists) {
            throw new HttpsError("failed-precondition", "Configurações de cobrança não encontradas. Salve as configurações primeiro.");
        }
        const settings = configSnap.data() || {};
        if (settings.auto_cobranca_ativo !== true) {
            throw new HttpsError("failed-precondition", "Cobrança automática está desativada nas configurações.");
        }

        // Carrega assinaturas ativas
        const assinaturasSnap = await db.collection(COLECAO_ASSINATURAS).get();
        let criadas = 0;
        let erros = 0;

        for (const doc of assinaturasSnap.docs) {
            try {
                const a = doc.data() || {};
                const result = await _gerarCobrancaUnica(db, a, doc.id, settings);
                if (result) criadas++;
            } catch (e) {
                erros++;
                console.warn(`[assinatura-cobrancas] erro ao gerar cobrança para ${doc.id}:`, e.message);
            }
        }

        return { ok: true, criadas, erros, totalProcessadas: assinaturasSnap.size };
    },
);

// ── assinaturaCobrancaAutoScheduled ─────────────────────────

exports.assinaturaCobrancaAutoScheduled = onSchedule(
    { schedule: "0 8 * * *", timeZone: "America/Sao_Paulo", region: "us-central1", timeoutSeconds: 540 },
    async () => {
        const db = admin.firestore();

        // Carrega configurações
        const configSnap = await db.collection(COLECAO_BILLING_SETTINGS).doc("global").get();
        if (!configSnap.exists) {
            console.log("[assinatura-cobrancas-scheduled] Configurações não encontradas. Pulando execução.");
            return null;
        }
        const settings = configSnap.data() || {};
        if (settings.auto_cobranca_ativo !== true) {
            console.log("[assinatura-cobrancas-scheduled] Cobrança automática desativada. Pulando.");
            return null;
        }

        // Verifica se é o dia de geração
        const hoje = new Date();
        const diaHoje = hoje.getDate();
        const diaGeracao = Math.max(1, Math.min(28, Number(settings.dia_geracao) || 1));
        if (diaHoje !== diaGeracao) {
            console.log(`[assinatura-cobrancas-scheduled] Hoje é dia ${diaHoje}, geração configurada para dia ${diaGeracao}. Pulando.`);
            return null;
        }

        // Verifica se já rodou hoje (evita duplicidade em re-execução)
        const logRef = db.collection(COLECAO_BILLING_SETTINGS).doc("global");
        const logSnap = await logRef.get();
        const logData = logSnap.data() || {};
        const ultimaGeracao = logData.ultima_geracao_auto;
        if (ultimaGeracao) {
            const ultima = ultimaGeracao instanceof admin.firestore.Timestamp
                ? ultimaGeracao.toDate()
                : new Date(ultimaGeracao);
            if (ultima.getFullYear() === hoje.getFullYear() &&
                ultima.getMonth() === hoje.getMonth() &&
                ultima.getDate() === hoje.getDate()) {
                console.log("[assinatura-cobrancas-scheduled] Geração já executada hoje. Pulando.");
                return null;
            }
        }

        // Carrega assinaturas ativas e gera cobranças
        const assinaturasSnap = await db.collection(COLECAO_ASSINATURAS).get();
        let criadas = 0;
        let erros = 0;

        for (const doc of assinaturasSnap.docs) {
            try {
                const a = doc.data() || {};
                const result = await _gerarCobrancaUnica(db, a, doc.id, settings);
                if (result) criadas++;
            } catch (e) {
                erros++;
                console.warn(`[assinatura-cobrancas-scheduled] erro assinatura ${doc.id}:`, e.message);
            }
        }

        // Registrar execução
        try {
            await logRef.set({
                ultima_geracao_auto: admin.firestore.Timestamp.now(),
                ultimo_geracao_log: { criadas, erros, total: assinaturasSnap.size, em: admin.firestore.Timestamp.now() },
            }, { merge: true });
        } catch (e) {
            console.warn("[assinatura-cobrancas-scheduled] erro ao logar execução:", e.message);
        }

        console.log(`[assinatura-cobrancas-scheduled] Concluído: ${criadas} criadas, ${erros} erros, ${assinaturasSnap.size} processadas.`);
        return null;
    },
);

// ── adminEnviarEmailPagamentoConfirmado ─────────────────────

exports.adminEnviarEmailPagamentoConfirmado = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        const adminInfo = await assertCallerStaff(request.auth);
        const db = admin.firestore();
        const data = request.data || {};

        const cobrancaId = String(data.cobrancaId || "").trim();
        const clienteEmail = String(data.clienteEmail || "").trim();
        if (!cobrancaId) throw new HttpsError("invalid-argument", "cobrancaId é obrigatório.");
        if (!clienteEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clienteEmail)) {
            throw new HttpsError("invalid-argument", "E-mail do cliente inválido.");
        }

        const clienteNome = String(data.clienteNome || "Lojista").trim();
        const fatura = String(data.fatura || "—").trim();
        const planoNome = String(data.planoNome || "").trim();
        const modulo = String(data.modulo || "").trim();
        const valorExibicao = String(data.valorExibicao || "").trim();
        const dataPagamento = String(data.dataPagamento || "").trim();

        const now = admin.firestore.Timestamp.now();
        const subject = `Pagamento Confirmado — ${fatura} — DiPertin`;

        const dadosTemplate = { clienteNome, clienteEmail, fatura, planoNome, modulo, valorExibicao, dataPagamento };

        let emailResult;
        try {
            const transport = smtp.criarTransport("padrao");
            await transport.sendMail({
                from: smtp.from("padrao"),
                to: clienteEmail,
                subject,
                text: `Olá ${clienteNome},\n\nO pagamento da fatura ${fatura} no valor de ${valorExibicao} foi confirmado!\n\nAcesse o painel DiPertin para mais detalhes.\n\n— DiPertin Gestão de Assinaturas`,
                html: templateHtmlPagamentoConfirmado(dadosTemplate),
            });
            emailResult = { ok: true };
        } catch (e) {
            console.warn("[assinatura-cobrancas] falha envio pagamento confirmado:", e.message);
            emailResult = { ok: false, motivo: e.message || "smtp_erro" };
        }

        // Histórico
        try {
            const ref = db.collection(COLECAO).doc(cobrancaId);
            const snap = await ref.get();
            if (snap.exists) {
                await ref.update({
                    atualizado_em: now,
                    historico: admin.firestore.FieldValue.arrayUnion({
                        tipo: "pagamento_confirmado_email",
                        descricao: "E-mail de pagamento confirmado enviado.",
                        data_em: now,
                        por_uid: adminInfo.uid,
                        email_destino: clienteEmail,
                        email_ok: emailResult.ok === true,
                    }),
                });
            }
        } catch (e) {
            console.warn("[assinatura-cobrancas] erro histórico pagamento:", e.message);
        }

        // Auditoria
        try {
            await db.collection("audit_logs").add({
                acao: "assinatura_pagamento_confirmado_email_enviado",
                categoria: "assinaturas_cobrancas",
                origem: "callable",
                criado_em: now,
                ator_uid: adminInfo.uid,
                ator_email: adminInfo.email || null,
                detalhe: { cobranca_id: cobrancaId, fatura, email_destino: clienteEmail, email_ok: emailResult.ok === true },
            });
        } catch (e) {
            console.warn("[assinatura-cobrancas] audit log:", e.message);
        }

        if (!emailResult.ok) {
            throw new HttpsError("internal", "Falha ao enviar e-mail: " + (emailResult.motivo || "erro SMTP"));
        }

        return { ok: true, cobrancaId, fatura, emailDestino: clienteEmail };
    },
);

// ── adminEnviarEmailCobrancaAtraso ──────────────────────────

exports.adminEnviarEmailCobrancaAtraso = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        const adminInfo = await assertCallerStaff(request.auth);
        const db = admin.firestore();
        const data = request.data || {};

        const cobrancaId = String(data.cobrancaId || "").trim();
        const clienteEmail = String(data.clienteEmail || "").trim();
        if (!cobrancaId) throw new HttpsError("invalid-argument", "cobrancaId é obrigatório.");
        if (!clienteEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clienteEmail)) {
            throw new HttpsError("invalid-argument", "E-mail do cliente inválido.");
        }

        const clienteNome = String(data.clienteNome || "Lojista").trim();
        const fatura = String(data.fatura || "—").trim();
        const planoNome = String(data.planoNome || "").trim();
        const modulo = String(data.modulo || "").trim();
        const valorExibicao = String(data.valorExibicao || "").trim();
        const vencimento = String(data.vencimento || "").trim();
        const diasAtraso = String(data.diasAtraso || "1").trim();

        const now = admin.firestore.Timestamp.now();
        const subject = `Cobrança em Atraso — ${fatura} — DiPertin`;

        const dadosTemplate = { clienteNome, clienteEmail, fatura, planoNome, modulo, valorExibicao, vencimento, diasAtraso };

        let emailResult;
        try {
            const transport = smtp.criarTransport("padrao");
            await transport.sendMail({
                from: smtp.from("padrao"),
                to: clienteEmail,
                subject,
                text: `Olá ${clienteNome},\n\nA fatura ${fatura} no valor de ${valorExibicao} venceu há ${diasAtraso} dia(s). Regularize o quanto antes.\n\nAcesse o painel DiPertin para efetuar o pagamento.\n\n— DiPertin Gestão de Assinaturas`,
                html: templateHtmlCobrancaAtraso(dadosTemplate),
            });
            emailResult = { ok: true };
        } catch (e) {
            console.warn("[assinatura-cobrancas] falha envio atraso:", e.message);
            emailResult = { ok: false, motivo: e.message || "smtp_erro" };
        }

        try {
            const ref = db.collection(COLECAO).doc(cobrancaId);
            const snap = await ref.get();
            if (snap.exists) {
                await ref.update({
                    atualizado_em: now,
                    ultimo_aviso_atraso_em: now,
                    historico: admin.firestore.FieldValue.arrayUnion({
                        tipo: "aviso_atraso_email",
                        descricao: `Aviso de atraso (${diasAtraso} dia(s)) enviado por e-mail.`,
                        data_em: now,
                        por_uid: adminInfo.uid,
                        email_destino: clienteEmail,
                        email_ok: emailResult.ok === true,
                    }),
                });
            }
        } catch (e) {
            console.warn("[assinatura-cobrancas] erro histórico atraso:", e.message);
        }

        try {
            await db.collection("audit_logs").add({
                acao: "assinatura_aviso_atraso_email_enviado",
                categoria: "assinaturas_cobrancas",
                origem: "callable",
                criado_em: now,
                ator_uid: adminInfo.uid,
                ator_email: adminInfo.email || null,
                detalhe: { cobranca_id: cobrancaId, fatura, email_destino: clienteEmail, dias_atraso: Number(diasAtraso), email_ok: emailResult.ok === true },
            });
        } catch (e) {
            console.warn("[assinatura-cobrancas] audit log:", e.message);
        }

        if (!emailResult.ok) {
            throw new HttpsError("internal", "Falha ao enviar e-mail: " + (emailResult.motivo || "erro SMTP"));
        }

        return { ok: true, cobrancaId, fatura, emailDestino: clienteEmail };
    },
);

// ── assinaturaCobrancaAtrasoScheduled ───────────────────────

exports.assinaturaCobrancaAtrasoScheduled = onSchedule(
    { schedule: "0 9 * * *", timeZone: "America/Sao_Paulo", region: "us-central1", timeoutSeconds: 540 },
    async () => {
        const db = admin.firestore();

        // Carrega configurações
        const configSnap = await db.collection(COLECAO_BILLING_SETTINGS).doc("global").get();
        if (!configSnap.exists) {
            console.log("[assinatura-cobrancas-atraso-scheduled] Configurações não encontradas.");
            return null;
        }
        const settings = configSnap.data() || {};
        if (settings.atraso_ativo !== true) {
            console.log("[assinatura-cobrancas-atraso-scheduled] Aviso de atraso desativado.");
            return null;
        }

        const regras = Array.isArray(settings.atraso_regras) ? settings.atraso_regras : [];
        const regrasAtivas = regras.filter((r) => r.ativo !== false);
        if (regrasAtivas.length === 0) {
            console.log("[assinatura-cobrancas-atraso-scheduled] Nenhuma regra de atraso ativa.");
            return null;
        }

        const hoje = new Date();
        const h = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate());

        // Busca cobranças em aberto/vencidas
        const cobrancasSnap = await db.collection(COLECAO)
            .where("status", "in", ["em_aberto", "vencida"])
            .get();

        let enviados = 0;
        let ignorados = 0;

        for (const doc of cobrancasSnap.docs) {
            try {
                const c = doc.data() || {};
                const vencimento = c.vencimento instanceof admin.firestore.Timestamp
                    ? c.vencimento.toDate()
                    : null;
                if (!vencimento) continue;

                const v = new Date(vencimento.getFullYear(), vencimento.getMonth(), vencimento.getDate());
                const diffMs = h.getTime() - v.getTime();
                const diasAtraso = Math.floor(diffMs / (1000 * 60 * 60 * 24));
                if (diasAtraso <= 0) continue;

                // Verifica se alguma regra ativa corresponde a estes dias de atraso
                const regra = regrasAtivas.find((r) => r.dias_apos_vencimento === diasAtraso);
                if (!regra) continue;

                // Verifica se já enviou aviso hoje para esta cobrança
                const historico = c.historico || [];
                const jaEnviouHoje = historico.some((h) => {
                    if (h.tipo !== "aviso_atraso_email") return false;
                    if (!h.data_em) return false;
                    const dataEnv = h.data_em instanceof admin.firestore.Timestamp
                        ? h.data_em.toDate()
                        : new Date(h.data_em);
                    return dataEnv.getFullYear() === hoje.getFullYear() &&
                        dataEnv.getMonth() === hoje.getMonth() &&
                        dataEnv.getDate() === hoje.getDate();
                });
                if (jaEnviouHoje) {
                    ignorados++;
                    continue;
                }

                const clienteEmail = String(c.email || "").trim();
                if (!clienteEmail || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clienteEmail)) {
                    ignorados++;
                    continue;
                }

                const dadosTemplate = {
                    clienteNome: String(c.store_name || "Lojista"),
                    clienteEmail,
                    fatura: String(c.fatura || "—"),
                    planoNome: String(c.plan_name || ""),
                    modulo: String(c.modulo || ""),
                    valorExibicao: Number(c.valor || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" }),
                    vencimento: vencimento.toLocaleDateString("pt-BR"),
                    diasAtraso: String(diasAtraso),
                };

                try {
                    const transport = smtp.criarTransport("padrao");
                    await transport.sendMail({
                        from: smtp.from("padrao"),
                        to: clienteEmail,
                        subject: `Cobrança em Atraso — ${dadosTemplate.fatura} — DiPertin`,
                        html: templateHtmlCobrancaAtraso(dadosTemplate),
                    });

                    await doc.ref.update({
                        atualizado_em: admin.firestore.Timestamp.now(),
                        ultimo_aviso_atraso_em: admin.firestore.Timestamp.now(),
                        historico: admin.firestore.FieldValue.arrayUnion({
                            tipo: "aviso_atraso_email",
                            descricao: `Aviso de atraso (${diasAtraso} dia(s)) enviado automaticamente.`,
                            data_em: admin.firestore.Timestamp.now(),
                            origem: "scheduled",
                            email_destino: clienteEmail,
                            email_ok: true,
                        }),
                    });
                    enviados++;
                } catch (e) {
                    console.warn(`[assinatura-cobrancas-atraso] erro envio atraso ${doc.id}:`, e.message);
                    ignorados++;

                    await doc.ref.update({
                        historico: admin.firestore.FieldValue.arrayUnion({
                            tipo: "aviso_atraso_email",
                            descricao: `Tentativa de aviso de atraso (${diasAtraso} dia(s)) falhou.`,
                            data_em: admin.firestore.Timestamp.now(),
                            origem: "scheduled",
                            email_destino: clienteEmail,
                            email_ok: false,
                            erro: e.message,
                        }),
                    });
                }
            } catch (e) {
                console.warn(`[assinatura-cobrancas-atraso] erro geral ${doc.id}:`, e.message);
                ignorados++;
            }
        }

        console.log(`[assinatura-cobrancas-atraso-scheduled] Concluído: ${enviados} enviados, ${ignorados} ignorados.`);
        return null;
    },
);

void STATUS_VALIDOS;
