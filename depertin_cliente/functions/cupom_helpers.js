"use strict";

const TIPOS_CUPOM = {
    PORCENTAGEM: "porcentagem",
    FIXO: "fixo",
    FRETE_GRATIS: "frete_gratis",
};

const FRETE_MODALIDADE = {
    SEM_LIMITE: "sem_limite",
    RAIO_KM: "raio_km",
};

function roundMoney(v) {
    const n = Number(v);
    if (Number.isNaN(n)) return 0;
    return Math.round(n * 100) / 100;
}

function lerTimestamp(data, campo) {
    const raw = data?.[campo];
    if (!raw) return null;
    if (typeof raw.toDate === "function") return raw.toDate();
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
}

/** YYYY-MM-DD no fuso do app (Brasil) — vigência é por dia civil, não instante UTC. */
const FUSO_VIGENCIA_CUPOM = "America/Sao_Paulo";

function dataCivilBrasil(date) {
    if (!date || Number.isNaN(date.getTime())) return null;
    return date.toLocaleDateString("en-CA", { timeZone: FUSO_VIGENCIA_CUPOM });
}

function cupomDentroDaVigencia(cupom, agora = new Date()) {
    const hoje = dataCivilBrasil(agora);
    if (!hoje) return { ok: true };

    const inicio = lerTimestamp(cupom, "validade_inicio");
    if (inicio) {
        const diaInicio = dataCivilBrasil(inicio);
        if (diaInicio && diaInicio > hoje) {
            return { ok: false, mensagem: "Este cupom ainda não está válido." };
        }
    }

    const fim =
        lerTimestamp(cupom, "validade") || lerTimestamp(cupom, "validade_fim");
    if (fim) {
        const diaFim = dataCivilBrasil(fim);
        if (diaFim && diaFim < hoje) {
            return { ok: false, mensagem: "Este cupom expirou." };
        }
    }

    return { ok: true };
}

/** Distância Haversine em km (loja → entrega). */
function distanciaKm(lat1, lon1, lat2, lon2) {
    const a1 = Number(lat1);
    const o1 = Number(lon1);
    const a2 = Number(lat2);
    const o2 = Number(lon2);
    if ([a1, o1, a2, o2].some((x) => Number.isNaN(x))) return null;
    const R = 6371;
    const dLat = ((a2 - a1) * Math.PI) / 180;
    const dLon = ((o2 - o1) * Math.PI) / 180;
    const s1 = Math.sin(dLat / 2);
    const s2 = Math.sin(dLon / 2);
    const h =
        s1 * s1 +
        Math.cos((a1 * Math.PI) / 180) *
            Math.cos((a2 * Math.PI) / 180) *
            s2 *
            s2;
    return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function validarFreteGratisRaio(cupom, params) {
    if (params.retirada_na_loja === true) {
        return {
            ok: false,
            mensagem: "Cupom de frete grátis válido apenas para entregas.",
        };
    }
    const taxaEntrega = roundMoney(Number(params.taxa_entrega ?? 0));
    if (taxaEntrega <= 0) {
        return {
            ok: false,
            mensagem: "Não há frete para aplicar este cupom.",
        };
    }
    const modalidade = String(
        cupom.frete_gratis_modalidade || FRETE_MODALIDADE.SEM_LIMITE,
    ).toLowerCase();
    if (modalidade !== FRETE_MODALIDADE.RAIO_KM) {
        return { ok: true, descontoFrete: taxaEntrega };
    }
    const raioMax = Number(cupom.frete_gratis_raio_km ?? 0);
    if (raioMax <= 0) {
        return {
            ok: false,
            mensagem: "Cupom de frete grátis mal configurado (raio inválido).",
        };
    }
    let distKm = Number(params.distancia_entrega_km);
    if (Number.isNaN(distKm) || distKm <= 0) {
        distKm = distanciaKm(
            params.loja_latitude,
            params.loja_longitude,
            params.entrega_latitude,
            params.entrega_longitude,
        );
    }
    if (distKm == null || Number.isNaN(distKm)) {
        return {
            ok: false,
            mensagem:
                "Não foi possível calcular a distância para validar o frete grátis.",
        };
    }
    if (distKm > raioMax + 0.05) {
        return {
            ok: false,
            mensagem:
                `Este cupom de frete grátis vale até ${raioMax} km. ` +
                `Seu endereço está a aproximadamente ${distKm.toFixed(1)} km da loja.`,
        };
    }
    return { ok: true, descontoFrete: taxaEntrega, distanciaKm: distKm };
}

function calcularDescontoProduto(tipo, valorCupom, subtotalProdutos) {
    const tipoNorm = String(tipo || TIPOS_CUPOM.PORCENTAGEM).toLowerCase();
    const valor = Number(valorCupom || 0);
    let desconto = 0;
    if (tipoNorm === TIPOS_CUPOM.PORCENTAGEM) {
        desconto = roundMoney(subtotalProdutos * (valor / 100));
    } else if (tipoNorm === TIPOS_CUPOM.FIXO) {
        desconto = roundMoney(Math.min(valor, subtotalProdutos));
    }
    desconto = Math.min(desconto, subtotalProdutos);
    return Math.max(0, desconto);
}

module.exports = {
    TIPOS_CUPOM,
    FRETE_MODALIDADE,
    FUSO_VIGENCIA_CUPOM,
    roundMoney,
    dataCivilBrasil,
    cupomDentroDaVigencia,
    distanciaKm,
    validarFreteGratisRaio,
    calcularDescontoProduto,
};
