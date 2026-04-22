"use strict";

/**
 * AdminCity — gestão de usuários master_city pelo painel master.
 *
 * Endpoints (callables v1):
 *   - adminCityCadastrarUsuario     → cria Auth + doc users + envia e-mail
 *   - adminCityAtualizarUsuario     → edita nome / telefone / cidade
 *   - adminCityBloquearUsuario      → bloqueia / reativa (toggle)
 *   - adminCityExcluirUsuario       → remove Auth + doc users
 *
 * Apenas chamadores com role=master podem executar.
 */

const admin = require("firebase-admin");
const functions = require("firebase-functions/v1");
const smtp = require("./smtp_transport");

function validarEmail(v) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

async function assertCallerMaster(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
  }
  const snap = await admin.firestore().collection("users").doc(context.auth.uid).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("failed-precondition", "Perfil não encontrado.");
  }
  const d = snap.data() || {};
  const role = String(d.role || d.tipoUsuario || d.tipo || "").trim().toLowerCase();
  if (role !== "master") {
    throw new functions.https.HttpsError("permission-denied", "Apenas contas master.");
  }
  return { uid: context.auth.uid, dados: d };
}

function textoPlanoCadastro({ nome, email, senha, cidade }) {
  return [
    `Olá, ${nome}!`,
    "",
    "Sua conta de gerente regional (AdminCity) no DiPertin foi criada com sucesso.",
    "",
    "Dados de acesso ao painel:",
    `• Painel: https://www.dipertin.com.br/sistema/#/login`,
    `• E-mail: ${email}`,
    `• Senha provisória: ${senha}`,
    cidade ? `• Cidade atendida: ${cidade}` : "",
    "",
    "Por segurança, recomendamos alterar a senha no primeiro acesso.",
    "",
    "Este é um e-mail automático. Por favor, não responda.",
    "— Equipe DiPertin",
  ]
    .filter(Boolean)
    .join("\n");
}

