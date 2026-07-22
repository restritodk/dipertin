"use strict";

/**
 * Régua de comunicação (até 3 tentativas) — Assinaturas GC.
 *
 * NÃO controla bloqueio/suspensão. Apenas e-mails + campos de controle na cobrança.
 * Bloqueio permanece em assinaturaVerificarSuspensaoScheduled.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const smtp = require("./smtp_transport");
const templates = require("./assinatura_emails_templates");

const COLECAO = "assinaturas_cobrancas";
const COLECAO_ASSINATURAS = "assinaturas_clientes";
const UM_DIA_MS = 24 * 60 * 60 * 1000;

function tsParaDate(v) {
    if (!v) return null;
    if (v instanceof admin.firestore.Timestamp) return v.toDate();
    if (v instanceof Date) return v;
    if (typeof v === "object" && typeof v._seconds === "number") {
        return new Date(v._seconds * 1000);
    }
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
}

function formatDateBr(d) {
    if (!d) return "—";
    const x = d instanceof Date ? d : tsParaDate(d);
    if (!x) return "—";
    return x.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
}

/**
 * Calcula data estimada de bloqueio SEM alterar regras:
 * next_billing + tolerancia_dias + suspender_apos_dias
 */
function calcularDataBloqueioEstimada(assinatura, vencimentoDate) {
    const a = assinatura || {};
    const suspenderApos = Number(a.suspender_apos_dias);
    if (!Number.isFinite(suspenderApos) || suspenderApos <= 0) return null;
    const tolerancia = Number(a.tolerancia_dias != null ? a.tolerancia_dias : 3);
    const base = vencimentoDate || tsParaDate(a.next_billing_date);
    if (!base) return null;
    const limite = tolerancia + suspenderApos;
    const out = new Date(base.getTime());
    out.setDate(out.getDate() + limite);
    return out;
}

function diasToleranciaRestantes(assinatura, agoraMs) {
    const a = assinatura || {};
    const venc = tsParaDate(a.next_billing_date);
    if (!venc) return null;
    const tolerancia = Number(a.tolerancia_dias != null ? a.tolerancia_dias : 3);
    const fimTolerancia = new Date(venc.getTime());
    fimTolerancia.setDate(fimTolerancia.getDate() + tolerancia);
    const dias = Math.ceil((fimTolerancia.getTime() - agoraMs) / UM_DIA_MS);
    return Math.max(0, dias);
}

async function enviarEmailTemplate(destinatario, mail) {
    if (!destinatario || !mail || !mail.html) {
        return { ok: false, motivo: "email_invalido" };
    }
    try {
        const transport = smtp.criarTransport("padrao");
        await transport.sendMail({
            from: smtp.from("padrao"),
            to: destinatario,
            subject: mail.subject,
            html: mail.html,
            text: mail.subject,
        });
        return { ok: true };
    } catch (e) {
        console.warn("[assinatura-avisos] SMTP erro:", e.message || e);
        return { ok: false, motivo: e.message || "smtp_erro" };
    }
}

/**
 * Envia tentativa N (1|2|3) de forma idempotente na cobrança.
 * Nunca altera status da assinatura para suspenso.
 */
