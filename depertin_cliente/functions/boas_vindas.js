"use strict";

/**
 * E-mail de boas-vindas ao criar documento em users/{uid}.
 * Usa a mesma SMTP da recuperação de senha (functions/.env).
 */

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");
const smtp = require("./smtp_transport");

function validarFormatoEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function primeiroNomeSeguro(nome) {
  if (!nome || typeof nome !== "string") return "Olá";
  const t = nome.trim();
  if (!t) return "Olá";
  const partes = t.split(/\s+/);
  const p = partes[0];
  if (p.length > 48) return "Olá";
  const pl = p.toLowerCase();
  if (pl === "me" || pl === "eu" || pl === "eu mesmo") return "Olá";
  return escapeHtml(p);
}

function textoPlanoBoasVindas(nomeExibicao) {
  return [
    `Olá, ${nomeExibicao}!`,
    "",
    "Seja bem-vindo(a) ao DiPertin — o marketplace da sua cidade para pedir onde você quiser, com praticidade e segurança.",
    "",
    "O que você pode fazer por aqui:",
    "• Descobrir lojas e produtos na sua região",
    "• Montar seu pedido e acompanhar tudo pelo app",
    "• Falar com o suporte quando precisar",
    "",
    "Abra o app DiPertin no seu celular e comece a explorar.",
    "",
    "Este é um e-mail automático. Por favor, não responda.",
    "— Equipe DiPertin",
  ].join("\n");
}

function templateHtmlBoasVindas(nomeExibicao) {
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="x-ua-compatible" content="ie=edge">
  <title>Bem-vindo(a) ao DiPertin</title>
</head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
          <tr>
            <td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 55%,#7B1FA2 100%);padding:36px 28px;text-align:center;">
              <p style="margin:0 0 6px;color:rgba(255,255,255,0.92);font-size:13px;font-weight:600;letter-spacing:2px;text-transform:uppercase;">DiPertin</p>
              <h1 style="margin:0;color:#ffffff;font-size:26px;font-weight:800;letter-spacing:-0.5px;line-height:1.25;">Bem-vindo(a)!</h1>
              <p style="margin:14px 0 0;color:rgba(255,255,255,0.95);font-size:16px;line-height:1.45;">Sua conta foi criada com sucesso.</p>
            </td>
          </tr>
          <tr>
            <td style="padding:36px 32px 28px;">
              <p style="margin:0 0 18px;font-size:17px;line-height:1.55;color:#1a1a2e;">
                Olá, <strong style="color:#6A1B9A;">${nomeExibicao}</strong>!
              </p>
              <p style="margin:0 0 18px;font-size:15px;line-height:1.65;color:#444;">
                É um prazer ter você no <strong style="color:#FF8F00;">DiPertin</strong> — o marketplace da sua cidade para pedir onde você quiser, com praticidade e segurança.
              </p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:24px 0;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
                <tr>
                  <td style="padding:22px 20px;">
                    <p style="margin:0 0 12px;font-size:13px;font-weight:700;color:#6A1B9A;letter-spacing:0.3px;text-transform:uppercase;">O que você pode fazer</p>
                    <p style="margin:0 0 10px;font-size:15px;line-height:1.55;color:#333;">
                      <span style="color:#FF8F00;font-weight:700;">✓</span> Explorar lojas e produtos na sua região
                    </p>
                    <p style="margin:0 0 10px;font-size:15px;line-height:1.55;color:#333;">
                      <span style="color:#FF8F00;font-weight:700;">✓</span> Montar pedidos e acompanhar tudo pelo app
                    </p>
                    <p style="margin:0;font-size:15px;line-height:1.55;color:#333;">
                      <span style="color:#FF8F00;font-weight:700;">✓</span> Falar com o suporte quando precisar
                    </p>
                  </td>
                </tr>
              </table>
              <p style="margin:0;font-size:15px;line-height:1.65;color:#555;">
                Abra o <strong>app DiPertin</strong> no seu celular e comece a usar. Qualquer dúvida, estamos por aqui.
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 32px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 22px;"></div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">
                Este é um e-mail automático de boas-vindas. Por favor, não responda a esta mensagem.<br/>
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

/**
 * Dispara ao criar users/{userId}. Envia e-mail se houver SMTP e e-mail válido.
 */
exports.onUsuarioCriadoBoasVindas = functions.firestore
  .document("users/{userId}")
  .onCreate(async (snap) => {
    const data = snap.data() || {};
    if (data.skip_email_boas_vindas === true) {
      console.log("[boas-vindas] skip_email_boas_vindas — ignorado.");
      return null;
    }
    const role = (data.role || data.tipoUsuario || "")
      .toString()
      .trim()
      .toLowerCase();
    if (role === "master" || role === "master_city") {
      console.log("[boas-vindas] Perfil administrativo — e-mail não enviado.");
      return null;
    }

    const email = typeof data.email === "string" ? data.email.trim() : "";
    if (!email || !validarFormatoEmail(email)) {
      console.log("[boas-vindas] E-mail ausente ou inválido — ignorado.");
      return null;
    }

    let transporter;
    try {
      transporter = smtp.criarTransport("padrao");
    } catch (e) {
      console.warn("[boas-vindas]", e.message, "— e-mail não enviado.");
      return null;
    }

    const nomeBruto =
      data.nome && String(data.nome).trim()
        ? String(data.nome).trim()
        : "Olá";
    const nomeHtml = primeiroNomeSeguro(nomeBruto);
    let nomeTexto = nomeBruto.split(/\s+/)[0] || "Olá";
    if (nomeTexto.length > 48) nomeTexto = "Olá";
    const ntLower = nomeTexto.toLowerCase();
    if (ntLower === "me" || ntLower === "eu") nomeTexto = "Olá";
    const nomeTextoLimpo = nomeTexto.replace(/[\r\n]/g, " ");

    try {
      await transporter.sendMail({
        from: smtp.from("padrao"),
        to: email,
        subject: "Bem-vindo(a) ao DiPertin — sua conta está pronta",
        text: textoPlanoBoasVindas(nomeTextoLimpo),
        html: templateHtmlBoasVindas(nomeHtml),
      });

      await snap.ref.set(
        {
          email_boas_vindas_em: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      console.log(`[boas-vindas] Enviado para ${email}`);
    } catch (err) {
      console.error("[boas-vindas] Falha ao enviar:", err && err.message ? err.message : err);
    }

    return null;
  });
