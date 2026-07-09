"use strict";

/**
 * Validação de CPF/CNPJ e BR Code PIX (EMV) — sem dependências de gateway.
 */

const MSG_CHAVE_PIX_INVALIDA =
    "A conta Mercado Pago configurada não possui uma chave PIX válida para recebimento. "
    + "Verifique o cadastro PIX no painel do Mercado Pago.";

const MSG_RESPOSTA_PIX_INVALIDA =
    "O gateway retornou um código PIX inválido. Verifique a configuração da conta no provedor.";

function cpfValidoMod11(cpfRaw) {
    const cpf = String(cpfRaw || "").replace(/\D/g, "");
    if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;
    let soma = 0;
    for (let i = 0; i < 9; i++) soma += parseInt(cpf[i], 10) * (10 - i);
    let resto = (soma * 10) % 11;
    if (resto === 10) resto = 0;
    if (resto !== parseInt(cpf[9], 10)) return false;
    soma = 0;
    for (let i = 0; i < 10; i++) soma += parseInt(cpf[i], 10) * (11 - i);
    resto = (soma * 10) % 11;
    if (resto === 10) resto = 0;
    return resto === parseInt(cpf[10], 10);
}

function cnpjValidoMod11(cnpjRaw) {
    const cnpj = String(cnpjRaw || "").replace(/\D/g, "");
    if (cnpj.length !== 14 || /^(\d)\1{13}$/.test(cnpj)) return false;
    const calcDig = function (base, pesos) {
        let soma = 0;
        for (let i = 0; i < pesos.length; i++) {
            soma += parseInt(base[i], 10) * pesos[i];
        }
        const resto = soma % 11;
        return resto < 2 ? 0 : 11 - resto;
    };
    const pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const pesos2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const d1 = calcDig(cnpj, pesos1);
    const d2 = calcDig(cnpj, pesos2);
    return d1 === parseInt(cnpj[12], 10) && d2 === parseInt(cnpj[13], 10);
}

function cpfPagadorValidoParaApi(cpfRaw) {
    const cpf = String(cpfRaw || "").replace(/\D/g, "").substring(0, 11);
    return cpf.length === 11 && cpfValidoMod11(cpf) ? cpf : null;
}

function parseSubTlvEmv(content) {
    const map = {};
    let i = 0;
    const s = String(content || "");
    while (i + 4 <= s.length) {
        const id = s.substring(i, i + 2);
        const len = parseInt(s.substring(i + 2, i + 4), 10);
        i += 4;
        if (!Number.isFinite(len) || len < 0 || i + len > s.length) break;
        map[id] = s.substring(i, i + len);
        i += len;
    }
    return map;
}

function extrairChavePixDoBrCode(qrCode) {
    const payload = String(qrCode || "");
    let i = 0;
    while (i + 4 <= payload.length) {
        const tag = payload.substring(i, i + 2);
        const len = parseInt(payload.substring(i + 2, i + 4), 10);
        i += 4;
        if (!Number.isFinite(len) || len < 0 || i + len > payload.length) break;
        const value = payload.substring(i, i + len);
        i += len;
        if (tag === "26") {
            const sub = parseSubTlvEmv(value);
            if (sub["01"]) {
                return { chave: sub["01"], gui: sub["00"] || "" };
            }
        }
    }
    return { chave: null, gui: "" };
}

function classificarChavePix(chave) {
    const k = String(chave || "").trim();
    if (!k) return { tipo: "desconhecida", valida: false };
    if (/^\d{11}$/.test(k)) {
        return { tipo: "cpf", valida: cpfValidoMod11(k), valor: k };
    }
    if (/^\d{14}$/.test(k)) {
        return { tipo: "cnpj", valida: cnpjValidoMod11(k), valor: k };
    }
    if (/^\+?\d{10,13}$/.test(k) || /^\d{10,11}$/.test(k)) {
        return { tipo: "telefone", valida: k.replace(/\D/g, "").length >= 10, valor: k };
    }
    if (k.includes("@") && k.length >= 5 && k.length <= 77) {
        return { tipo: "email", valida: true, valor: k };
    }
    if (/^[0-9a-fA-F-]{32,36}$/.test(k)) {
        return { tipo: "aleatoria", valida: true, valor: k };
    }
    return { tipo: "desconhecida", valida: false, valor: k };
}

