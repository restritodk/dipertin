"use strict";

/**
 * Cadastro inicial de cliente: grava users/{uid}, consome ticket SMS e reserva CPF
 * em users_cpf_index/{cpf11} de forma atômica (sem corrida entre dois cadastros).
 */
const admin = require("firebase-admin");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const COL_TICKETS = "cadastro_telefone_verificado_tickets";
const COL_CPF_INDEX = "users_cpf_index";

const VERSOES_ACEITE_PERMITIDAS = new Set(["2026-04"]);

const fnOpcoes = {
  cors: true,
  region: "us-central1",
  enforceAppCheck: false,
};

function apenasDigitos(s) {
  return String(s || "").replace(/\D/g, "");
}

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

function normalizarCpf11(raw) {
  const d = apenasDigitos(raw);
  if (d.length !== 11) return null;
  if (/^(\d)\1{10}$/.test(d)) return null;
  return d;
}

function cpfValidoMod11(d11) {
  if (!d11 || d11.length !== 11) return false;
  let soma = 0;
  for (let i = 0; i < 9; i++) {
    soma += parseInt(d11[i], 10) * (10 - i);
  }
  let r = (soma * 10) % 11;
  if (r === 10 || r === 11) r = 0;
  if (r !== parseInt(d11[9], 10)) return false;
  soma = 0;
  for (let i = 0; i < 10; i++) {
    soma += parseInt(d11[i], 10) * (11 - i);
  }
  r = (soma * 10) % 11;
  if (r === 10 || r === 11) r = 0;
  return r === parseInt(d11[10], 10);
}

function strLimpo(s, max) {
  const t = String(s ?? "").trim();
  if (!t) return "";
  return t.length > max ? t.slice(0, max) : t;
}

function cpfComMascara11(d11) {
  if (!d11 || d11.length !== 11) return "";
  return `${d11.slice(0, 3)}.${d11.slice(3, 6)}.${d11.slice(6, 9)}-${d11.slice(9)}`;
}

/** Bloqueia CPF já usado em outro doc `users` (inclui legados sem users_cpf_index). */
async function assertCpfLivreOuDoProprioUsuario(db, cpf11, uid) {
  const snap = await db
    .collection("users")
    .where("cpf_digitos", "==", cpf11)
    .limit(25)
    .get();
  for (const doc of snap.docs) {
    if (doc.id !== uid) {
      throw new HttpsError(
        "already-exists",
        "Já existe um cadastro com este CPF."
      );
    }
  }
}

