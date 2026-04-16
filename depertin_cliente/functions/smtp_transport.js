"use strict";

/**
 * Módulo centralizado de transporte SMTP — DiPertin.
 *
 * Perfis disponíveis:
 *   "padrao"       → naoresponder@dipertin.com.br  (boas-vindas, recuperação, contato, saques)
 *   "candidatura"  → candidatura@dipertin.com.br   (exclusivo vagas de emprego)
 *
 * Uso:
 *   const smtp = require("./smtp_transport");
 *   const transport = smtp.criarTransport("padrao");   // ou "candidatura"
 *   const from      = smtp.from("padrao");
 */

const nodemailer = require("nodemailer");

function limparEnv(s) {
    if (s == null) return "";
    let v = String(s).trim().replace(/\r/g, "").replace(/\n/g, "");
    if (v.length >= 2 && ((v[0] === '"' && v[v.length - 1] === '"') || (v[0] === "'" && v[v.length - 1] === "'"))) {
        v = v.slice(1, -1);
    }
    return v;
}

const PERFIS = {
    padrao: {
        user: () => limparEnv(process.env.SMTP_USER) || limparEnv(process.env.SMTP_RECUPERACAO_USER) || "naoresponder@dipertin.com.br",
        pass: () => limparEnv(process.env.SMTP_PASS) || limparEnv(process.env.SMTP_RECUPERACAO_PASS),
        from: () => limparEnv(process.env.SMTP_FROM) || "DiPertin <naoresponder@dipertin.com.br>",
    },
    candidatura: {
        user: () => limparEnv(process.env.SMTP_CANDIDATURA_USER) || "candidatura@dipertin.com.br",
        pass: () => limparEnv(process.env.SMTP_CANDIDATURA_PASS),
        from: () => limparEnv(process.env.SMTP_CANDIDATURA_FROM) || "DiPertin Vagas <candidatura@dipertin.com.br>",
    },
};

function host() {
    return limparEnv(process.env.SMTP_HOST) || "smtp.titan.email";
}

function port() {
    return parseInt(limparEnv(process.env.SMTP_PORT) || "465", 10);
}

function obterPerfil(nome) {
    const perfil = PERFIS[nome];
    if (!perfil) {
        throw new Error(`Perfil SMTP desconhecido: "${nome}". Use "padrao" ou "candidatura".`);
    }
    return perfil;
}

/**
 * Cria um nodemailer transport para o perfil indicado.
 * @param {"padrao"|"candidatura"} perfil
 */
function criarTransport(perfil) {
    const p = obterPerfil(perfil);
    const user = p.user();
    const pass = p.pass();

    if (!pass) {
        throw new Error(`Senha SMTP não configurada para o perfil "${perfil}".`);
    }

    const smtpHost = host();
    const smtpPort = port();
    const maskedPass = pass.length > 2 ? pass[0] + "*".repeat(pass.length - 2) + pass[pass.length - 1] : "***";
    console.log(`[smtp] perfil="${perfil}" host=${smtpHost} port=${smtpPort} user=${user} pass=${maskedPass} (${pass.length} chars)`);

    if (smtpPort === 587) {
        return nodemailer.createTransport({
            host: smtpHost,
            port: 587,
            secure: false,
            requireTLS: true,
            auth: { user, pass },
        });
    }

    return nodemailer.createTransport({
        host: smtpHost,
        port: smtpPort,
        secure: smtpPort === 465,
        auth: { user, pass },
    });
}

/**
 * Retorna o header From para o perfil indicado.
 * @param {"padrao"|"candidatura"} perfil
 */
function from(perfil) {
    const p = obterPerfil(perfil);
    const raw = p.from();
    if (!raw || !raw.includes("@")) {
        return perfil === "candidatura"
            ? "DiPertin Vagas <candidatura@dipertin.com.br>"
            : "DiPertin <naoresponder@dipertin.com.br>";
    }
    const lower = raw.toLowerCase();
    if (lower === "me" || lower.startsWith("me ")) {
        return perfil === "candidatura"
            ? "DiPertin Vagas <candidatura@dipertin.com.br>"
            : "DiPertin <naoresponder@dipertin.com.br>";
    }
    return raw;
}

module.exports = { criarTransport, from, limparEnv };
