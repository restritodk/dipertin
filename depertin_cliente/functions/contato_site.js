/**
 * Cloud Function — formulário de contato do site institucional.
 * Recebe POST JSON, valida e envia e-mail via SMTP (Titan).
 * Inclui IP, geolocalização e timestamp no e-mail.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("crypto");
const smtp = require("./smtp_transport");

const COOLDOWN_MS = 10_000;
const ORIGENS_PERMITIDAS = (() => {
    const padrao = [
        "https://www.dipertin.com.br",
        "https://dipertin.com.br",
        "http://localhost:3000",
        "http://localhost:5173",
    ];
    const extra = String(process.env.SITE_ALLOWED_ORIGINS || "")
        .split(",")
        .map((o) => o.trim())
        .filter(Boolean);
    return new Set([...padrao, ...extra]);
})();

function origemPermitida(origin) {
    if (!origin) return true;
    return ORIGENS_PERMITIDAS.has(String(origin).trim());
}

function aplicarCors(req, res) {
    const origin = req.headers.origin ? String(req.headers.origin) : "";
    if (origemPermitida(origin) && origin) {
        res.set("Access-Control-Allow-Origin", origin);
    }
    res.set("Vary", "Origin");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
}

function chaveRatePorIp(ip) {
    return crypto.createHash("sha256").update(String(ip || "desconhecido")).digest("hex");
}

async function reservarJanelaCooldown(ip, agora) {
    const db = admin.firestore();
    const ref = db.collection("contato_site_rate").doc(chaveRatePorIp(ip));
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const ultimoEnvioMs = Number(snap.data()?.ultimo_envio_ms || 0);
        if (ultimoEnvioMs > 0 && agora - ultimoEnvioMs < COOLDOWN_MS) {
            throw new functions.https.HttpsError("resource-exhausted", "Aguarde antes de enviar novamente.");
        }
        tx.set(ref, {
            ultimo_envio_ms: agora,
            atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}

function limpar(str, max) {
    if (!str || typeof str !== "string") return "";
    return str.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "").replace(/[<>]/g, "").trim().slice(0, max);
}

function criarTransporter() {
    return smtp.criarTransport("padrao");
}

function formatarData(d) {
    const pad = (n) => String(n).padStart(2, "0");
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} às ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function buildHtml(nome, email, assunto, mensagem, ip, lat, lng, dataStr) {
    const temGeo = lat !== null && lng !== null && lat !== undefined && lng !== undefined;
    const mapsLink = temGeo
        ? `https://www.google.com/maps?q=${lat},${lng}`
        : null;

    return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f4f3f7;font-family:'Segoe UI',Arial,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f3f7;padding:32px 16px">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08)">

  <!-- Header -->
  <tr>
    <td style="background:linear-gradient(135deg,#6A1B9A 0%,#4A148C 100%);padding:32px 32px 28px;text-align:center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        <tr>
          <td align="center" style="padding-bottom:16px">
            <div style="width:56px;height:56px;background:rgba(255,255,255,.15);border-radius:14px;display:inline-block;line-height:56px;text-align:center">
              <span style="font-size:28px;color:#fff;font-weight:800;letter-spacing:-.02em">D</span>
            </div>
          </td>
        </tr>
        <tr>
          <td align="center">
            <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700;letter-spacing:-.02em">Nova mensagem do site</h1>
            <p style="margin:6px 0 0;color:rgba(255,255,255,.7);font-size:13px;font-weight:400">${dataStr} · Formulário de contato</p>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Badge assunto -->
  <tr>
    <td style="padding:28px 32px 0">
      <table role="presentation" cellpadding="0" cellspacing="0">
        <tr>
          <td style="background:#f3e5f5;color:#6A1B9A;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;padding:6px 14px;border-radius:20px">
            ${assunto}
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Dados do remetente -->
  <tr>
    <td style="padding:20px 32px 0">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#faf9fc;border:1px solid #ece9f1;border-radius:12px;overflow:hidden">
        <tr>
          <td style="padding:20px 24px">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td width="50%" style="padding-bottom:12px;vertical-align:top">
                  <p style="margin:0;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">Nome</p>
                  <p style="margin:4px 0 0;font-size:15px;font-weight:600;color:#1a1a2e">${nome}</p>
                </td>
                <td width="50%" style="padding-bottom:12px;vertical-align:top">
                  <p style="margin:0;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">E-mail</p>
                  <p style="margin:4px 0 0;font-size:15px;font-weight:600;color:#1a1a2e"><a href="mailto:${email}" style="color:#6A1B9A;text-decoration:none">${email}</a></p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Mensagem -->
  <tr>
    <td style="padding:20px 32px 0">
      <p style="margin:0 0 10px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">Mensagem</p>
      <div style="background:#ffffff;border:1px solid #ece9f1;border-radius:12px;padding:20px 24px;border-left:4px solid #6A1B9A">
        <p style="margin:0;font-size:14px;line-height:1.7;color:#333;white-space:pre-wrap">${mensagem}</p>
      </div>
    </td>
  </tr>

  <!-- Botão responder -->
  <tr>
    <td align="center" style="padding:28px 32px 0">
      <a href="mailto:${email}?subject=Re: [DiPertin] ${assunto}" style="display:inline-block;background:#6A1B9A;color:#ffffff;font-size:14px;font-weight:600;padding:14px 36px;border-radius:999px;text-decoration:none;letter-spacing:.01em">Responder ${nome.split(" ")[0]}</a>
    </td>
  </tr>

  <!-- Separador -->
  <tr>
    <td style="padding:28px 32px 0">
      <hr style="border:none;border-top:1px solid #ece9f1;margin:0"/>
    </td>
  </tr>

  <!-- Dados técnicos -->
  <tr>
    <td style="padding:20px 32px 24px">
      <p style="margin:0 0 12px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">Dados técnicos do envio</p>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="font-size:13px;color:#666">
        <tr>
          <td style="padding:4px 0" width="120"><strong style="color:#444">IP</strong></td>
          <td style="padding:4px 0"><code style="background:#f4f3f7;padding:2px 8px;border-radius:4px;font-size:12px;color:#333">${ip}</code></td>
        </tr>
        ${temGeo ? `
        <tr>
          <td style="padding:4px 0"><strong style="color:#444">Latitude</strong></td>
          <td style="padding:4px 0"><code style="background:#f4f3f7;padding:2px 8px;border-radius:4px;font-size:12px;color:#333">${lat}</code></td>
        </tr>
        <tr>
          <td style="padding:4px 0"><strong style="color:#444">Longitude</strong></td>
          <td style="padding:4px 0"><code style="background:#f4f3f7;padding:2px 8px;border-radius:4px;font-size:12px;color:#333">${lng}</code></td>
        </tr>
        <tr>
          <td style="padding:4px 0"><strong style="color:#444">Mapa</strong></td>
          <td style="padding:4px 0"><a href="${mapsLink}" style="color:#6A1B9A;font-size:12px;text-decoration:none">Abrir no Google Maps &rarr;</a></td>
        </tr>` : `
        <tr>
          <td style="padding:4px 0"><strong style="color:#444">Localização</strong></td>
          <td style="padding:4px 0;font-size:12px;color:#999">Não disponível (usuário negou permissão)</td>
        </tr>`}
        <tr>
          <td style="padding:4px 0"><strong style="color:#444">Data/hora</strong></td>
          <td style="padding:4px 0;font-size:12px">${dataStr} (Brasília)</td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Footer -->
  <tr>
    <td style="background:#faf9fc;padding:20px 32px;text-align:center;border-top:1px solid #ece9f1">
      <p style="margin:0;font-size:12px;color:#999">
        <strong style="color:#6A1B9A">DiPertin</strong> · Formulário de contato do site institucional
      </p>
      <p style="margin:6px 0 0;font-size:11px;color:#bbb">
        Este e-mail foi gerado automaticamente. Responda diretamente ao remetente usando o botão acima.
      </p>
    </td>
  </tr>

</table>
</td></tr>
</table>
</body>
</html>`;
}

exports.enviarContatoSite = functions
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onRequest(async (req, res) => {
        aplicarCors(req, res);
        const origin = req.headers.origin ? String(req.headers.origin) : "";

        if (req.method === "OPTIONS") {
            if (!origemPermitida(origin)) {
                return res.status(403).json({ error: "Origem não permitida." });
            }
            return res.status(204).send("");
        }
        if (req.method !== "POST") {
            return res.status(405).json({ error: "Método não permitido." });
        }
        if (!origemPermitida(origin)) {
            return res.status(403).json({ error: "Origem não permitida." });
        }

        const ip = (req.headers["x-forwarded-for"] || req.ip || "desconhecido").split(",")[0].trim();
        const agora = Date.now();
        try {
            await reservarJanelaCooldown(ip, agora);
        } catch (err) {
            if (err instanceof functions.https.HttpsError && err.code === "resource-exhausted") {
                return res.status(429).json({ error: "Aguarde antes de enviar novamente." });
            }
            console.error("[contato-site] erro cooldown:", err.message || err);
            return res.status(500).json({ error: "Falha ao validar envio. Tente novamente." });
        }

        const body = req.body || {};
        const nome = limpar(body.nome, 120);
        const email = limpar(body.email, 120);
        const assunto = limpar(body.assunto, 200);
        const mensagem = limpar(body.mensagem, 4000);
        const honeypot = (body.website || "").trim();
        const lat = typeof body.lat === "number" ? body.lat : null;
        const lng = typeof body.lng === "number" ? body.lng : null;

        if (honeypot) {
            return res.status(200).json({ ok: true });
        }

        const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (nome.length < 2) return res.status(400).json({ error: "Nome inválido." });
        if (!emailRe.test(email)) return res.status(400).json({ error: "E-mail inválido." });
        if (!assunto) return res.status(400).json({ error: "Assunto é obrigatório." });
        if (mensagem.length < 10) return res.status(400).json({ error: "Mensagem muito curta." });

        const dataBr = new Date(agora + (-3 * 60 * 60 * 1000));
        const dataStr = formatarData(dataBr);

        const htmlBody = buildHtml(nome, email, assunto, mensagem, ip, lat, lng, dataStr);
        const textBody = [
            `Nome: ${nome}`,
            `E-mail: ${email}`,
            `Assunto: ${assunto}`,
            ``,
            `Mensagem:`,
            mensagem,
            ``,
            `--- Dados técnicos ---`,
            `IP: ${ip}`,
            lat !== null ? `Latitude: ${lat}` : "Latitude: não disponível",
            lng !== null ? `Longitude: ${lng}` : "Longitude: não disponível",
            `Data: ${dataStr} (Brasília)`,
        ].join("\n");

        try {
            const transporter = criarTransporter();

            // Roteamento de destino:
            //  - "Solicitação de exclusão de conta" → SMTP_DELETE_ACCOUNT_DEST (caixa LGPD)
            //  - demais assuntos                    → SMTP_SITE_DEST (caixa geral do site)
            const ehSolicitacaoExclusao = /^Solicita(ç|c)(ã|a)o de exclus(ã|a)o de conta/i.test(assunto);
            const destino = ehSolicitacaoExclusao
                ? (process.env.SMTP_DELETE_ACCOUNT_DEST
                    || process.env.SMTP_SITE_DEST
                    || process.env.SMTP_USER)
                : (process.env.SMTP_SITE_DEST || process.env.SMTP_USER);

            const subjectPrefix = ehSolicitacaoExclusao ? "[DiPertin LGPD]" : "[DiPertin Site]";

            await transporter.sendMail({
                from: smtp.from("padrao"),
                to: destino,
                replyTo: email,
                subject: `${subjectPrefix} ${assunto} — ${nome}`,
                html: htmlBody,
                text: textBody,
            });

            console.log(`[contato-site] E-mail enviado — de=${email} para=${destino} ip=${ip} assunto="${assunto}"`);
            return res.status(200).json({ ok: true });
        } catch (err) {
            console.error("[contato-site] Erro SMTP:", err.message);
            return res.status(500).json({ error: "Erro ao enviar. Tente novamente." });
        }
    });
