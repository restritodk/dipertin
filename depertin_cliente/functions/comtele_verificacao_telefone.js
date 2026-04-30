"use strict";

/**
 * Verificação de telefone no cadastro (SMS) via API Comtele — dois fatores.
 * Chave: COMTELE_AUTH_KEY em functions/.env (nunca commitar).
 * Docs: https://docs.comtele.com.br/
 */

const crypto = require("crypto");
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const COL_TICKETS = "cadastro_telefone_verificado_tickets";
const COL_RATE_IP = "comtele_cadastro_rate_ip";
const COL_RATE_PHONE = "comtele_cadastro_rate_phone";

const TICKET_TTL_MS = 15 * 60 * 1000;
const TOKEN_EXPIRE_MINUTES = 10;
const MAX_ENVIO_PHONE_15M = 6;
const MAX_ENVIO_IP_15M = 30;
const WINDOW_15M = 15 * 60 * 1000;
const MIN_RESPONSE_MS = 400;

const COMTELE_TOKEN_URL = "https://sms.comtele.com.br/api/v2/tokenmanager";

const fnOpcoes = {
  cors: true,
  region: "us-central1",
  enforceAppCheck: false,
};

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function getAuthKey() {
  const k = (process.env.COMTELE_AUTH_KEY || "").trim();
  if (!k || k.length < 20) {
    throw new HttpsError(
      "failed-precondition",
      "Serviço de SMS não configurado (COMTELE_AUTH_KEY)."
    );
  }
  return k;
}

function apenasDigitos(s) {
  return String(s || "").replace(/\D/g, "");
}

