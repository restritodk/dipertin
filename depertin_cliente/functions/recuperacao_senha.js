"use strict";

/**
 * Recuperação de senha: OTP 4 dígitos, e-mail SMTP, tokens em Firestore.
 * Credenciais: arquivo functions/.env (carregado em index.js).
 */

const crypto = require("crypto");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const smtp = require("./smtp_transport");

const COL_TOKENS = "password_reset_tokens";
const COL_SESSIONS = "password_recovery_sessions";
const COL_RATE_EMAIL = "password_reset_rate_email";
const COL_RATE_IP = "password_reset_rate_ip";

const OTP_TTL_MS = 10 * 60 * 1000;
/** Tempo para informar a nova senha após OTP válido (evita createCustomToken / IAM). */
const SESSION_TTL_MS = 15 * 60 * 1000;
const MAX_OTP_ATTEMPTS = 5;
const MAX_SOLICIT_EMAIL_15M = 5;
const MAX_SOLICIT_IP_15M = 20;
const WINDOW_15M = 15 * 60 * 1000;
const MIN_RESPONSE_MS = 450;

const fnOpcoes = {
  cors: true,
  region: "us-central1",
  enforceAppCheck: false,
};

const limparEnv = smtp.limparEnv;

/** Firestore Timestamp / objeto serializado — evita crash em .toMillis() indefinido. */
function timestampMillis(ts) {
  if (ts == null) return null;
  if (typeof ts.toMillis === "function") return ts.toMillis();
  if (typeof ts.toDate === "function") return ts.toDate().getTime();
  if (typeof ts.seconds === "number") {
    return ts.seconds * 1000 + (ts.nanoseconds || 0) / 1e6;
  }
  return null;
}

function getOtpPepper() {
  const p = limparEnv(process.env.OTP_RECUPERACAO_PEPPER);
  if (!p || p.length < 16) {
    throw new HttpsError(
      "failed-precondition",
      "Configuração do servidor incompleta (OTP_RECUPERACAO_PEPPER)."
    );
  }
  return p;
}

function assertSmtpPadraoConfigurado() {
  try {
    smtp.criarTransport("padrao");
  } catch (e) {
    throw new HttpsError("failed-precondition", "Configuração SMTP do servidor incompleta.");
  }
}

function hashEmailKey(emailNorm) {
  return crypto.createHash("sha256").update(emailNorm, "utf8").digest("hex").slice(0, 48);
}

function hashOtp(emailNorm, otp, pepper) {
  return crypto
    .createHash("sha256")
    .update(`${pepper}|${emailNorm}|${otp}`, "utf8")
    .digest("hex");
}

