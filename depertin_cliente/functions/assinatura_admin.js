"use strict";

/**
 * Admin — cancelamento de plano de assinatura (Gestão Comercial).
 *
 * Callable v2: adminCancelarPlanoAssinatura
 * - Apenas staff (master / master_city / staff)
 * - Atualiza assinaturas_clientes → status cancelado
 * - Registra histórico completo
 * - Envia e-mail premium ao lojista
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const smtp = require("./smtp_transport");

const URL_CONTRATAR_PLANO =
    "https://www.dipertin.com.br/sistema/#/comercial_dashboard";

const MOTIVOS = {
    solicitacao_lojista: "Solicitação do lojista",
    falta_pagamento: "Falta de pagamento",
    uso_indevido: "Uso indevido do sistema",
    troca_plano: "Troca de plano",
    encerramento_loja: "Encerramento da loja",
    problemas_cadastrais: "Problemas cadastrais",
    decisao_administrativa: "Decisão administrativa",
    outro: "Outro motivo",
};

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
    const dd = String(d.getDate()).padStart(2, "0");
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    const yyyy = d.getFullYear();
    return dd + "/" + mm + "/" + yyyy;
}

function formatarMoeda(valor) {
    const n = Number(valor) || 0;
    return n.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

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
            "Apenas administradores podem cancelar planos.",
        );
    }
    return {
        uid: auth.uid,
        email: auth.token && auth.token.email ? String(auth.token.email) : "",
        nome: d.nome || d.nome_completo || d.displayName || "",
    };
}

function resolverMotivoTexto(codigo, outroTexto) {
    const c = String(codigo || "").trim();
    if (!c || !Object.prototype.hasOwnProperty.call(MOTIVOS, c)) {
        throw new HttpsError("invalid-argument", "Motivo do cancelamento inválido.");
    }
    if (c === "outro") {
        const t = String(outroTexto || "").trim();
        if (t.length < 3) {
            throw new HttpsError(
                "invalid-argument",
                "Informe o motivo manualmente (mínimo 3 caracteres).",
            );
        }
        if (t.length > 500) {
            throw new HttpsError(
                "invalid-argument",
                "Motivo manual muito longo (máx. 500 caracteres).",
            );
        }
        return t;
    }
    return MOTIVOS[c];
}

function templateHtmlCancelamento(dados) {
    const loja = escapeHtml(dados.lojaNome || "Sua loja");
    const plano = escapeHtml(dados.planName || "—");
    const dataCancel = escapeHtml(dados.dataCancelamento || "—");
    const motivo = escapeHtml(dados.motivoTexto || "—");
    const url = escapeHtml(dados.urlContratar || URL_CONTRATAR_PLANO);

    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Plano cancelado — DiPertin</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <tr>
            <td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 55%,#7B1FA2 100%);padding:36px 28px;text-align:center;">
              <p style="margin:0 0 6px;color:rgba(255,255,255,0.92);font-size:13px;font-weight:600;letter-spacing:2px;text-transform:uppercase;">DiPertin</p>
              <h1 style="margin:0;color:#ffffff;font-size:24px;font-weight:800;letter-spacing:-0.5px;line-height:1.25;">Gestão Comercial</h1>
              <p style="margin:14px 0 0;color:rgba(255,255,255,0.95);font-size:15px;line-height:1.45;">Seu plano foi cancelado</p>
            </td>
          </tr>
          <tr>
            <td style="padding:36px 32px 28px;">
              <p style="margin:0 0 18px;font-size:16px;line-height:1.55;color:#1a1a2e;">
                Olá, <strong style="color:#6A1B9A;">${loja}</strong>!
              </p>
              <p style="margin:0 0 18px;font-size:15px;line-height:1.65;color:#444;">
                Informamos que o plano <strong style="color:#FF8F00;">${plano}</strong> do módulo
                <strong>Gestão Comercial</strong> foi cancelado em <strong>${dataCancel}</strong>.
              </p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:24px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 12px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">Detalhes</p>
                    <p style="margin:0 0 8px;font-size:14px;line-height:1.55;color:#333;"><strong>Plano:</strong> ${plano}</p>
                    <p style="margin:0 0 8px;font-size:14px;line-height:1.55;color:#333;"><strong>Data do cancelamento:</strong> ${dataCancel}</p>
                    <p style="margin:0;font-size:14px;line-height:1.55;color:#333;"><strong>Motivo:</strong> ${motivo}</p>
                  </td>
                </tr>
              </table>
              <p style="margin:0 0 18px;font-size:15px;line-height:1.65;color:#444;">
                O acesso ao <strong>Gestão Comercial</strong> (PDV, crediário, relatórios e demais ferramentas do módulo)
                foi encerrado. Seus pedidos, cardápio e demais funcionalidades do marketplace DiPertin continuam normais.
              </p>
              <p style="margin:0 0 24px;font-size:15px;line-height:1.65;color:#444;">
                Caso deseje voltar a usar o Gestão Comercial, você pode contratar um novo plano a qualquer momento.
              </p>
              <table role="presentation" cellspacing="0" cellpadding="0" align="center">
                <tr>
                  <td style="border-radius:12px;background:linear-gradient(135deg,#6A1B9A,#8E24AA);">
                    <a href="${url}" target="_blank" rel="noopener noreferrer"
                       style="display:inline-block;padding:14px 32px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;letter-spacing:0.2px;">
                      Contratar novo plano
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 32px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 22px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">
                Este é um e-mail automático. Por favor, não responda a esta mensagem.<br/>
                <span style="color:#aaa;">© ${new Date().getFullYear()} DiPertin</span>
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

function textoPlanoCancelamento(dados) {
    return [
        "Olá, " + (dados.lojaNome || "lojista") + "!",
        "",
        "Seu plano do Gestão Comercial foi cancelado.",
        "",
        "Plano: " + (dados.planName || "—"),
        "Data do cancelamento: " + (dados.dataCancelamento || "—"),
        "Motivo: " + (dados.motivoTexto || "—"),
        "",
        "O acesso ao Gestão Comercial foi encerrado. Para contratar novamente:",
        dados.urlContratar || URL_CONTRATAR_PLANO,
        "",
        "— Equipe DiPertin",
    ].join("\n");
}

async function enviarEmailCancelamento(dados) {
    const dest = String(dados.emailDestino || "").trim();
    if (!dest || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(dest)) {
        return { ok: false, motivo: "email_invalido" };
    }

    try {
        const transport = smtp.criarTransport("padrao");
        await transport.sendMail({
            from: smtp.from("padrao"),
            to: dest,
            subject: "Seu plano do Gestão Comercial foi cancelado",
            text: textoPlanoCancelamento(dados),
            html: templateHtmlCancelamento(dados),
        });
        return { ok: true };
    } catch (e) {
        console.warn("[assinatura-admin] falha SMTP:", e.message || e);
        return { ok: false, motivo: e.message || "smtp_erro" };
    }
}

exports.adminCancelarPlanoAssinatura = onCall(
    { region: "us-central1", enforceAppCheck: false, timeoutSeconds: 60 },
    async (request) => {
        const adminInfo = await assertCallerStaff(request.auth);

        const data = request.data || {};
        const assinaturaId = String(data.assinaturaId || "").trim();
        const motivoCodigo = String(data.motivoCodigo || "").trim();
        const motivoOutroTexto = String(data.motivoOutroTexto || "").trim();
        const observacaoInterna = String(data.observacaoInterna || "").trim();

        if (!assinaturaId) {
            throw new HttpsError("invalid-argument", "assinaturaId é obrigatório.");
        }

        const motivoTexto = resolverMotivoTexto(motivoCodigo, motivoOutroTexto);

        if (observacaoInterna.length > 900) {
            throw new HttpsError(
                "invalid-argument",
                "Observação interna muito longa (máx. 900 caracteres).",
            );
        }

        const db = admin.firestore();
        const ref = db.collection("assinaturas_clientes").doc(assinaturaId);
        const snap = await ref.get();

        if (!snap.exists) {
            throw new HttpsError("not-found", "Assinatura não encontrada.");
        }

        const assinatura = snap.data() || {};

        if (String(assinatura.status || "") === "cancelado") {
            throw new HttpsError(
                "failed-precondition",
                "Esta assinatura já está cancelada.",
            );
        }

        const now = admin.firestore.Timestamp.now();
        const dataCancelFmt = formatarDataPtBr(now.toDate());

        const historicoEntry = {
            tipo: "cancelamento",
            descricao: "Plano cancelado pelo administrador.",
            data_em: now,
            por_uid: adminInfo.uid,
            por_email: adminInfo.email || null,
            motivo_codigo: motivoCodigo,
            motivo_texto: motivoTexto,
            plano_cancelado: assinatura.plan_name || "",
            plan_id: assinatura.plan_id || "",
        };

        if (observacaoInterna) {
            historicoEntry.observacao_interna = observacaoInterna;
        }

        const patch = {
            status: "cancelado",
            cancelado_em: now,
            cancelado_por_uid: adminInfo.uid,
            cancelado_por_email: adminInfo.email || null,
            cancel_motivo_codigo: motivoCodigo,
            cancel_motivo_texto: motivoTexto,
            cancel_plano_nome: assinatura.plan_name || "",
            cancel_plano_id: assinatura.plan_id || "",
            updated_at: now,
            blocked_at: admin.firestore.FieldValue.delete(),
            block_reason: admin.firestore.FieldValue.delete(),
            historico: admin.firestore.FieldValue.arrayUnion(historicoEntry),
        };

        if (observacaoInterna) {
            patch.cancel_observacao_interna = observacaoInterna;
        } else {
            patch.cancel_observacao_interna = admin.firestore.FieldValue.delete();
        }

        await ref.update(patch);

        const emailDestino =
            String(assinatura.email || "").trim() ||
            String(data.emailFallback || "").trim();

        const emailResult = await enviarEmailCancelamento({
            emailDestino: emailDestino,
            lojaNome: assinatura.store_name || "",
            planName: assinatura.plan_name || "",
            dataCancelamento: dataCancelFmt,
            motivoTexto: motivoTexto,
            urlContratar: URL_CONTRATAR_PLANO,
        });

        try {
            await db.collection("audit_logs").add({
                acao: "assinatura_plano_cancelado",
                categoria: "assinaturas",
                origem: "callable",
                criado_em: now,
                ator_uid: adminInfo.uid,
                ator_email: adminInfo.email || null,
                detalhe: {
                    assinatura_id: assinaturaId,
                    store_id: assinatura.store_id || "",
                    plan_name: assinatura.plan_name || "",
                    motivo_codigo: motivoCodigo,
                    email_enviado: emailResult.ok === true,
                },
            });
        } catch (e) {
            console.warn("[assinatura-admin] audit log error:", e.message);
        }

        return {
            ok: true,
            assinaturaId: assinaturaId,
            status: "cancelado",
            emailEnviado: emailResult.ok === true,
            emailErro: emailResult.ok ? null : emailResult.motivo || null,
        };
    },
);
