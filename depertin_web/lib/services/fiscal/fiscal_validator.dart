import 'fiscal_payload.dart';

/// Resultado da validação de um campo fiscal.
class ValidationResult {
  final bool valido;
  final List<ValidationError> erros;
  final List<ValidationWarning> avisos;

  const ValidationResult({
    this.valido = true,
    this.erros = const [],
    this.avisos = const [],
  });

  static const ok = ValidationResult();
}

/// Erro de validação que bloqueia a emissão.
class ValidationError {
  final String campo;
  final String mensagem;
  final String? codigo;

  const ValidationError(this.campo, this.mensagem, {this.codigo});
}

/// Alerta de validação que não bloqueia a emissão.
class ValidationWarning {
  final String campo;
  final String mensagem;

  const ValidationWarning(this.campo, this.mensagem);
}

/// Validador fiscal completo para NF-e/NFC-e.
///
/// Valida antes da emissão:
/// - Dados do emitente (CNPJ, IE, endereço, regime tributário)
/// - Dados do destinatário (CPF/CNPJ, IE, endereço)
/// - Produtos (NCM, CFOP, CST/CSOSN, CEST, valores)
/// - Impostos (ICMS, IPI, PIS, COFINS)
/// - Totais (base de cálculo, valores)
/// - Documento (série, número, finalidade, tipo de operação)
class FiscalValidator {
  const FiscalValidator._();

  // ─── Constantes ───

  static const _cepRegex = r'^\d{8}$';
  static const _emailRegex = r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$';
  static const _ncmRegex = r'^\d{8}$';
  static const _cestRegex = r'^\d{7}$';
  static const _cfopRegex = r'^\d{4}$';
  static const _ieRegex = r'^\d{2,14}$';

  /// Códigos de finalidade.
  static const finalidadesValidas = ['1', '2', '3', '4'];

  /// CFOPs por tipo de operação.
  static const cfopsEntrada = <String>[
    '1101', '1102', '1111', '1113', '1116', '1117', '1118',
    '1120', '1121', '1122', '1124', '1125', '1126', '1128',
    '1150', '1151', '1152', '1153', '1154', '1155', '1156',
    '1157', '1159', '1160', '1161', '1162', '1163', '1201',
    '1202', '1203', '1204', '1205', '1206', '1207', '1208',
    '1209', '1210', '1251', '1252', '1253', '1254', '1255',
    '1256', '1257', '1301', '1302', '1303', '1304', '1305',
    '1306', '1401', '1403', '1406', '1407', '1408', '1409',
    '1410', '1411', '1414', '1451', '1452', '1501', '1502',
    '1503', '1504', '1505', '1506', '1507', '1551', '1552',
    '1553', '1554', '1555', '1556', '1557', '1601', '1602',
    '1603', '1604', '1651', '1652', '1653', '1701', '1702',
    '1703', '1704', '1705', '1706', '1708', '1709', '1710',
    '1711', '1712', '1713', '1714', '1715', '1716', '1717',
    '1718', '1719', '1720', '1721', '1722', '1723', '1724',
    '1725', '1726', '1751', '1752', '1753', '1754', '1755',
    '1756', '1757', '1758', '1759', '1760', '1761', '1901',
    '1902', '1903', '1904', '1905', '1906', '1907', '1908',
    '1909', '1910', '1911', '1912', '1913', '1914', '1915',
    '1916', '1917', '1918', '1919', '1920', '1921', '1922',
    '1923', '1924', '1925', '1926', '1931', '1932', '1933',
    '1934', '1949', '1104', '1404',
  ];