function templateHtmlCadastro({ nome, email, senha, cidade }) {
  const nomeH = escapeHtml(nome);
  const emailH = escapeHtml(email);
  const senhaH = escapeHtml(senha);
  const cidadeH = cidade ? escapeHtml(cidade) : "";
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Acesso AdminCity — DiPertin</title></head>
<body style="margin:0;background:#f5f4f8;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5f4f8;padding:36px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;box-shadow:0 12px 40px rgba(106,27,154,0.14);">
        <tr><td style="background:linear-gradient(135deg,#6A1B9A 0%,#8E24AA 55%,#7B1FA2 100%);padding:36px 28px;text-align:center;">
          <p style="margin:0 0 6px;color:rgba(255,255,255,0.92);font-size:13px;font-weight:600;letter-spacing:2px;text-transform:uppercase;">DiPertin</p>
          <h1 style="margin:0;color:#ffffff;font-size:26px;font-weight:800;letter-spacing:-0.5px;line-height:1.25;">Bem-vindo(a) à equipe!</h1>
          <p style="margin:14px 0 0;color:rgba(255,255,255,0.95);font-size:16px;line-height:1.45;">Sua conta de gerente regional (AdminCity) foi criada.</p>
        </td></tr>
        <tr><td style="padding:36px 32px 24px;">
          <p style="margin:0 0 18px;font-size:17px;line-height:1.55;color:#1a1a2e;">
            Olá, <strong style="color:#6A1B9A;">${nomeH}</strong>!
          </p>
          <p style="margin:0 0 18px;font-size:15px;line-height:1.65;color:#444;">
            Sua conta de administrador regional foi criada no painel do <strong style="color:#FF8F00;">DiPertin</strong>. Use os dados abaixo para o primeiro acesso:
          </p>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:18px 0 8px;background:#faf8fc;border-radius:14px;border:1px solid #ece8f2;">
            <tr><td style="padding:20px;">
              <p style="margin:0 0 10px;font-size:13px;color:#6A1B9A;font-weight:700;letter-spacing:0.3px;text-transform:uppercase;">Painel</p>
              <p style="margin:0 0 16px;font-size:15px;color:#333;">
                <a href="https://www.dipertin.com.br/sistema/#/login" style="color:#6A1B9A;text-decoration:none;font-weight:600;">www.dipertin.com.br/sistema</a>
              </p>
              <p style="margin:0 0 4px;font-size:13px;color:#6A1B9A;font-weight:700;letter-spacing:0.3px;text-transform:uppercase;">E-mail</p>
              <p style="margin:0 0 14px;font-size:15px;color:#333;"><strong>${emailH}</strong></p>
              <p style="margin:0 0 4px;font-size:13px;color:#6A1B9A;font-weight:700;letter-spacing:0.3px;text-transform:uppercase;">Senha provisória</p>
              <p style="margin:0 0 ${cidadeH ? "14px" : "0"};font-size:16px;color:#FF8F00;font-weight:700;letter-spacing:0.5px;font-family:Consolas,'Courier New',monospace;">${senhaH}</p>
              ${cidadeH ? `<p style="margin:0 0 4px;font-size:13px;color:#6A1B9A;font-weight:700;letter-spacing:0.3px;text-transform:uppercase;">Cidade atendida</p>
              <p style="margin:0;font-size:15px;color:#333;"><strong>${cidadeH}</strong></p>` : ""}
            </td></tr>
          </table>
          <p style="margin:18px 0 0;font-size:14px;line-height:1.6;color:#666;">
            <strong>Importante:</strong> por segurança, recomendamos alterar a senha no primeiro acesso.
          </p>
        </td></tr>
        <tr><td style="padding:0 32px 32px;">
          <div style="height:1px;background:linear-gradient(90deg,transparent,#e0dee8,transparent);margin:0 0 22px;"></div>
          <p style="margin:0;font-size:12px;line-height:1.55;color:#888;text-align:center;">
            Este é um e-mail automático. Por favor, não responda a esta mensagem.<br/>
            <span style="color:#aaa;">© ${new Date().getFullYear()} DiPertin</span>
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

/**
 * Cria usuário master_city: Auth + doc users + e-mail de confirmação.
 *
 * data: { nome, telefone, email, senha, cidadeLabel?, cidadeUf?, cidadeNorm?, ufNorm? }
 */
exports.adminCityCadastrarUsuario = functions.https.onCall(async (data, context) => {
  await assertCallerMaster(context);

  const nome = String(data?.nome ?? "").trim();
  const telefone = String(data?.telefone ?? "").trim();
  const email = String(data?.email ?? "").trim().toLowerCase();
  const senha = String(data?.senha ?? "");
  const cidadeLabel = String(data?.cidadeLabel ?? "").trim();
  const cidadeUf = String(data?.cidadeUf ?? "").trim().toUpperCase();
  const cidadeNorm = String(data?.cidadeNorm ?? "").trim().toLowerCase();
  const ufNorm = String(data?.ufNorm ?? "").trim().toLowerCase();

  if (nome.length < 3) {
    throw new functions.https.HttpsError("invalid-argument", "Informe o nome completo.");
  }
  if (!validarEmail(email)) {
    throw new functions.https.HttpsError("invalid-argument", "E-mail inválido.");
  }
  if (senha.length < 6) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A senha deve ter pelo menos 6 caracteres."
    );
  }

  let novoUid;
  try {
    const rec = await admin.auth().createUser({
      email,
      password: senha,
      displayName: nome,
    });
    novoUid = rec.uid;
  } catch (e) {
    if (e.code === "auth/email-already-exists") {
      throw new functions.https.HttpsError(
        "already-exists",
        "Já existe uma conta com este e-mail."
      );
    }
    console.error("[adminCityCadastrarUsuario] createUser", e);
    throw new functions.https.HttpsError(
      "internal",
      "Não foi possível criar o utilizador. Tente outro e-mail."
    );
  }

  const ts = admin.firestore.FieldValue.serverTimestamp();
  const cidadesGerenciadas = cidadeNorm ? [cidadeNorm] : [];
  const payload = {
    nome: nome,
    nome_completo: nome,
    email: email,
    telefone: telefone,
    role: "master_city",
    tipoUsuario: "master_city",
    cidade: cidadeLabel,
    cidade_normalizada: cidadeNorm,
    uf: cidadeUf,
    uf_normalizado: ufNorm,
    cidades_gerenciadas: cidadesGerenciadas,
    ativo: true,
    primeiro_acesso: true,
    dataCadastro: ts,
    data_cadastro: ts,
    skip_email_boas_vindas: true,
    cadastro_painel_admincity: true,
  };

  try {
    await admin.firestore().collection("users").doc(novoUid).set(payload);
  } catch (e) {
    console.error("[adminCityCadastrarUsuario] gravar users", e);
    try {
      await admin.auth().deleteUser(novoUid);
    } catch (_) {}
    throw new functions.https.HttpsError(
      "internal",
      "Falha ao gravar o perfil. Tente novamente."
    );
  }

  // E-mail de confirmação (melhor esforço — não bloqueia a criação).
  try {
    const transporter = smtp.criarTransport("padrao");
    const cidadeExibir = cidadeLabel || "";
    await transporter.sendMail({
      from: smtp.from("padrao"),
      to: email,
      subject: "Sua conta AdminCity no DiPertin foi criada",
      text: textoPlanoCadastro({ nome, email, senha, cidade: cidadeExibir }),
      html: templateHtmlCadastro({ nome, email, senha, cidade: cidadeExibir }),
    });
    await admin.firestore().collection("users").doc(novoUid).update({
      email_cadastro_admincity_em: admin.firestore.FieldValue.serverTimestamp(),
      email_cadastro_admincity_ok: true,
    });
  } catch (e) {
    console.warn("[adminCityCadastrarUsuario] e-mail falhou:", e && e.message);
    try {
      await admin.firestore().collection("users").doc(novoUid).update({
        email_cadastro_admincity_ok: false,
        email_cadastro_admincity_erro: String((e && e.message) || e).slice(0, 400),
      });
    } catch (_) {}
  }

  return { ok: true, uid: novoUid };
});

