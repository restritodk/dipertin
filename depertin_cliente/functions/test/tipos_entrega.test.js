// Arquivo: functions/test/tipos_entrega.test.js
//
// Smoke tests do helper Node `functions/tipos_entrega.js`. Roda com o
// test runner nativo do Node 18+ (zero dependências adicionais):
//
//   npm test   (após adicionar `"test": "node --test test/"` ao package.json)
//   ou
//   node --test test/tipos_entrega.test.js
//
// Este arquivo é o espelho JS dos testes Dart em
// `depertin_cliente/test/constants/tipos_entrega_test.dart` — garantem que
// os 3 builds (mobile, web, backend) concordem sobre a regra de negócio.

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../tipos_entrega");

test("normalizarLista descarta valores fora do canônico", () => {
    assert.deepEqual(
        T.normalizarLista(["moto", "drone", "carro", null, 123, "BICICLETA"]),
        ["bicicleta", "moto", "carro"],
    );
});

test("normalizarLista remove duplicatas e lowercase", () => {
    assert.deepEqual(
        T.normalizarLista(["MOTO", "moto", "Moto", "carro", "carro"]),
        ["moto", "carro"],
    );
});

test("normalizarLista ordena por hierarquia ascendente", () => {
    assert.deepEqual(
        T.normalizarLista(["carro_frete", "bicicleta", "carro", "moto"]),
        ["bicicleta", "moto", "carro", "carro_frete"],
    );
});

test("normalizarLista devolve [] para não-array", () => {
    assert.deepEqual(T.normalizarLista(null), []);
    assert.deepEqual(T.normalizarLista(42), []);
    assert.deepEqual(T.normalizarLista("moto"), []);
});

test("maiorTipo: null para vazio", () => {
    assert.equal(T.maiorTipo([]), null);
    assert.equal(T.maiorTipo(null), null);
});

test("maiorTipo: escolhe o topo da hierarquia", () => {
    assert.equal(T.maiorTipo(["moto", "carro"]), "carro");
    assert.equal(
        T.maiorTipo(["bicicleta", "moto", "carro", "carro_frete"]),
        "carro_frete",
    );
    assert.equal(T.maiorTipo(["bicicleta"]), "bicicleta");
});

test("compativel: loja sem config aceita qualquer entregador (legado)", () => {
    assert.equal(T.compativel("moto", []), true);
    assert.equal(T.compativel("", []), true);
    assert.equal(T.compativel("bicicleta", null), true);
});

test("compativel: loja só carro_frete filtra motoboy", () => {
    assert.equal(T.compativel("moto", ["carro_frete"]), false);
    assert.equal(T.compativel("carro_frete", ["carro_frete"]), true);
});

test("compativel: loja com múltiplos tipos aceita todos da lista", () => {
    const aceitos = ["bicicleta", "moto", "carro"];
    assert.equal(T.compativel("bicicleta", aceitos), true);
    assert.equal(T.compativel("moto", aceitos), true);
    assert.equal(T.compativel("carro", aceitos), true);
    assert.equal(T.compativel("carro_frete", aceitos), false);
});

test("defaultLegado (Opção B): sem volumoso → [moto]", () => {
    assert.deepEqual(
        T.defaultLegado({ temProdutoRequerVeiculoGrande: false }),
        ["moto"],
    );
});

test("defaultLegado: com volumoso → [carro, carro_frete]", () => {
    assert.deepEqual(
        T.defaultLegado({ temProdutoRequerVeiculoGrande: true }),
        ["carro", "carro_frete"],
    );
});

test("defaultLegado: bicicleta nunca entra em default", () => {
    const sem = T.defaultLegado({ temProdutoRequerVeiculoGrande: false });
    const com = T.defaultLegado({ temProdutoRequerVeiculoGrande: true });
    assert.ok(!sem.includes("bicicleta"));
    assert.ok(!com.includes("bicicleta"));
});

test("CADEIA_FALLBACK_TABELA.carro_frete cobre 3 níveis", () => {
    assert.deepEqual(
        T.CADEIA_FALLBACK_TABELA[T.COD.CARRO_FRETE],
        ["carro_frete", "carro", "padrao"],
    );
});

test("CADEIA_FALLBACK_TABELA.carro cai em padrao", () => {
    assert.deepEqual(
        T.CADEIA_FALLBACK_TABELA[T.COD.CARRO],
        ["carro", "padrao"],
    );
});

test("CADEIA_FALLBACK_TABELA moto e bike usam padrao direto", () => {
    assert.deepEqual(T.CADEIA_FALLBACK_TABELA[T.COD.MOTO], ["padrao"]);
    assert.deepEqual(T.CADEIA_FALLBACK_TABELA[T.COD.BICICLETA], ["padrao"]);
});

