"use strict";

/**
 * Templates premium de e-mail — Assinaturas Gestão Comercial DiPertin.
 * Remetente: DiPertin <naoresponder@dipertin.com.br> (via smtp.from("padrao")).
 * Nunca incluir tokens, CVV, número completo de cartão ou credenciais.
 */

const ROXO = "#6A1B9A";
const ROXO_CLARO = "#8E24AA";
const LARANJA = "#FF8F00";
const TEXTO = "#1A1A2E";
const MUTED = "#64748B";
const FUNDO = "#F5F4F8";
const BRANCO = "#FFFFFF";

const URL_PAINEL =
    "https://www.dipertin.com.br/sistema/app.html#/comercial_dashboard";
const URL_PAGAR =
    "https://www.dipertin.com.br/sistema/app.html#/minha_loja";

function esc(v) {
    return String(v == null ? "" : v)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function fmtMoney(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return "—";
    return n.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
}

function shell({ titulo, destaque, corpoHtml, ctaLabel, ctaUrl, ctaSecundarioLabel, ctaSecundarioUrl }) {
    const cta = ctaLabel && ctaUrl
        ? `<a href="${esc(ctaUrl)}" style="display:inline-block;padding:14px 28px;background:linear-gradient(135deg,${ROXO},${ROXO_CLARO});color:${BRANCO};text-decoration:none;border-radius:12px;font-weight:700;font-size:15px;">${esc(ctaLabel)}</a>`
        : "";
    const cta2 = ctaSecundarioLabel && ctaSecundarioUrl
        ? `<a href="${esc(ctaSecundarioUrl)}" style="display:inline-block;padding:12px 22px;margin-left:8px;border:2px solid ${ROXO};color:${ROXO};text-decoration:none;border-radius:12px;font-weight:700;font-size:14px;">${esc(ctaSecundarioLabel)}</a>`
        : "";

    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${esc(titulo)}</title>
</head>
<body style="margin:0;padding:0;background:${FUNDO};font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:${TEXTO};">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${FUNDO};padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:600px;background:${BRANCO};border-radius:20px;overflow:hidden;border:1px solid #E8E4F0;">
        <tr>
          <td style="background:linear-gradient(135deg,${ROXO},${ROXO_CLARO});padding:28px 24px;text-align:center;">
            <div style="font-size:22px;font-weight:800;color:${BRANCO};letter-spacing:0.3px;">DiPertin</div>
            <div style="margin-top:6px;font-size:13px;color:rgba(255,255,255,0.9);">Gestão Comercial</div>
          </td>
        </tr>
        <tr>
          <td style="padding:28px 24px 8px;">
            <h1 style="margin:0 0 8px;font-size:22px;font-weight:800;color:${TEXTO};line-height:1.3;">${esc(titulo)}</h1>
            ${destaque ? `<p style="margin:0 0 16px;font-size:14px;color:${LARANJA};font-weight:700;">${esc(destaque)}</p>` : ""}
            <div style="font-size:15px;line-height:1.6;color:${MUTED};">${corpoHtml}</div>
          </td>
        </tr>
        ${(cta || cta2) ? `<tr><td style="padding:8px 24px 28px;text-align:center;">${cta}${cta2}</td></tr>` : ""}
        <tr>
          <td style="padding:16px 24px 24px;border-top:1px solid #EEEAF6;font-size:12px;color:${MUTED};line-height:1.5;">
            Este e-mail foi enviado automaticamente por <strong>DiPertin</strong>
            (&lt;naoresponder@dipertin.com.br&gt;). Não responda esta mensagem.
            Nunca solicitamos senha, token ou dados de cartão por e-mail.
            <br/>© DiPertin — Todos os direitos reservados.
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function cardDetalhes(d) {
    const linhas = [
        ["Loja", d.lojaNome],
        ["Plano", d.planoNome],
        ["Valor", d.valorExibicao || fmtMoney(d.valor)],
        ["Vencimento", d.vencimento],
        ["Situação", d.situacao],
        ["Cobrança", d.fatura || d.cobrancaId],
        ["Forma de pagamento", d.formaPagamento],
        ["Tolerância restante", d.diasToleranciaRestantes],
        ["Bloqueio estimado", d.dataBloqueioEstimada],
    ].filter(([, v]) => v != null && String(v).trim() !== "");

    const rows = linhas.map(([k, v]) =>
        `<tr>
          <td style="padding:8px 0;font-size:13px;color:${MUTED};width:42%;">${esc(k)}</td>
          <td style="padding:8px 0;font-size:13px;font-weight:700;color:${TEXTO};">${esc(v)}</td>
        </tr>`
    ).join("");

    return `<table role="presentation" width="100%" style="margin:16px 0;background:${FUNDO};border-radius:14px;padding:4px 16px;">${rows}</table>`;
}

function dadosPadrao(d) {
    return {
        lojaNome: d.lojaNome || d.store_name || "Lojista",
        planoNome: d.planoNome || d.plan_name || "Plano",
        valor: d.valor,
        valorExibicao: d.valorExibicao,
        vencimento: d.vencimento || "—",
        situacao: d.situacao || "—",
        fatura: d.fatura || "",
        cobrancaId: d.cobrancaId || d.cobranca_id || "",
        formaPagamento: d.formaPagamento || "—",
        diasToleranciaRestantes: d.diasToleranciaRestantes,
        dataBloqueioEstimada: d.dataBloqueioEstimada,
        urlPainel: d.urlPainel || URL_PAINEL,
        urlPagar: d.urlPagar || URL_PAGAR,
    };
}

/** 6.1 Pagamento próximo do vencimento */
function templateVencimentoProximo(raw) {
    const d = dadosPadrao(raw);
    return {
        subject: "Sua assinatura DiPertin vence em breve",
        html: shell({
            titulo: "Sua assinatura vence em breve",
            destaque: "Evite interrupções no Gestão Comercial",
            corpoHtml: `<p>Olá, <strong style="color:${TEXTO}">${esc(d.lojaNome)}</strong>.</p>
              <p>Identificamos que a mensalidade do plano <strong style="color:${TEXTO}">${esc(d.planoNome)}</strong> está próxima do vencimento.</p>
              ${cardDetalhes(d)}
              <p>Regularize com antecedência para manter seu acesso sem interrupções.</p>`,
            ctaLabel: "Acessar o painel",
            ctaUrl: d.urlPainel,
            ctaSecundarioLabel: "Pagar agora",
            ctaSecundarioUrl: d.urlPagar,
        }),
    };
}

/** 6.2 Primeira tentativa / vencimento */
function templateTentativa1(raw) {
    const d = dadosPadrao(raw);
    const isCartao = String(d.formaPagamento || "").toLowerCase().includes("cart");
    return {
        subject: "Pagamento da assinatura pendente",
        html: shell({
            titulo: "Pagamento da assinatura pendente",
            destaque: isCartao
                ? "A cobrança no cartão não foi aprovada"
                : "A mensalidade venceu e aguarda pagamento",
            corpoHtml: `<p>Olá, <strong style="color:${TEXTO}">${esc(d.lojaNome)}</strong>.</p>
              <p>${isCartao
        ? "Não conseguimos confirmar o débito automático no cartão cadastrado."
        : "A mensalidade do seu plano venceu e ainda não identificamos o pagamento."
}</p>
              ${cardDetalhes({ ...d, situacao: d.situacao || "Pendente — tentativa 1" })}
              <p>Você pode regularizar agora pelo painel. Seu acesso continua conforme a regra de tolerância do plano.</p>`,
            ctaLabel: "Pagar agora",
            ctaUrl: d.urlPagar,
            ctaSecundarioLabel: "Abrir painel",
            ctaSecundarioUrl: d.urlPainel,
        }),
    };
}

/** 6.3 Segunda tentativa */
function templateTentativa2(raw) {
    const d = dadosPadrao(raw);
    return {
        subject: "Sua assinatura continua pendente",
        html: shell({
            titulo: "Sua assinatura continua pendente",
            destaque: "Segundo lembrete de pagamento",
            corpoHtml: `<p>Olá, <strong style="color:${TEXTO}">${esc(d.lojaNome)}</strong>.</p>
              <p>Passadas 24 horas, o pagamento da assinatura <strong style="color:${TEXTO}">${esc(d.planoNome)}</strong> ainda não foi confirmado.</p>
              ${cardDetalhes({ ...d, situacao: d.situacao || "Pendente — tentativa 2" })}
              <p>Regularize o quanto antes. A suspensão segue apenas a regra de tolerância configurada no seu plano — este aviso não altera essa data.</p>`,
            ctaLabel: "Pagar agora",
            ctaUrl: d.urlPagar,
            ctaSecundarioLabel: "Abrir painel",
            ctaSecundarioUrl: d.urlPainel,
        }),
    };
}

/** 6.4 Terceira tentativa */
function templateTentativa3(raw) {
    const d = dadosPadrao(raw);
    return {
        subject: "Último lembrete antes da suspensão programada",
        html: shell({
            titulo: "Último lembrete da régua de avisos",
            destaque: "Suspensão segue a regra do plano — não esta tentativa",
            corpoHtml: `<p>Olá, <strong style="color:${TEXTO}">${esc(d.lojaNome)}</strong>.</p>
              <p>Este é o <strong style="color:${TEXTO}">terceiro e último aviso</strong> da nossa régua de comunicação sobre o pagamento pendente.</p>
              ${cardDetalhes({ ...d, situacao: d.situacao || "Pendente — tentativa 3" })}
              <p>Seu plano continua sujeito à regra normal de tolerância e suspensão. Este e-mail <strong>não bloqueia</strong> o acesso. Após o prazo configurado, o acesso à Gestão Comercial poderá ser temporariamente suspenso até a regularização.</p>
              <p>Seus dados comerciais permanecem intactos em qualquer hipótese.</p>`,
            ctaLabel: "Regularizar pagamento",
            ctaUrl: d.urlPagar,
            ctaSecundarioLabel: "Abrir painel",
            ctaSecundarioUrl: d.urlPainel,
        }),
    };
}

/** 6.5 Pagamento aprovado */
function templatePagamentoAprovado(raw) {
    const d = dadosPadrao(raw);
    return {
        subject: "Pagamento confirmado — assinatura renovada",
        html: shell({
            titulo: "Pagamento confirmado",
            destaque: "Assinatura renovada com sucesso",
            corpoHtml: `<p>Olá, <strong style="color:${TEXTO}">${esc(d.lojaNome)}</strong>.</p>
              <p>Confirmamos o pagamento da sua assinatura. O acesso à Gestão Comercial permanece ativo.</p>
              ${cardDetalhes({ ...d, situacao: d.situacao || "Ativo / renovado" })}`,
            ctaLabel: "Acessar Gestão Comercial",
            ctaUrl: d.urlPainel,
        }),
    };
}

/** 6.6 Plano suspenso */
function templatePlanoSuspenso(raw) {
    const d = dadosPadrao(raw);
    return {
        subject: "Seu acesso à Gestão Comercial foi temporariamente suspenso",
        html: shell({
            titulo: "Acesso temporariamente suspenso",
            destaque: "Seus dados permanecem seguros",
            corpoHtml: `<p>Olá, <strong style="color:${TEXTO}">${esc(d.lojaNome)}</strong>.</p>
              <p>O acesso aos módulos da Gestão Comercial foi temporariamente suspenso conforme a regra de tolerância e suspensão do plano <strong style="color:${TEXTO}">${esc(d.planoNome)}</strong>.</p>
              ${cardDetalhes({ ...d, situacao: "Suspenso" })}
              <p><strong style="color:${TEXTO}">Importante:</strong> nenhum cliente, venda, estoque, financeiro, pedido ou configuração foi apagado. Após o pagamento, tudo volta exatamente como estava.</p>`,
            ctaLabel: "Pagar e reativar",
            ctaUrl: d.urlPagar,
        }),
    };
}

/** 6.7 Plano reativado */
function templatePlanoReativado(raw) {
    const d = dadosPadrao(raw);
    return {
        subject: "Seu acesso à Gestão Comercial foi restabelecido",
        html: shell({
            titulo: "Acesso restabelecido",
            destaque: "Bem-vindo de volta",
            corpoHtml: `<p>Olá, <strong style="color:${TEXTO}">${esc(d.lojaNome)}</strong>.</p>
              <p>O pagamento foi confirmado e o acesso à Gestão Comercial foi restabelecido. Seus dados e configurações permanecem intactos.</p>
              ${cardDetalhes({ ...d, situacao: "Ativo" })}`,
            ctaLabel: "Abrir Gestão Comercial",
            ctaUrl: d.urlPainel,
        }),
    };
}

module.exports = {
    URL_PAINEL,
    URL_PAGAR,
    fmtMoney,
    templateVencimentoProximo,
    templateTentativa1,
    templateTentativa2,
    templateTentativa3,
    templatePagamentoAprovado,
    templatePlanoSuspenso,
    templatePlanoReativado,
};
