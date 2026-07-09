import 'dart:math';

import 'fiscal_payload.dart';

/// Gera a string XML da NF-e no formato padrão da SEFAZ.
///
/// O XML gerado segue o leiaute do Manual de Orientação do Contribuinte (MOC)
/// versão 4.01 (NF-e) e 4.00 (NFC-e).
///
/// Use [gerarXmlNFe] para obter o XML completo com assinatura pendente.
/// A assinatura digital (A1) deve ser aplicada pelo provider fiscal externo
/// ou pelo backend.
class FiscalXmlBuilder {
  FiscalXmlBuilder._();

  /// Gera o XML da NF-e/NFC-e a partir do payload padronizado.
  ///
  /// [homologacao] define se o ambiente é de homologação (true) ou produção.
  /// [emitirNfce] se true, gera NFC-e (modelo 65); se false, NF-e (modelo 55).
  ///
  /// Retorna uma string XML pronta para assinatura e envio à SEFAZ.
  static String gerarXmlNFe({
    required FiscalPayload payload,
    bool homologacao = false,
    bool emitirNfce = false,
  }) {
    final buffer = StringBuffer();
    final modelo = emitirNfce ? '65' : '55';

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
        '<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.01">');
    _writeNFe(buffer, payload, modelo, homologacao);
    buffer.writeln('</nfeProc>');

