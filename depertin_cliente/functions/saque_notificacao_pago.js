"use strict";

/**
 * Quando um saque passa a status `pago`, envia e-mail + push (FCM) ao usuário.
 * Idempotência: campo `notif_saque_pago_enviada` no documento.
 */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const notificationDispatcher = require("./notification_dispatcher");
const smtp = require("./smtp_transport");

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

/**
 * Formata data/hora em pt-BR (America/Sao_Paulo).
 * Aceita Date, Timestamp ou number (ms). Retorna `null` se inválido.
 */
function formatarDataHoraBr(data) {
    let d;
    if (!data) {
        d = new Date();
    } else if (data && typeof data.toDate === "function") {
        d = data.toDate();
    } else if (data instanceof Date) {
        d = data;
    } else {
        d = new Date(data);
    }
    if (isNaN(d.getTime())) return null;
    try {
        return new Intl.DateTimeFormat("pt-BR", {
            timeZone: "America/Sao_Paulo",
            day: "2-digit",
            month: "2-digit",
            year: "numeric",
            hour: "2-digit",
            minute: "2-digit",
        }).format(d);
    } catch (e) {
        return d.toISOString();
    }
}

/**
 * Constrói o HTML do e-mail de saque pago — layout marketplace profissional.
 *
 * Decisões:
 * - Tabelas (não flex/grid) para compatibilidade com Outlook/Gmail.
 * - Estilos INLINE em todos os elementos (clientes de e-mail ignoram <style>).
 * - Largura máxima 600px (padrão de e-mail design).
 * - Header com gradiente da marca (roxo → laranja).
 * - Bloco de valor em destaque com tipografia grande.
 * - Sem imagens externas (não dependem de "exibir imagens").
 */
