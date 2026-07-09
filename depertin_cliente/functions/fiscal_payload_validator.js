/**
 * FiscalPayloadValidator — Validador central de payload fiscal
 *
 * Valida todo o payload de emissão NF-e antes de enviar para a Focus NFe.
 * Busca dados REAIS do banco (Firestore) — nunca confia apenas no que veio da UI.
 *
 * Regras:
 * - Emitente: CNPJ, razão social, IE (se aplicável), regime tributário,
 *   CNAE, endereço completo, CEP, município, UF, código IBGE
 * - Destinatário: nome, CPF/CNPJ válido, endereço, CEP, município, UF, código IBGE
 * - Produtos: nome, NCM, CFOP, unidade, quantidade, valor unitário,
 *   valor total, origem, impostos
 * - Pagamento: forma, valor, total
 *
 * Uso:
 *   const validator = require('./fiscal_payload_validator');
 *   const result = await validator.validate({
 *     storeId, integrationId, nfePayload, userId
 *   });
 */
const admin = require("firebase-admin");

/**
 * Valida CNPJ (14 dígitos).
 */
function cnpjValido(cnpj) {
  if (!cnpj || typeof cnpj !== "string") return false;
  const digitos = cnpj.replace(/\D/g, "");
  return digitos.length === 14;
}

/**
 * Valida CPF (11 dígitos).
 */
function cpfValido(cpf) {
  if (!cpf || typeof cpf !== "string") return false;
  const digitos = cpf.replace(/\D/g, "");
  return digitos.length === 11;
}

/**
 * Valida CPF ou CNPJ.
 */
function documentoValido(documento) {
  if (!documento || typeof documento !== "string") return false;
  const digitos = documento.replace(/\D/g, "");
  return digitos.length === 11 || digitos.length === 14;
}

/**
 * Valida CEP (8 dígitos).
 */
function cepValido(cep) {
  if (!cep || typeof cep !== "string") return false;
  const digitos = cep.replace(/\D/g, "");
  return digitos.length === 8;
}

/**
 * Lista de regimes tributários válidos para a Focus NFe.
 * @see https://doc.focusnfe.com.br/reference/regimetributario
 */
const REGIMES_TRIBUTARIOS_VALIDOS = [
  "simples_nacional",
  "simples",
  "lucro_presumido",
  "lucro_real",
  "mei", // Microempreendedor Individual (SIMEI)
];

/**
 * Lista de origens de mercadoria válidas.
 * 0 = Nacional, 1 = Estrangeira-Importação Direta, 2 = Estrangeira-Adquirida Mercado Interno,
 * 3 = Nacional com >40% Conteúdo Estrangeiro, 4 = Nacional com Processos Produtivos,
 * 5 = Nacional com <40% Conteúdo Estrangeiro, 6 = Estrangeira-Importação Direta sem Similar,
 * 7 = Estrangeira-Adquirida Mercado Interno sem Similar, 8 = Nacional com >70% Conteúdo Estrangeiro
 */
const ORIGENS_MERCADORIA_VALIDAS = ["0", "1", "2", "3", "4", "5", "6", "7", "8"];

/**
 * Formas de pagamento NF-e.
 */
const FORMAS_PAGAMENTO_VALIDAS = [
  "01", // Dinheiro
  "02", // Cheque
  "03", // Cartão de Crédito
  "04", // Cartão de Débito
  "05", // Crédito Loja
  "10", // Vale Alimentação
  "11", // Vale Refeição
  "12", // Vale Presente
  "13", // Vale Combustível
  "14", // Duplicata Mercantil
  "15", // Boleto Bancário
  "16", // Depósito Bancário
  "17", // Pagamento Instantâneo (PIX)
  "18", // Transferência Bancária
  "19", // Programa de Fidelidade
  "90", // Sem Pagamento
  "99", // Outros
];

/**
 * Unidades de medida aceitas pela SEFAZ.
 */
const UNIDADES_VALIDAS = [
  "un", "UN", "UNIDADE", "kg", "KG", "g", "G", "mg", "MG",
  "m", "M", "cm", "CM", "mm", "MM",
  "l", "L", "ml", "ML",
  "m2", "M2", "m3", "M3",
  "cx", "CX", "pc", "PC", "pct", "PCT",
  "tb", "TB", "lt", "LT",
  "par", "PAR", "par", "PAR",
  "bj", "BJ", "cj", "CJ",
  "dzn", "DZN", "gr", "GR",
];

