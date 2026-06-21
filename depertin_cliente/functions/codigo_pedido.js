"use strict";

/** Mesmo hash de String do Dart SDK — garante PED-XXXXXX idêntico no app e no painel. */
function dartStringHashCode(s) {
    let hash = 0;
    const str = String(s || "");
    for (let i = 0; i < str.length; i++) {
        hash = 0x1fffffff & (hash + str.charCodeAt(i));
        hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 5));
    }
    return hash | 0;
}

function gerarCodigoPedido(firebaseId) {
    const id = String(firebaseId || "").trim();
    if (!id) return "—";
    const hash = Math.abs(dartStringHashCode(id));
    const numero = String(hash % 999999).padStart(6, "0");
    return `PED-${numero}`;
}

function codigoPedidoExibir(pedidoId, dados) {
    const gravado =
        dados && dados.codigo_pedido != null
            ? String(dados.codigo_pedido).trim()
            : "";
    if (gravado) return gravado;
    return gerarCodigoPedido(pedidoId);
}

module.exports = {
    dartStringHashCode,
    gerarCodigoPedido,
    codigoPedidoExibir,
};