exports.cadastroClienteSalvarPerfilInicial = onCall(fnOpcoes, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Faça login novamente e conclua o cadastro.");
  }

  const uid = request.auth.uid;
  const tokenEmail = String(request.auth.token.email || "").trim().toLowerCase();
  if (!tokenEmail) {
    throw new HttpsError(
      "failed-precondition",
      "Conta sem e-mail confirmado. Use outro método de cadastro."
    );
  }

  const data = request.data || {};
  const ticketId =
    typeof data.ticketId === "string" ? data.ticketId.trim() : "";
  const rawTel = data.telefone;
  const phoneDigits = normalizarTelefoneBr(rawTel);

  const nome = strLimpo(data.nome, 120);
  const cpfRaw = data.cpf;
  const cpf11 = normalizarCpf11(cpfRaw);
  const cidade = strLimpo(data.cidade, 120);
  const uf = strLimpo(data.uf, 8);
  const cidadeNorm = strLimpo(data.cidade_normalizada, 160);
  const ufNorm = strLimpo(data.uf_normalizado, 80);
  const versaoAceite = strLimpo(data.aceite_termos_versao, 32);

  if (!ticketId || ticketId.length < 16) {
    throw new HttpsError("invalid-argument", "Sessão de verificação inválida.");
  }
  if (!phoneDigits) {
    throw new HttpsError("invalid-argument", "Telefone inválido.");
  }
  if (!nome) {
    throw new HttpsError("invalid-argument", "Informe seu nome.");
  }
  if (!cpf11 || !cpfValidoMod11(cpf11)) {
    throw new HttpsError("invalid-argument", "CPF inválido.");
  }
  if (!cidade) {
    throw new HttpsError("invalid-argument", "Informe a cidade.");
  }
  if (!VERSOES_ACEITE_PERMITIDAS.has(versaoAceite)) {
    throw new HttpsError(
      "failed-precondition",
      "Atualize o aplicativo para concluir o cadastro."
    );
  }

  const telefoneDoc = apenasDigitos(String(data.telefone || ""));
  if (telefoneDoc !== phoneDigits) {
    throw new HttpsError("invalid-argument", "Telefone inválido.");
  }

  const db = admin.firestore();
  await assertCpfLivreOuDoProprioUsuario(db, cpf11, uid);

  const ticketRef = db.collection(COL_TICKETS).doc(ticketId);
  const userRef = db.collection("users").doc(uid);
  const cpfIndexRef = db.collection(COL_CPF_INDEX).doc(cpf11);

  await db.runTransaction(async (tx) => {
    const ticketSnap = await tx.get(ticketRef);
    if (!ticketSnap.exists) {
      throw new HttpsError(
        "not-found",
        "Verificação expirada ou inválida. Valide o celular novamente."
      );
    }
    const t = ticketSnap.data();
    if (t.consumido === true) {
      throw new HttpsError(
        "failed-precondition",
        "Este código de verificação já foi utilizado."
      );
    }
    if (t.telefone_digitos !== phoneDigits) {
      throw new HttpsError(
        "invalid-argument",
        "O telefone não confere com o número verificado."
      );
    }
    const exp = t.expira_em;
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

    const cpfIdxSnap = await tx.get(cpfIndexRef);
    if (cpfIdxSnap.exists) {
      const owner = String(cpfIdxSnap.data().uid || "");
      if (owner && owner !== uid) {
        throw new HttpsError(
          "already-exists",
          "Já existe um cadastro com este CPF."
        );
      }
    }

    const userSnap = await tx.get(userRef);
    if (userSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Este usuário já possui cadastro. Entre com e-mail e senha."
      );
    }

    tx.set(userRef, {
      nome,
      cpf: cpfComMascara11(cpf11).slice(0, 20),
      cpf_digitos: cpf11,
      telefone: String(data.telefone || "").trim().slice(0, 32),
      email: tokenEmail,
      cidade,
      uf,
      cidade_normalizada: cidadeNorm || cidade,
      uf_normalizado: ufNorm,
      tipoUsuario: "cliente",
      role: "cliente",
      ativo: true,
      status_conta: "ativa",
      onboarding_endereco_pendente: true,
      onboarding_endereco_criado_em: admin.firestore.FieldValue.serverTimestamp(),
      cpf_alteracao_bloqueada: true,
      dataCadastro: admin.firestore.FieldValue.serverTimestamp(),
      totalConcluido: 0,
      saldo: 0,
      aceite_termos_privacidade_em: admin.firestore.FieldValue.serverTimestamp(),
      aceite_termos_versao: versaoAceite,
      telefone_verificado_sms_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(cpfIndexRef, {
      uid,
      cpf_digitos: cpf11,
      criado_em: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.update(ticketRef, {
      consumido: true,
      consumido_por_uid: uid,
      consumido_em: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

/**
 * Primeira gravação de CPF no perfil (ex.: conta Google) — reserva users_cpf_index
 * e define cpf_digitos, com as mesmas regras de unicidade do cadastro por e-mail.
 */
exports.perfilClienteReservarCpf = onCall(fnOpcoes, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError(
      "unauthenticated",
      "Faça login para atualizar o CPF."
    );
  }

  const uid = request.auth.uid;
  const cpf11 = normalizarCpf11(request.data && request.data.cpf);
  if (!cpf11 || !cpfValidoMod11(cpf11)) {
    throw new HttpsError("invalid-argument", "CPF inválido.");
  }

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Perfil não encontrado.");
  }

  const u = userSnap.data() || {};
  const bloqueado = u.cpf_alteracao_bloqueada === true;
  const cpfAtual = normalizarCpf11(u.cpf_digitos || u.cpf || "");

  if (bloqueado) {
    if (cpfAtual === cpf11) {
      return { ok: true, inalterado: true };
    }
    throw new HttpsError(
      "failed-precondition",
      "O CPF já foi confirmado e não pode ser alterado aqui. Fale com o suporte."
    );
  }

  await assertCpfLivreOuDoProprioUsuario(db, cpf11, uid);

  const cpfIndexRef = db.collection(COL_CPF_INDEX).doc(cpf11);
  const cpfMascarado = cpfComMascara11(cpf11);

  await db.runTransaction(async (tx) => {
    const idxSnap = await tx.get(cpfIndexRef);
    if (idxSnap.exists) {
      const owner = String(idxSnap.data().uid || "");
      if (owner && owner !== uid) {
        throw new HttpsError(
          "already-exists",
          "Já existe um cadastro com este CPF."
        );
      }
    }

    const uSnap = await tx.get(userRef);
    if (!uSnap.exists) {
      throw new HttpsError("not-found", "Perfil não encontrado.");
    }
    const u2 = uSnap.data() || {};
    if (u2.cpf_alteracao_bloqueada === true) {
      const cur = normalizarCpf11(u2.cpf_digitos || u2.cpf || "");
      if (cur && cur !== cpf11) {
        throw new HttpsError(
          "failed-precondition",
          "O CPF não pode ser alterado aqui."
        );
      }
      if (cur === cpf11) {
        return;
      }
    }

    tx.set(
      cpfIndexRef,
      {
        uid,
        cpf_digitos: cpf11,
        criado_em: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.update(userRef, {
      cpf: cpfMascarado.slice(0, 20),
      cpf_digitos: cpf11,
      cpf_alteracao_bloqueada: true,
    });
  });

  return { ok: true };
});