/**
 * Validação principal do payload fiscal.
 *
 * Busca dados reais do Firestore para cross-check:
 * - store_fiscal_settings para dados do emitente
 * - Gestão Comercial para cliente e produtos
 *
 * @param {Object} params
 * @param {string} params.storeId - ID da loja
 * @param {string} params.integrationId - ID da integração fiscal
 * @param {Object} params.nfePayload - Payload recebido do frontend
 * @returns {Promise<{ isValid: boolean, errors: string[], missingFields: string[], blocking: boolean }>}
 */
async function validate({ storeId, integrationId, nfePayload }) {
  const errors = [];
  const missingFields = [];
  const db = admin.firestore();

  // ═══ Normalizar payload: suportar formato flat (Focus NFe v2) e nested (legado) ═══
  // Flat → nested para compatibilidade com validações abaixo
  if (nfePayload.cnpj_emitente && !nfePayload.emitente) {
    nfePayload.emitente = {
      cnpj: nfePayload.cnpj_emitente,
      razao_social: nfePayload.nome_emitente || "",
      nome_fantasia: nfePayload.nome_fantasia_emitente || "",
      ie: nfePayload.inscricao_estadual_emitente || "",
      crt: nfePayload.crt,
      endereco: {
        logradouro: nfePayload.logradouro_emitente || "",
        numero: nfePayload.numero_emitente || "",
        bairro: nfePayload.bairro_emitente || "",
        cidade: nfePayload.municipio_emitente || "",
        uf: nfePayload.uf_emitente || "",
        cep: nfePayload.cep_emitente || "",
        codigo_municipio: nfePayload.codigo_municipio_emitente || "",
      },
    };
    // Destinatário: precisa de endereco aninhado (validador espera destinatario.endereco.logradouro)
    nfePayload.destinatario = {
      cpf_cnpj: nfePayload.cpf_destinatario || nfePayload.cnpj_destinatario || "",
      nome: nfePayload.nome_destinatario || "",
      email: nfePayload.email_destinatario || "",
      logradouro: nfePayload.logradouro_destinatario || "",
      numero: nfePayload.numero_destinatario || "",
      bairro: nfePayload.bairro_destinatario || "",
      cidade: nfePayload.municipio_destinatario || "",
      uf: nfePayload.uf_destinatario || "",
      cep: nfePayload.cep_destinatario || "",
      codigo_cidade: nfePayload.codigo_municipio_destinatario || "",
      endereco: {
        logradouro: nfePayload.logradouro_destinatario || "",
        numero: nfePayload.numero_destinatario || "",
        bairro: nfePayload.bairro_destinatario || "",
        cidade: nfePayload.municipio_destinatario || "",
        uf: nfePayload.uf_destinatario || "",
        cep: nfePayload.cep_destinatario || "",
        codigo_municipio: nfePayload.codigo_municipio_destinatario || "",
      },
    };
    nfePayload.pagamento = {
      forma: nfePayload.forma_pagamento || "01",
      forma_pagamento: nfePayload.forma_pagamento || "01",
      valor_pago: nfePayload.valor_pagamento || nfePayload.valor_total || 0,
      valor: nfePayload.valor_pagamento || nfePayload.valor_total || 0,
    };
    // Normalizar itens (flat → nested com campos que o validador espera)
    const flatItems = nfePayload.items || nfePayload.itens || [];
    if (flatItems.length > 0) {
      nfePayload.produtos = flatItems.map((item) => {
        const csosn = item.icms_situacao_tributaria || "400";
        return {
          nome: item.descricao || item.nome || "",
          descricao: item.descricao || item.nome || "",
          ncm: item.codigo_ncm || item.ncm || "99999999",
          cfop: item.cfop || "5102",
          unidade: item.unidade_comercial || item.unidade || "UN",
          quantidade: parseFloat(item.quantidade_comercial || item.quantidade || 0),
          valor_unitario: parseFloat(item.valor_unitario_comercial || item.valorUnitario || 0),
          valor_total: parseFloat(item.valor_bruto || item.valorTotal || 0),
          origem: item.icms_origem || 0,
          imposto: { csosn: csosn },
        };
      });
    }
  }

  // ─── Buscar configurações fiscais da loja no Firestore ───
  let storeFiscalSettings = null;
  const settingsSnap = await db
    .collection("store_fiscal_settings")
    .where("store_id", "==", storeId)
    .where("integration_id", "==", integrationId)
    .limit(1)
    .get();

  if (!settingsSnap.empty) {
    storeFiscalSettings = settingsSnap.docs[0].data();
  }

  // ─── Extrair company_tax_data (fonte oficial dos dados fiscais) ───
  // O admin salva em store_fiscal_settings/{id}/company_tax_data/{campo}
  // O validador ANTES lia só campos top-level, o que causava o erro.
  // Agora lê PRIMEIRO de company_tax_data, depois fallback top-level.
  const taxData = (storeFiscalSettings && storeFiscalSettings.company_tax_data) || {};

  // ─── Buscar dados da loja (users) ───
  let storeData = null;
  const storeSnap = await db.collection("users").doc(storeId).get();
  if (storeSnap.exists) {
    storeData = storeSnap.data();
  }

  // Helper para extrair campo: company_tax_data > top-level > users > fallback
  function field(...sources) {
    for (const s of sources) {
      if (s && typeof s === "string" && s.trim().length > 0) return s.trim();
    }
    return "";
  }

  // ═══ DEBUG: imprime tudo que foi encontrado ═══
  if (storeFiscalSettings) {
    console.log("[FiscalPayloadValidator] store_fiscal_settings ENCONTRADO");
    console.log("[FiscalPayloadValidator] company_tax_data:", JSON.stringify(taxData));
    console.log("[FiscalPayloadValidator] taxData.cnpj:", taxData.cnpj || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.razao_social:", taxData.razao_social || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.nome_fantasia:", taxData.nome_fantasia || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.ie:", taxData.ie || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.regime_tributario:", taxData.regime_tributario || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.cnae:", taxData.cnae || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.cidade:", taxData.cidade || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.codigo_cidade:", taxData.codigo_cidade || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.logradouro:", taxData.logradouro || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.numero:", taxData.numero || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.bairro:", taxData.bairro || "❌ VAZIO");
    console.log("[FiscalPayloadValidator] taxData.cep:", taxData.cep || "❌ VAZIO");
  } else {
    console.log("[FiscalPayloadValidator] store_fiscal_settings NÃO ENCONTRADO");
  }

  // ══════════════════════════════════════════════════════════════
  // 1. VALIDAÇÃO DO EMITENTE (dados reais da loja)
  // ══════════════════════════════════════════════════════════════

  const emitente = nfePayload.emitente || nfePayload.emitente || {};

  // ── CNPJ: company_tax_data.cnpj > top-level > users > fallback ──
  const cnpjFirestore = field(
    taxData.cnpj,
    storeFiscalSettings?.cnpj,
    storeFiscalSettings?.emitente_cnpj,
    storeData?.cnpj,
    storeData?.documento
  );

  const cnpjPayload = emitente.cnpj || emitente.CNPJ || "";

  if (!cnpjFirestore || !cnpjValido(cnpjFirestore)) {
    errors.push("Loja está sem CNPJ configurado. Configure o CNPJ nas configurações fiscais.");
    missingFields.push("emitente.cnpj");
  } else if (cnpjFirestore !== cnpjPayload.replace(/\D/g, "")) {
    errors.push("CNPJ do emitente não corresponde ao cadastro da loja.");
    missingFields.push("emitente.cnpj_inconsistente");
  }

  // ── Razão social: company_tax_data.razao_social > top-level > users ──
  const razaoSocial = field(
    taxData.razao_social,
    storeFiscalSettings?.razao_social,
    storeFiscalSettings?.emitente_razao_social,
    storeData?.razao_social,
    storeData?.nome
  );
  if (!razaoSocial || razaoSocial.trim().length < 3) {
    errors.push("Loja está sem razão social configurada.");
    missingFields.push("emitente.razao_social");
  }

  // ── Nome fantasia: company_tax_data.nome_fantasia > top-level > users ──
  const nomeFantasia = field(
    taxData.nome_fantasia,
    storeFiscalSettings?.nome_fantasia,
    storeFiscalSettings?.emitente_nome_fantasia,
    storeData?.nome_fantasia,
    storeData?.nome_loja
  );
  if (!nomeFantasia || nomeFantasia.trim().length < 2) {
    errors.push("Loja está sem nome fantasia configurado.");
    missingFields.push("emitente.nome_fantasia");
  }

  // ── Inscrição Estadual: company_tax_data.ie > company_tax_data.inscricao_estadual > top-level ──
  const ie = field(
    taxData.ie,
    taxData.inscricao_estadual,
    storeFiscalSettings?.inscricao_estadual,
    storeFiscalSettings?.emitente_ie
  );

  // ── Regime tributário: company_tax_data.regime_tributario > top-level ──
  const regimeTributario = field(
    taxData.regime_tributario,
    storeFiscalSettings?.regime_tributario,
    storeFiscalSettings?.emitente_regime_tributario
  );
  // Normaliza para minúsculo sem espaços (ex.: "MEI" → "mei", "Simples Nacional" → "simples_nacional")
  const regimeNorm = (regimeTributario || "").toLowerCase().replace(/\s+/g, "_");

  // IE é obrigatória exceto para MEI (regime="mei")
  if (regimeNorm !== "mei" && (!ie || ie.trim().length < 2)) {
    errors.push(
      "Loja está sem Inscrição Estadual configurada. IE é obrigatória para este regime tributário."
    );
    missingFields.push("emitente.inscricao_estadual");
  }

  // Regime tributário — validar valor
  if (!regimeTributario) {
    errors.push("Loja está sem regime tributário configurado.");
    missingFields.push("emitente.regime_tributario");
  } else {
    // Normaliza: "Simples Nacional" → "simples_nacional", "MEI" → "mei"
    const regimesAceitos = REGIMES_TRIBUTARIOS_VALIDOS.map(r => r.toLowerCase());
    if (!regimesAceitos.includes(regimeNorm)) {
      errors.push(
        `Regime tributário "${regimeTributario}" inválido. Use: simples_nacional, lucro_presumido, lucro_real ou mei.`
      );
      missingFields.push("emitente.regime_tributario_invalido");
    }
  }

  // ── CNAE: company_tax_data.cnae > top-level > fallback ──
  const cnae = field(
    taxData.cnae,
    storeFiscalSettings?.cnae,
    storeFiscalSettings?.emitente_cnae
  );
  if (!cnae || cnae.trim().length < 5) {
    errors.push("Loja está sem CNAE configurado. Informe o CNAE fiscal.");
    missingFields.push("emitente.cnae");
  }

  // ── Endereço completo do emitente: company_tax_data.* > top-level > payload > fallback ──
  const endLogradouro = field(
    taxData.logradouro,
    storeFiscalSettings?.endereco_logradouro,
    storeFiscalSettings?.emitente_logradouro,
    emitente.endereco?.logradouro
  );
  const endNumero = field(
    taxData.numero,
    storeFiscalSettings?.endereco_numero,
    storeFiscalSettings?.emitente_numero,
    emitente.endereco?.numero
  );
  const endBairro = field(
    taxData.bairro,
    storeFiscalSettings?.endereco_bairro,
    storeFiscalSettings?.emitente_bairro,
    emitente.endereco?.bairro
  );
  const endCep = field(
    taxData.cep,
    storeFiscalSettings?.endereco_cep,
    storeFiscalSettings?.emitente_cep,
    emitente.endereco?.cep
  );
  const endCidade = field(
    taxData.cidade,
    storeFiscalSettings?.endereco_municipio,
    storeFiscalSettings?.emitente_municipio,
    storeFiscalSettings?.cidade,
    emitente.endereco?.municipio
  );
  const endUf = field(
    taxData.uf,
    storeFiscalSettings?.endereco_uf,
    storeFiscalSettings?.emitente_uf,
    storeFiscalSettings?.uf,
    emitente.endereco?.uf
  );
  const endIbge = field(
    taxData.codigo_cidade,
    taxData.codigo_ibge,
    storeFiscalSettings?.endereco_codigo_ibge,
    storeFiscalSettings?.emitente_codigo_ibge,
    storeFiscalSettings?.codigo_ibge,
    emitente.endereco?.codigo_ibge,
    emitente.endereco?.codigo_municipio
  );

  if (!endLogradouro) {
    errors.push("Loja está sem logradouro configurado no endereço fiscal.");
    missingFields.push("emitente.endereco.logradouro");
  }
  if (!endNumero) {
    errors.push("Loja está sem número no endereço fiscal.");
    missingFields.push("emitente.endereco.numero");
  }
  if (!endBairro) {
    errors.push("Loja está sem bairro configurado no endereço fiscal.");
    missingFields.push("emitente.endereco.bairro");
  }
  if (!endCep || !cepValido(endCep)) {
    errors.push("Loja está sem CEP válido no endereço fiscal.");
    missingFields.push("emitente.endereco.cep");
  }
  if (!endCidade) {
    errors.push("Loja está sem município configurado no endereço fiscal.");
    missingFields.push("emitente.endereco.municipio");
  }
  if (!endUf || endUf.length !== 2) {
    errors.push("Loja está sem UF configurada no endereço fiscal.");
    missingFields.push("emitente.endereco.uf");
  }
  if (!endIbge) {
    errors.push("Loja está sem código IBGE do município configurado.");
    missingFields.push("emitente.endereco.codigo_ibge");
  }

  // ══════════════════════════════════════════════════════════════
  // 2. VALIDAÇÃO DO DESTINATÁRIO (cliente real do Gestão Comercial)
  // ══════════════════════════════════════════════════════════════

  const destinatario = nfePayload.destinatario || nfePayload.destinatario || {};

  // Nome / Razão Social
  const destNome = destinatario.nome || destinatario.razao_social || destinatario.nome_cliente || "";
  if (!destNome || destNome.trim().length < 2) {
    errors.push("Cliente está sem nome ou razão social informado.");
    missingFields.push("destinatario.nome");
  }

  // CPF ou CNPJ — aceita cpf_cnpj, cnpj_cpf, CPF, CNPJ, documento
  const destDocumento =
    destinatario.cpf_cnpj || destinatario.cnpj_cpf ||
    destinatario.CPF || destinatario.CNPJ ||
    destinatario.documento || "";
  if (!destDocumento || !documentoValido(destDocumento)) {
    errors.push("Cliente está com CPF/CNPJ inválido. Informe um CPF (11 dígitos) ou CNPJ (14 dígitos).");
    missingFields.push("destinatario.cpf_cnpj");
  }

  // Endereço do destinatário
  const destLogradouro = destinatario.endereco?.logradouro || "";
  const destNumero = destinatario.endereco?.numero || "";
  const destBairro = destinatario.endereco?.bairro || "";
  const destCep = destinatario.endereco?.cep || "";
  const destCidade = destinatario.endereco?.municipio || destinatario.endereco?.cidade || "";
  const destUf = destinatario.endereco?.uf || "";
  const destIbge = destinatario.endereco?.codigo_ibge || destinatario.endereco?.codigo_municipio || "";

  if (!destLogradouro) {
    errors.push("Cliente está sem logradouro no endereço.");
    missingFields.push("destinatario.endereco.logradouro");
  }
  if (!destNumero) {
    errors.push("Cliente está sem número no endereço.");
    missingFields.push("destinatario.endereco.numero");
  }
  if (!destBairro) {
    errors.push("Cliente está sem bairro no endereço.");
    missingFields.push("destinatario.endereco.bairro");
  }
  if (!destCep || !cepValido(destCep)) {
    errors.push("Cliente está sem CEP válido no endereço.");
    missingFields.push("destinatario.endereco.cep");
  }
  if (!destCidade) {
    errors.push("Cliente está sem município no endereço.");
    missingFields.push("destinatario.endereco.municipio");
  }
  if (!destUf || destUf.length !== 2) {
    errors.push("Cliente está sem UF no endereço.");
    missingFields.push("destinatario.endereco.uf");
  }
  if (!destIbge) {
    errors.push("Cliente está sem código IBGE do município.");
    missingFields.push("destinatario.endereco.codigo_ibge");
  }

  // ══════════════════════════════════════════════════════════════
  // 3. VALIDAÇÃO DOS PRODUTOS
  // ══════════════════════════════════════════════════════════════

  const produtos = nfePayload.produtos || nfePayload.itens || nfePayload.items || [];

  if (!produtos || !Array.isArray(produtos) || produtos.length === 0) {
    errors.push("Nenhum produto informado na nota fiscal.");
    missingFields.push("produtos");
  } else {
    let totalProdutos = 0;

    for (let i = 0; i < produtos.length; i++) {
      const p = produtos[i];
      const idx = i + 1;
      const nomeProd = p.nome || p.descricao || p.produto_nome || `Produto #${idx}`;

      if (!p.nome && !p.descricao) {
        errors.push(`Produto #${idx} está sem nome.`);
        missingFields.push(`produtos[${i}].nome`);
      }

      if (!p.ncm || p.ncm.trim().length < 6) {
        errors.push(`"${nomeProd}" está sem NCM. Informe o NCM de 8 dígitos.`);
        missingFields.push(`produtos[${i}].ncm`);
      }

      if (!p.cfop || p.cfop.trim().length < 4) {
        errors.push(`"${nomeProd}" está sem CFOP. Informe o CFOP de 4 dígitos.`);
        missingFields.push(`produtos[${i}].cfop`);
      }

      if (!p.unidade || p.unidade.trim().length === 0) {
        errors.push(`"${nomeProd}" está sem unidade de medida.`);
        missingFields.push(`produtos[${i}].unidade`);
      }

      const quantidade = parseFloat(p.quantidade || p.qtd || 0);
      if (!quantidade || quantidade <= 0) {
        errors.push(`"${nomeProd}" está com quantidade inválida.`);
        missingFields.push(`produtos[${i}].quantidade`);
      }

      const valorUnitario = parseFloat(p.valor_unitario || p.valorUnitario || p.preco || 0);
      if (!valorUnitario || valorUnitario <= 0) {
        errors.push(`"${nomeProd}" está com valor unitário inválido.`);
        missingFields.push(`produtos[${i}].valor_unitario`);
      }

      const valorTotal = parseFloat(p.valor_total || p.valorTotal || p.total || 0);
      if (!valorTotal || valorTotal <= 0) {
        errors.push(`"${nomeProd}" está com valor total inválido.`);
        missingFields.push(`produtos[${i}].valor_total`);
      }

      // Origem da mercadoria
      const origem = String(p.origem || p.origem_mercadoria || "");
      if (origem && !ORIGENS_MERCADORIA_VALIDAS.includes(origem)) {
        errors.push(
          `"${nomeProd}" está com origem da mercadoria inválida "${origem}". Use 0 (Nacional) a 8.`
        );
        missingFields.push(`produtos[${i}].origem`);
      }

      // Impostos obrigatórios conforme regime tributário
      const imposto = p.imposto || p.impostos || {};
      if (regimeNorm === "simples_nacional" || regimeNorm === "simples" || regimeNorm === "mei") {
        // Simples Nacional: CSOSN obrigatório
        if (!imposto.csosn && !imposto.CSOSN) {
          errors.push(`"${nomeProd}" está sem CSOSN (Simples Nacional).`);
          missingFields.push(`produtos[${i}].imposto.csosn`);
        }
      } else {
        // Lucro Presumido/Real: CST ICMS obrigatório
        if (!imposto.cst_icms && !imposto.CST && !imposto.cst) {
          errors.push(`"${nomeProd}" está sem CST de ICMS.`);
          missingFields.push(`produtos[${i}].imposto.cst_icms`);
        }
      }

      // IPI (quando aplicável)
      if (p.tributavel_ipi && !imposto.ipi) {
        errors.push(`"${nomeProd}" é tributável IPI mas não possui dados de IPI.`);
        missingFields.push(`produtos[${i}].imposto.ipi`);
      }

      totalProdutos += valorTotal;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 4. VALIDAÇÃO DO PAGAMENTO
  // ══════════════════════════════════════════════════════════════

  const pagamento = nfePayload.pagamento || nfePayload.pagamento || {};

  const formaPagamento = pagamento.forma || pagamento.forma_pagamento || "";
  if (!formaPagamento) {
    errors.push("Forma de pagamento não informada.");
    missingFields.push("pagamento.forma");
  } else {
    // Aceita código numérico (01-99) ou texto (pix, credito, etc.)
    const formaNum = _normalizarFormaPagamento(formaPagamento);
    if (!FORMAS_PAGAMENTO_VALIDAS.includes(formaNum)) {
      errors.push(
        `Forma de pagamento "${formaPagamento}" inválida. Use o código Tabela de Pagamento NF-e (01 a 99).`
      );
      missingFields.push("pagamento.forma_invalida");
    }
  }

  const valorPago = parseFloat(pagamento.valor_pago || pagamento.valor || 0);
  if (!valorPago || valorPago <= 0) {
    errors.push("Valor do pagamento não informado ou inválido.");
    missingFields.push("pagamento.valor_pago");
  }

  const totalNota = parseFloat(
    nfePayload.total ||
    nfePayload.valor_total ||
    nfePayload.totais?.valor_total ||
    nfePayload.total_nota || 0
  );
  if (!totalNota || totalNota <= 0) {
    errors.push("Total da nota não informado ou inválido.");
    missingFields.push("total_nota");
  }

  // ══════════════════════════════════════════════════════════════
  // 5. VALIDAÇÕES CRUZADAS
  // ══════════════════════════════════════════════════════════════

  // Ambiente fiscal — busca primeiro em nfe_settings (submap), depois top-level
  const nfeSettings = storeFiscalSettings?.nfe_settings || {};
  const ambiente = nfeSettings.environment ||
    storeFiscalSettings?.environment ||
    storeFiscalSettings?.ambiente ||
    "";

  if (!ambiente) {
    errors.push("Ambiente fiscal não configurado (homologação ou produção).");
    missingFields.push("environment");
  }

  // Bloqueio: nota em produção com ambiente sandbox
  const ambientePayload = nfePayload.ambiente || "";
  if (
    ambientePayload === "producao" &&
    (ambiente === "sandbox" || ambiente === "homologacao")
  ) {
    errors.push(
      "Não é possível emitir NF-e em produção com ambiente configurado como homologação/sandbox."
    );
    missingFields.push("ambiente_incompativel");
  }

  return {
    isValid: errors.length === 0,
    errors,
    missingFields,
    blocking: errors.length > 0,
  };
}

/**
 * Normaliza forma de pagamento: aceita texto (pix, credito, dinheiro) ou
 * código numérico NF-e (01-99). Retorna o código numérico normalizado.
 */
function _normalizarFormaPagamento(forma) {
  if (!forma || typeof forma !== "string") return "";
  const f = forma.trim().toLowerCase();

  // Se já é código numérico, retorna como está
  if (/^\d{2}$/.test(f)) return f;

  // Mapeamento texto → código (compatível com focus_nfe_provider.dart)
  const mapa = {
    "dinheiro": "01", "cheque": "02",
    "credito": "03", "crédito": "03", "cartao credito": "03", "cartão crédito": "03",
    "debito": "04", "débito": "04", "cartao debito": "04", "cartão débito": "04",
    "credito_loja": "05", "crédito loja": "05",
    "vale_alimentacao": "10", "vale alimentação": "10",
    "vale_refeicao": "11", "vale refeição": "11",
    "boleto": "15", "boleto bancário": "15",
    "pix": "17",
    "transferencia": "18", "transferência": "18", "transferência bancária": "18",
    "sem_pagamento": "90",
    "outros": "99", "outro": "99",
    "a vista": "01", "à vista": "01",
  };
  // Tenta match exato ou parcial
  if (mapa[f]) return mapa[f];
  for (const [chave, codigo] of Object.entries(mapa)) {
    if (f.includes(chave)) return codigo;
  }
  return ""; // não reconhecido
}

module.exports = {
  validate,
  cnpjValido,
  cpfValido,
  documentoValido,
  REGIMES_TRIBUTARIOS_VALIDOS,
  FORMAS_PAGAMENTO_VALIDAS,
};
