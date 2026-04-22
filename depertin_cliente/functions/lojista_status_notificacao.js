"use strict";

/**
 * Notifica lojista por e-mail e push quando o cadastro sai de "pendente"
 * para "aprovada" ou "bloqueada" (recusa cadastral) no painel master.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const smtp = require("./smtp_transport");
const notificationDispatcher = require("./notification_dispatcher");

const STATUS_APROVADO = new Set(["aprovada", "aprovado", "ativo"]);
const STATUS_BLOQUEADO = new Set(["bloqueada", "bloqueado"]);

function normalizarStatus(status) {
    return String(status || "")
        .trim()
        .toLowerCase();
}

function validarEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || "").trim());
}

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function nomeExibicaoSeguro(nomeBruto) {
    const bruto = String(nomeBruto || "").trim();
    if (!bruto) return "Olá";
    const primeiro = bruto.split(/\s+/)[0] || "Olá";
    if (primeiro.length > 48) return "Olá";
    const p = primeiro.toLowerCase();
    if (p === "me" || p === "eu") return "Olá";
    return primeiro;
}

function docIndicaLojista(d) {
    if (!d) return false;
    for (const k of ["role", "tipo", "tipoUsuario"]) {
        if (String(d[k] || "").toLowerCase().trim() === "lojista") return true;
    }
    return false;
}

function templateHtmlAprovado(nome) {
    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="x-ua-compatible" content="ie=edge">
  <title>Conta aprovada no DiPertin</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <tr>
            <td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 55%,#7B1FA2 100%);padding:34px 28px;text-align:center;">
              <p style="margin:0 0 6px;color:rgba(255,255,255,0.92);font-size:13px;font-weight:600;letter-spacing:2px;text-transform:uppercase;">DiPertin</p>
              <h1 style="margin:0;color:#ffffff;font-size:25px;font-weight:800;letter-spacing:-0.4px;line-height:1.25;">Conta aprovada</h1>
              <p style="margin:14px 0 0;color:rgba(255,255,255,0.95);font-size:15px;line-height:1.45;">Sua loja foi validada pela equipe.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:34px 32px 26px;">
              <p style="margin:0 0 14px;font-size:17px;line-height:1.55;color:#1a1a2e;">
                Olá, <strong style="color:#6A1B9A;">${escapeHtml(nome)}</strong>!
              </p>
              <p style="margin:0 0 18px;font-size:15px;line-height:1.65;color:#444;">
                Sua conta de <strong>lojista</strong> foi <strong style="color:#0f766e;">aprovada</strong> no DiPertin.
              </p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:20px 0;background:#f0fdf4;border-radius:14px;border:1px solid #bbf7d0;">
                <tr>
                  <td style="padding:18px 18px;">
                    <p style="margin:0;font-size:14px;line-height:1.55;color:#14532d;">
                      Você já pode acessar o app e começar a configurar sua operação: catálogo, pedidos e dados da loja.
                    </p>
                  </td>
                </tr>
              </table>
              <p style="margin:0;font-size:14px;line-height:1.65;color:#555;">
                Se precisar de apoio, nossa equipe está pronta para ajudar.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 30px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 20px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">
                Este é um e-mail automático. Por favor, não responda.<br/>
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

function templateHtmlRecusado(nome, motivo) {
    const motivoSeguro = escapeHtml(motivo || "Não informado.");
    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="x-ua-compatible" content="ie=edge">
  <title>Atualização do cadastro de loja</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <tr>
            <td style="background:linear-gradient(135deg,#7f1d1d 0%,#b91c1c 55%,#991b1b 100%);padding:34px 28px;text-align:center;">
              <p style="margin:0 0 6px;color:rgba(255,255,255,0.92);font-size:13px;font-weight:600;letter-spacing:2px;text-transform:uppercase;">DiPertin</p>
              <h1 style="margin:0;color:#ffffff;font-size:25px;font-weight:800;letter-spacing:-0.4px;line-height:1.25;">Cadastro não aprovado</h1>
              <p style="margin:14px 0 0;color:rgba(255,255,255,0.95);font-size:15px;line-height:1.45;">Identificamos pendências no seu envio.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:34px 32px 26px;">
              <p style="margin:0 0 14px;font-size:17px;line-height:1.55;color:#1a1a2e;">
                Olá, <strong style="color:#6A1B9A;">${escapeHtml(nome)}</strong>!
              </p>
              <p style="margin:0 0 16px;font-size:15px;line-height:1.65;color:#444;">
                Seu cadastro de lojista foi analisado e, no momento, não pôde ser aprovado.
              </p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:18px 0;background:#fef2f2;border-radius:14px;border:1px solid #fecaca;">
                <tr>
                  <td style="padding:18px 18px;">
                    <p style="margin:0 0 8px;font-size:12px;font-weight:700;letter-spacing:0.3px;text-transform:uppercase;color:#991b1b;">Motivo informado</p>
                    <p style="margin:0;font-size:14px;line-height:1.6;color:#7f1d1d;">${motivoSeguro}</p>
                  </td>
                </tr>
              </table>
              <p style="margin:0;font-size:14px;line-height:1.65;color:#555;">
                Revise os dados/documentos e atualize seu cadastro para uma nova análise.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 30px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 20px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">
                Este é um e-mail automático. Por favor, não responda.<br/>
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

function textoPlanoAprovado(nome) {
    return [
        `Olá, ${nome}!`,
        "",
        "Sua conta de lojista foi aprovada no DiPertin.",
        "Você já pode acessar o app e concluir as configurações da sua loja.",
        "",
        "Se precisar de ajuda, conte com nossa equipe.",
        "",
        "DiPertin — mensagem automática.",
    ].join("\n");
}

function textoPlanoRecusado(nome, motivo) {
    return [
        `Olá, ${nome}!`,
        "",
        "Seu cadastro de lojista foi analisado e não pôde ser aprovado neste momento.",
        `Motivo informado: ${motivo || "Não informado."}`,
        "",
        "Revise os dados/documentos e atualize seu cadastro para nova análise.",
        "",
        "DiPertin — mensagem automática.",
    ].join("\n");
}

function _hostDoEmail(from) {
    try {
        const s = String(from || "");
        const match = s.match(/<([^>]+)>/) || [null, s.trim()];
        const addr = match[1] || "";
        const parts = addr.split("@");
        return parts[1] || "dipertin.com.br";
    } catch (_) {
        return "dipertin.com.br";
    }
}

function _subjectComMarcador(base) {
    const agora = new Date();
    const dd = String(agora.getDate()).padStart(2, "0");
    const mm = String(agora.getMonth() + 1).padStart(2, "0");
    const hh = String(agora.getHours()).padStart(2, "0");
    const mi = String(agora.getMinutes()).padStart(2, "0");
    return `${base} [${dd}/${mm} ${hh}:${mi}]`;
}

async function enviarEmailStatus(destinoEmail, nome, evento, motivoRecusa, uid) {
    let transport;
    try {
        transport = smtp.criarTransport("padrao");
    } catch (e) {
        console.warn("[lojista-status] SMTP não configurado. E-mail não enviado:", e.message);
        return false;
    }

    const aprovado = evento === "aprovada";
    const from = smtp.from("padrao");
    const subjectBase = aprovado
        ? "DiPertin — sua conta de lojista foi aprovada"
        : "DiPertin — atualização do seu cadastro de lojista";
    const subject = aprovado
        ? subjectBase
        : _subjectComMarcador(subjectBase);

    const host = _hostDoEmail(from);
    const random = Math.random().toString(36).slice(2, 12);
    const messageId = `<lojista-status-${evento}-${uid || "x"}-${Date.now()}-${random}@${host}>`;

    console.log(
        `[lojista-status] SMTP enviando → evento=${evento} para=${destinoEmail} uid=${uid || "?"} msgId=${messageId}`,
    );

    try {
        const info = await transport.sendMail({
            from,
            to: destinoEmail,
            subject,
            messageId,
            headers: {
                "X-DiPertin-Evento": evento,
                "X-DiPertin-Uid": String(uid || ""),
                "X-DiPertin-Timestamp": String(Date.now()),
            },
            text: aprovado
                ? textoPlanoAprovado(nome)
                : textoPlanoRecusado(nome, motivoRecusa),
            html: aprovado
                ? templateHtmlAprovado(nome)
                : templateHtmlRecusado(nome, motivoRecusa),
        });

        const accepted = (info && info.accepted) || [];
        const rejected = (info && info.rejected) || [];
        const responseServidor = info && info.response ? String(info.response) : "";

        console.log(
            `[lojista-status] SMTP OK → aceitos=${accepted.length} rejeitados=${rejected.length} resposta=${responseServidor}`,
        );

        if (rejected.length > 0 && accepted.length === 0) {
            console.error(
                `[lojista-status] SMTP TODOS OS DESTINOS REJEITADOS → rejeitados=${JSON.stringify(rejected)}`,
            );
            return false;
        }
        return true;
    } catch (e) {
        console.error(
            `[lojista-status] SMTP FALHOU → evento=${evento} uid=${uid || "?"} err=${e && e.message ? e.message : e}`,
        );
        throw e;
    }
}

async function enviarPushStatus(db, uid, evento, motivoRecusa) {
    const { token, ok } = await notificationDispatcher.obterTokenValidado(db, uid, "loja");
    if (!ok || !token) return false;

    const aprovado = evento === "aprovada";
    const titulo = aprovado ? "Conta aprovada" : "Cadastro não aprovado";
    const bodyBase = aprovado
        ? "Seu cadastro de lojista foi aprovado. Acesse o app para continuar."
        : "Seu cadastro de lojista não foi aprovado. Verifique o motivo e atualize seus dados.";
    const body = !aprovado && motivoRecusa
        ? `Cadastro não aprovado: ${motivoRecusa}`.slice(0, 180)
        : bodyBase;

    const data = notificationDispatcher.dataSoStrings({
        type: aprovado ? "LOJISTA_CADASTRO_APROVADO" : "LOJISTA_CADASTRO_RECUSADO",
        tipoNotificacao: aprovado ? "lojista_cadastro_aprovado" : "lojista_cadastro_recusado",
        segmento: "loja",
        evento: aprovado ? "cadastro_aprovado" : "cadastro_recusado",
        motivo_recusa: aprovado ? "" : String(motivoRecusa || ""),
    });

    // Logo DiPertin hospedado no site — faz o Android exibir o ícone do app
    // ao lado da notificação (big picture / large icon expandido), em vez de
    // mostrar apenas a silhueta monocromática de status bar.
    const LOGO_DIPERTIN_URL = "https://www.dipertin.com.br/assets/logo.png";

    await admin.messaging().send({
        notification: {
            title: titulo,
            body,
            imageUrl: LOGO_DIPERTIN_URL,
        },
        android: {
            priority: "high",
            collapseKey: aprovado
                ? `lojista_cadastro_aprovado_${uid}`
                : `lojista_cadastro_recusado_${uid}`,
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
                imageUrl: LOGO_DIPERTIN_URL,
            },
        },
        apns: {
            headers: {
                "apns-priority": "10",
                "apns-push-type": "alert",
            },
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                },
            },
        },
        data,
        token,
    });

    return true;
}

exports.onLojistaStatusCadastroAtualizado = functions.firestore
    .document("users/{uid}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data() || {};
        const depois = change.after.data() || {};

        if (!docIndicaLojista(depois)) return null;

        const statusAntes = normalizarStatus(antes.status_loja);
        const statusDepois = normalizarStatus(depois.status_loja);
        if (!statusDepois) return null;

        // --- APROVAÇÃO: qualquer -> aprovada (desde que antes NÃO estivesse
        // aprovado). Cobre pendente→aprovada e também bloqueada→aprovada
        // (master reaprova um lojista anteriormente recusado). O trigger só
        // dispara se houve mudança real de status (statusAntes !== statusDepois),
        // garantindo idempotência em updates de outros campos do doc.
        let evento = "";
        if (
            STATUS_APROVADO.has(statusDepois) &&
            !STATUS_APROVADO.has(statusAntes) &&
            statusAntes !== statusDepois
        ) {
            evento = "aprovada";
        }

        // --- RECUSA: dispara quando transitou para bloqueada OU quando já
        // estava bloqueada mas o motivo mudou (painel re-classificou recusa).
        if (!evento && STATUS_BLOQUEADO.has(statusDepois)) {
            const motivoDepois = String(depois.motivo_recusa || "").trim();
            const motivoAntes = String(antes.motivo_recusa || "").trim();
            const codigoAntes = String(antes.motivo_recusa_codigo || "").trim();
            const codigoDepois = String(depois.motivo_recusa_codigo || "").trim();
            const recusaCadastro =
                depois.recusa_cadastro === true || motivoDepois.length > 0;

            const transitouParaBloqueada =
                statusAntes === "pendente" && statusAntes !== statusDepois;
            const reclassificouMotivo =
                STATUS_BLOQUEADO.has(statusAntes) &&
                recusaCadastro &&
                (motivoAntes !== motivoDepois || codigoAntes !== codigoDepois);

            if (recusaCadastro && (transitouParaBloqueada || reclassificouMotivo)) {
                evento = "recusada";
            }
        }

        if (!evento) return null;

        const uid = context.params.uid;
        const email = String(depois.email || "").trim();
        const nome = nomeExibicaoSeguro(depois.nome || depois.nome_completo || "");
        const motivoRecusa = String(depois.motivo_recusa || "").trim();
        const db = admin.firestore();

        console.log(
            `[lojista-status] evento=${evento} uid=${uid} email=${email || "(vazio)"} motivoLen=${motivoRecusa.length}`,
        );

        let emailOk = false;
        if (validarEmail(email)) {
            try {
                emailOk = await enviarEmailStatus(email, nome, evento, motivoRecusa, uid);
            } catch (e) {
                console.error(`[lojista-status] Falha e-mail uid=${uid}:`, e.message || e);
            }
        } else {
            console.warn(`[lojista-status] E-mail inválido/ausente uid=${uid}`);
        }

        let pushOk = false;
        try {
            pushOk = await enviarPushStatus(db, uid, evento, motivoRecusa);
        } catch (e) {
            console.error(`[lojista-status] Falha push uid=${uid}:`, e.message || e);
        }

        try {
            await change.after.ref.set(
                {
                    notif_cadastro_lojista_ultimo_evento: evento,
                    notif_cadastro_lojista_em: admin.firestore.FieldValue.serverTimestamp(),
                    notif_cadastro_lojista_email_ok: emailOk,
                    notif_cadastro_lojista_push_ok: pushOk,
                },
                { merge: true },
            );
        } catch (e) {
            console.warn(`[lojista-status] Falha ao persistir auditoria uid=${uid}:`, e.message || e);
        }

        return null;
    });
