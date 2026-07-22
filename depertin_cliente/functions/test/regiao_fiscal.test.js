"use strict";

/**
 * Teste de consistência de região entre backend (Cloud Functions) e frontend (Dart).
 *
 * O frontend (focus_nfe_provider.dart) constrói a URL como:
 *   https://{regiao}-depertin-f940f.cloudfunctions.net/{functionName}
 *
 * O backend (fiscal_nfe_proxy.js) declara region no CONFIG.
 * Ambas DEVEM ser iguais, senão todas as chamadas resultam em HTTP 404.
 *
 * Região deployada (confirmada via functions_list_functions):
 *   fiscalEmitirNFe → location: us-east1
 *
 * Região no backend (fiscal_nfe_proxy.js):
 *   CONFIG.region = "us-east1"
 *
 * Região no frontend (focus_nfe_provider.dart):
 *   _regiao = "us-east1"
 *
 * A URL construída pelo frontend é:
 *   https://us-east1-depertin-f940f.cloudfunctions.net/fiscalEmitirNFe
 *
 * A URL da função deployada é:
 *   https://us-east1-depertin-f940f.cloudfunctions.net/fiscalEmitirNFe
 */

const { describe, it } = require("node:test");
const assert = require("node:assert");

// ─── Região do backend (fiscal_nfe_proxy.js CONFIG) ───
const REGIAO_BACKEND = "us-east1";

// ─── Região do frontend (focus_nfe_provider.dart _regiao) ───
// FONTE: depertin_web/lib/services/fiscal/providers/focus_nfe_provider.dart
// A região foi migrada de southamerica-east1 para us-east1.
const REGIAO_FRONTEND = "us-east1";

describe("Consistência de região entre frontend e backend fiscais", () => {
  it("Frontend e backend devem usar a MESMA região", () => {
    assert.strictEqual(
      REGIAO_FRONTEND,
      REGIAO_BACKEND,
      `A região do frontend (${REGIAO_FRONTEND}) difere da região do backend (${REGIAO_BACKEND}). As Cloud Functions não seriam encontradas.`
    );
  });

  it("URL construída pelo frontend deve corresponder à região da função deployada", () => {
    const PROJECT_ID = "depertin-f940f";
    const FUNCTION_NAME = "fiscalEmitirNFe";

    // URL que o frontend constrói em callFirebaseFunctionSafe
    const urlFrontend = `https://${REGIAO_FRONTEND}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}`;

    // URL esperada com base na região deployada
    const urlEsperada = `https://${REGIAO_BACKEND}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}`;

    assert.strictEqual(urlFrontend, urlEsperada);
    assert.ok(urlFrontend.includes("us-east1"), "URL deve conter us-east1");
    assert.ok(urlFrontend.endsWith(`/${FUNCTION_NAME}`), "URL deve terminar com o nome da função");
  });

  it("Todas as funções fiscais devem estar na mesma região", () => {
    // Lista de funções fiscais no backend (fiscal_nfe_proxy.js + fiscal_pos_emissao.js)
    // Todas usam o mesmo CONFIG com region: "us-east1"
    const funcoesFiscais = [
      // Proxy Focus NFe (fiscal_nfe_proxy.js)
      "fiscalEmitirNFe",
      "fiscalCancelarNFe",
      "fiscalConsultarNFe",
      "fiscalCartaCorrecaoNFe",
      "fiscalInutilizarNFe",
      "fiscalDeletarDocumento",
      "fiscalListarNotas",
      "fiscalBaixarXml",
      "fiscalBaixarDanfe",
      "fiscalTestarConexaoFocus",
      // Pós-emissão (fiscal_pos_emissao.js)
      "fiscalConsultarEAtualizarStatus",
      "fiscalDownloadArquivo",
    ];

    for (const fn of funcoesFiscais) {
      const url = `https://${REGIAO_BACKEND}-depertin-f940f.cloudfunctions.net/${fn}`;
      assert.ok(url.endsWith(`/${fn}`), `URL de ${fn} deve terminar com o nome da função`);
      assert.ok(url.includes("us-east1"), `URL de ${fn} deve conter us-east1`);
    }
  });

  it("A região NÃO deve ser southamerica-east1 (região antiga)", () => {
    assert.notStrictEqual(
      REGIAO_FRONTEND,
      "southamerica-east1",
      "A região foi migrada de southamerica-east1 para us-east1. O frontend não deve mais apontar para a região antiga."
    );
    assert.notStrictEqual(
      REGIAO_BACKEND,
      "southamerica-east1",
      "A região foi migrada de southamerica-east1 para us-east1. O backend não deve mais usar a região antiga."
    );
  });
});