test("HIERARQUIA bike(1)<moto(2)<carro(3)<frete(4)", () => {
    assert.equal(T.HIERARQUIA.bicicleta, 1);
    assert.equal(T.HIERARQUIA.moto, 2);
    assert.equal(T.HIERARQUIA.carro, 3);
    assert.equal(T.HIERARQUIA.carro_frete, 4);
});

test("lerDeDoc: null → []", () => {
    assert.deepEqual(T.lerDeDoc(null), []);
    assert.deepEqual(T.lerDeDoc(undefined), []);
});

test("lerDeDoc lê tipos_entrega_permitidos e normaliza", () => {
    assert.deepEqual(
        T.lerDeDoc({ tipos_entrega_permitidos: ["CARRO", "moto", "bicicleta"] }),
        ["bicicleta", "moto", "carro"],
    );
});

test("lerDeDoc: doc sem campo → []", () => {
    assert.deepEqual(T.lerDeDoc({ outra_coisa: true }), []);
});

test("normalizarTipoVeiculo: variações comuns", () => {
    assert.equal(T.normalizarTipoVeiculo("Moto"), "moto");
    assert.equal(T.normalizarTipoVeiculo("motocicleta"), "moto");
    assert.equal(T.normalizarTipoVeiculo("scooter"), "moto");
    assert.equal(T.normalizarTipoVeiculo("Carro popular"), "carro");
    assert.equal(T.normalizarTipoVeiculo("carro"), "carro");
    assert.equal(T.normalizarTipoVeiculo("carro_frete"), "carro_frete");
    assert.equal(T.normalizarTipoVeiculo("Fiorino"), "carro_frete");
    assert.equal(T.normalizarTipoVeiculo("pick-up"), "carro_frete");
    assert.equal(T.normalizarTipoVeiculo("Kombi"), "carro_frete");
    assert.equal(T.normalizarTipoVeiculo("utilitário"), "carro_frete");
    assert.equal(T.normalizarTipoVeiculo("Bike"), "bicicleta");
    assert.equal(T.normalizarTipoVeiculo("bicicleta"), "bicicleta");
    assert.equal(T.normalizarTipoVeiculo(""), "");
    assert.equal(T.normalizarTipoVeiculo(null), "");
    assert.equal(T.normalizarTipoVeiculo("avião"), "");
});

test("normalizarTipoSolicitado: aceita código canônico direto", () => {
    assert.equal(T.normalizarTipoSolicitado("moto"), "moto");
    assert.equal(T.normalizarTipoSolicitado("carro"), "carro");
    assert.equal(T.normalizarTipoSolicitado("carro_frete"), "carro_frete");
    assert.equal(T.normalizarTipoSolicitado("bicicleta"), "bicicleta");
});

test("normalizarTipoSolicitado: aceita variações livres (ex: Carro Popular)", () => {
    assert.equal(T.normalizarTipoSolicitado("Carro Popular"), "carro");
    assert.equal(T.normalizarTipoSolicitado("motocicleta"), "moto");
    assert.equal(T.normalizarTipoSolicitado("Pick-up"), "carro_frete");
});

test("normalizarTipoSolicitado: retorno vazio em lixo/null", () => {
    assert.equal(T.normalizarTipoSolicitado(null), "");
    assert.equal(T.normalizarTipoSolicitado(""), "");
    assert.equal(T.normalizarTipoSolicitado("drone"), "");
    assert.equal(T.normalizarTipoSolicitado(42), "");
});

test("categoriaEfetivaPedido: tipo_entrega_solicitado explícito sobrescreve lista aceita", () => {
    const r = T.categoriaEfetivaPedido(
        { tipo_entrega_solicitado: "moto" },
        ["moto", "carro"],
    );
    assert.equal(r, "moto");
});

test("categoriaEfetivaPedido: loja com 1 tipo aceito → tipo implícito", () => {
    const r = T.categoriaEfetivaPedido({}, ["moto"]);
    assert.equal(r, "moto");
});

test("categoriaEfetivaPedido: loja multi-tipo sem escolha → null", () => {
    const r = T.categoriaEfetivaPedido({}, ["moto", "carro"]);
    assert.equal(r, null);
});

test("categoriaEfetivaPedido: loja sem config e pedido sem escolha → null", () => {
    assert.equal(T.categoriaEfetivaPedido({}, []), null);
    assert.equal(T.categoriaEfetivaPedido({}, null), null);
});

test("categoriaEfetivaPedido: variação 'Carro Popular' no solicitado é canonizada", () => {
    const r = T.categoriaEfetivaPedido(
        { tipo_entrega_solicitado: "Carro Popular" },
        ["moto", "carro"],
    );
    assert.equal(r, "carro");
});

test("compativel: escolha explícita de moto não admite entregador de carro", () => {
    assert.equal(T.compativel("moto", ["moto"]), true);
    assert.equal(T.compativel("carro", ["moto"]), false);
    assert.equal(T.compativel("moto", ["carro"]), false);
});