function timingSafeEqualHex(a, b) {
  try {
    const ba = Buffer.from(a, "hex");
    const bb = Buffer.from(b, "hex");
    if (ba.length !== bb.length) return false;
    return crypto.timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}

function gerarOtp4() {
  return crypto.randomInt(0, 10000).toString().padStart(4, "0");
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function normalizarEmail(raw) {
  if (typeof raw !== "string") return "";
  return raw.trim().toLowerCase().normalize("NFC");
}

function validarFormatoEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function extrairIp(request) {
  const h = request.rawRequest && request.rawRequest.headers;
  if (!h) return "";
  const xff = h["x-forwarded-for"] || h["X-Forwarded-For"];
  if (xff && typeof xff === "string") {
    return xff.split(",")[0].trim();
  }
  return (request.rawRequest.ip || "").toString();
}

function hashIpKey(ip) {
  if (!ip) return "unknown";
  return crypto.createHash("sha256").update(ip, "utf8").digest("hex").slice(0, 32);
}

async function rateLimitDoc(db, col, docId, max, windowMs) {
  const ref = db.collection(col).doc(docId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    let times = snap.exists ? snap.data().timestamps || [] : [];
    times = times.filter((t) => now - t < windowMs);
    if (times.length >= max) {
      throw new HttpsError(
        "resource-exhausted",
        "Muitas solicitações. Tente novamente mais tarde."
      );
    }
    times.push(now);
    tx.set(
      ref,
      {
        timestamps: times,
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

function templateHtmlOtp(otp, minutos) {
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;background:#f4f2f8;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#333;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f2f8;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:520px;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 8px 32px rgba(106,27,154,0.12);">
        <tr><td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 100%);padding:28px 24px;text-align:center;">
          <h1 style="margin:0;color:#fff;font-size:22px;font-weight:700;letter-spacing:0.5px;">DiPertin</h1>
          <p style="margin:8px 0 0;color:rgba(255,255,255,0.9);font-size:14px;">Recuperação de senha</p>
        </td></tr>
        <tr><td style="padding:32px 28px;">
          <p style="margin:0 0 16px;font-size:15px;line-height:1.5;">Use o código abaixo para redefinir sua senha. Não compartilhe este código com ninguém.</p>
          <div style="text-align:center;margin:28px 0;">
            <span style="display:inline-block;font-size:32px;font-weight:800;letter-spacing:12px;color:#FF8F00;background:#fff8e6;padding:16px 28px;border-radius:12px;border:2px dashed #FF8F00;">${otp}</span>
          </div>
          <p style="margin:0 0 8px;font-size:14px;color:#666;">Este código expira em <strong>${minutos} minutos</strong>.</p>
          <p style="margin:16px 0 0;font-size:13px;color:#888;line-height:1.5;">Se você não solicitou essa recuperação, ignore este e-mail. Sua conta continua segura.</p>
        </td></tr>
        <tr><td style="padding:16px 24px 28px;border-top:1px solid #eee;text-align:center;font-size:12px;color:#aaa;">
          Mensagem automática — não responda a este e-mail.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function templateTextoOtp(otp, minutos) {
  return `DiPertin — Recuperação de senha\n\nCódigo: ${otp}\nVálido por ${minutos} minutos.\n\nSe não foi você, ignore este e-mail.`;
}

function validarSenhaRecuperacao(pw) {
  if (typeof pw !== "string") return false;
  if (pw.length < 8 || pw.length > 4096) return false;
  if (!/[A-Za-z]/.test(pw)) return false;
  if (!/\d/.test(pw)) return false;
  return true;
}

/** E-mail de confirmação após troca de senha (Admin SDK / fluxo recuperação). */
async function enviarEmailConfirmacaoSenhaAlterada(emailNorm) {
  const agora = new Date();
  const fmt = agora.toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    dateStyle: "short",
    timeStyle: "medium",
  });
  try {
    const transport = smtp.criarTransport("padrao");
    const info = await transport.sendMail({
      from: smtp.from("padrao"),
      to: emailNorm,
      subject: "Senha alterada com sucesso",
      text: `DiPertin\n\nSua senha foi alterada em ${fmt}.\n\nSe não foi você, entre em contato com o suporte pelo aplicativo.`,
      html: templateHtmlSenhaAlterada(fmt),
    });
    console.log(`[recuperacao] Confirmação senha enviada para ${emailNorm} messageId=${info.messageId}`);
  } catch (err) {
    console.error("[recuperacao] SMTP confirmação", err);
  }
}

function templateHtmlSenhaAlterada(dataHoraBr) {
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;background:#f4f2f8;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#333;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f2f8;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:520px;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 8px 32px rgba(106,27,154,0.12);">
        <tr><td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 100%);padding:28px 24px;text-align:center;">
          <h1 style="margin:0;color:#fff;font-size:22px;">Senha alterada</h1>
        </td></tr>
        <tr><td style="padding:32px 28px;">
          <p style="margin:0 0 12px;font-size:15px;">Sua senha no DiPertin foi alterada com sucesso.</p>
          <p style="margin:0;font-size:14px;color:#666;"><strong>Data e hora:</strong> ${dataHoraBr}</p>
          <p style="margin:20px 0 0;font-size:13px;color:#888;">Se você não reconhece essa alteração, entre em contato com o suporte imediatamente pelo aplicativo.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

async function invalidarTokensAtivos(db, userId) {
  const q = await db
    .collection(COL_TOKENS)
    .where("user_id", "==", userId)
    .where("status", "==", "ativo")
    .get();
  if (q.empty) return;
  const batch = db.batch();
  q.docs.forEach((d) => {
    batch.update(d.ref, {
      status: "expirado",
      invalidado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  await batch.commit();
}

/**
 * 1) Solicita OTP — resposta genérica se o e-mail não existir (sem enumeração).
 */
exports.recuperacaoSenhaSolicitar = onCall(fnOpcoes, async (request) => {
  const inicio = Date.now();
  const emailRaw = request.data && request.data.email;
  const emailNorm = normalizarEmail(emailRaw);
  if (!validarFormatoEmail(emailNorm)) {
    throw new HttpsError("invalid-argument", "E-mail inválido.");
  }

  const db = admin.firestore();
  const emailKey = hashEmailKey(emailNorm);
  const ipKey = hashIpKey(extrairIp(request));

  try {
    await rateLimitDoc(db, COL_RATE_EMAIL, emailKey, MAX_SOLICIT_EMAIL_15M, WINDOW_15M);
    await rateLimitDoc(db, COL_RATE_IP, ipKey, MAX_SOLICIT_IP_15M, WINDOW_15M);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw e;
  }

  let userRecord = null;
  try {
    userRecord = await admin.auth().getUserByEmail(emailNorm);
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      userRecord = null;
    } else {
      console.error("[recuperacao] getUserByEmail", e);
      throw new HttpsError("internal", "Não foi possível processar a solicitação.");
    }
  }

  /** ID do doc Firestore (ou UUID falso se não houver conta) — cliente envia na verificação. */
  let tokenIdCliente = crypto.randomUUID();

  if (userRecord) {
    const pepper = getOtpPepper();
    assertSmtpPadraoConfigurado();

    await invalidarTokensAtivos(db, userRecord.uid);
    const otp = gerarOtp4();
    const otpHash = hashOtp(emailNorm, otp, pepper);
    const agora = admin.firestore.Timestamp.now();
    const expira = admin.firestore.Timestamp.fromMillis(
      agora.toMillis() + OTP_TTL_MS
    );

    const docRef = await db.collection(COL_TOKENS).add({
      user_id: userRecord.uid,
      email: emailNorm,
      otp_hash: otpHash,
      expires_at: expira,
      status: "ativo",
      attempts: 0,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      const transport = smtp.criarTransport("padrao");
      const info = await transport.sendMail({
        from: smtp.from("padrao"),
        to: emailNorm,
        subject: "Recuperação de senha",
        text: templateTextoOtp(otp, 10),
        html: templateHtmlOtp(otp, 10),
      });
      console.log(`[recuperacao] OTP enviado para ${emailNorm} messageId=${info.messageId}`);
    } catch (err) {
      console.error("[recuperacao] SMTP envio OTP", err);
      try {
        await docRef.delete();
      } catch (del) {
        console.error("[recuperacao] rollback token", del);
      }
      throw new HttpsError("internal", "Não foi possível enviar o e-mail. Tente mais tarde.");
    }
    tokenIdCliente = docRef.id;
  }

  const decorrido = Date.now() - inicio;
  if (decorrido < MIN_RESPONSE_MS) {
    await sleep(MIN_RESPONSE_MS - decorrido);
  }

  return {
    ok: true,
    mensagem:
      "Se o e-mail estiver associado a uma conta, enviamos um código de verificação. Verifique sua caixa de entrada.",
    tokenId: tokenIdCliente,
  };
});

/**
 * 2) Valida OTP e devolve custom token para updatePassword no cliente.
 */
exports.recuperacaoSenhaVerificarOtp = onCall(fnOpcoes, async (request) => {
  const msgErro = "Código inválido ou expirado. Solicite um novo código.";
  try {
    const emailNorm = normalizarEmail(request.data && request.data.email);
    const otp = (request.data && String(request.data.otp || "").replace(/\D/g, "")).slice(0, 4);
    const tokenIdIn = limparEnv(
      request.data && request.data.tokenId != null
        ? String(request.data.tokenId)
        : ""
    );

    if (!validarFormatoEmail(emailNorm)) {
      throw new HttpsError("invalid-argument", "Dados inválidos.");
    }
    if (otp.length !== 4) {
      throw new HttpsError("invalid-argument", "Código deve ter 4 dígitos.");
    }

    const db = admin.firestore();

    let docSnap = null;

    if (tokenIdIn.length > 0) {
      const direct = await db.collection(COL_TOKENS).doc(tokenIdIn).get();
      if (direct.exists) {
        const d0 = direct.data() || {};
        if (normalizarEmail(d0.email || "") !== emailNorm) {
          throw new HttpsError("invalid-argument", msgErro);
        }
        docSnap = direct;
      }
    }

    if (!docSnap) {
      try {
        const snap = await db
          .collection(COL_TOKENS)
          .where("email", "==", emailNorm)
          .where("status", "==", "ativo")
          .get();
        if (snap.empty) {
          throw new HttpsError("invalid-argument", msgErro);
        }
        const sorted = snap.docs.slice().sort((a, b) => {
          const ca = timestampMillis(a.data().created_at) || 0;
          const cb = timestampMillis(b.data().created_at) || 0;
          return cb - ca;
        });
        docSnap = sorted[0];
      } catch (qerr) {
        if (qerr instanceof HttpsError) throw qerr;
        console.error("[recuperacao] query password_reset_tokens", qerr);
        const needIndex =
          (qerr && qerr.code === 9) ||
          (qerr && String(qerr.message || "").includes("index"));
        if (needIndex) {
          throw new HttpsError(
            "failed-precondition",
            "Serviço em atualização. Aguarde 1 minuto e tente novamente."
          );
        }
        throw qerr;
      }
    }

    const data = docSnap.data();
    if (!data) {
      throw new HttpsError("invalid-argument", msgErro);
    }

    const expMs = timestampMillis(data.expires_at);
    const agoraMs = admin.firestore.Timestamp.now().toMillis();
    if (expMs == null) {
      console.error("[recuperacao] token sem expires_at válido", docSnap.id);
      throw new HttpsError("invalid-argument", msgErro);
    }
    if (expMs < agoraMs) {
      await docSnap.ref.update({
        status: "expirado",
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("invalid-argument", msgErro);
    }

    const attempts = (data.attempts || 0) + 1;
    if (attempts > MAX_OTP_ATTEMPTS) {
      await docSnap.ref.update({
        status: "expirado",
        attempts,
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("invalid-argument", msgErro);
    }

    const pepper = getOtpPepper();
    const esperado = String(data.otp_hash || "").trim();
    const calculado = hashOtp(emailNorm, otp, pepper);

    if (!timingSafeEqualHex(esperado, calculado)) {
      await docSnap.ref.update({
        attempts,
        atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("invalid-argument", msgErro);
    }

    const uid = String(data.user_id || "").trim();
    if (!uid) {
      console.error("[recuperacao] token sem user_id", docSnap.id);
      throw new HttpsError("internal", "Erro ao concluir a recuperação.");
    }

    /**
     * Sessão de recuperação no Firestore + marca OTP como utilizado (batch).
     * Não usamos createCustomToken (costuma falhar por IAM / signBlob na conta de serviço).
     * A nova senha é aplicada em recuperacaoSenhaDefinirNovaSenha com admin.auth().updateUser.
     */
    const sessionId = crypto.randomUUID();
    const sessRef = db.collection(COL_SESSIONS).doc(sessionId);
    const agoraTs = admin.firestore.Timestamp.now();
    const expiraSess = admin.firestore.Timestamp.fromMillis(
      agoraTs.toMillis() + SESSION_TTL_MS
    );

    const batch = db.batch();
    batch.set(sessRef, {
      uid,
      email: emailNorm,
      expires_at: expiraSess,
      status: "pendente",
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(docSnap.ref, {
      status: "utilizado",
      attempts,
      utilizado_em: admin.firestore.FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } catch (batchErr) {
      console.error("[recuperacao] batch sessão OTP", batchErr);
      throw new HttpsError(
        "internal",
        "Erro ao gerar sessão de recuperação. Tente novamente."
      );
    }

    return { ok: true, sessionId };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[recuperacao] recuperacaoSenhaVerificarOtp", e);
    throw new HttpsError(
      "internal",
      "Erro ao validar o código. Tente novamente."
    );
  }
});

/**
 * 3) Define a nova senha no Auth (servidor), após OTP validado (sessionId).
 */
exports.recuperacaoSenhaDefinirNovaSenha = onCall(fnOpcoes, async (request) => {
  const sessionId = limparEnv(request.data && request.data.sessionId);
  const newPassword =
    request.data && request.data.newPassword != null
      ? String(request.data.newPassword)
      : "";

  if (!sessionId || !validarSenhaRecuperacao(newPassword)) {
    throw new HttpsError("invalid-argument", "Dados inválidos.");
  }

  const db = admin.firestore();
  const ref = db.collection(COL_SESSIONS).doc(sessionId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError(
      "invalid-argument",
      "Sessão inválida ou expirada. Solicite um novo código."
    );
  }
  const s = snap.data();
  const expMs = timestampMillis(s.expires_at);
  if (expMs == null || expMs < Date.now()) {
    await ref.update({ status: "expirado" }).catch(() => {});
    throw new HttpsError(
      "invalid-argument",
      "Sessão expirada. Solicite um novo código."
    );
  }
  if (s.status !== "pendente") {
    throw new HttpsError(
      "invalid-argument",
      "Sessão inválida ou expirada. Solicite um novo código."
    );
  }
  const uid = String(s.uid || "").trim();
  if (!uid) {
    throw new HttpsError("internal", "Erro ao concluir a recuperação.");
  }

  try {
    await admin.auth().updateUser(uid, { password: newPassword });
  } catch (e) {
    console.error("[recuperacao] updateUser", e);
    const code = e && e.code;
    if (code === "auth/weak-password") {
      throw new HttpsError(
        "invalid-argument",
        "Senha fraca. Use mais caracteres ou combine letras, números e símbolos."
      );
    }
    if (code === "auth/invalid-password") {
      throw new HttpsError(
        "invalid-argument",
        "Senha inválida. Tente outra combinação."
      );
    }
    throw new HttpsError(
      "internal",
      "Não foi possível alterar a senha. Tente novamente."
    );
  }

  await ref.update({
    status: "usado",
    usado_em: admin.firestore.FieldValue.serverTimestamp(),
  });

  await invalidarTokensAtivos(db, uid);

  const user = await admin.auth().getUser(uid);
  if (user.email) {
    await enviarEmailConfirmacaoSenhaAlterada(user.email);
  }

  return { ok: true };
});

/**
 * 4) Opcional: após updatePassword no cliente (fluxo antigo): e-mail de confirmação.
 */
exports.recuperacaoSenhaPosAlteracao = onCall(fnOpcoes, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Sessão necessária.");
  }

  const uid = request.auth.uid;
  const user = await admin.auth().getUser(uid);
  const email = user.email;
  if (!email) {
    throw new HttpsError("failed-precondition", "Conta sem e-mail.");
  }

  const db = admin.firestore();
  await invalidarTokensAtivos(db, uid);

  await enviarEmailConfirmacaoSenhaAlterada(email);

  return { ok: true };
});
