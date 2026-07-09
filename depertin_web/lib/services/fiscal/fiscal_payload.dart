/// Payload fiscal padronizado do DiPertin.
///
/// Representa os dados necessários para emissão de um documento fiscal
/// (NF-e, NFC-e, NFS-e) transformados a partir dos módulos:
/// - Gestão de Assinaturas (assinaturas_clientes)
/// - Gestão Comercial (vendas_credito, clientes_comercial, parcelas)
///
/// Cada [FiscalProvider] converte este payload para o formato JSON
/// exigido pela API fiscal externa (Focus NFe, Nuvem Fiscal, etc.).
library;

/// Tipo de documento fiscal suportado.
enum TipoDocumentoFiscal {
  nfe('NF-e', 'nfe'),
  nfce('NFC-e', 'nfce'),
  nfse('NFS-e', 'nfse');

  const TipoDocumentoFiscal(this.rotulo, this.codigo);
  final String rotulo;
  final String codigo;

  static TipoDocumentoFiscal fromCodigo(String c) =>
      TipoDocumentoFiscal.values.firstWhere(
        (t) => t.codigo == c,
        orElse: () => TipoDocumentoFiscal.nfe,
      );
}

/// Dados do emitente (loja/empresa que emite a nota).
class FiscalEmitente {
  const FiscalEmitente({
    required this.razaoSocial,
    required this.nomeFantasia,
    required this.cnpj,
    required this.ie,
    this.im,
    this.crt,
    this.cnae,
    this.regimeTributario,
    required this.logradouro,
    required this.numero,
    this.complemento,
    required this.bairro,
    required this.cidade,
    required this.uf,
    required this.cep,
    this.telefone,
    this.emailFiscal,
    this.codigoCidade,
  });

  final String razaoSocial;
  final String nomeFantasia;
  final String cnpj;
  final String ie;
  final String? im;
  final String? crt;
  final String? cnae;
  final String? regimeTributario;
  final String logradouro;
  final String numero;
  final String? complemento;
  final String bairro;
  final String cidade;
  final String uf;
  final String cep;
  final String? telefone;
  final String? emailFiscal;
  final String? codigoCidade;

  Map<String, dynamic> toJson() => {
        'razao_social': razaoSocial,
        'nome_fantasia': nomeFantasia,
        'cnpj': cnpj,
        'ie': ie,
        if (im != null) 'im': im,
        if (crt != null) 'crt': crt,
        if (cnae != null) 'cnae': cnae,
        if (regimeTributario != null) 'regime_tributario': regimeTributario,
        'endereco': {
          'logradouro': logradouro,
          'numero': numero,
          if (complemento != null) 'complemento': complemento,
          'bairro': bairro,
          'cidade': cidade,
          'uf': uf,
          'cep': cep,
          if (telefone != null) 'telefone': telefone,
        },
        if (emailFiscal != null) 'email_fiscal': emailFiscal,
        if (codigoCidade != null) 'codigo_cidade': codigoCidade,
      };
}

/// Dados do destinatário (cliente que recebe a nota).
class FiscalDestinatario {
  const FiscalDestinatario({
    required this.nome,
    this.cpfCnpj,
    this.ie,
    this.email,
    this.logradouro,
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.uf,
    this.cep,
    this.telefone,
    this.indicadorContribuinte,
    this.codigoCidade,
  });

  final String nome;
  final String? cpfCnpj;
  final String? ie;
  final String? email;
  final String? logradouro;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? cidade;
  final String? uf;
  final String? cep;
  final String? telefone;
  /// 1=Contribuinte, 2=Isento, 9=Não contribuinte
  final String? indicadorContribuinte;
  /// Código IBGE do município do destinatário (7 dígitos).
  final String? codigoCidade;

  bool get ehConsumidorFinal => cpfCnpj == null || cpfCnpj!.isEmpty;

  Map<String, dynamic> toJson() => {
        'nome': nome,
        if (cpfCnpj != null && cpfCnpj!.isNotEmpty) 'cpf_cnpj': cpfCnpj,
        if (ie != null && ie!.isNotEmpty) 'ie': ie,
        if (email != null && email!.isNotEmpty) 'email': email,
        if (logradouro != null) 'endereco': {
          'logradouro': logradouro,
          if (numero != null) 'numero': numero,
          if (complemento != null) 'complemento': complemento,
          if (bairro != null) 'bairro': bairro,
          if (cidade != null) 'cidade': cidade,
          if (uf != null) 'uf': uf,
          if (cep != null) 'cep': cep,
          if (telefone != null) 'telefone': telefone,
          if (codigoCidade != null && codigoCidade!.isNotEmpty)
            'codigo_municipio': codigoCidade,
        },
        if (indicadorContribuinte != null)
          'indicador_contribuinte': indicadorContribuinte,
      };
}

/// Item da nota fiscal (produto/serviço).
class FiscalItem {
  const FiscalItem({
    required this.descricao,
    required this.quantidade,
    required this.valorUnitario,
    required this.valorTotal,
    this.ncm,
    this.cfop,
    this.cest,
    this.unidade = 'UN',
    this.codigoProduto,
    this.codigoServico,
    this.aliquotaIcms,
    this.cstIcms,
    this.aliquotaPis,
    this.aliquotaCofins,
    this.aliquotaIss,
    this.desconto,
    this.outros,
  });

  final String descricao;
  final double quantidade;
  final double valorUnitario;
  final double valorTotal;
  final String? ncm;
  final String? cfop;
  final String? cest;
  final String unidade;
  final String? codigoProduto;
  final String? codigoServico;
  final double? aliquotaIcms;
  final String? cstIcms;
  final double? aliquotaPis;
  final double? aliquotaCofins;
  final double? aliquotaIss;
  final double? desconto;
  final double? outros;