async function registrarEEnviarTentativa(db, cobrancaId, numeroTentativa, origem) {
    const n = Number(numeroTentativa);
    if (![1, 2, 3].includes(n)) {
        return { ok: false, reason: "tentativa_invalida" };
    }

    const cobRef = db.collection(COLECAO).doc(cobrancaId);
    const now = admin.firestore.Timestamp.now();
    const agoraMs = Date.now();

    let dadosEmail = null;
    let emailDestino = "";
    let jaEnviada = false;

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(cobRef);
        if (!snap.exists) {
            throw new Error("cobranca_nao_encontrada");
        }
        const c = snap.data() || {};
        const status = String(c.status || "");
        if (status === "paga" || status === "cancelada" || status === "reembolsada") {
            jaEnviada = true;
            return;
        }

        const campoEm = `tentativa_${n}_enviada_em`;
        if (c[campoEm]) {
            jaEnviada = true;
            return;
        }

        const tentativasAtuais = Math.max(0, Number(c.tentativas_aviso || 0));
        if (tentativasAtuais >= n) {
            jaEnviada = true;
            return;
        }

        const assinaturaId = String(c.assinatura_id || "").trim();
        let assinatura = {};
        if (assinaturaId) {
            const aSnap = await tx.get(db.collection(COLECAO_ASSINATURAS).doc(assinaturaId));
            if (aSnap.exists) assinatura = aSnap.data() || {};
        }

        const venc = tsParaDate(c.vencimento) || tsParaDate(assinatura.next_billing_date);
        const bloqueioEst = calcularDataBloqueioEstimada(assinatura, venc);
        const diasTol = diasToleranciaRestantes(assinatura, agoraMs);

        emailDestino = String(c.email || assinatura.email || "").trim();
        dadosEmail = {
            lojaNome: c.store_name || assinatura.store_name || "Lojista",
            planoNome: c.plan_name || assinatura.plan_name || "Plano",
            valor: Number(c.valor || assinatura.monthly_amount || 0),
            vencimento: formatDateBr(venc),
            situacao: status === "vencida" ? "Vencida" : "Em aberto",
            fatura: c.fatura || cobrancaId,
            cobrancaId,
            formaPagamento: c.forma_pagamento_esperada ||
                (String(assinatura.tipo_cobranca || "").includes("cartao") ? "Cartão" : "PIX"),
            diasToleranciaRestantes: diasTol != null ? `${diasTol} dia(s)` : undefined,
            dataBloqueioEstimada: bloqueioEst ? formatDateBr(bloqueioEst) : undefined,
        };

        const patch = {
            tentativas_aviso: n,
            ultima_tentativa_em: now,
            status_notificacao: `tentativa_${n}_registrada`,
            atualizado_em: now,
            [campoEm]: now,
            historico: admin.firestore.FieldValue.arrayUnion({
                tipo: `aviso_tentativa_${n}`,
                descricao: `Régua de comunicação — tentativa ${n} registrada (origem: ${origem || "scheduled"}).`,
                data_em: now,
                origem: origem || "scheduled",
            }),
        };

        if (n < 3) {
            patch.proxima_tentativa_em = admin.firestore.Timestamp.fromMillis(agoraMs + UM_DIA_MS);
        } else {
            patch.proxima_tentativa_em = admin.firestore.FieldValue.delete();
            patch.status_notificacao = "regua_completa";
        }

        tx.update(cobRef, patch);
    });

    if (jaEnviada) {
        return { ok: true, already: true };
    }

    if (!dadosEmail || !emailDestino) {
        await cobRef.update({
            ultimo_erro_notificacao: "email_destino_ausente",
            status_notificacao: `tentativa_${n}_sem_email`,
        }).catch(() => {});
        return { ok: false, reason: "email_destino_ausente" };
    }

    let mail;
    if (n === 1) mail = templates.templateTentativa1(dadosEmail);
    else if (n === 2) mail = templates.templateTentativa2(dadosEmail);
    else mail = templates.templateTentativa3(dadosEmail);

    const envio = await enviarEmailTemplate(emailDestino, mail);
    await cobRef.update({
        status_notificacao: envio.ok ? `tentativa_${n}_enviada` : `tentativa_${n}_falha_smtp`,
        ultimo_erro_notificacao: envio.ok ? admin.firestore.FieldValue.delete() : String(envio.motivo || "smtp"),
        historico: admin.firestore.FieldValue.arrayUnion({
            tipo: envio.ok ? `email_tentativa_${n}_ok` : `email_tentativa_${n}_falha`,
            descricao: envio.ok
                ? `E-mail da tentativa ${n} enviado.`
                : `Falha ao enviar e-mail da tentativa ${n}: ${envio.motivo || "erro"}`,
            data_em: admin.firestore.Timestamp.now(),
            email_destino: emailDestino,
        }),
    }).catch(() => {});

    return { ok: envio.ok, tentativa: n, email: emailDestino };
}

/**
 * Dispara tentativa 1 ao criar/vencer cobrança (se ainda não enviada).
 */
async function dispararTentativa1SeNecessario(db, cobrancaId, origem) {
    try {
        return await registrarEEnviarTentativa(db, cobrancaId, 1, origem || "geracao");
    } catch (e) {
        console.warn("[assinatura-avisos] tentativa1:", e.message || e);
        return { ok: false, reason: e.message };
    }
}