  static const cfopsSaida = <String>[
    '5101', '5102', '5103', '5104', '5105', '5106', '5107',
    '5108', '5109', '5110', '5111', '5112', '5113', '5114',
    '5115', '5116', '5117', '5118', '5119', '5120', '5122',
    '5123', '5124', '5151', '5152', '5153', '5155', '5156',
    '5157', '5158', '5159', '5160', '5161', '5162', '5201',
    '5202', '5203', '5204', '5205', '5206', '5207', '5208',
    '5209', '5210', '5251', '5252', '5253', '5254', '5255',
    '5256', '5257', '5258', '5301', '5302', '5303', '5304',
    '5305', '5306', '5307', '5351', '5352', '5353', '5354',
    '5355', '5356', '5357', '5359', '5360', '5401', '5402',
    '5403', '5405', '5406', '5407', '5408', '5409', '5410',
    '5411', '5412', '5413', '5414', '5415', '5451', '5452',
    '5453', '5454', '5455', '5456', '5457', '5501', '5502',
    '5503', '5551', '5552', '5553', '5554', '5555', '5556',
    '5557', '5601', '5602', '5603', '5651', '5652', '5653',
    '5654', '5655', '5656', '5661', '5662', '5663', '5664',
    '5665', '5666', '5667', '5701', '5901', '5902', '5903',
    '5904', '5905', '5906', '5907', '5908', '5909', '5910',
    '5911', '5912', '5913', '5921', '5922', '5923', '5924',
    '5925', '5926', '5927', '5928', '5929', '5931', '5932',
    '5933', '5934', '5935', '5936', '5937', '5938', '5939',
    '5940', '5941', '5942', '5943', '5944', '5945', '5946',
    '5947', '5948', '5949', '5950', '5951', '5952', '5953',
    '5961', '5962', '5963', '5964', '5965',
  ];

  static const cstIcmsValidos = [
    '00', '10', '20', '30', '40', '41', '50', '51',
    '60', '70', '90', '101', '102', '103', '201', '202',
    '203', '300', '400', '500', '900',
  ];

  static const csosnValidos = [
    '101', '102', '103', '201', '202', '203', '300', '400',
    '500', '900',
  ];

  static const cstPisValidos = [
    '01', '02', '03', '04', '05', '06', '07', '08', '09',
    '49', '50', '51', '52', '53', '54', '55', '56', '60',
    '61', '62', '63', '64', '65', '66', '67', '70', '71',
    '72', '73', '74', '75', '98', '99',
  ];

  static const cstCofinsValidos = [
    '01', '02', '03', '04', '05', '06', '07', '08', '09',
    '49', '50', '51', '52', '53', '54', '55', '56', '60',
    '61', '62', '63', '64', '65', '66', '67', '70', '71',
    '72', '73', '74', '75', '98', '99',
  ];

  static const ufsValidas = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO',
    'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI',
    'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  ];

  // ─── Validação principal ───

  static ValidationResult validarParaEmissao(FiscalPayload payload) {
    final erros = <ValidationError>[];
    final avisos = <ValidationWarning>[];

    erros.addAll(_validarEmitente(payload.emitente).erros);
    avisos.addAll(_validarEmitente(payload.emitente).avisos);

    erros.addAll(_validarDestinatario(payload.destinatario).erros);
    avisos.addAll(_validarDestinatario(payload.destinatario).avisos);

    for (var i = 0; i < payload.itens.length; i++) {
      final itemResult = _validarItem(payload.itens[i], i);
      erros.addAll(itemResult.erros);
      avisos.addAll(itemResult.avisos);
    }

    erros.addAll(_validarTotais(payload.totais, payload.itens).erros);
    avisos.addAll(_validarTotais(payload.totais, payload.itens).avisos);

    erros.addAll(_validarPagamento(payload.pagamento).erros);

    erros.addAll(_validarDocumento(payload).erros);

    return ValidationResult(
      valido: erros.isEmpty,
      erros: erros,
      avisos: avisos,
    );
  }

  // ─── Validação do emitente ───