/** Brasil: DDD + 9 + 8 dígitos (11 números), sem +55. */
function normalizarTelefoneBr(raw) {
  let d = apenasDigitos(raw);
  if (d.startsWith("55") && d.length >= 13) {
    d = d.slice(2);
  }
  if (d.length !== 11) return null;
  const ddd = parseInt(d.slice(0, 2), 10);
  if (ddd < 11 || ddd > 99) return null;
  if (d.charAt(2) !== "9") return null;
  return d;
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
        "Muitas solicitações de SMS. Aguarde alguns minutos e tente novamente."
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

async function comtelePostEnviar(authKey, phoneDigits) {
  const res = await fetch(COMTELE_TOKEN_URL, {
    method: "POST",
    headers: {
      "auth-key": authKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      PhoneNumber: phoneDigits,
      // Comtele concatena: "{Prefix}: Codigo de Autorizacao {XXXXXX}"
      // Texto curto em GSM-7 (sem acentos) para custo/previsibilidade.
      Prefix:
        "DiPertin - Verificacao de cadastro. Valido 10 min. Nao compartilhe este codigo",
      EnforceSecureValidation: true,
      ExpireInMinutes: TOKEN_EXPIRE_MINUTES,
    }),
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = { Message: text };
  }
  if (!res.ok) {
    console.error("[comtele] POST tokenmanager", res.status, data);
    throw new HttpsError(
      "internal",
      "Não foi possível enviar o SMS agora. Confira o número e tente em instantes."
    );
  }
  return data;
}

async function comtelePutValidar(authKey, phoneDigits, tokenCode) {
  const res = await fetch(COMTELE_TOKEN_URL, {
    method: "PUT",
    headers: {
      "auth-key": authKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      TokenCode: String(tokenCode).trim(),
      PhoneNumber: phoneDigits,
    }),
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = { Message: text };
  }
  return { ok: res.ok, status: res.status, data };
}

exports.comteleCadastroTelefoneEnviarCodigo = onCall(fnOpcoes, async (request) => {
  const authKey = getAuthKey();
  const raw = request.data && request.data.telefone;
  const phoneDigits = normalizarTelefoneBr(raw);
  if (!phoneDigits) {
    throw new HttpsError(
      "invalid-argument",
      "Informe um celular válido com DDD (11 dígitos). Ex.: (11) 98765-4321."
    );
  }

  const db = admin.firestore();
  const ip = extrairIp(request);
  await rateLimitDoc(db, COL_RATE_IP, hashIpKey(ip), MAX_ENVIO_IP_15M, WINDOW_15M);
  await rateLimitDoc(
    db,
    COL_RATE_PHONE,
    crypto.createHash("sha256").update(phoneDigits, "utf8").digest("hex").slice(0, 48),
    MAX_ENVIO_PHONE_15M,
    WINDOW_15M
  );

  await sleep(MIN_RESPONSE_MS);
  await comtelePostEnviar(authKey, phoneDigits);

  return { ok: true };
});

exports.comteleCadastroTelefoneValidarCodigo = onCall(fnOpcoes, async (request) => {
  const authKey = getAuthKey();
  const raw = request.data && request.data.telefone;
  const codigo = request.data && request.data.codigo;
  const phoneDigits = normalizarTelefoneBr(raw);
  if (!phoneDigits) {
    throw new HttpsError("invalid-argument", "Telefone inválido.");
  }
  if (typeof codigo !== "string" && typeof codigo !== "number") {
    throw new HttpsError("invalid-argument", "Informe o código recebido por SMS.");
  }
  const codigoStr = String(codigo).replace(/\D/g, "");
  if (codigoStr.length !== 6) {
    throw new HttpsError(
      "invalid-argument",
      "O código deve ter 6 dígitos."
    );
  }

  const db = admin.firestore();
  await sleep(MIN_RESPONSE_MS);

  const { ok, status, data } = await comtelePutValidar(authKey, phoneDigits, codigoStr);
  if (!ok) {
    console.warn("[comtele] PUT validar", status, data);
    const msg =
      (data && data.Message) ||
      (data && data.message) ||
      "Código inválido ou expirado. Peça um novo código.";
    throw new HttpsError(
      status === 400 ? "invalid-argument" : "internal",
      typeof msg === "string" ? msg : "Não foi possível validar o código."
    );
  }

  const ticketId = crypto.randomBytes(24).toString("hex");
  const agora = Date.now();
  await db.collection(COL_TICKETS).doc(ticketId).set({
    telefone_digitos: phoneDigits,
    criado_em: admin.firestore.FieldValue.serverTimestamp(),
    expira_em: admin.firestore.Timestamp.fromMillis(agora + TICKET_TTL_MS),
    consumido: false,
  });

  return { ok: true, ticketId };
});

/**
 * Após createUser + doc inicial em `users`, confirma que o telefone foi validado por SMS.
 */
exports.cadastroConfirmarTelefoneVerificadoSms = onCall(fnOpcoes, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Faça o cadastro até o fim e tente novamente.");
  }

  const uid = request.auth.uid;
  const ticketId =
    request.data &&
    (typeof request.data.ticketId === "string" ? request.data.ticketId.trim() : "");
  const rawTel = request.data && request.data.telefone;
  const phoneDigits = normalizarTelefoneBr(rawTel);

  if (!ticketId || ticketId.length < 16) {
    throw new HttpsError("invalid-argument", "Sessão de verificação inválida.");
  }
  if (!phoneDigits) {
    throw new HttpsError("invalid-argument", "Telefone inválido.");
  }

  const db = admin.firestore();
  const ref = db.collection(COL_TICKETS).doc(ticketId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError(
        "not-found",
        "Verificação expirada ou inválida. Valide o celular novamente."
      );
    }
    const d = snap.data();
    if (d.consumido === true) {
      throw new HttpsError(
        "failed-precondition",
        "Este código de verificação já foi utilizado."
      );
    }
    if (d.telefone_digitos !== phoneDigits) {
      throw new HttpsError(
        "invalid-argument",
        "O telefone não confere com o número verificado."
      );
    }
    const exp = d.expira_em;
    const expMs =
      exp && typeof exp.toMillis === "function"
        ? exp.toMillis()
        : exp && exp.seconds
          ? exp.seconds * 1000
          : 0;
    if (!expMs || Date.now() > expMs) {
      throw new HttpsError(
        "deadline-exceeded",
        "A verificação do celular expirou. Envie um novo código."
      );
    }

    tx.update(ref, {
      consumido: true,
      consumido_por_uid: uid,
      consumido_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    const userRef = db.collection("users").doc(uid);
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Perfil ainda não criado. Conclua o cadastro e tente novamente."
      );
    }
    const u = userSnap.data();
    const telDoc = apenasDigitos(u.telefone || "");
    if (telDoc !== phoneDigits) {
      throw new HttpsError(
        "invalid-argument",
        "O telefone do cadastro não confere com o número verificado por SMS."
      );
    }

    tx.update(userRef, {
      telefone_verificado_sms_em: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});