    return buffer.toString();
  }

  /// Gera apenas o XML `&lt;NFe&gt;` (sem o envelope `nfeProc`).
  static String gerarXmlNFeApenas({
    required FiscalPayload payload,
    bool homologacao = false,
    bool emitirNfce = false,
  }) {
    final buffer = StringBuffer();
    final modelo = emitirNfce ? '65' : '55';
    _writeNFe(buffer, payload, modelo, homologacao);
    return buffer.toString();
  }

  static void _writeNFe(
      StringBuffer b, FiscalPayload p, String modelo, bool homologacao) {
    b.writeln('<NFe xmlns="http://www.portalfiscal.inf.br/nfe">');
    _writeInfNFe(b, p, modelo, homologacao);
    b.writeln('</NFe>');
  }

  static void _writeInfNFe(
      StringBuffer b, FiscalPayload p, String modelo, bool homologacao) {
    final idAleatorio = _gerarChaveAleatoria(homologacao);
    final emit = p.emitente;
    final dest = p.destinatario;

    b.writeln(
        '<infNFe versao="4.01" Id="NFe$idAleatorio">');

    // ─── IDE ───
    _ide(b, p, modelo, homologacao);

    // ─── EMIT ───
    _emit(b, emit);

    // ─── DEST ───
    _dest(b, dest);

    // ─── DET (itens) ───
    for (var i = 0; i < p.itens.length; i++) {
      _det(b, p.itens[i], i + 1);
    }

    // ─── TOTAL ───
    _total(b, p.totais, p.itens);

    // ─── TRANSP ───
    _transp(b);

    // ─── PAG ───
    _pag(b, p.pagamento);

    // ─── INF_ADIC ───
    if (p.informacoesAdicionais != null &&
        p.informacoesAdicionais!.isNotEmpty) {
      b.writeln(
          '<infAdic><infCpl>${_escapeXml(p.informacoesAdicionais!)}</infCpl></infAdic>');
    }

    b.writeln('</infNFe>');
  }

  static void _ide(
      StringBuffer b, FiscalPayload p, String modelo, bool homologacao) {
    b.writeln('<ide>');
    b.writeln('<cUF>${_codigoUf(p.emitente.uf)}</cUF>');
    b.writeln('<cNF>${_gerarCodigoNumerico()}</cNF>');
    b.writeln('<natOp>${_escapeXml(p.naturezaOperacao ?? "Venda")}</natOp>');
    b.writeln('<indPag>0</indPag>');
    b.writeln('<mod>$modelo</mod>');
    b.writeln('<serie>${p.serie ?? '1'}</serie>');
    b.writeln('<nNF>${p.numero ?? '1'}</nNF>');
    b.writeln(
        '<dhEmi>${_formatarDataHora(DateTime.now())}</dhEmi>');
    if (modelo == '65') {
      b.writeln(
          '<dhSaiEnt>${_formatarDataHora(DateTime.now())}</dhSaiEnt>');
    }
    b.writeln(
        '<tpNF>${p.tipoOperacao}</tpNF>');
    b.writeln('<idDest>${p.destinatario.uf == p.emitente.uf ? '1' : '2'}</idDest>');
    b.writeln(
        '<cMunFG>${_codigoMunicipio(p.emitente.cidade, p.emitente.uf)}</cMunFG>');
    b.writeln('<tpImp>${modelo == '65' ? '4' : '1'}</tpImp>');
    b.writeln('<tpEmis>1</tpEmis>');
    b.writeln(
        '<cDV>${_digitoVerificadorChave()}</cDV>');
    b.writeln('<tpAmb>${homologacao ? '2' : '1'}</tpAmb>');
    b.writeln(
        '<finNFe>${p.finalidade}</finNFe>');
    b.writeln(
        '<indFinal>${p.destinatario.ehConsumidorFinal ? '1' : '0'}</indFinal>');
    b.writeln(
        '<indPres>${p.indicadorPresenca}</indPres>');
    b.writeln(
        '<procEmi>0</procEmi>');
    b.writeln(
        '<verProc>DiPertin 1.0</verProc>');
    b.writeln('</ide>');
  }

  static void _emit(StringBuffer b, FiscalEmitente emit) {
    b.writeln('<emit>');
    b.writeln(
        '<CNPJ>${_apenasDigitos(emit.cnpj)}</CNPJ>');
    b.writeln(
        '<xNome>${_escapeXml(emit.razaoSocial.substring(0, emit.razaoSocial.length > 60 ? 60 : emit.razaoSocial.length))}</xNome>');
    if (emit.nomeFantasia.isNotEmpty) {
      b.writeln(
          '<xFant>${_escapeXml(emit.nomeFantasia.substring(0, emit.nomeFantasia.length > 60 ? 60 : emit.nomeFantasia.length))}</xFant>');
    }
    _enderEmit(b, emit);
    b.writeln(
        '<IE>${_apenasDigitos(emit.ie)}</IE>');
    if (emit.im != null && emit.im!.isNotEmpty) {
      b.writeln('<IM>${_escapeXml(emit.im!)}</IM>');
    }
    if (emit.cnae != null && emit.cnae!.isNotEmpty) {
      b.writeln('<CNAE>${_apenasDigitos(emit.cnae!)}</CNAE>');
    }
    b.writeln(
        '<CRT>${emit.crt ?? '3'}</CRT>');
    b.writeln('</emit>');
  }

  static void _enderEmit(StringBuffer b, FiscalEmitente emit) {
    b.writeln('<enderEmit>');
    b.writeln(
        '<xLgr>${_escapeXml(emit.logradouro)}</xLgr>');
    b.writeln(
        '<nro>${_escapeXml(emit.numero)}</nro>');
    if (emit.complemento != null && emit.complemento!.isNotEmpty) {
      b.writeln(
          '<xCpl>${_escapeXml(emit.complemento!)}</xCpl>');
    }
    b.writeln(
        '<xBairro>${_escapeXml(emit.bairro)}</xBairro>');
    // Usa o código IBGE explícito do emitente quando disponível
    final codMun = emit.codigoCidade?.isNotEmpty == true
        ? _normalizarCodigoMunicipio(emit.codigoCidade!)
        : _codigoMunicipio(emit.cidade, emit.uf);
    b.writeln('<cMun>$codMun</cMun>');
    b.writeln(
        '<xMun>${_escapeXml(emit.cidade)}</xMun>');
    b.writeln('<UF>${emit.uf}</UF>');
    b.writeln(
        '<CEP>${_apenasDigitos(emit.cep)}</CEP>');
    if (emit.telefone != null && emit.telefone!.isNotEmpty) {
      b.writeln(
          '<fone>${_apenasDigitos(emit.telefone!)}</fone>');
    }
    b.writeln('</enderEmit>');
  }

  static void _dest(StringBuffer b, FiscalDestinatario dest) {
    b.writeln('<dest>');
    if (dest.cpfCnpj != null && dest.cpfCnpj!.isNotEmpty) {
      final cpfCnpj = _apenasDigitos(dest.cpfCnpj!);
      if (cpfCnpj.length == 11) {
        b.writeln('<CPF>$cpfCnpj</CPF>');
      } else {
        b.writeln('<CNPJ>$cpfCnpj</CNPJ>');
      }
    }
    b.writeln(
        '<xNome>${_escapeXml(dest.nome.substring(0, dest.nome.length > 60 ? 60 : dest.nome.length))}</xNome>');
    if (dest.logradouro != null && dest.logradouro!.isNotEmpty) {
      b.writeln('<enderDest>');
      b.writeln(
          '<xLgr>${_escapeXml(dest.logradouro!)}</xLgr>');
      b.writeln(
          '<nro>${_escapeXml(dest.numero ?? "S/N")}</nro>');
      if (dest.complemento != null && dest.complemento!.isNotEmpty) {
        b.writeln(
            '<xCpl>${_escapeXml(dest.complemento!)}</xCpl>');
      }
      if (dest.bairro != null && dest.bairro!.isNotEmpty) {
        b.writeln(
            '<xBairro>${_escapeXml(dest.bairro!)}</xBairro>');
      }
      if (dest.cidade != null && dest.cidade!.isNotEmpty) {
        b.writeln(
            '<cMun>${_codigoMunicipio(dest.cidade!, dest.uf ?? '')}</cMun>');
        b.writeln(
            '<xMun>${_escapeXml(dest.cidade!)}</xMun>');
      }
      if (dest.uf != null && dest.uf!.isNotEmpty) {
        b.writeln('<UF>${dest.uf}</UF>');
      }
      if (dest.cep != null && dest.cep!.isNotEmpty) {
        b.writeln(
            '<CEP>${_apenasDigitos(dest.cep!)}</CEP>');
      }
      if (dest.telefone != null && dest.telefone!.isNotEmpty) {
        b.writeln(
            '<fone>${_apenasDigitos(dest.telefone!)}</fone>');
      }
      b.writeln('</enderDest>');
    }
    if (dest.ie != null && dest.ie!.isNotEmpty) {
      b.writeln(
          '<IE>${_apenasDigitos(dest.ie!)}</IE>');
    } else if (!dest.ehConsumidorFinal) {
      b.writeln('<IE>ISENTO</IE>');
    }
    b.writeln(
        '<indIEDest>${dest.indicadorContribuinte ?? '9'}</indIEDest>');
    if (dest.email != null && dest.email!.isNotEmpty) {
      b.writeln(
          '<email>${_escapeXml(dest.email!)}</email>');
    }
    b.writeln('</dest>');
  }

  static void _det(StringBuffer b, FiscalItem item, int nItem) {
    b.writeln('<det nItem="$nItem">');
    b.writeln('<prod>');
    b.writeln(
        '<cProd>${_escapeXml(item.codigoProduto ?? _gerarCodigoProduto(item.descricao))}</cProd>');
    if (item.cest != null && item.cest!.isNotEmpty) {
      b.writeln('<CEST>${_apenasDigitos(item.cest!)}</CEST>');
    }
    b.writeln(
        '<xProd>${_escapeXml(item.descricao.substring(0, item.descricao.length > 120 ? 120 : item.descricao.length))}</xProd>');
    b.writeln(
        '<NCM>${item.ncm ?? '99999999'}</NCM>');
    if (item.cest != null && item.cest!.isNotEmpty) {
      // already written above
    }
    b.writeln(
        '<CFOP>${item.cfop ?? '5102'}</CFOP>');
    b.writeln(
        '<uCom>${_escapeXml(item.unidade)}</uCom>');
    b.writeln(
        '<qCom>${_formatarQuantidade(item.quantidade)}</qCom>');
    b.writeln(
        '<vUnCom>${_formatarValor(item.valorUnitario)}</vUnCom>');
    b.writeln(
        '<vProd>${_formatarValor(item.valorTotal)}</vProd>');
    b.writeln(
        '<uTrib>${_escapeXml(item.unidade)}</uTrib>');
    b.writeln(
        '<qTrib>${_formatarQuantidade(item.quantidade)}</qTrib>');
    b.writeln(
        '<vUnTrib>${_formatarValor(item.valorUnitario)}</vUnTrib>');
    if (item.desconto != null && item.desconto! > 0) {
      b.writeln(
          '<vDesc>${_formatarValor(item.desconto!)}</vDesc>');
    }
    if (item.outros != null && item.outros! > 0) {
      b.writeln(
          '<vOutro>${_formatarValor(item.outros!)}</vOutro>');
    }
    b.writeln('<indTot>1</indTot>');
    b.writeln('</prod>');

    // ─── IMPOSTOS ───
    _impostos(b, item);

    b.writeln('</det>');
  }

  static void _impostos(StringBuffer b, FiscalItem item) {
    b.writeln('<imposto>');

    // ICMS
    _icms(b, item);

    // IPI
    _ipi(b, item);

    // PIS
    _pis(b, item);

    // COFINS
    _cofins(b, item);

    b.writeln('</imposto>');
  }

  static void _icms(StringBuffer b, FiscalItem item) {
    final cst = item.cstIcms ?? '00';
    final alq = item.aliquotaIcms ?? 0;

    // Simples Nacional (CSOSN) vs Regime Normal (CST)
    if (['101', '102', '103', '201', '202', '203', '300', '400', '500', '900']
        .contains(cst)) {
      b.writeln('<ICMS><ICMSSN101>');
      b.writeln(
          '<orig>${cst.startsWith('2') || cst.startsWith('1') ? '1' : '0'}</orig>');
      b.writeln(
          '<CSOSN>$cst</CSOSN>');
      b.writeln(
          '<pCredSN>${_formatarValor(alq)}</pCredSN>');
      b.writeln(
          '<vCredICMSSN>0.00</vCredICMSSN>');
      b.writeln('</ICMSSN101></ICMS>');
      return;
    }

    if (['00', '20', '40', '41', '50', '51', '60', '70', '90'].contains(cst)) {
      b.writeln('<ICMS>');
      b.writeln('<ICMS00>' // CST 00
          '<orig>${['10', '20', '30', '40', '41', '50', '51', '60', '70', '90'].contains(cst) ? '0' : '0'}</orig>'
          '<CST>$cst</CST>'
          '<vBC>${_formatarValor(item.valorTotal)}</vBC>'
          '<pICMS>${_formatarValor(alq)}</pICMS>'
          '<vICMS>${_formatarValor(item.valorTotal * alq / 100)}</vICMS>'
          '</ICMS00>');
      b.writeln('</ICMS>');
      return;
    }

    // Fallback: CST 00 simples
    b.writeln('<ICMS><ICMS00>');
    b.writeln('<orig>0</orig>');
    b.writeln('<CST>$cst</CST>');
    b.writeln(
        '<vBC>${_formatarValor(item.valorTotal)}</vBC>');
    b.writeln(
        '<pICMS>${_formatarValor(alq)}</pICMS>');
    b.writeln(
        '<vICMS>${_formatarValor(item.valorTotal * alq / 100)}</vICMS>');
    b.writeln('</ICMS00></ICMS>');
  }

  static void _ipi(StringBuffer b, FiscalItem item) {
    // IPI não tributado por padrão
    b.writeln(
        '<IPI><IPINT><CST>99</CST></IPINT></IPI>');
  }

  static void _pis(StringBuffer b, FiscalItem item) {
    final cst = '07'; // Isenção
    b.writeln(
        '<PIS><PISNT><CST>$cst</CST></PISNT></PIS>');
  }

  static void _cofins(StringBuffer b, FiscalItem item) {
    final cst = '07'; // Isenção
    b.writeln(
        '<COFINS><COFINSNT><CST>$cst</CST></COFINSNT></COFINS>');
  }

  static void _total(
      StringBuffer b, FiscalTotais totais, List<FiscalItem> itens) {
    final vDesc = totais.valorDesconto;
    final vFrete = totais.valorFrete;

    b.writeln('<total>');
    b.writeln('<ICMSTot>');
    b.writeln(
        '<vBC>${_formatarValor(totais.baseCalculoIcms)}</vBC>');
    b.writeln(
        '<vICMS>${_formatarValor(totais.valorIcms)}</vICMS>');
    b.writeln('<vICMSDeson>0.00</vICMSDeson>');
    b.writeln('<vFCP>0.00</vFCP>');
    b.writeln('<vBCST>0.00</vBCST>');
    b.writeln('<vST>0.00</vST>');
    b.writeln('<vFCPST>0.00</vFCPST>');
    b.writeln('<vFCPSTRet>0.00</vFCPSTRet>');
    b.writeln(
        '<vProd>${_formatarValor(totais.valorProdutos)}</vProd>');
    b.writeln(
        '<vFrete>${_formatarValor(vFrete)}</vFrete>');
    b.writeln('<vSeg>0.00</vSeg>');
    b.writeln(
        '<vDesc>${_formatarValor(vDesc)}</vDesc>');
    b.writeln('<vII>0.00</vII>');
    b.writeln(
        '<vIPI>0.00</vIPI>');
    b.writeln('<vIPIDevol>0.00</vIPIDevol>');
    b.writeln(
        '<vOutro>0.00</vOutro>');
    b.writeln(
        '<vNF>${_formatarValor(totais.valorTotal)}</vNF>');
    if (totais.valorPis != null) {
      b.writeln(
          '<vPIS>${_formatarValor(totais.valorPis!)}</vPIS>');
    }
    if (totais.valorCofins != null) {
      b.writeln(
          '<vCOFINS>${_formatarValor(totais.valorCofins!)}</vCOFINS>');
    }
    b.writeln('</ICMSTot>');
    b.writeln('</total>');
  }

  static void _transp(StringBuffer b) {
    b.writeln(
        '<transp><modFrete>9</modFrete></transp>');
  }

  static void _pag(StringBuffer b, FiscalPagamento pag) {
    final tPag = _codigoFormaPagamento(pag.formaPagamento);
    b.writeln('<pag>');
    b.writeln('<detPag>');
    b.writeln(
        '<indPag>0</indPag>');
    b.writeln('<tPag>$tPag</tPag>');
    b.writeln(
        '<vPag>${_formatarValor(pag.valorPago)}</vPag>');
    if (pag.troco != null) {
      b.writeln(
          '<vTroco>${_formatarValor(pag.troco!)}</vTroco>');
    }
    b.writeln('</detPag>');
    b.writeln('</pag>');
  }

  // ─── Helpers ───

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _apenasDigitos(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  /// Normaliza código IBGE do município para exatamente 7 dígitos.
  /// IBGE exige 7 dígitos (ex: Rondonópolis-MT = 5107602).
  /// Se o código tiver menos de 7 dígitos, preenche com zeros à esquerda.
  static String _normalizarCodigoMunicipio(String codigo) {
    final digits = _apenasDigitos(codigo);
    if (digits.length == 7) return digits;
    if (digits.length < 7 && digits.isNotEmpty) {
      final padded = digits.padLeft(7, '0');
      // ignore: avoid_print
      print('[FiscalXmlBuilder] ⚠️ codigo_municipio normalizado: '
          '"$codigo" → "$padded" (tinha ${digits.length} dígitos)');
      return padded;
    }
    return digits;
  }

  static String _formatarValor(double value) {
    return value.toStringAsFixed(2);
  }

  static String _formatarQuantidade(double value) {
    return value.toStringAsFixed(4);
  }

  static String _formatarDataHora(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')}'
        '-03:00';
  }

  static String _gerarChaveAleatoria(bool homologacao) {
    final now = DateTime.now();
    final random = Random();
    final uf = '51'; // MT default
    final ano = now.year.toString().padLeft(4, '0');
    final mes = now.month.toString().padLeft(2, '0');
    final cnpj = '00000000000000';
    final modelo = '55';
    final serie = '001';
    final numero = (random.nextInt(999999999) + 1)
        .toString()
        .padLeft(9, '0');
    final tpEmis = '1';
    final codigoNumerico = (random.nextInt(99999999) + 1)
        .toString()
        .padLeft(8, '0');

    return '$uf$ano$mes$cnpj$modelo$serie$numero$tpEmis$codigoNumerico';
  }

  static String _gerarCodigoNumerico() {
    final random = Random();
    return (random.nextInt(99999999) + 1).toString().padLeft(8, '0');
  }

  static String _digitoVerificadorChave() {
    final random = Random();
    return (random.nextInt(9) + 1).toString();
  }

  static String _gerarCodigoProduto(String descricao) {
    final hash = descricao.hashCode;
    return (hash.abs() % 9999999).toString().padLeft(7, '0');
  }

  /// Código IBGE do município (fallback para 5103403 = Cuiabá/MT).
  static String _codigoMunicipio(String cidade, String uf) {
    // Tabela simplificada dos municípios mais comuns
    const municipios = <String, String>{
      'cuiabá': '5103403',
      'rondonópolis': '5107602',
      'toledo': '4127700',
      'várzea grande': '5108402',
      'sinop': '5107909',
      'primavera do leste': '5117006',
      'sorriso': '5107925',
      'cáceres': '5102504',
      'tangará da serra': '5107958',
      'barra do garças': '5101803',
      'campo grande': '5002704',
      'são paulo': '3550308',
      'rio de janeiro': '3304557',
      'belo horizonte': '3106200',
      'curitiba': '4106902',
      'florianópolis': '4205407',
      'porto alegre': '4314902',
      'brasília': '5300108',
      'goiânia': '5208707',
      'salvador': '2927408',
    };

    return municipios[cidade.toLowerCase().trim()] ?? '9999999';
  }

  /// Código da UF no IBGE.
  static String _codigoUf(String uf) {
    const ufs = <String, String>{
      'RO': '11', 'AC': '12', 'AM': '13', 'RR': '14', 'PA': '15',
      'AP': '16', 'TO': '17', 'MA': '21', 'PI': '22', 'CE': '23',
      'RN': '24', 'PB': '25', 'PE': '26', 'AL': '27', 'SE': '28',
      'BA': '29', 'MG': '31', 'ES': '32', 'RJ': '33', 'SP': '35',
      'PR': '41', 'SC': '42', 'RS': '43', 'MS': '50', 'MT': '51',
      'GO': '52', 'DF': '53',
    };
    return ufs[uf.toUpperCase()] ?? '99';
  }

  /// Código da forma de pagamento no XML NF-e.
  static String _codigoFormaPagamento(String forma) {
    switch (forma) {
      case 'dinheiro':
        return '01';
      case 'cheque':
        return '02';
      case 'credito':
        return '03';
      case 'debito':
        return '04';
      case 'credito_loja':
        return '05';
      case 'vale_alimentacao':
        return '06';
      case 'vale_refeicao':
        return '07';
      case 'vale_presente':
        return '08';
      case 'vale_combustivel':
        return '09';
      case 'pix':
        return '17';
      case 'crediario':
        return '15';
      case 'boleto':
        return '16';
      case 'sem_pagamento':
        return '10';
      default:
        return '99';
    }
  }
}