  static ValidationResult _validarEmitente(FiscalEmitente emit) {
    final erros = <ValidationError>[];
    final avisos = <ValidationWarning>[];

    if (emit.razaoSocial.trim().isEmpty) {
      erros.add(const ValidationError('emitente.razao_social',
          'Razão social do emitente é obrigatória'));
    }
    if (emit.razaoSocial.length > 60) {
      avisos.add(const ValidationWarning('emitente.razao_social',
          'Razão social muito longa (>60 caracteres)'));
    }

    _validarCnpj(emit.cnpj, 'emitente.cnpj', erros);

    if (!emit.ieIsento && emit.ie.trim().isEmpty) {
      erros.add(const ValidationError(
          'emitente.ie', 'Inscrição estadual do emitente é obrigatória'));
    } else if (!emit.ieIsento &&
        emit.ie.trim().isNotEmpty &&
        !RegExp(_ieRegex).hasMatch(emit.ie.replaceAll(RegExp(r'\D'), ''))) {
      avisos.add(ValidationWarning(
          'emitente.ie', 'IE com formato atípico: ${emit.ie}'));
    }

    if (emit.crt == null || emit.crt!.isEmpty) {
      erros.add(const ValidationError(
          'emitente.crt', 'Código de Regime Tributário (CRT) é obrigatório'));
    } else if (!['1', '2', '3'].contains(emit.crt)) {
      erros.add(ValidationError(
          'emitente.crt', 'CRT inválido: ${emit.crt}. Valores: 1=Simples, 2=Simples(SC), 3=Regime Normal'));
    }

    _validarEndereco('emitente', emit.logradouro, emit.numero, emit.bairro,
        emit.cidade, emit.uf, emit.cep, erros, avisos);

    if (emit.emailFiscal != null && emit.emailFiscal!.isNotEmpty) {
      if (!RegExp(_emailRegex).hasMatch(emit.emailFiscal!)) {
        avisos.add(const ValidationWarning(
            'emitente.email_fiscal', 'Email fiscal com formato inválido'));
      }
    }

    return ValidationResult(erros: erros, avisos: avisos);
  }

  // ─── Validação do destinatário ───

  static ValidationResult _validarDestinatario(FiscalDestinatario dest) {
    final erros = <ValidationError>[];
    final avisos = <ValidationWarning>[];

    if (dest.nome.trim().isEmpty) {
      erros.add(const ValidationError(
          'destinatario.nome', 'Nome/razão social do destinatário é obrigatório'));
    }

    final cpfCnpjLimpo =
        dest.cpfCnpj?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (dest.ehConsumidorFinal) {
      avisos.add(const ValidationWarning(
          'destinatario.cpf_cnpj', 'CPF/CNPJ não informado — NF-e sem cadastro'));
    } else {
      if (cpfCnpjLimpo.length == 11) {
        if (!_validarDigitosCpf(cpfCnpjLimpo)) {
          erros.add(const ValidationError(
              'destinatario.cpf_cnpj', 'CPF do destinatário inválido'));
        }
      } else if (cpfCnpjLimpo.length == 14) {
        if (!_validarDigitosCnpj(cpfCnpjLimpo)) {
          erros.add(const ValidationError(
              'destinatario.cpf_cnpj', 'CNPJ do destinatário inválido'));
        }
      } else {
        erros.add(const ValidationError(
            'destinatario.cpf_cnpj', 'CPF/CNPJ do destinatário deve ter 11 ou 14 dígitos'));
      }
    }

    if (dest.ie != null && dest.ie!.isNotEmpty && !dest.ehConsumidorFinal) {
      if (dest.uf != null && ufsValidas.contains(dest.uf)) {
        if (dest.ie!.length < 2 || dest.ie!.length > 14) {
          avisos.add(const ValidationWarning(
              'destinatario.ie', 'IE com tamanho atípico'));
        }
      }
    }

    if (dest.logradouro != null && dest.logradouro!.isNotEmpty) {
      _validarEndereco(
        'destinatario',
        dest.logradouro ?? '',
        dest.numero ?? '',
        dest.bairro ?? '',
        dest.cidade ?? '',
        dest.uf ?? '',
        dest.cep ?? '',
        erros,
        avisos,
      );
    }

    if (dest.email != null && dest.email!.isNotEmpty) {
      if (!RegExp(_emailRegex).hasMatch(dest.email!)) {
        avisos.add(const ValidationWarning(
            'destinatario.email', 'Email do destinatário com formato inválido'));
      }
    }

    return ValidationResult(erros: erros, avisos: avisos);
  }