function montarHtmlSaquePago({ nome, valorFmt, tipoLabel, dataPagamentoFmt, saqueId }) {
    const ano = new Date().getFullYear();
    const idCurto = saqueId ? String(saqueId).slice(0, 8).toUpperCase() : "";
    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="x-apple-disable-message-reformatting">
<title>Saque PIX confirmado</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f5f9;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
<div style="display:none;max-height:0;overflow:hidden;font-size:1px;line-height:1px;color:#f4f5f9;opacity:0;">
Seu saque PIX de R$ ${escapeHtml(valorFmt)} foi pago. Confira os detalhes.
</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f5f9;padding:32px 16px;">
  <tr>
    <td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;background-color:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(106,27,154,0.08);">

        <tr>
          <td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 60%,#FF8F00 100%);padding:32px 32px 28px;text-align:center;">
            <div style="font-size:11px;font-weight:700;letter-spacing:2px;color:rgba(255,255,255,0.85);text-transform:uppercase;margin-bottom:6px;">DiPertin</div>
            <div style="font-size:22px;font-weight:700;color:#ffffff;letter-spacing:-0.3px;">Saque PIX confirmado</div>
          </td>
        </tr>

        <tr>
          <td style="padding:32px 36px 8px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td align="center" style="padding-bottom:24px;">
                  <div style="display:inline-block;background-color:#dcfce7;color:#15803d;font-size:12px;font-weight:700;letter-spacing:0.5px;padding:6px 14px;border-radius:999px;text-transform:uppercase;">
                    &#10004; Pagamento concluído
                  </div>
                </td>
              </tr>
              <tr>
                <td style="padding-bottom:18px;">
                  <p style="margin:0;font-size:16px;color:#1e1b4b;line-height:1.5;">
                    Olá, <strong>${escapeHtml(nome)}</strong>,
                  </p>
                </td>
              </tr>
              <tr>
                <td style="padding-bottom:24px;">
                  <p style="margin:0;font-size:15px;color:#475569;line-height:1.6;">
                    Confirmamos o repasse do seu saque via PIX. O valor abaixo foi enviado pela equipe DiPertin para a chave cadastrada na sua conta.
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:0 36px 12px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#faf5ff;border:1px solid #e9d5ff;border-radius:14px;">
              <tr>
                <td style="padding:22px 24px;text-align:center;">
                  <div style="font-size:11px;font-weight:600;color:#6A1B9A;letter-spacing:1.5px;text-transform:uppercase;margin-bottom:6px;">Valor pago</div>
                  <div style="font-size:34px;font-weight:800;color:#1e1b4b;letter-spacing:-0.5px;line-height:1.1;">
                    R$ ${escapeHtml(valorFmt)}
                  </div>
                  <div style="font-size:12px;color:#64748b;margin-top:8px;">via PIX &middot; transferência instantânea</div>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:20px 36px 4px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid #f1f5f9;">
              <tr>
                <td style="padding:14px 0;border-bottom:1px solid #f1f5f9;">
                  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="font-size:13px;color:#64748b;width:40%;">Perfil</td>
                      <td style="font-size:13px;color:#1e1b4b;font-weight:600;text-align:right;">${escapeHtml(tipoLabel)}</td>
                    </tr>
                  </table>
                </td>
              </tr>
              <tr>
                <td style="padding:14px 0;border-bottom:1px solid #f1f5f9;">
                  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="font-size:13px;color:#64748b;width:40%;">Confirmado em</td>
                      <td style="font-size:13px;color:#1e1b4b;font-weight:600;text-align:right;">${escapeHtml(dataPagamentoFmt || "—")}</td>
                    </tr>
                  </table>
                </td>
              </tr>
              ${idCurto ? `<tr>
                <td style="padding:14px 0;">
                  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                    <tr>
                      <td style="font-size:13px;color:#64748b;width:40%;">Protocolo</td>
                      <td style="font-size:13px;color:#1e1b4b;font-weight:600;text-align:right;font-family:'Courier New',monospace;letter-spacing:0.5px;">#${escapeHtml(idCurto)}</td>
                    </tr>
                  </table>
                </td>
              </tr>` : ""}
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:20px 36px 4px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#fffbeb;border:1px solid #fde68a;border-radius:10px;">
              <tr>
                <td style="padding:14px 18px;">
                  <p style="margin:0;font-size:13px;color:#92400e;line-height:1.5;">
                    <strong>Ainda não apareceu na sua conta?</strong><br>
                    Aguarde alguns minutos para a compensação bancária. Em horários de pico ou finais de semana o crédito pode levar um pouco mais.
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:28px 36px 8px;">
            <p style="margin:0;font-size:14px;color:#475569;line-height:1.6;">
              Se tiver qualquer dúvida sobre este pagamento, fale com a gente pela <strong>Central de Ajuda</strong> dentro do aplicativo.
            </p>
          </td>
        </tr>

        <tr>
          <td style="padding:8px 36px 32px;">
            <p style="margin:0;font-size:14px;color:#1e1b4b;line-height:1.6;">
              Obrigado por fazer parte da DiPertin. <span style="color:#FF8F00;">&#9733;</span>
            </p>
          </td>
        </tr>

        <tr>
          <td style="background-color:#1e1b4b;padding:24px 36px;text-align:center;">
            <div style="font-size:13px;font-weight:700;color:#ffffff;letter-spacing:0.3px;margin-bottom:6px;">DiPertin</div>
            <div style="font-size:11px;color:rgba(255,255,255,0.65);line-height:1.6;">
              Marketplace e delivery local &middot; ${ano}<br>
              Esta é uma mensagem automática. Por favor, não responda este e-mail.
            </div>
          </td>
        </tr>

      </table>
      <div style="max-width:600px;margin:14px auto 0;text-align:center;font-size:11px;color:#94a3b8;line-height:1.5;">
        Você está recebendo este e-mail porque possui uma conta DiPertin com saque solicitado.
      </div>
    </td>
  </tr>
</table>
</body>
</html>`;
}

/**
 * Versão TEXTO PLAIN do e-mail (anti-spam + acessibilidade).
 * Clientes que não renderizam HTML (ou usuários com proteção) leem isto.
 */
function montarTextoSaquePago({ nome, valorFmt, tipoLabel, dataPagamentoFmt, saqueId }) {
    const idCurto = saqueId ? String(saqueId).slice(0, 8).toUpperCase() : "";
    return [
        `Olá, ${nome},`,
        ``,
        `Seu saque via PIX foi PAGO.`,
        ``,
        `Valor: R$ ${valorFmt}`,
        `Perfil: ${tipoLabel}`,
        `Confirmado em: ${dataPagamentoFmt || "—"}`,
        ...(idCurto ? [`Protocolo: #${idCurto}`] : []),
        ``,
        `Se ainda não apareceu na sua conta, aguarde a compensação bancária.`,
        `Em horários de pico ou finais de semana o crédito pode demorar um pouco mais.`,
        ``,
        `Dúvidas? Fale com a gente pela Central de Ajuda dentro do app.`,
        ``,
        `— Equipe DiPertin`,
        `Mensagem automática, não responda este e-mail.`,
    ].join("\n");
}