  Map<String, dynamic> toJson() => {
        'descricao': descricao,
        'quantidade': quantidade,
        'valor_unitario': valorUnitario,
        'valor_total': valorTotal,
        if (ncm != null) 'ncm': ncm,
        if (cfop != null) 'cfop': cfop,
        if (cest != null) 'cest': cest,
        'unidade': unidade,
        if (codigoProduto != null) 'codigo_produto': codigoProduto,
        if (codigoServico != null) 'codigo_servico': codigoServico,
        if (aliquotaIcms != null) 'aliquota_icms': aliquotaIcms,
        if (cstIcms != null) 'cst_icms': cstIcms,
        if (aliquotaPis != null) 'aliquota_pis': aliquotaPis,
        if (aliquotaCofins != null) 'aliquota_cofins': aliquotaCofins,
        if (aliquotaIss != null) 'aliquota_iss': aliquotaIss,
        if (desconto != null) 'desconto': desconto,
        if (outros != null) 'outros': outros,
      };
}

/// Totais da nota fiscal.
class FiscalTotais {
  const FiscalTotais({
    required this.baseCalculoIcms,
    required this.valorIcms,
    required this.valorProdutos,
    required this.valorFrete,
    required this.valorDesconto,
    required this.valorTotal,
    this.baseCalculoIss,
    this.valorIss,
    this.valorPis,
    this.valorCofins,
  });

  final double baseCalculoIcms;
  final double valorIcms;
  final double valorProdutos;
  final double valorFrete;
  final double valorDesconto;
  final double valorTotal;
  final double? baseCalculoIss;
  final double? valorIss;
  final double? valorPis;
  final double? valorCofins;

  Map<String, dynamic> toJson() => {
        'base_calculo_icms': baseCalculoIcms,
        'valor_icms': valorIcms,
        'valor_produtos': valorProdutos,
        'valor_frete': valorFrete,
        'valor_desconto': valorDesconto,
        'valor_total': valorTotal,
        if (baseCalculoIss != null) 'base_calculo_iss': baseCalculoIss,
        if (valorIss != null) 'valor_iss': valorIss,
        if (valorPis != null) 'valor_pis': valorPis,
        if (valorCofins != null) 'valor_cofins': valorCofins,
      };
}

/// Informações de pagamento.
class FiscalPagamento {
  const FiscalPagamento({
    required this.formaPagamento,
    required this.valorPago,
    this.troco,
    this.cnpjAdquirente,
    this.bandeiraCartao,
    this.numeroAutorizacao,
  });

  final String formaPagamento; // dinheiro, credito, debito, pix, boleto, crediario
  final double valorPago;
  final double? troco;
  final String? cnpjAdquirente;
  final String? bandeiraCartao;
  final String? numeroAutorizacao;

  Map<String, dynamic> toJson() => {
        'forma_pagamento': formaPagamento,
        'valor_pago': valorPago,
        if (troco != null) 'troco': troco,
        if (cnpjAdquirente != null) 'cnpj_adquirente': cnpjAdquirente,
        if (bandeiraCartao != null) 'bandeira_cartao': bandeiraCartao,
        if (numeroAutorizacao != null) 'numero_autorizacao': numeroAutorizacao,
      };
}

/// Payload fiscal padrão do DiPertin.
///
/// Todos os providers recebem este payload e o convertem
/// para o formato JSON específico da API fiscal externa.
class FiscalPayload {
  const FiscalPayload({
    required this.tipoDocumento,
    required this.emitente,
    required this.destinatario,
    required this.itens,
    required this.totais,
    required this.pagamento,
    this.serie,
    this.numero,
    this.naturezaOperacao,
    this.cfop,
    this.finalidade = '1',
    this.tipoOperacao = '1',
    this.indicadorPresenca = '1',
    this.informacoesAdicionais,
    this.pedidoId,
    this.vendaId,
    this.clienteId,
    this.configuracoesExtras = const {},
  });

  final TipoDocumentoFiscal tipoDocumento;
  final FiscalEmitente emitente;
  final FiscalDestinatario destinatario;
  final List<FiscalItem> itens;
  final FiscalTotais totais;
  final FiscalPagamento pagamento;
  final String? serie;
  final String? numero;
  final String? naturezaOperacao;
  final String? cfop;
  final String finalidade;
  final String tipoOperacao;
  final String indicadorPresenca;
  final String? informacoesAdicionais;
  final String? pedidoId;
  final String? vendaId;
  final String? clienteId;
  final Map<String, dynamic> configuracoesExtras;

  /// Converte o payload padronizado para um Map (JSON).
  /// Cada provider usará este map como base para construir o formato
  /// específico exigido pela API externa.
  Map<String, dynamic> toStandardJson() => {
        'tipo_documento': tipoDocumento.codigo,
        'emitente': emitente.toJson(),
        'destinatario': destinatario.toJson(),
        'itens': itens.map((i) => i.toJson()).toList(),
        'totais': totais.toJson(),
        'pagamento': pagamento.toJson(),
        if (serie != null) 'serie': serie,
        if (numero != null) 'numero': numero,
        if (naturezaOperacao != null) 'natureza_operacao': naturezaOperacao,
        if (cfop != null) 'cfop': cfop,
        'finalidade': finalidade,
        'tipo_operacao': tipoOperacao,
        'indicador_presenca': indicadorPresenca,
        if (informacoesAdicionais != null)
          'informacoes_adicionais': informacoesAdicionais,
        if (pedidoId != null) 'pedido_id': pedidoId,
        if (vendaId != null) 'venda_id': vendaId,
        if (clienteId != null) 'cliente_id': clienteId,
        if (configuracoesExtras.isNotEmpty) 'extras': configuracoesExtras,
      };
}