  // ─── Validação de item/produto ───

  static ValidationResult _validarItem(FiscalItem item, int index) {
    final erros = <ValidationError>[];
    final avisos = <ValidationWarning>[];
    final prefixo = 'itens[$index]';

    if (item.descricao.trim().isEmpty) {
      erros.add(ValidationError(
          '$prefixo.descricao', 'Descrição do item $index é obrigatória'));
    }

    if (item.quantidade <= 0) {
      erros.add(ValidationError(
          '$prefixo.quantidade', 'Quantidade do item $index deve ser > 0'));
    }

    if (item.valorUnitario < 0) {
      erros.add(ValidationError(
          '$prefixo.valor_unitario', 'Valor unitário do item $index não pode ser negativo'));
    }

    if (item.valorTotal <= 0) {
      erros.add(ValidationError(
          '$prefixo.valor_total', 'Valor total do item $index deve ser > 0'));
    }

    final diff =
        (item.valorTotal - (item.quantidade * item.valorUnitario)).abs();
    if (diff > 0.015) {
      avisos.add(ValidationWarning(
          '$prefixo.valor_total',
          'Valor total (${item.valorTotal}) difere de qtd x unitário '
          '(${item.quantidade} x ${item.valorUnitario} = ${item.quantidade * item.valorUnitario})'));
    }

    if (item.ncm == null || item.ncm!.isEmpty) {
      avisos.add(ValidationWarning(
          '$prefixo.ncm', 'NCM não informado para o item $index'));
    } else if (!RegExp(_ncmRegex).hasMatch(item.ncm!.replaceAll(RegExp(r'\D'), '')) &&
        item.ncm != '99999999') {
      avisos.add(ValidationWarning(
          '$prefixo.ncm', 'NCM "${item.ncm}" com formato inválido (deve ter 8 dígitos)'));
    }

    if (item.cfop == null || item.cfop!.isEmpty) {
      erros.add(ValidationError(
          '$prefixo.cfop', 'CFOP do item $index é obrigatório'));
    } else if (!RegExp(_cfopRegex).hasMatch(item.cfop!)) {
      erros.add(ValidationError(
          '$prefixo.cfop', 'CFOP "${item.cfop}" inválido (deve ter 4 dígitos)'));
    } else if (!cfopsSaida.contains(item.cfop)) {
      avisos.add(ValidationWarning(
          '$prefixo.cfop', 'CFOP "${item.cfop}" não é um CFOP de saída comum'));
    }

    if (item.cest != null && item.cest!.isNotEmpty) {
      if (!RegExp(_cestRegex).hasMatch(item.cest!)) {
        avisos.add(ValidationWarning(
            '$prefixo.cest', 'CEST "${item.cest}" com formato inválido (deve ter 7 dígitos)'));
      }
    }

    if (item.cstIcms != null && item.cstIcms!.isNotEmpty) {
      if (!cstIcmsValidos.contains(item.cstIcms)) {
        avisos.add(ValidationWarning(
            '$prefixo.cst_icms', 'CST ICMS "${item.cstIcms}" não é um valor comum'));
      }
    }

    if (item.desconto != null && item.desconto! > 0) {
      if (item.desconto! > item.valorTotal) {
        erros.add(ValidationError(
            '$prefixo.desconto', 'Desconto não pode ser maior que o valor total do item'));
      }
    }

    return ValidationResult(erros: erros, avisos: avisos);
  }

  // ─── Validação de totais ───

