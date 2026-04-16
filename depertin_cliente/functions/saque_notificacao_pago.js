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

async function enviarEmailSaquePago(destinoEmail, nome, valorFmt, tipoLabel) {
    let transport;
    try {
        transport = smtp.criarTransport("padrao");
    } catch (e) {
        console.warn("[saque-pago] SMTP não configurado — e-mail não enviado.", e.message);
        return false;
    }
    const html = `
<!DOCTYPE html><html><body style="font-family:system-ui,sans-serif;line-height:1.5;color:#1e1b4b;">
<p>Olá, ${escapeHtml(nome)},</p>
<p>Seu saque via PIX de <strong>R$ ${escapeHtml(valorFmt)}</strong> foi <strong>marcado como pago</strong> pela equipe DiPertin.</p>
<p>Perfil: <strong>${escapeHtml(tipoLabel)}</strong>.</p>
<p>Se o valor ainda não aparecer na sua conta, aguarde a compensação bancária.</p>
<p style="margin-top:24px;color:#64748b;font-size:12px;">DiPertin — mensagem automática.</p>
</body></html>`;
    await transport.sendMail({
        from: smtp.from("padrao"),
        to: destinoEmail,
        subject: "DiPertin — saque PIX confirmado",
        html,
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

        let emailOk = false;
        if (email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            try {
                emailOk = await enviarEmailSaquePago(email, nome, valorFmt, tipoLabel);
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
