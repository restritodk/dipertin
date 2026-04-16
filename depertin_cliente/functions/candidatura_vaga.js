/**
 * Cloud Function — envio de candidatura para vaga de emprego.
 * Recebe dados via callable, valida e envia e-mail para a empresa via SMTP.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const smtp = require("./smtp_transport");
const COOLDOWN_CANDIDATURA_MS = 30 * 1000;

function formatarData(d) {
    const pad = (n) => String(n).padStart(2, "0");
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} às ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function buildHtml(nome, telefone, cargo, empresa, urlCurriculo, nomeArquivo, dataStr) {
    return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f4f3f7;font-family:'Segoe UI',Arial,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f3f7;padding:32px 16px">
<tr><td align="center">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.08)">

  <!-- Header -->
  <tr>
    <td style="background:linear-gradient(135deg,#2E7D32 0%,#1B5E20 100%);padding:32px 32px 28px;text-align:center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        <tr>
          <td align="center" style="padding-bottom:16px">
            <div style="width:56px;height:56px;background:rgba(255,255,255,.15);border-radius:14px;display:inline-block;line-height:56px;text-align:center">
              <span style="font-size:28px;color:#fff;font-weight:800">&#128188;</span>
            </div>
          </td>
        </tr>
        <tr>
          <td align="center">
            <h1 style="margin:0;color:#ffffff;font-size:22px;font-weight:700;letter-spacing:-.02em">Nova Candidatura Recebida</h1>
            <p style="margin:6px 0 0;color:rgba(255,255,255,.7);font-size:13px;font-weight:400">${dataStr} · Via App DiPertin</p>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Badge vaga -->
  <tr>
    <td style="padding:28px 32px 0">
      <table role="presentation" cellpadding="0" cellspacing="0">
        <tr>
          <td style="background:#e8f5e9;color:#2E7D32;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;padding:6px 14px;border-radius:20px">
            Vaga: ${cargo}
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Dados do candidato -->
  <tr>
    <td style="padding:20px 32px 0">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#faf9fc;border:1px solid #ece9f1;border-radius:12px;overflow:hidden">
        <tr>
          <td style="padding:20px 24px">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td width="50%" style="padding-bottom:12px;vertical-align:top">
                  <p style="margin:0;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">Candidato</p>
                  <p style="margin:4px 0 0;font-size:15px;font-weight:600;color:#1a1a2e">${nome}</p>
                </td>
                <td width="50%" style="padding-bottom:12px;vertical-align:top">
                  <p style="margin:0;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">Telefone</p>
                  <p style="margin:4px 0 0;font-size:15px;font-weight:600;color:#1a1a2e">${telefone}</p>
                </td>
              </tr>
              <tr>
                <td colspan="2" style="vertical-align:top">
                  <p style="margin:0;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">Empresa</p>
                  <p style="margin:4px 0 0;font-size:15px;font-weight:600;color:#1a1a2e">${empresa}</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <!-- Botão currículo -->
  <tr>
    <td align="center" style="padding:28px 32px 0">
      <p style="margin:0 0 14px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#9e9e9e">Currículo anexado: ${nomeArquivo}</p>
      <a href="${urlCurriculo}" style="display:inline-block;background:#2E7D32;color:#ffffff;font-size:14px;font-weight:600;padding:14px 36px;border-radius:999px;text-decoration:none;letter-spacing:.01em">Baixar Currículo</a>
    </td>
  </tr>

  <!-- Separador -->
  <tr>
    <td style="padding:28px 32px 0">
      <hr style="border:none;border-top:1px solid #ece9f1;margin:0"/>
    </td>
  </tr>

  <!-- Footer -->
  <tr>
    <td style="background:#faf9fc;padding:20px 32px;text-align:center;border-top:1px solid #ece9f1">
      <p style="margin:0;font-size:12px;color:#999">
        <strong style="color:#2E7D32">DiPertin</strong> · Plataforma de vagas de emprego
      </p>
      <p style="margin:6px 0 0;font-size:11px;color:#bbb">
        Este e-mail foi gerado automaticamente pelo aplicativo DiPertin.
      </p>
    </td>
  </tr>

</table>
</td></tr>
</table>
</body>
</html>`;
}

function urlCurriculoValida(url) {
    const raw = String(url || "").trim();
    if (!raw || raw.length > 2048) return false;
    if (!/^https?:\/\//i.test(raw)) return false;
    try {
        const parsed = new URL(raw);
        return parsed.protocol === "https:" || parsed.protocol === "http:";
    } catch (_) {
        return false;
    }
}

exports.enviarCandidaturaVaga = functions
    .runWith({ timeoutSeconds: 60, memory: "256MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth?.uid) {
            throw new functions.https.HttpsError("unauthenticated", "Login necessário para enviar candidatura.");
        }

        const uid = String(context.auth.uid);
        const { vagaId, cargo, empresa, emailEmpresa, nomeCompleto, telefone, urlCurriculo, nomeArquivo } = data || {};

        if (!nomeCompleto || nomeCompleto.trim().length < 3) {
            throw new functions.https.HttpsError("invalid-argument", "Nome completo é obrigatório.");
        }
        if (!telefone || telefone.trim().length < 8) {
            throw new functions.https.HttpsError("invalid-argument", "Telefone é obrigatório.");
        }
        if (!urlCurriculoValida(urlCurriculo)) {
            throw new functions.https.HttpsError("invalid-argument", "Currículo é obrigatório.");
        }

        const rateRef = admin.firestore().collection("rate_candidatura_vaga").doc(uid);
        await admin.firestore().runTransaction(async (tx) => {
            const snap = await tx.get(rateRef);
            const ultimoMs = Number(snap.data()?.ultimo_envio_ms || 0);
            const agora = Date.now();
            if (ultimoMs > 0 && (agora - ultimoMs) < COOLDOWN_CANDIDATURA_MS) {
                throw new functions.https.HttpsError(
                    "resource-exhausted",
                    "Aguarde alguns segundos para enviar outra candidatura.",
                );
            }
            tx.set(rateRef, {
                uid,
                ultimo_envio_ms: agora,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });

        let destino = (emailEmpresa || "").trim();

        if (!destino || !destino.includes("@")) {
            if (vagaId) {
                const vagaDoc = await admin.firestore().collection("vagas").doc(vagaId).get();
                if (vagaDoc.exists) {
                    destino = (vagaDoc.data().email || "").trim();
                }
            }
        }

        if (!destino || !destino.includes("@")) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Esta vaga não possui um e-mail de contato cadastrado."
            );
        }

        const dataBr = new Date(Date.now() + (-3 * 60 * 60 * 1000));
        const dataStr = formatarData(dataBr);

        const htmlBody = buildHtml(
            nomeCompleto.trim(),
            telefone.trim(),
            cargo || "Não informado",
            empresa || "Não informada",
            urlCurriculo,
            nomeArquivo || "curriculo.pdf",
            dataStr
        );

        const textBody = [
            `Nova candidatura recebida via App DiPertin`,
            ``,
            `Vaga: ${cargo}`,
            `Empresa: ${empresa}`,
            ``,
            `Candidato: ${nomeCompleto}`,
            `Telefone: ${telefone}`,
            `Currículo: ${urlCurriculo}`,
            ``,
            `Data: ${dataStr} (Brasília)`,
        ].join("\n");

        try {
            const transporter = smtp.criarTransport("candidatura");
            await transporter.sendMail({
                from: smtp.from("candidatura"),
                to: destino,
                subject: `[DiPertin] Candidatura — ${nomeCompleto.trim()} — ${cargo}`,
                html: htmlBody,
                text: textBody,
            });

            console.log(`[candidatura-vaga] E-mail enviado para=${destino} vaga="${cargo}" candidato="${nomeCompleto}"`);
            return { ok: true };
        } catch (err) {
            console.error("[candidatura-vaga] Erro SMTP:", err.message);
            throw new functions.https.HttpsError("internal", "Erro ao enviar candidatura. Tente novamente.");
        }
    });