  static ValidationResult _validarTotais(
      FiscalTotais totais, List<FiscalItem> itens) {
    final erros = <ValidationError>[];
    final avisos = <ValidationWarning>[];

    final somaProdutos = itens.fold<double>(0, (t, i) => t + i.valorTotal);
    if ((somaProdutos - totais.valorProdutos).abs() > 0.02) {
      avisos.add(ValidationWarning(
          'totais.valor_produtos',
          'Valor dos produtos (${totais.valorProdutos}) difere da soma dos itens ($somaProdutos)'));
    }

    if (totais.baseCalculoIcms < 0) {
      erros.add(const ValidationError(
          'totais.base_calculo_icms', 'Base de cálculo do ICMS não pode ser negativa'));
    }

    if (totais.valorTotal <= 0) {
      erros.add(const ValidationError(
          'totais.valor_total', 'Valor total da nota deve ser > 0'));
    }

    if (totais.valorDesconto > totais.valorProdutos) {
      erros.add(const ValidationError(
          'totais.desconto', 'Desconto não pode ser maior que o valor dos produtos'));
    }

    if (totais.valorFrete < 0) {
      erros.add(const ValidationError(
          'totais.frete', 'Valor do frete não pode ser negativo'));
    }

    return ValidationResult(erros: erros, avisos: avisos);
  }

  // ─── Validação do pagamento ───

  static ValidationResult _validarPagamento(FiscalPagamento pag) {
    final erros = <ValidationError>[];
    final avisos = <ValidationWarning>[];

    if (pag.formaPagamento.trim().isEmpty) {
      erros.add(const ValidationError(
          'pagamento.forma_pagamento', 'Forma de pagamento é obrigatória'));
    } else {
      final formasValidas = [
        'dinheiro', 'cheque', 'credito', 'debito', 'credito_loja',
        'vale_alimentacao', 'vale_refeicao', 'vale_presente',
        'vale_combustivel', 'duplicata_mercantil', 'boleto', 'sem_pagamento',
        'outro', 'pix', 'crediario',
      ];
      if (!formasValidas.contains(pag.formaPagamento)) {
        avisos.add(ValidationWarning(
            'pagamento.forma_pagamento',
            'Forma de pagamento "${pag.formaPagamento}" não é padrão'));
      }
    }

    if (pag.valorPago <= 0) {
      erros.add(const ValidationError(
          'pagamento.valor_pago', 'Valor pago deve ser > 0'));
    }

    return ValidationResult(erros: erros, avisos: avisos);
  }

  // ─── Validação do documento ───

  static ValidationResult _validarDocumento(FiscalPayload payload) {
    final erros = <ValidationError>[];
    final avisos = <ValidationWarning>[];

    if (payload.naturezaOperacao == null || payload.naturezaOperacao!.trim().isEmpty) {
      erros.add(const ValidationError(
          'natureza_operacao', 'Natureza da operação é obrigatória'));
    }

    if (payload.itens.isEmpty) {
      erros.add(const ValidationError(
          'itens', 'Pelo menos um item é obrigatório na NF-e'));
    }

    if (!finalidadesValidas.contains(payload.finalidade)) {
      avisos.add(ValidationWarning(
          'finalidade',
          'Finalidade "${payload.finalidade}" inválida. '
          'Valores: 1=Normal, 2=Complementar, 3=Ajuste, 4=Devolução'));
    }

    if (payload.tipoOperacao != '0' && payload.tipoOperacao != '1') {
      erros.add(const ValidationError(
          'tipo_operacao', 'Tipo de operação deve ser 0 (Entrada) ou 1 (Saída)'));
    }

    if (payload.serie != null && payload.serie!.isNotEmpty) {
      final serieNum = int.tryParse(payload.serie!);
      if (serieNum != null && (serieNum < 0 || serieNum > 999)) {
        erros.add(ValidationError(
            'serie', 'Série inválida: "${payload.serie}". Deve ser 0-999'));
      }
    }

    if (payload.numero != null && payload.numero!.isNotEmpty) {
      final num = int.tryParse(payload.numero!);
      if (num != null && num <= 0) {
        erros.add(ValidationError(
            'numero', 'Número da NF-e deve ser maior que zero'));
      }
    }

    // NF-e exige CFOP por item
    final semCfop = payload.itens.where((i) =>
        i.cfop == null || i.cfop!.isEmpty);
    if (semCfop.isNotEmpty) {
      erros.add(ValidationError(
          'itens',
          'Todos os itens devem ter CFOP preenchido para emissão NF-e'));
    }

    // NFC-e exige CST
    if (payload.tipoDocumento == TipoDocumentoFiscal.nfce) {
      final semCst = payload.itens.where((i) =>
          i.cstIcms == null || i.cstIcms!.isEmpty);
      if (semCst.isNotEmpty) {
        erros.add(ValidationError(
            'itens',
            'NFC-e exige CST ICMS em todos os itens'));
      }
    }

    return ValidationResult(erros: erros, avisos: avisos);
  }