exports.adminCityAtualizarUsuario = functions.https.onCall(async (data, context) => {
  await assertCallerMaster(context);

  const uid = String(data?.uid ?? "").trim();
  if (!uid) {
    throw new functions.https.HttpsError("invalid-argument", "UID obrigatório.");
  }
  const nome = String(data?.nome ?? "").trim();
  const telefone = String(data?.telefone ?? "").trim();
  const cidadeLabel = String(data?.cidadeLabel ?? "").trim();
  const cidadeUf = String(data?.cidadeUf ?? "").trim().toUpperCase();
  const cidadeNorm = String(data?.cidadeNorm ?? "").trim().toLowerCase();
  const ufNorm = String(data?.ufNorm ?? "").trim().toLowerCase();

  const upd = {
    data_atualizacao: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (nome) {
    upd.nome = nome;
    upd.nome_completo = nome;
  }
  if (telefone) upd.telefone = telefone;
  if (cidadeLabel) {
    upd.cidade = cidadeLabel;
    upd.cidade_normalizada = cidadeNorm;
    upd.uf = cidadeUf;
    upd.uf_normalizado = ufNorm;
    upd.cidades_gerenciadas = cidadeNorm ? [cidadeNorm] : [];
  }

  try {
    await admin.firestore().collection("users").doc(uid).update(upd);
    if (nome) {
      try {
        await admin.auth().updateUser(uid, { displayName: nome });
      } catch (_) {}
    }
  } catch (e) {
    console.error("[adminCityAtualizarUsuario]", e);
    throw new functions.https.HttpsError("internal", "Falha ao atualizar o usuário.");
  }
  return { ok: true };
});

exports.adminCityBloquearUsuario = functions.https.onCall(async (data, context) => {
  await assertCallerMaster(context);
  const uid = String(data?.uid ?? "").trim();
  const bloquear = data?.bloquear === true;
  if (!uid) {
    throw new functions.https.HttpsError("invalid-argument", "UID obrigatório.");
  }
  try {
    await admin.auth().updateUser(uid, { disabled: bloquear });
    await admin.firestore().collection("users").doc(uid).update({
      ativo: !bloquear,
      bloqueado: bloquear,
      data_atualizacao: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("[adminCityBloquearUsuario]", e);
    throw new functions.https.HttpsError("internal", "Falha ao alterar status.");
  }
  return { ok: true };
});

exports.adminCityExcluirUsuario = functions.https.onCall(async (data, context) => {
  await assertCallerMaster(context);
  const uid = String(data?.uid ?? "").trim();
  if (!uid) {
    throw new functions.https.HttpsError("invalid-argument", "UID obrigatório.");
  }
  try {
    try {
      await admin.auth().deleteUser(uid);
    } catch (e) {
      if (e.code !== "auth/user-not-found") {
        throw e;
      }
    }
    await admin.firestore().collection("users").doc(uid).delete();
  } catch (e) {
    console.error("[adminCityExcluirUsuario]", e);
    throw new functions.https.HttpsError("internal", "Falha ao excluir o usuário.");
  }
  return { ok: true };
});