function analisarCopiaColaPixApi(qrCode, opts) {
    opts = opts || {};
    const qr = String(qrCode || "").trim();
    if (!qr) {
        return { ok: false, motivo: "Código PIX vazio.", codigo: "pix_vazio" };
    }
    if (!qr.startsWith("000201")) {
        return { ok: false, motivo: MSG_RESPOSTA_PIX_INVALIDA, codigo: "emv_prefixo" };
    }
    if (!/6304[0-9A-Fa-f]{4}$/.test(qr)) {
        return { ok: false, motivo: MSG_RESPOSTA_PIX_INVALIDA, codigo: "emv_crc" };
    }

    const dinamico = /mpqrinter/i.test(qr)
        || /br\.gov\.bcb\.qr01/i.test(qr)
        || /pix-qr\.mercadopago\.com/i.test(qr)
        || /62\d{2}\d{2}05/i.test(qr);

    const { chave, gui } = extrairChavePixDoBrCode(qr);
    if (!chave) {
        if (dinamico) {
            return { ok: true, formato: "dinamico_sem_chave_embutida", dinamico: true };
        }
        return { ok: false, motivo: MSG_CHAVE_PIX_INVALIDA, codigo: "chave_ausente" };
    }

    const cls = classificarChavePix(chave);
    if ((cls.tipo === "cpf" || cls.tipo === "cnpj") && !cls.valida) {
        return {
            ok: false,
            motivo: MSG_CHAVE_PIX_INVALIDA,
            codigo: cls.tipo === "cpf" ? "cpf_invalido" : "cnpj_invalido",
            chaveTipo: cls.tipo,
            chaveValor: cls.valor,
            dinamico,
            gui,
        };
    }

    // PIX estático com CPF/CNPJ no EMV — apps bancários rejeitam se a chave não estiver no DICT.
    if (!dinamico && (cls.tipo === "cpf" || cls.tipo === "cnpj")) {
        return {
            ok: false,
            motivo: MSG_CHAVE_PIX_INVALIDA,
            codigo: "chave_documento_estatica",
            chaveTipo: cls.tipo,
            chaveValor: cls.valor,
            dinamico,
            gui,
        };
    }

    // PIX dinâmico Mercado Pago (tag 62 com mpqrinter): CNPJ do arranjo na tag 26 é padrão oficial —
    // mesmo formato do marketplace (mpCriarPagamentoPix). Não rejeitar; confiar na API como no checkout DiPertin.
    const ehPixDinamicoMercadoPago = dinamico && /mpqrinter/i.test(qr);

    // PIX dinâmico de outros gateways: CPF/CNPJ na tag 26 costuma ser chave estática mal embutida.
    if (opts.exigirPixDinamico && dinamico && (cls.tipo === "cpf" || cls.tipo === "cnpj") && !ehPixDinamicoMercadoPago) {
        return {
            ok: false,
            motivo: MSG_CHAVE_PIX_INVALIDA,
            codigo: "chave_documento_em_qr_dinamico",
            chaveTipo: cls.tipo,
            chaveValor: cls.valor,
            dinamico,
            gui,
        };
    }

    // Mercado Pago Payments API: cobrança deve ser PIX dinâmico (URL no EMV tag 62).
    if (opts.exigirPixDinamico && !dinamico) {
        return {
            ok: false,
            motivo: MSG_CHAVE_PIX_INVALIDA,
            codigo: "pix_nao_dinamico",
            chaveTipo: cls.tipo,
            chaveValor: cls.valor,
            dinamico: false,
            gui,
        };
    }

    if (cls.tipo === "desconhecida") {
        return {
            ok: false,
            motivo: MSG_CHAVE_PIX_INVALIDA,
            codigo: "chave_formato_desconhecido",
            chaveValor: chave,
            dinamico,
        };
    }

    return {
        ok: true,
        formato: dinamico ? "dinamico" : "estatico",
        dinamico,
        chaveTipo: cls.tipo,
        chaveValor: cls.valor,
        gui,
    };
}

function ambienteTokenMercadoPago(accessToken) {
    const t = String(accessToken || "").trim();
    if (t.startsWith("TEST-")) return "sandbox";
    if (t.startsWith("APP_USR-")) return "producao";
    return "desconhecido";
}

module.exports = {
    MSG_CHAVE_PIX_INVALIDA,
    MSG_RESPOSTA_PIX_INVALIDA,
    cpfValidoMod11,
    cnpjValidoMod11,
    cpfPagadorValidoParaApi,
    analisarCopiaColaPixApi,
    ambienteTokenMercadoPago,
};