  // ─── Helpers ───

  static void _validarCnpj(
      String cnpj, String campo, List<ValidationError> erros) {
    final limpo = cnpj.replaceAll(RegExp(r'\D'), '');
    if (limpo.isEmpty) {
      erros.add(
          ValidationError(campo, 'CNPJ do emitente é obrigatório'));
    } else if (limpo.length != 14) {
      erros.add(ValidationError(
          campo, 'CNPJ deve ter 14 dígitos (encontrado ${limpo.length})'));
    } else if (!_validarDigitosCnpj(limpo)) {
      erros.add(
          ValidationError(campo, 'CNPJ inválido (dígitos verificadores não conferem)'));
    }
  }

  static void _validarEndereco(
    String prefixo,
    String logradouro,
    String numero,
    String bairro,
    String cidade,
    String uf,
    String cep,
    List<ValidationError> erros,
    List<ValidationWarning> avisos,
  ) {
    if (logradouro.trim().isEmpty) {
      erros.add(ValidationError(
          '$prefixo.logradouro', 'Logradouro é obrigatório'));
    }
    if (numero.trim().isEmpty) {
      avisos.add(ValidationWarning(
          '$prefixo.numero', 'Número não informado — use "S/N" se não houver'));
    }
    if (bairro.trim().isEmpty) {
      erros.add(ValidationError(
          '$prefixo.bairro', 'Bairro é obrigatório'));
    }
    if (cidade.trim().isEmpty) {
      erros.add(ValidationError(
          '$prefixo.cidade', 'Cidade é obrigatória'));
    }
    if (uf.trim().isEmpty) {
      erros.add(ValidationError(
          '$prefixo.uf', 'UF é obrigatória'));
    } else if (!ufsValidas.contains(uf.toUpperCase())) {
      avisos.add(ValidationWarning(
          '$prefixo.uf', 'UF "$uf" não reconhecida'));
    }
    if (cep.isNotEmpty && !RegExp(_cepRegex).hasMatch(cep.replaceAll(RegExp(r'\D'), ''))) {
      avisos.add(ValidationWarning(
          '$prefixo.cep', 'CEP com formato inválido'));
    }
  }

  static bool _validarDigitosCpf(String cpf) {
    if (cpf.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;

    int calcDigito(String cpf, int peso) {
      int soma = 0;
      for (int i = 0; i < peso - 1; i++) {
        soma += int.parse(cpf[i]) * (peso - i);
      }
      int resto = (soma * 10) % 11;
      return resto == 10 ? 0 : resto;
    }

    if (int.parse(cpf[9]) != calcDigito(cpf, 10)) return false;
    if (int.parse(cpf[10]) != calcDigito(cpf, 11)) return false;
    return true;
  }

  static bool _validarDigitosCnpj(String cnpj) {
    if (cnpj.length != 14) return false;
    if (RegExp(r'^(\d)\1{13}$').hasMatch(cnpj)) return false;

    int calcDigitoCnpj(String cnpj, List<int> pesos) {
      int soma = 0;
      for (int i = 0; i < pesos.length; i++) {
        soma += int.parse(cnpj[i]) * pesos[i];
      }
      int resto = soma % 11;
      return resto < 2 ? 0 : 11 - resto;
    }

    const pesos1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const pesos2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

    if (int.parse(cnpj[12]) != calcDigitoCnpj(cnpj, pesos1)) return false;
    if (int.parse(cnpj[13]) != calcDigitoCnpj(cnpj, pesos2)) return false;
    return true;
  }
}
