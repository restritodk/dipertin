"use strict";

/**
 * Gestão Comercial — E-mail transacional por loja.
 * SMTP (nodemailer) ou API (SendGrid, SES, Mailgun, Resend, Postmark, custom).
 * Secrets criptografados em repouso (AES-256-GCM).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");
const https = require("https");
const http = require("http");

const CONFIG_PADRAO = {
    region: "southamerica-east1",
    cpu: 1,
    memory: "512MiB",
    maxInstances: 10,
    timeoutSeconds: 60,
};

const ALGO = "aes-256-gcm";
const ENC_PREFIX = "enc:v1:";

const TEMPLATE_SLUGS = [
    "cobranca",
    "pagamento_recebido",
    "pix_gerado",
    "pedido_confirmado",
    "pedido_enviado",
    "pedido_entregue",
    "bem_vindo",
    "recuperacao_senha",
    "alteracao_senha",
    "cadastro_aprovado",
    "cliente_bloqueado",
    "cliente_desbloqueado",
    "promocao",
    "aniversario",
    "lembrete_vencimento",
    "parcela_vencida",
];

const API_PROVIDER_DEFAULTS = {
    sendgrid: "https://api.sendgrid.com",
    amazon_ses: "https://email.us-east-1.amazonaws.com",
    mailgun: "https://api.mailgun.net",
    resend: "https://api.resend.com",
    postmark: "https://api.postmarkapp.com",
    personalizado: "",
};

function db() {
    return admin.firestore();
}

function limparEnv(s) {
    if (s == null) return "";
    return String(s).trim();
}

function getEncryptionKey() {
    // Produção: definir GC_EMAIL_CONFIG_SECRET em functions/.env
    // Ver env.gestao_comercial_email.example e docs/GESTAO_COMERCIAL_CHECKLIST_PRODUCAO.md
    const raw =
        limparEnv(process.env.GC_EMAIL_CONFIG_SECRET) ||
        limparEnv(process.env.OTP_RECUPERACAO_PEPPER) ||
        "dipertin-gc-email-fallback-change-in-prod";
    return crypto.createHash("sha256").update(raw).digest();
}

function encryptSecret(plain) {
    const text = limparEnv(plain);
    if (!text) return "";
    const key = getEncryptionKey();
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv(ALGO, key, iv);
    const enc = Buffer.concat([cipher.update(text, "utf8"), cipher.final()]);
    const tag = cipher.getAuthTag();
    return (
        ENC_PREFIX +
        iv.toString("base64") +
        ":" +
        tag.toString("base64") +
        ":" +
        enc.toString("base64")
    );
}

function decryptSecret(stored) {
    const s = limparEnv(stored);
    if (!s) return "";
    if (!s.startsWith(ENC_PREFIX)) return s;
    const parts = s.slice(ENC_PREFIX.length).split(":");
    if (parts.length !== 3) return "";
    const key = getEncryptionKey();
    const iv = Buffer.from(parts[0], "base64");
    const tag = Buffer.from(parts[1], "base64");
    const data = Buffer.from(parts[2], "base64");
    const decipher = crypto.createDecipheriv(ALGO, key, iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(data), decipher.final()]).toString("utf8");
}

function maskSecret() {
    return "••••••••";
}

function gerarProtocoloAmigavel() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let code = "";
    for (let i = 0; i < 6; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return "PRO-" + code;
}

async function assertAcessoLoja(auth, lojaId) {
    if (!auth) throw new HttpsError("unauthenticated", "Login necessário.");
    const lid = limparEnv(lojaId);
    if (!lid) throw new HttpsError("invalid-argument", "lojaId é obrigatório.");
    const userSnap = await db().collection("users").doc(auth.uid).get();
    if (!userSnap.exists) throw new HttpsError("permission-denied", "Usuário não encontrado.");
    const u = userSnap.data() || {};
    const role = String(u.role || "").toLowerCase();
    if (role === "master" || role === "master_city" || role === "staff") return lid;
    if (role !== "lojista") throw new HttpsError("permission-denied", "Sem permissão.");
    const lojaEfetiva = limparEnv(u.lojista_owner_uid) || auth.uid;
    if (lojaEfetiva !== lid) throw new HttpsError("permission-denied", "Sem permissão para esta loja.");
    return lid;
}

async function carregarEmailConfig(lojaId) {
    const snap = await db().collection("gestao_comercial_configuracoes").doc(lojaId).get();
    const cobranca = (snap.data() || {}).cobranca || {};
    const email = cobranca.email || {};
    const et = email.emailTransacional || {};
    return { snap, email, et };
}

function resolverSenhaSmtp(payload, existenteEnc) {
    const nova = payload.smtpSenha;
    if (nova === undefined || nova === null) return existenteEnc || "";
    const t = limparEnv(nova);
    if (!t || t === maskSecret()) return existenteEnc || "";
    return encryptSecret(t);
}

function resolverApiKey(payload, existenteEnc) {
    const nova = payload.apiKey;
    if (nova === undefined || nova === null) return existenteEnc || "";
    const t = limparEnv(nova);
    if (!t || t === maskSecret()) return existenteEnc || "";
    return encryptSecret(t);
}

function smtpTransportOpts(smtp, senhaPlain) {
    const host = limparEnv(smtp.host);
    const port = parseInt(String(smtp.port || 587), 10);
    const enc = limparEnv(smtp.encryption || "tls").toLowerCase();
    const user = limparEnv(smtp.user);
    const pass = senhaPlain;

    if (!host) throw new Error("Servidor SMTP não informado.");
    if (!port || port < 1 || port > 65535) throw new Error("Porta inválida.");

    const opts = {
        host,
        port,
        connectionTimeout: 15000,
        greetingTimeout: 10000,
        auth: user ? { user, pass } : pass ? { user, pass } : undefined,
    };

    if (enc === "ssl") {
        opts.secure = true;
    } else if (enc === "tls") {
        opts.secure = false;
        opts.requireTLS = true;
    } else {
        opts.secure = false;
        opts.ignoreTLS = true;
    }

    return opts;
}

function mapSmtpError(err) {
    const code = String(err && err.code ? err.code : "").toUpperCase();
    const msg = String(err && err.message ? err.message : err || "").toLowerCase();

    if (code === "EAUTH" || /auth/i.test(msg)) {
        if (/password|senha|credential/i.test(msg)) return "Senha incorreta ou usuário inválido.";
        return "Usuário inválido ou senha incorreta.";
    }
    if (code === "ENOTFOUND" || /getaddrinfo enotfound/i.test(msg)) return "Host não encontrado.";
    if (code === "ETIMEDOUT" || /timeout/i.test(msg)) return "Timeout — servidor não respondeu a tempo.";
    if (code === "ECONNREFUSED") return "Servidor recusou conexão — verifique host e porta.";
    if (code === "ESOCKET" || /socket/i.test(msg)) return "Porta inválida ou conexão interrompida.";
    if (/certificate|ssl|tls/i.test(msg)) return "Falha TLS/SSL — ajuste a criptografia (TLS/SSL/Nenhuma).";
    if (/mailbox does not exist|5\.4\.6.*rejected.*30 days|all recipients were rejected/i.test(msg)) {
        const extra = msg.includes("mailing list") ? " O servidor bloqueou este e-mail porque ele foi rejeitado como inexistente nos últimos 30 dias." : "";
        return "E-mail do destinatário rejeitado pelo servidor SMTP (550)." + extra + " Verifique se o endereço está correto ou entre em contato com o suporte da hospedagem para liberar.";
    }
    return String(err && err.message ? err.message : err || "Erro de conexão SMTP.");
}

function httpRequest(url, options, body) {
    return new Promise((resolve, reject) => {
        const parsed = new URL(url);
        const lib = parsed.protocol === "https:" ? https : http;
        const req = lib.request(
            parsed,
            {
                method: options.method || "GET",
                headers: options.headers || {},
                timeout: options.timeout || 15000,
            },
            (res) => {
                let data = "";
                res.on("data", (c) => (data += c));
                res.on("end", () => {
                    resolve({ status: res.statusCode, body: data, headers: res.headers });
                });
            },
        );
        req.on("error", reject);
        req.on("timeout", () => {
            req.destroy();
            reject(new Error("Timeout"));
        });
        if (body) req.write(body);
        req.end();
    });
}

async function testarApiProvider(provider, baseUrl, apiKey) {
    const key = limparEnv(apiKey);
    if (!key) throw new Error("API Key não informada.");
    const prov = limparEnv(provider).toLowerCase();

    try {
        if (prov === "sendgrid") {
            const r = await httpRequest("https://api.sendgrid.com/v3/user/profile", {
                method: "GET",
                headers: { Authorization: "Bearer " + key },
            });
            if (r.status === 200) return { ok: true, mensagem: "Conexão SendGrid realizada com sucesso." };
            if (r.status === 401 || r.status === 403) return { ok: false, mensagem: "API Key inválida ou sem permissão." };
            return { ok: false, mensagem: "SendGrid respondeu com código " + r.status + "." };
        }

        if (prov === "mailgun") {
            const auth = Buffer.from("api:" + key).toString("base64");
            const r = await httpRequest("https://api.mailgun.net/v3/domains", {
                method: "GET",
                headers: { Authorization: "Basic " + auth },
            });
            if (r.status === 200) return { ok: true, mensagem: "Conexão Mailgun realizada com sucesso." };
            if (r.status === 401) return { ok: false, mensagem: "API Key Mailgun inválida." };
            return { ok: false, mensagem: "Mailgun respondeu com código " + r.status + "." };
        }

        if (prov === "resend") {
            const r = await httpRequest("https://api.resend.com/domains", {
                method: "GET",
                headers: { Authorization: "Bearer " + key },
            });
            if (r.status === 200) return { ok: true, mensagem: "Conexão Resend realizada com sucesso." };
            if (r.status === 401) return { ok: false, mensagem: "API Key Resend inválida." };
            return { ok: false, mensagem: "Resend respondeu com código " + r.status + "." };
        }

        if (prov === "postmark") {
            const r = await httpRequest("https://api.postmarkapp.com/server", {
                method: "GET",
                headers: {
                    Accept: "application/json",
                    "X-Postmark-Server-Token": key,
                },
            });
            if (r.status === 200) return { ok: true, mensagem: "Conexão Postmark realizada com sucesso." };
            if (r.status === 401) return { ok: false, mensagem: "Token Postmark inválido." };
            return { ok: false, mensagem: "Postmark respondeu com código " + r.status + "." };
        }

        if (prov === "amazon_ses") {
            if (key.length < 16) return { ok: false, mensagem: "Credencial SES muito curta — verifique Access Key." };
            return {
                ok: true,
                mensagem: "Credencial SES registrada. Confirme envio de teste para validar região e permissões IAM.",
            };
        }

        const url = limparEnv(baseUrl) || API_PROVIDER_DEFAULTS.personalizado;
        if (!url) return { ok: false, mensagem: "Base URL da API não informada." };
        const r = await httpRequest(url.replace(/\/$/, "") + "/", {
            method: "GET",
            headers: { Authorization: "Bearer " + key, Accept: "application/json" },
        });
        if (r.status >= 200 && r.status < 500) {
            return {
                ok: r.status < 400,
                mensagem:
                    r.status < 400
                        ? "API respondeu com sucesso (HTTP " + r.status + ")."
                        : "API recusou autenticação (HTTP " + r.status + ").",
            };
        }
        return { ok: false, mensagem: "API respondeu com HTTP " + r.status + "." };
    } catch (e) {
        const m = String(e.message || e);
        if (/timeout/i.test(m)) return { ok: false, mensagem: "Timeout ao contactar a API." };
        if (/ENOTFOUND/i.test(m)) return { ok: false, mensagem: "Host da API não encontrado." };
        return { ok: false, mensagem: m };
    }
}

function substituirVariaveis(texto, vars) {
    let out = String(texto || "");
    for (const [k, v] of Object.entries(vars || {})) {
        out = out.split("{" + k + "}").join(String(v ?? ""));
    }
    return out;
}

const VARS_FICTICIAS = {
    cliente: "Maria Silva",
    cpf: "123.456.789-00",
    email: "maria@email.com",
    telefone: "(44) 99999-0000",
    loja: "Loja Exemplo",
    cnpj: "12.345.678/0001-90",
    pedido: "PED-000042",
    valor: "R$ 150,00",
    desconto: "R$ 10,00",
    juros: "R$ 2,50",
    multa: "R$ 5,00",
    dias_atraso: "3",
    vencimento: "15/07/2026",
    pix: "00020126580014BR.GOV.BCB.PIX...",
    linha_digitavel: "23793.38128 60000.000000 00000.000000 1 84370000015000",
    codigo_barras: "23793381286000000000000000000000000000001500",
    link: "https://www.dipertin.com.br/pagar/exemplo",
    numero_parcela: "2",
    quantidade_parcelas: "6",
    data: "27/06/2026",
    hora: "14:30",
    cidade: "Toledo",
    estado: "PR",
};

function escapeHtml(s) {
    return String(s || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function blocksToHtml(blocks, vars, identidade, assunto) {
    const id = identidade || {};
    const corPrincipal = id.corPrincipal || "#6A1B9A";
    const corSecundaria = id.corSecundaria || "#FF8F00";
    const corBotao = id.corBotao || corPrincipal;
    const nomeLoja = id.nomeLoja || vars.loja || "Sua Loja";

    let body = "";
    for (const b of blocks || []) {
        const tipo = String(b.tipo || b.type || "texto");
        const conteudo = substituirVariaveis(b.conteudo || b.text || "", vars);
        if (tipo === "titulo") {
            body +=
                '<h1 style="font-family:Arial,sans-serif;color:' +
                corPrincipal +
                ';font-size:22px;margin:0 0 12px;">' +
                escapeHtml(conteudo) +
                "</h1>";
        } else if (tipo === "texto") {
            body +=
                '<p style="font-family:Arial,sans-serif;color:#1A1A2E;font-size:15px;line-height:1.6;margin:0 0 12px;">' +
                escapeHtml(conteudo).replace(/\n/g, "<br>") +
                "</p>";
        } else if (tipo === "imagem" && (b.url || b.conteudo)) {
            const url = substituirVariaveis(b.url || b.conteudo, vars);
            body +=
                '<p style="text-align:center;margin:16px 0;"><img src="' +
                escapeHtml(url) +
                '" alt="" style="max-width:100%;height:auto;border-radius:8px;" /></p>';
        } else if (tipo === "botao") {
            const textoBtn = substituirVariaveis(b.textoBotao || b.texto || "Pagar Agora", vars);
            // REGRA: vars.link (link real de pagamento) SEMPRE tem prioridade sobre
            // URLs estáticas que o template possa ter salvo.
            // Se vars.link existe, usamos ele direto (já substituído).
            // Senão, tenta o destino do template (que pode conter {link}).
            let dest;
            if (vars.link && vars.link !== "#" && String(vars.link).includes("pagar?token=")) {
                dest = vars.link;
            } else {
                dest = substituirVariaveis(b.destino || b.link || vars.link || "#", vars);
            }
            body +=
                '<p style="text-align:center;margin:20px 0;"><a href="' +
                escapeHtml(dest) +
                '" style="background:' +
                corBotao +
                ";color:#fff;text-decoration:none;padding:14px 28px;border-radius:8px;font-weight:bold;font-family:Arial,sans-serif;display:inline-block;\">" +
                escapeHtml(textoBtn) +
                "</a></p>";
        } else if (tipo === "divisor") {
            body +=
                '<hr style="border:none;border-top:1px solid #E5E7EB;margin:20px 0;" />';
        }
    }

    const logo = id.logoUrl ? '<img src="' + escapeHtml(id.logoUrl) + '" alt="" style="max-height:48px;margin-bottom:16px;" />' : "";

    const rodape =
        '<p style="font-family:Arial,sans-serif;color:#64748B;font-size:12px;line-height:1.5;margin-top:24px;">' +
        "Recebeu este e-mail porque possui cadastro na loja.<br>" +
        escapeHtml(nomeLoja) +
        (id.telefone ? " · " + escapeHtml(id.telefone) : "") +
        (id.whatsapp ? " · WhatsApp " + escapeHtml(id.whatsapp) : "") +
        (id.site ? '<br><a href="' + escapeHtml(id.site) + '" style="color:' + corSecundaria + ';">' + escapeHtml(id.site) + "</a>" : "") +
        (id.instagram ? " · Instagram " + escapeHtml(id.instagram) : "") +
        "</p>";

    return (
        '<!DOCTYPE html><html><head><meta charset="utf-8"><title>' +
        escapeHtml(assunto || "") +
        '</title></head><body style="margin:0;padding:0;background:#F5F4F8;">' +
        '<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px;">' +
        '<table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;background:#fff;border-radius:12px;padding:32px;box-shadow:0 2px 8px rgba(0,0,0,0.06);">' +
        "<tr><td>" +
        logo +
        body +
        rodape +
        "</td></tr></table></td></tr></table></body></html>"
    );
}

function textoLegadoFromBlocks(blocks) {
    return (blocks || [])
        .map((b) => String(b.conteudo || b.text || "").trim())
        .filter(Boolean)
        .join("\n\n");
}

async function registrarHistorico(lojaId, entry) {
    const ref = db()
        .collection("gestao_comercial_email_historico")
        .doc(lojaId)
        .collection("envios")
        .doc();
    await ref.set(
        Object.assign(
            {
                loja_id: lojaId,
                criado_em: admin.firestore.FieldValue.serverTimestamp(),
            },
            entry,
        ),
    );
    return ref.id;
}

async function incrementarEnviadosHoje(lojaId) {
    const ref = db().collection("gestao_comercial_configuracoes").doc(lojaId);
    const hoje = new Date().toISOString().slice(0, 10);
    await db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const email = ((snap.data() || {}).cobranca || {}).email || {};
        const et = email.emailTransacional || {};
        const status = et.status || {};
        const dia = status.contadorDia || "";
        let qtd = status.enviadosHoje || 0;
        if (dia !== hoje) qtd = 0;
        tx.set(
            ref,
            {
                cobranca: {
                    email: {
                        emailTransacional: {
                            status: {
                                enviadosHoje: qtd + 1,
                                contadorDia: hoje,
                                ultimoEnvioEm: admin.firestore.FieldValue.serverTimestamp(),
                            },
                        },
                    },
                },
            },
            { merge: true },
        );
    });
}

async function enviarViaSmtp(smtp, senha, opts) {
    const transport = nodemailer.createTransport(smtpTransportOpts(smtp, senha));
    const fromEmail = limparEnv(opts.fromEmail || smtp.fromEmail);
    const fromName = limparEnv(opts.fromName || smtp.fromName);
    const replyTo = limparEnv(opts.replyTo || smtp.replyTo);
    if (!fromEmail) throw new Error("E-mail remetente não configurado.");

    const from = fromName ? fromName + " <" + fromEmail + ">" : fromEmail;
    const info = await transport.sendMail({
        from,
        to: opts.to,
        subject: opts.subject,
        html: opts.html,
        text: opts.text,
        replyTo: replyTo || undefined,
        headers: {
            "X-Mailer": "DiPertin - Gestão Comercial",
            "X-Auto-Response-Suppress": "All",
            "Auto-Submitted": "auto-generated",
        },
    });
    return info;
}

async function enviarViaApi(api, apiKeyPlain, opts) {
    const prov = limparEnv(api.provider).toLowerCase();
    const fromEmail = limparEnv(opts.fromEmail || api.fromEmail);
    const fromName = limparEnv(opts.fromName || api.fromName);
    if (!fromEmail) throw new Error("E-mail remetente não configurado.");

    if (prov === "sendgrid") {
        const payload = JSON.stringify({
            personalizations: [{ to: [{ email: opts.to }] }],
            from: { email: fromEmail, name: fromName || undefined },
            subject: opts.subject,
            content: [{ type: "text/html", value: opts.html }],
        });
        const r = await httpRequest("https://api.sendgrid.com/v3/mail/send", {
            method: "POST",
            headers: {
                Authorization: "Bearer " + apiKeyPlain,
                "Content-Type": "application/json",
            },
        }, payload);
        if (r.status >= 200 && r.status < 300) {
            return { messageId: r.headers["x-message-id"] || "sendgrid-" + Date.now(), resposta: r.body };
        }
        throw new Error("SendGrid: HTTP " + r.status + " — " + (r.body || "").slice(0, 200));
    }

    if (prov === "resend") {
        const payload = JSON.stringify({
            from: fromName ? fromName + " <" + fromEmail + ">" : fromEmail,
            to: [opts.to],
            subject: opts.subject,
            html: opts.html,
        });
        const r = await httpRequest("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                Authorization: "Bearer " + apiKeyPlain,
                "Content-Type": "application/json",
            },
        }, payload);
        if (r.status >= 200 && r.status < 300) {
            let id = "";
            try {
                id = JSON.parse(r.body).id || "";
            } catch (_) { }
            return { messageId: id || "resend-" + Date.now(), resposta: r.body };
        }
        throw new Error("Resend: HTTP " + r.status + " — " + (r.body || "").slice(0, 200));
    }

    throw new Error("Envio via API para o provedor \"" + prov + "\" ainda não implementado no servidor. Use SMTP ou SendGrid/Resend.");
}

async function enviarEmailLoja(lojaId, to, subject, html, text, templateSlug, overrides) {
    const { email, et } = await carregarEmailConfig(lojaId);
    const modo = limparEnv(overrides?.modoIntegracao || et.modoIntegracao || "smtp").toLowerCase();
    const smtp = Object.assign({}, et.smtp || {}, overrides?.smtp || {});
    const api = Object.assign({}, et.api || {}, overrides?.api || {});
    const fromEmail = modo === "api" ? api.fromEmail : smtp.fromEmail;
    const fromName = modo === "api" ? api.fromName : smtp.fromName;
    const replyTo = modo === "api" ? api.replyTo : smtp.replyTo;
    const inicio = Date.now();
    let messageId = "";
    let respostaTecnica = "";
    let provedor = modo === "api" ? api.provider : "smtp";

    try {
        if (modo === "api") {
            let key = limparEnv(overrides?.api?.apiKey);
            if (!key || key === maskSecret()) {
                key = decryptSecret(api.apiKeyEnc || email.token);
            }
            if (!key) throw new Error("API Key não configurada.");
            const r = await enviarViaApi(api, key, {
                to,
                subject,
                html,
                text,
                fromEmail: fromEmail || email.emailRemetente,
                fromName: fromName || email.remetente,
                replyTo,
            });
            messageId = r.messageId;
            respostaTecnica = r.resposta || "";
        } else {
            let senha = limparEnv(overrides?.smtp?.senha);
            if (!senha || senha === maskSecret()) {
                senha = decryptSecret(smtp.senhaEnc || email.token);
            }
            if (!senha) throw new Error("Senha SMTP não configurada.");
            const info = await enviarViaSmtp(smtp, senha, {
                to,
                subject,
                html,
                text,
                fromEmail: fromEmail || email.emailRemetente,
                fromName: fromName || email.remetente,
                replyTo,
            });
            messageId = info.messageId || "";
            respostaTecnica = JSON.stringify({ accepted: info.accepted, response: info.response });
        }

        const tempoMs = Date.now() - inicio;
        await incrementarEnviadosHoje(lojaId);
        const histId = await registrarHistorico(lojaId, {
            status: "enviado",
            destinatario: to,
            assunto: subject,
            tipo: templateSlug || "teste",
            provedor,
            tempo_ms: tempoMs,
            message_id: messageId,
            resposta_tecnica: respostaTecnica.slice(0, 4000),
            log_tecnico: "OK " + tempoMs + "ms",
        });

        return { ok: true, messageId, protocolo: gerarProtocoloAmigavel(), historicoId: histId, tempoMs };
    } catch (e) {
        const tempoMs = Date.now() - inicio;
        await registrarHistorico(lojaId, {
            status: "erro",
            destinatario: to,
            assunto: subject,
            tipo: templateSlug || "teste",
            provedor,
            tempo_ms: tempoMs,
            resposta_tecnica: String(e.message || e).slice(0, 4000),
            log_tecnico: mapSmtpError(e),
        });
        throw e;
    }
}

function sanitizarConfigResposta(et) {
    const out = JSON.parse(JSON.stringify(et || {}));
    if (out.smtp) {
        out.smtp.senhaEnc = out.smtp.senhaEnc ? maskSecret() : "";
        out.smtp.temSenha = !!et.smtp && !!et.smtp.senhaEnc;
    }
    if (out.api) {
        out.api.apiKeyEnc = out.api.apiKeyEnc ? maskSecret() : "";
        out.api.temApiKey = !!et.api && !!et.api.apiKeyEnc;
    }
    return out;
}

exports.gestaoComercialEmailSalvarConfig = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const payload = request.data?.config || {};
        const { email, et } = await carregarEmailConfig(lojaId);

        const modo = limparEnv(payload.modoIntegracao || et.modoIntegracao || "smtp").toLowerCase();
        const smtpAtual = et.smtp || {};
        const apiAtual = et.api || {};

        const smtp = {
            host: limparEnv(payload.smtp?.host ?? smtpAtual.host),
            port: parseInt(String(payload.smtp?.port ?? smtpAtual.port ?? 587), 10),
            encryption: limparEnv(payload.smtp?.encryption ?? smtpAtual.encryption ?? "tls"),
            user: limparEnv(payload.smtp?.user ?? smtpAtual.user),
            senhaEnc: resolverSenhaSmtp(
                { smtpSenha: payload.smtp?.senha },
                smtpAtual.senhaEnc || (email.token && email.token.startsWith(ENC_PREFIX) ? email.token : encryptSecret(email.token)),
            ),
            fromEmail: limparEnv(payload.smtp?.fromEmail ?? smtpAtual.fromEmail ?? email.emailRemetente),
            fromName: limparEnv(payload.smtp?.fromName ?? smtpAtual.fromName ?? email.remetente),
            replyTo: limparEnv(payload.smtp?.replyTo ?? smtpAtual.replyTo),
        };

        const api = {
            provider: limparEnv(payload.api?.provider ?? apiAtual.provider ?? "sendgrid"),
            baseUrl: limparEnv(payload.api?.baseUrl ?? apiAtual.baseUrl ?? API_PROVIDER_DEFAULTS.sendgrid),
            apiKeyEnc: resolverApiKey(
                { apiKey: payload.api?.apiKey },
                apiAtual.apiKeyEnc || (modo === "api" && email.token ? encryptSecret(email.token) : ""),
            ),
            fromEmail: limparEnv(payload.api?.fromEmail ?? apiAtual.fromEmail ?? email.emailRemetente),
            fromName: limparEnv(payload.api?.fromName ?? apiAtual.fromName ?? email.remetente),
            replyTo: limparEnv(payload.api?.replyTo ?? apiAtual.replyTo),
        };

        const avancado = Object.assign({}, et.avancado || {}, payload.avancado || {});
        const identidadeVisual = Object.assign({}, et.identidadeVisual || {}, payload.identidadeVisual || {});
        const automacao = Object.assign({}, et.automacao || {}, payload.automacao || {});

        const ativo = payload.ativo !== undefined ? payload.ativo === true : email.ativo === true;
        const nome = limparEnv(payload.nome ?? email.nome) || "E-mail";

        const configurado =
            modo === "api"
                ? !!(api.apiKeyEnc && api.fromEmail)
                : !!(smtp.host && smtp.senhaEnc && smtp.fromEmail);

        const emailTransacional = {
            modoIntegracao: modo,
            smtp,
            api,
            avancado,
            identidadeVisual,
            automacao,
            status: Object.assign({}, et.status || {}, {
                configurado,
                atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }),
        };

        const legacyToken = modo === "api" ? api.apiKeyEnc : smtp.senhaEnc;
        const legacyUrl = modo === "api" ? api.baseUrl : smtp.host + (smtp.port ? ":" + smtp.port : "");

        await db()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId)
            .set(
                {
                    loja_id: lojaId,
                    cobranca: {
                        email: {
                            nome,
                            tipo: "email",
                            apiUrl: legacyUrl,
                            token: legacyToken ? maskSecret() : "",
                            remetente: modo === "api" ? api.fromName : smtp.fromName,
                            emailRemetente: modo === "api" ? api.fromEmail : smtp.fromEmail,
                            ativo,
                            emailTransacional,
                        },
                    },
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
            );

        return { ok: true, configurado, emailTransacional: sanitizarConfigResposta(emailTransacional) };
    },
);

exports.gestaoComercialEmailTestarSmtp = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const smtpIn = request.data?.smtp || {};
        const { email, et } = await carregarEmailConfig(lojaId);
        const smtp = Object.assign({}, et.smtp || {}, smtpIn);
        let senha = limparEnv(smtpIn.senha);
        if (!senha || senha === maskSecret()) {
            senha = decryptSecret((et.smtp || {}).senhaEnc || email.token);
        }

        try {
            const transport = nodemailer.createTransport(smtpTransportOpts(smtp, senha));
            await transport.verify();
            await db()
                .collection("gestao_comercial_configuracoes")
                .doc(lojaId)
                .set(
                    {
                        cobranca: {
                            email: {
                                emailTransacional: {
                                    status: {
                                        ultimoTesteEm: admin.firestore.FieldValue.serverTimestamp(),
                                        ultimoTesteOk: true,
                                        ultimoTesteMsg: "Conexão realizada com sucesso.",
                                    },
                                },
                            },
                        },
                    },
                    { merge: true },
                );
            return { ok: true, mensagem: "Conexão realizada com sucesso." };
        } catch (e) {
            const msg = mapSmtpError(e);
            await db()
                .collection("gestao_comercial_configuracoes")
                .doc(lojaId)
                .set(
                    {
                        cobranca: {
                            email: {
                                emailTransacional: {
                                    status: {
                                        ultimoTesteEm: admin.firestore.FieldValue.serverTimestamp(),
                                        ultimoTesteOk: false,
                                        ultimoTesteMsg: msg,
                                    },
                                },
                            },
                        },
                    },
                    { merge: true },
                );
            return { ok: false, mensagem: msg };
        }
    },
);

exports.gestaoComercialEmailTestarApi = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const apiIn = request.data?.api || {};
        const { email, et } = await carregarEmailConfig(lojaId);
        const api = Object.assign({}, et.api || {}, apiIn);
        let key = limparEnv(apiIn.apiKey);
        if (!key || key === maskSecret()) {
            key = decryptSecret((et.api || {}).apiKeyEnc || email.token);
        }

        const result = await testarApiProvider(api.provider, api.baseUrl, key);
        await db()
            .collection("gestao_comercial_configuracoes")
            .doc(lojaId)
            .set(
                {
                    cobranca: {
                        email: {
                            emailTransacional: {
                                status: {
                                    ultimoTesteEm: admin.firestore.FieldValue.serverTimestamp(),
                                    ultimoTesteOk: result.ok,
                                    ultimoTesteMsg: result.mensagem,
                                },
                            },
                        },
                    },
                },
                { merge: true },
            );
        return { ok: result.ok, mensagem: result.mensagem };
    },
);

exports.gestaoComercialEmailEnviarTeste = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const destino = limparEnv(request.data?.destino);
        if (!destino || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(destino)) {
            throw new HttpsError("invalid-argument", "E-mail destino inválido.");
        }

        // Aceita config inline para enviar sem precisar salvar primeiro
        const overrides = {};
        if (request.data?.modoIntegracao) overrides.modoIntegracao = request.data.modoIntegracao;
        if (request.data?.smtp) overrides.smtp = request.data.smtp;
        if (request.data?.api) overrides.api = request.data.api;

        const subject = limparEnv(request.data?.assunto) || "Teste — E-mail transacional DiPertin";
        const html =
            request.data?.html ||
            "<p>A configuração do serviço de E-mail Transacional do DiPertin foi concluída com sucesso. Este e-mail foi enviado automaticamente para confirmar que o sistema está apto a realizar envios de mensagens transacionais.</p>";
        const text = request.data?.text || "E-mail de teste DiPertin.";

        try {
            const r = await enviarEmailLoja(lojaId, destino, subject, html, text, "teste",
                Object.keys(overrides).length ? overrides : undefined);
            return { ok: true, mensagem: "E-mail de teste enviado com sucesso.", messageId: r.messageId, tempoMs: r.tempoMs };
        } catch (e) {
            throw new HttpsError("failed-precondition", mapSmtpError(e));
        }
    },
);

exports.gestaoComercialEmailSalvarTemplate = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const slug = limparEnv(request.data?.slug);
        if (!slug) throw new HttpsError("invalid-argument", "slug do template é obrigatório.");

        const assunto = limparEnv(request.data?.assunto);
        const blocks = Array.isArray(request.data?.blocks) ? request.data.blocks : [];
        const identidadeVisual = request.data?.identidadeVisual || {};
        const botao = request.data?.botao || {};

        const htmlPreview = blocksToHtml(blocks, VARS_FICTICIAS, identidadeVisual, assunto);
        const textoPlano = textoLegadoFromBlocks(blocks);

        await db()
            .collection("gestao_comercial_email_templates")
            .doc(lojaId)
            .collection("templates")
            .doc(slug)
            .set(
                {
                    slug,
                    assunto,
                    blocks,
                    botao,
                    identidadeVisual,
                    html_preview: htmlPreview,
                    texto_plano: textoPlano,
                    atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
                    loja_id: lojaId,
                },
                { merge: true },
            );

        if (slug === "cobranca") {
            await db()
                .collection("gestao_comercial_configuracoes")
                .doc(lojaId)
                .set(
                    {
                        cobranca: {
                            email: {
                                templateMensagem: textoPlano || assunto,
                            },
                        },
                    },
                    { merge: true },
                );
        }

        return { ok: true, slug };
    },
);

exports.gestaoComercialEmailEnviarTemplateTeste = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const destino = limparEnv(request.data?.destino);
        if (!destino) throw new HttpsError("invalid-argument", "Informe o e-mail destino.");

        const slug = limparEnv(request.data?.slug) || "cobranca";
        const assunto = substituirVariaveis(limparEnv(request.data?.assunto), VARS_FICTICIAS);
        const blocks = request.data?.blocks;
        const identidade = request.data?.identidadeVisual || {};
        let html;

        if (Array.isArray(blocks) && blocks.length) {
            html = blocksToHtml(blocks, VARS_FICTICIAS, identidade, assunto);
        } else {
            const tplSnap = await db()
                .collection("gestao_comercial_email_templates")
                .doc(lojaId)
                .collection("templates")
                .doc(slug)
                .get();
            const d = tplSnap.data() || {};
            html = d.html_preview || blocksToHtml(d.blocks, VARS_FICTICIAS, d.identidadeVisual, d.assunto);
        }

        try {
            const r = await enviarEmailLoja(lojaId, destino, assunto || "Teste template", html, textoLegadoFromBlocks(blocks), slug);
            return { ok: true, mensagem: "Template enviado com dados fictícios.", protocolo: gerarProtocoloAmigavel(), tempoMs: r.tempoMs };
        } catch (e) {
            throw new HttpsError("failed-precondition", mapSmtpError(e));
        }
    },
);

exports.gestaoComercialEmailListarHistorico = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const limite = Math.min(parseInt(String(request.data?.limite || 50), 10), 200);

        const snap = await db()
            .collection("gestao_comercial_email_historico")
            .doc(lojaId)
            .collection("envios")
            .orderBy("criado_em", "desc")
            .limit(limite)
            .get();

        const items = snap.docs.map((doc) => {
            const d = doc.data();
            return {
                id: doc.id,
                status: d.status,
                criado_em: d.criado_em,
                cliente: d.cliente || d.destinatario,
                assunto: d.assunto,
                tipo: d.tipo,
                email: d.destinatario,
                loja: d.loja_id || lojaId,
                provedor: d.provedor,
                tempo_ms: d.tempo_ms,
                message_id: d.message_id,
                resposta_tecnica: d.resposta_tecnica,
                log_tecnico: d.log_tecnico,
                corpo_html: d.corpo_html,
            };
        });

        return { ok: true, items };
    },
);

exports.gestaoComercialEmailInicializarTemplates = onCall(
    Object.assign({}, CONFIG_PADRAO, { enforceAppCheck: false }),
    async (request) => {
        const lojaId = await assertAcessoLoja(request.auth, request.data?.lojaId);
        const batch = db().batch();
        const col = db().collection("gestao_comercial_email_templates").doc(lojaId).collection("templates");

        for (const slug of TEMPLATE_SLUGS) {
            const ref = col.doc(slug);
            const ex = await ref.get();
            if (ex.exists) continue;
            batch.set(ref, {
                slug,
                assunto: slug === "cobranca" ? "Sua cobrança — {loja}" : "Mensagem — {loja}",
                blocks: [
                    { tipo: "titulo", conteudo: "Olá, {cliente}" },
                    {
                        tipo: "texto",
                        conteudo:
                            slug === "cobranca"
                                ? "Sua parcela no valor de {valor} vence em {vencimento}.\nLink: {link}"
                                : "Esta é uma mensagem automática da {loja}.",
                    },
                    { tipo: "botao", textoBotao: "Pagar Agora", destino: "{link}" },
                ],
                identidadeVisual: {},
                loja_id: lojaId,
                criado_em: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        await batch.commit();
        return { ok: true };
    },
);

exports._gestaoComercialEmailHelpers = {
    encryptSecret,
    decryptSecret,
    blocksToHtml,
    mapSmtpError,
    TEMPLATE_SLUGS,
    enviarEmailLoja,
    carregarEmailConfig,
    substituirVariaveis,
    textoLegadoFromBlocks,
    gerarProtocoloAmigavel,
    limparEnv,
    maskSecret,
    db,
};
