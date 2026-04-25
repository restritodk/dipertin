// Arquivo: functions/tipos_entrega.js
//
// Tabela canônica de tipos de entrega aceitos por uma loja. Espelha (com
// mesma API semântica) o arquivo Dart em:
//   - depertin_cliente/lib/constants/tipos_entrega.dart
//   - depertin_web/lib/constants/tipos_entrega.dart
//
// Mantenha as três em sincronia. Builds separadas impedem import comum.

"use strict";

const COD = Object.freeze({
    BICICLETA: "bicicleta",
    MOTO: "moto",
    CARRO: "carro",
    CARRO_FRETE: "carro_frete",
});

const ORDEM_CANONICA = [COD.BICICLETA, COD.MOTO, COD.CARRO, COD.CARRO_FRETE];

const HIERARQUIA = Object.freeze({
    [COD.BICICLETA]: 1,
    [COD.MOTO]: 2,
    [COD.CARRO]: 3,
    [COD.CARRO_FRETE]: 4,
});

const TABELA_FRETE_POR_TIPO = Object.freeze({
    [COD.BICICLETA]: "padrao",
    [COD.MOTO]: "padrao",
    [COD.CARRO]: "carro",
    [COD.CARRO_FRETE]: "carro_frete",
});

const CADEIA_FALLBACK_TABELA = Object.freeze({
    [COD.CARRO_FRETE]: ["carro_frete", "carro", "padrao"],
    [COD.CARRO]: ["carro", "padrao"],
    [COD.MOTO]: ["padrao"],
    [COD.BICICLETA]: ["padrao"],
});

const RAIO_KM_RECOMENDADO = Object.freeze({
    [COD.BICICLETA]: 2.0,
    [COD.MOTO]: 15.0,
    [COD.CARRO]: 25.0,
    [COD.CARRO_FRETE]: 100.0,
});

/**
 * Normaliza o tipo de veículo do entregador (campo `veiculoTipo`, `veiculo`
 * ou `tipo_veiculo` em `users/{uid}`) para o set canônico.
 * Aceita variações: "Moto", "moto", "motocicleta", "Carro", "carro popular",
 * "carro_frete", "carro frete", "fiorino", "pick-up", "kombi", "bicicleta",
 * "bike".
 */
function normalizarTipoVeiculo(raw) {
    const s = String(raw || "").trim().toLowerCase();
    if (!s) return "";
    if (s.includes("frete") || s.includes("fiorino") || s.includes("pick") ||
        s.includes("kombi") || s.includes("utilitário") || s.includes("utilitario") ||
        s.includes("van") || s === "carro_frete") {
        return COD.CARRO_FRETE;
    }
    if (s.includes("carro")) return COD.CARRO;
    if (s.includes("moto") || s.includes("scooter") || s.includes("motocicleta")) {
        return COD.MOTO;
    }
    if (s.includes("bike") || s.includes("bicicleta") || s.includes("bicy")) {
        return COD.BICICLETA;
    }
    return "";
}

/**
 * Normaliza a lista `tipos_entrega_permitidos` de uma loja. Descarta valores
 * fora do set canônico, remove duplicatas, ordena por hierarquia crescente.
 */
function normalizarLista(raw) {
    if (!Array.isArray(raw)) return [];
    const set = new Set();
    for (const v of raw) {
        const s = String(v || "").trim().toLowerCase();
        if (HIERARQUIA[s] != null) set.add(s);
    }
    return Array.from(set).sort(
        (a, b) => (HIERARQUIA[a] || 0) - (HIERARQUIA[b] || 0),
    );
}

/** Tipo de MAIOR hierarquia da lista (ou null se vazia). */
function maiorTipo(tipos) {
    if (!Array.isArray(tipos) || tipos.length === 0) return null;
    let melhor = null;
    let maior = -1;
    for (const t of tipos) {
        const h = HIERARQUIA[t] || -1;
        if (h > maior) {
            maior = h;
            melhor = t;
        }
    }
    return melhor;
}

/**
 * Retorna true se o entregador pode receber a corrida.
 * `aceitos` vazio → loja legada sem config → NÃO filtra (compat).
 */
function compativel(tipoVeiculoEntregador, aceitos) {
    if (!Array.isArray(aceitos) || aceitos.length === 0) return true;
    return aceitos.includes(tipoVeiculoEntregador);
}

/**
 * Deriva default para lojas legado. Chamar só quando o doc da loja ainda
 * não tem `tipos_entrega_permitidos`. Input:
 *   - `temProdutoRequerVeiculoGrande`: bool (agregado dos produtos da loja).
 */
function defaultLegado({ temProdutoRequerVeiculoGrande }) {
    if (temProdutoRequerVeiculoGrande) {
        return [COD.CARRO, COD.CARRO_FRETE];
    }
    // Política conservadora — preserva comportamento pré-migração para
    // lojas legado. Bicicleta e carro são opt-in explícito do lojista.
    return [COD.MOTO];
}

function lerDeDoc(data) {
    if (!data || typeof data !== "object") return [];
    return normalizarLista(data.tipos_entrega_permitidos);
}

/**
 * Normaliza a categoria **escolhida pelo lojista no momento da solicitação**
 * (`pedido.tipo_entrega_solicitado`). Diferente de `tipos_entrega_permitidos`
 * (lista aceita pela loja), aqui o valor é uma string canônica única
 * decidida a cada clique em "Solicitar entregador". Aceita variações e
 * devolve código canônico (ou string vazia se inválido).
 */
function normalizarTipoSolicitado(raw) {
    const s = String(raw || "").trim().toLowerCase();
    if (!s) return "";
    if (HIERARQUIA[s] != null) return s;
    return normalizarTipoVeiculo(s);
}

/**
 * Deriva a categoria efetivamente buscada para o pedido.
 *
 * Ordem de precedência:
 *   1. `pedido.tipo_entrega_solicitado` — escolha explícita do lojista.
 *   2. Se a lista aceita tem **apenas um** tipo → esse tipo é implícito.
 *   3. `null` quando a loja aceita múltiplos tipos mas ainda não escolheu
 *      (bloqueia o despacho até nova decisão).
 *   4. `null` também para loja legado sem config (caller decide se filtra
 *      ou não — compatibilidade preservada em outro helper).
 *
 * Retornos possíveis:
 *   - string canônica (ex: "moto") → filtra entregadores por esse tipo exato.
 *   - null → não há categoria decidida para este pedido.
 */
function categoriaEfetivaPedido(pedido, tiposAceitosLoja) {
    const explicito = normalizarTipoSolicitado(pedido && pedido.tipo_entrega_solicitado);
    if (explicito) return explicito;
    const aceitos = Array.isArray(tiposAceitosLoja)
        ? normalizarLista(tiposAceitosLoja)
        : [];
    if (aceitos.length === 1) return aceitos[0];
    return null;
}

function rotulo(codigo) {
    switch (codigo) {
        case COD.BICICLETA: return "Bicicleta";
        case COD.MOTO: return "Moto";
        case COD.CARRO: return "Carro popular";
        case COD.CARRO_FRETE: return "Carro frete";
        default: return String(codigo || "");
    }
}

module.exports = {
    COD,
    TIPOS: COD,
    ORDEM_CANONICA,
    HIERARQUIA,
    TABELA_FRETE_POR_TIPO,
    CADEIA_FALLBACK_TABELA,
    RAIO_KM_RECOMENDADO,
    normalizarTipoVeiculo,
    normalizarLista,
    maiorTipo,
    compativel,
    defaultLegado,
    lerDeDoc,
    rotulo,
    normalizarTipoSolicitado,
    categoriaEfetivaPedido,
};