async function enviarEmailSaquePago(destinoEmail, nome, valorFmt, tipoLabel, dataPagamentoFmt, saqueId) {
    let transport;
    try {
        transport = smtp.criarTransport("padrao");
    } catch (e) {
        console.warn("[saque-pago] SMTP não configurado — e-mail não enviado.", e.message);
        return false;
    }
    const ctx = { nome, valorFmt, tipoLabel, dataPagamentoFmt, saqueId };
    await transport.sendMail({
        from: smtp.from("padrao"),
        to: destinoEmail,
        subject: `Saque PIX de R$ ${valorFmt} confirmado — DiPertin`,
        text: montarTextoSaquePago(ctx),
        html: montarHtmlSaquePago(ctx),
    });
    return true;
}

/**
 * FCM para lojista ou entregador.
 */
async function enviarPushSaquePago(db, uid, tipoUsuario, valorFmt, saqueId) {
    const segmento = tipoUsuario === "entregador" ? "entregador" : "loja";
    const { token, ok } = await notificationDispatcher.obterTokenValidado(db, uid, segmento);
    if (!ok || !token) {
        console.log(`[saque-pago] sem push uid=${uid} segmento=${segmento}`);
        return false;
    }
    const data = notificationDispatcher.dataSoStrings({
        type: "SAQUE_PAGO",
        tipoNotificacao: "saque_pago",
        segmento: segmento === "loja" ? "loja" : "entregador",
        evento: "saque_pago",
        saque_id: String(saqueId),
        valor: valorFmt,
    });
    const mensagem = {
        notification: {
            title: "Saque confirmado",
            body: `Seu saque de R$ ${valorFmt} foi pago.`,
        },
        android: {
            priority: "high",
            collapseKey: `saque_pago_${saqueId}`,
            notification: {
                channelId: "high_importance_channel",
                sound: "default",
                defaultVibrateTimings: true,
                visibility: "public",
            },
        },
        apns: {
            headers: { "apns-priority": "10", "apns-push-type": "alert" },
            payload: { aps: { sound: "default", badge: 1 } },
        },
        data,
        token,
    };
    await admin.messaging().send(mensagem);
    console.log(`[saque-pago] push enviado uid=${uid} saque=${saqueId}`);
    return true;
}

exports.onSaqueSolicitacaoAtualizado = functions.firestore
    .document("saques_solicitacoes/{saqueId}")
    .onUpdate(async (change, context) => {
        const depois = change.after.data() || {};
        const antes = change.before.data() || {};

        if (depois.status !== "pago") {
            return null;
        }
        if (depois.notif_saque_pago_enviada === true) {
            return null;
        }

        const uid = depois.user_id ? String(depois.user_id) : "";
        if (!uid) {
            console.warn("[saque-pago] sem user_id");
            return null;
        }

        const valor = Number(depois.valor || 0);
        const valorFmt = valor.toFixed(2).replace(".", ",");

        const db = admin.firestore();
        const userSnap = await db.collection("users").doc(uid).get();
        const u = userSnap.exists ? userSnap.data() : {};
        const email = (u && u.email) ? String(u.email).trim() : "";
        const nome =
            (u && (u.nome || u.nomeCompleto || u.displayName))
                ? String(u.nome || u.nomeCompleto || u.displayName).split(/\s+/)[0]
                : "Olá";
        const tipoUsuario = String(depois.tipo_usuario || "").toLowerCase();
        const tipoLabel =
            tipoUsuario === "entregador" ? "Entregador" : "Lojista";

        // Data do pagamento: prioriza `pago_em` gravado pelo painel quando
        // marca como pago; senão usa `now` (momento da confirmação aqui).
        const dataPagamentoFmt = formatarDataHoraBr(depois.pago_em) || formatarDataHoraBr(new Date());

        let emailOk = false;
        if (email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            try {
                emailOk = await enviarEmailSaquePago(
                    email,
                    nome,
                    valorFmt,
                    tipoLabel,
                    dataPagamentoFmt,
                    context.params.saqueId,
                );
            } catch (e) {
                console.error("[saque-pago] e-mail falhou:", e.message);
            }
        } else {
            console.warn(`[saque-pago] sem e-mail válido uid=${uid}`);
        }

        let pushOk = false;
        try {
            pushOk = await enviarPushSaquePago(
                db,
                uid,
                tipoUsuario,
                valorFmt,
                context.params.saqueId,
            );
        } catch (e) {
            console.error("[saque-pago] push falhou:", e.message);
        }

        await change.after.ref.update({
            notif_saque_pago_enviada: true,
            notif_saque_pago_em: admin.firestore.FieldValue.serverTimestamp(),
            notif_saque_pago_email_ok: emailOk,
            notif_saque_pago_push_ok: pushOk,
        });

        return null;
    });