async function enviarEmailPagamentoAprovado(dados) {
    const email = String(dados.email || "").trim();
    if (!email) return { ok: false };
    const mail = templates.templatePagamentoAprovado(dados);
    return enviarEmailTemplate(email, mail);
}

async function enviarEmailReativado(dados) {
    const email = String(dados.email || "").trim();
    if (!email) return { ok: false };
    const mail = templates.templatePlanoReativado(dados);
    return enviarEmailTemplate(email, mail);
}

async function enviarEmailSuspenso(dados) {
    const email = String(dados.email || "").trim();
    if (!email) return { ok: false };
    const mail = templates.templatePlanoSuspenso(dados);
    return enviarEmailTemplate(email, mail);
}

async function enviarEmailFalhaCartao(dados) {
    const email = String(dados.email || "").trim();
    if (!email) return { ok: false };
    // Usa template tentativa 1 com forma cartão (não bloqueia)
    const mail = templates.templateTentativa1({
        ...dados,
        formaPagamento: "Cartão recorrente",
        situacao: dados.situacao || "Falha no débito automático",
    });
    return enviarEmailTemplate(email, mail);
}

/**
 * Scheduled diário: processa cobranças com próxima tentativa devida.
 * Não suspende assinaturas.
 */
exports.assinaturaAvisosTentativasScheduled = onSchedule(
    {
        schedule: "0 10 * * *",
        timeZone: "America/Sao_Paulo",
        region: "us-central1",
        timeoutSeconds: 540,
    },
    async () => {
        const db = admin.firestore();
        const agora = admin.firestore.Timestamp.now();

        const snap = await db.collection(COLECAO)
            .where("status", "in", ["em_aberto", "vencida"])
            .get();

        let enviados = 0;
        let ignorados = 0;
        let erros = 0;

        for (const doc of snap.docs) {
            try {
                const c = doc.data() || {};
                const tentativas = Math.max(0, Number(c.tentativas_aviso || 0));
                if (tentativas >= 3) {
                    ignorados++;
                    continue;
                }

                const proxima = tsParaDate(c.proxima_tentativa_em);
                const venc = tsParaDate(c.vencimento);
                const agoraMs = Date.now();

                // Sem próxima marcada: se vencida ou venceu hoje → tentativa 1
                if (!proxima) {
                    if (tentativas === 0 && venc && venc.getTime() <= agoraMs) {
                        const r = await registrarEEnviarTentativa(db, doc.id, 1, "scheduled_vencimento");
                        if (r.ok && !r.already) enviados++;
                        else ignorados++;
                    } else {
                        ignorados++;
                    }
                    continue;
                }

                if (proxima.getTime() > agoraMs) {
                    ignorados++;
                    continue;
                }

                const proximaNum = tentativas + 1;
                if (proximaNum > 3) {
                    ignorados++;
                    continue;
                }

                const r = await registrarEEnviarTentativa(db, doc.id, proximaNum, "scheduled");
                if (r.ok && !r.already) enviados++;
                else ignorados++;
            } catch (e) {
                erros++;
                console.warn("[assinatura-avisos] erro doc", doc.id, e.message || e);
            }
        }

        console.log(
            `[assinatura-avisos] Concluído: enviados=${enviados}, ignorados=${ignorados}, erros=${erros}, agora=${agora.toDate().toISOString()}`
        );
        return null;
    },
);

exports.registrarEEnviarTentativa = registrarEEnviarTentativa;
exports.dispararTentativa1SeNecessario = dispararTentativa1SeNecessario;
exports.enviarEmailPagamentoAprovado = enviarEmailPagamentoAprovado;
exports.enviarEmailReativado = enviarEmailReativado;
exports.enviarEmailSuspenso = enviarEmailSuspenso;
exports.enviarEmailFalhaCartao = enviarEmailFalhaCartao;
exports.calcularDataBloqueioEstimada = calcularDataBloqueioEstimada;
exports.diasToleranciaRestantes = diasToleranciaRestantes;
exports.formatDateBr = formatDateBr;
