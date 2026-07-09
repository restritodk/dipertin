import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../fiscal_payload.dart';
import '../fiscal_provider.dart';
import '../../firebase_functions_config.dart';

/// Provider para a Focus NFe (https://focusnfe.com.br).
///
/// As chamadas HTTP são feitas via Cloud Function backend (fiscal_nfe_proxy.js),
/// NUNCA diretamente do navegador. O token/api_key fica apenas no backend.
///
/// Homologacao: https://homologacao.focusnfe.com.br/v2
/// Producao:    https://api.focusnfe.com.br/v2
class FocusNFeProvider implements FiscalProvider {
  @override
  String get id => 'focus_nfe';

  @override
  String get nome => 'Focus NFe';

  @override
  FiscalProviderInfo get info => const FiscalProviderInfo(
        id: 'focus_nfe',
        nome: 'Focus NFe',
        descricao:
            'API fiscal para emissao de NF-e, NFC-e, NFS-e, CT-e e MDF-e.',
        documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
        site: 'https://focusnfe.com.br',
        temHomologacao: true,
      );

  @override
  List<String> get documentosSuportados => info.documentosSuportados;

  /// Região das Cloud Functions fiscais (southamerica-east1).
  static const _regiao = 'southamerica-east1';
  static const _timeout = Duration(seconds: 90);

  @override
  Future<FiscalProviderResult> emitirNota(
    FiscalPayload payload,
    Map<String, dynamic> config,
  ) async {
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('PROVA: ENTROU NO FocusNFeProvider.emitirNota');
    debugPrint('PROVA: Este é o provider REAL usado na emissão.');
    debugPrint('═══════════════════════════════════════════════════════');
    try {
      final erros = validarConfiguracao(config);
      if (erros != null && erros.isNotEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuracao invalida: ${erros.values.join(', ')}',
          statusEnvio: 'erro',
        );
      }

      final integrationId = config['integration_id'] as String? ?? '';
      if (integrationId.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'ID da integracao fiscal nao encontrado.',
          statusEnvio: 'erro',
        );
      }

      final body = converterParaFormatoProvedor(payload, config);
      final cnpj = _digitos(payload.emitente.cnpj);

      // Valida CNPJ de 14 digitos antes de enviar ao backend
      if (cnpj.length != 14) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'CNPJ do emitente invalido ($cnpj). Deve ter 14 digitos.',
          statusEnvio: 'erro',
        );
      }

      final storeId = config['store_id'] as String? ?? payload.emitente.cnpj;

      debugPrint(
        '[FocusNFeProvider] Emitindo NF-e via Cloud Function fiscalEmitirNFe: '
        'integration_id=$integrationId store_id=$storeId cnpj=$cnpj',
      );

      // ═══ LOG DO PAYLOAD COMPLETO ENVIADO PARA A CLOUD FUNCTION ═══
      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════╗');
      debugPrint('║      PAYLOAD COMPLETO ENVIADO AO BACKEND           ║');
      debugPrint('╚══════════════════════════════════════════════════════╝');
      debugPrint('PROVA: Abaixo o JSON exato enviado para fiscalEmitirNFe:');
      try {
        final encoder = const JsonEncoder.withIndent('  ');
        debugPrint(encoder.convert(body));
      } catch (e) {
        debugPrint('(erro ao serializar body: $e)');
        debugPrint('body keys: ${body.keys.join(', ')}');
      }
      debugPrint('══════════════════════════════════════════════════════');
      debugPrint('');

      // Lê lojista_integration_id e certificate_id da config (passados do frontend)
      final lojistaIntegrationId = config['lojista_integration_id'] as String? ?? '';
      final certificateId = config['certificate_id'] as String? ?? '';

      final result = await callFirebaseFunctionSafe(
        'fiscalEmitirNFe',
        parameters: {
          'integration_id': integrationId,
          'store_id': storeId,
          'nfe_payload': body,
          'cnpj': cnpj,
          'document_type': payload.tipoDocumento.codigo,
          'serie': payload.serie ?? '1',
          'numero': payload.numero ?? '',
          if (lojistaIntegrationId.isNotEmpty) 'lojista_integration_id': lojistaIntegrationId,
          if (certificateId.isNotEmpty) 'certificate_id': certificateId,
        },
        timeout: _timeout,
        region: _regiao,
      );

      return _parseEmitirResponse(result, integrationId);
    } catch (e) {
      debugPrint('[FocusNFeProvider] Erro ao emitir NF-e: $e');
      return FiscalProviderResult(
        sucesso: false,
        erro: _mensagemErro(e),
        statusEnvio: 'erro',
        providerResponse: e.toString(),
      );
    }
  }

  @override
  Future<FiscalProviderResult> cancelarNota({
    required String chaveAcesso,
    required String justificativa,
    required String numeroProtocolo,
    required Map<String, dynamic> config,
  }) async {
    try {
      final erros = validarConfiguracao(config);
      if (erros != null && erros.isNotEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuracao invalida: ${erros.values.join(', ')}',
          statusEnvio: 'erro',
        );
      }

      final integrationId = config['integration_id'] as String? ?? '';
      if (integrationId.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'ID da integracao fiscal nao encontrado.',
          statusEnvio: 'erro',
        );
      }

      // store_id é obrigatório para validação de segurança no backend
      final storeId = config['store_id'] as String? ?? '';

      final result = await callFirebaseFunctionSafe(
        'fiscalCancelarNFe',
        parameters: {
          'integration_id': integrationId,
          'store_id': storeId,
          'chave_acesso': chaveAcesso,
          'justificativa': justificativa,
          if (numeroProtocolo.isNotEmpty)
            'numero_protocolo': numeroProtocolo,
        },
        timeout: _timeout,
        region: _regiao,
      );

      return FiscalProviderResult(
        sucesso: result['sucesso'] == true,
        chaveAcesso: result['chave_acesso'] as String?,
        protocolo: result['protocolo'] as String?,
        numero: result['numero'] as String?,
        mensagem: result['mensagem'] as String?,
        erro: result['erro'] as String?,
        statusEnvio: result['status'] as String? ?? 'erro',
        providerResponse: result['provider_response'] as String?,
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: _mensagemErro(e),
        statusEnvio: 'erro',
      );
    }
  }

  @override
  Future<FiscalProviderResult> enviarCartaCorrecao({
    required String chaveAcesso,
    required String textoCorrecao,
    required int sequencia,
    required Map<String, dynamic> config,
  }) async {
    try {
      final erros = validarConfiguracao(config);
      if (erros != null && erros.isNotEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuracao invalida: ${erros.values.join(', ')}',
          statusEnvio: 'erro',
        );
      }

      final integrationId = config['integration_id'] as String? ?? '';
      if (integrationId.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'ID da integracao fiscal nao encontrado.',
          statusEnvio: 'erro',
        );
      }

      // store_id é obrigatório para validação de segurança no backend
      final storeId = config['store_id'] as String? ?? '';

      final result = await callFirebaseFunctionSafe(
        'fiscalCartaCorrecaoNFe',
        parameters: {
          'integration_id': integrationId,
          'store_id': storeId,
          'chave_acesso': chaveAcesso,
          'texto_correcao': textoCorrecao,
          'sequencia': sequencia,
        },
        timeout: _timeout,
        region: _regiao,
      );

      return FiscalProviderResult(
        sucesso: result['sucesso'] == true,
        chaveAcesso: result['chave_acesso'] as String?,
        protocolo: result['protocolo'] as String?,
        mensagem: result['mensagem'] as String?,
        erro: result['erro'] as String?,
        statusEnvio: result['status'] as String? ?? 'erro',
        providerResponse: result['provider_response'] as String?,
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: _mensagemErro(e),
        statusEnvio: 'erro',
      );
    }
  }

  @override
  Future<FiscalProviderResult> inutilizarNumeracao({
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    required String justificativa,
    required Map<String, dynamic> config,
  }) async {
    try {
      final erros = validarConfiguracao(config);
      if (erros != null && erros.isNotEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuracao invalida: ${erros.values.join(', ')}',
          statusEnvio: 'erro',
        );
      }

      final integrationId = config['integration_id'] as String? ?? '';
      if (integrationId.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'ID da integracao fiscal nao encontrado.',
          statusEnvio: 'erro',
        );
      }

      // store_id é obrigatório para validação de segurança no backend
      final storeId = config['store_id'] as String? ?? '';

      final result = await callFirebaseFunctionSafe(
        'fiscalInutilizarNFe',
        parameters: {
          'integration_id': integrationId,
          'store_id': storeId,
          'serie': serie,
          'numero_inicial': numeroInicial,
          'numero_final': numeroFinal,
          'justificativa': justificativa,
        },
        timeout: _timeout,
        region: _regiao,
      );

      return FiscalProviderResult(
        sucesso: result['sucesso'] == true,
        protocolo: result['protocolo'] as String?,
        mensagem: result['mensagem'] as String?,
        erro: result['erro'] as String?,
        statusEnvio: result['status'] as String? ?? 'erro',
        providerResponse: result['provider_response'] as String?,
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: _mensagemErro(e),
        statusEnvio: 'erro',
      );
    }
  }

  @override
  Future<bool> testarConexao(Map<String, dynamic> config) async {
    try {
      final integrationId = config['integration_id'] as String? ?? '';
      if (integrationId.isEmpty) return false;

      // ═══════════════════════════════════════════════════════════════
      // TESTE REAL na API Focus NFe via Cloud Function backend.
      //
      // O backend (fiscalTestarConexaoFocus) faz uma chamada GET
      // autêntica para https://homologacao.focusnfe.com.br/v2/empresas
      // ou https://api.focusnfe.com.br/v2/empresas com HTTP Basic Auth.
      //
      // Se o token for inválido, a Focus retorna HTTP 401/403.
      // Se a URL estiver errada, retorna 404.
      // Se tudo OK, retorna 200/201/202.
      //
      // NUNCA retorna sucesso por mock, fallback ou catch genérico.
      // ═══════════════════════════════════════════════════════════════
      final result = await callFirebaseFunctionSafe(
        'fiscalTestarConexaoFocus',
        parameters: {
          'integration_id': integrationId,
        },
        timeout: const Duration(seconds: 30),
        region: _regiao,
      );

      final validado = result['validado'] == true;
      final sucesso = result['sucesso'] == true;

      debugPrint(
        '[FocusNFeProvider] testarConexao: '
        'sucesso=$sucesso validado=$validado '
        'ambiente=${result['ambiente']} '
        'http=${result['status_http']}',
      );

      return validado && sucesso;
    } catch (e) {
      debugPrint('[FocusNFeProvider] testarConexao ERRO: $e');
      return false;
    }
  }

  @override
  Map<String, String>? validarConfiguracao(Map<String, dynamic> config) {
    final erros = <String, String>{};
    if (config['integration_id'] == null ||
        (config['integration_id'] as String).isEmpty) {
      erros['integration_id'] = 'ID da integracao e obrigatorio';
    }
    return erros.isEmpty ? null : erros;
  }

  @override
  Map<String, dynamic> converterParaFormatoProvedor(
    FiscalPayload payload,
    Map<String, dynamic> config,
  ) {
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('PROVA: ENTROU NO converterParaFormatoProvedor');
    debugPrint('PROVA: Formato FLAT Focus NFe v2');
    debugPrint('PROVA: Campos planos cnpj_emitente, nome_emitente, etc.');
    debugPrint('═══════════════════════════════════════════════════════');
    final regimeValor = _calcRegimeFocus(payload.emitente.regimeTributario);
    final ieIsento = config['ie_isento'] == true;

    return {
      // ─── Campos planos do emitente ───
      'cnpj_emitente': _apenasDigitos(payload.emitente.cnpj),
      'nome_emitente': payload.emitente.razaoSocial,
      'nome_fantasia_emitente': payload.emitente.nomeFantasia,
      'logradouro_emitente': payload.emitente.logradouro,
      'numero_emitente': payload.emitente.numero,
      'bairro_emitente': payload.emitente.bairro,
      'municipio_emitente': payload.emitente.cidade,
      'uf_emitente': payload.emitente.uf,
      'cep_emitente': payload.emitente.cep,
      // IE — envia "ISENTO" se dispensada, senão envia o valor real
      // Porém, se ie_isento=true, remove completamente o campo (SEFAZ/MT
      // rejeita "ISENTO" como valor mesmo em homologação)
      if (!ieIsento && payload.emitente.ie.trim().isNotEmpty)
        'inscricao_estadual_emitente': payload.emitente.ie.trim(),
      'regime_tributario_emitente': regimeValor,

      // Código IBGE do município do emitente (7 dígitos)
      if (payload.emitente.codigoCidade != null &&
          payload.emitente.codigoCidade!.isNotEmpty)
        'codigo_municipio_emitente': payload.emitente.codigoCidade!,

      // ─── Campos planos do destinatário ───
      'nome_destinatario': payload.destinatario.nome,
      if (payload.destinatario.cpfCnpj != null)
        _apenasDigitos(payload.destinatario.cpfCnpj!).length == 14
            ? 'cnpj_destinatario'
            : 'cpf_destinatario': _apenasDigitos(payload.destinatario.cpfCnpj!),
      'logradouro_destinatario': payload.destinatario.logradouro ?? '',
      if (payload.destinatario.numero != null)
        'numero_destinatario': payload.destinatario.numero,
      if (payload.destinatario.bairro != null)
        'bairro_destinatario': payload.destinatario.bairro,
      'municipio_destinatario': payload.destinatario.cidade ?? '',
      'uf_destinatario': payload.destinatario.uf ?? '',
      'cep_destinatario': payload.destinatario.cep ?? '',
      // Código IBGE do destinatário (7 dígitos)
      if (payload.destinatario.codigoCidade != null &&
          payload.destinatario.codigoCidade!.isNotEmpty)
        'codigo_municipio_destinatario': payload.destinatario.codigoCidade!,
      if (payload.destinatario.email != null)
        'email_destinatario': payload.destinatario.email,

      // ─── Items (produtos) ───
      'items': payload.itens.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final ncmValue = (item.ncm != null && item.ncm!.trim().isNotEmpty)
            ? item.ncm!.trim()
            : '99999999';

        final itemMap = <String, dynamic>{
          'numero_item': idx + 1,
          'codigo_produto': (item.codigoProduto != null && item.codigoProduto!.trim().isNotEmpty)
              ? item.codigoProduto!.trim()
              : 'REF-${idx + 1}',
          'descricao': item.descricao,
          'codigo_ncm': ncmValue,
          'cfop': item.cfop ?? '5102',
          'unidade_comercial': item.unidade,
          'quantidade_comercial': item.quantidade,
          'valor_unitario_comercial': item.valorUnitario,
          'valor_bruto': item.valorTotal,
        };

        // Imposto do item — campos planos (Focus NFe v2)
        final csosn = item.cstIcms ?? '400';
        itemMap['icms_situacao_tributaria'] = csosn;
        itemMap['icms_origem'] = 0; // Nacional
        itemMap['pis_situacao_tributaria'] = '07';
        itemMap['cofins_situacao_tributaria'] = '07';

        return itemMap;
      }).toList(),

      // ─── Pagamento ───
      'forma_pagamento': _codigoFormaPagamento(payload.pagamento.formaPagamento),
      'valor_pagamento': payload.pagamento.valorPago,

      // ─── Totais ───
      'valor_produtos': payload.totais.valorProdutos,
      'valor_total': payload.totais.valorTotal,
      'valor_frete': payload.totais.valorFrete,
      'valor_desconto': payload.totais.valorDesconto,
      'base_calculo_icms': payload.totais.baseCalculoIcms,
      'valor_icms': payload.totais.valorIcms,

      // ─── Metadados ───
      'natureza_operacao':
          payload.naturezaOperacao ?? 'Venda de mercadoria',
      'serie': payload.serie ?? '1',
      'numero': payload.numero ??
          DateTime.now().millisecondsSinceEpoch.toString().substring(5),
      'data_emissao': DateTime.now().toIso8601String(),
      'tipo_documento': 1, // 1=saída (NF-e de venda)
      'modalidade_frete': 9, // 9=sem frete (venda digital)
      'finalidade_emissao': 1, // 1=normal
      'informacoes_adicionais': payload.informacoesAdicionais,
    };
  }

  // ─── Helpers ───

  FiscalProviderResult _parseEmitirResponse(
    Map<String, dynamic> result,
    String integrationId,
  ) {
    final sucesso = result['sucesso'] == true;
    final chave = result['chave_acesso'] as String?;
    final protocolo = result['protocolo'] as String?;
    final numero = result['numero'] as String?;
    final serie = result['serie'] as String?;
    final xmlUrl = result['xml_url'] as String?;
    final pdfUrl = result['pdf_url'] as String?;
    final status = result['status'] as String? ?? 'erro';
    final mensagem = result['mensagem'] as String?;
    final erro = result['erro'] as String?;
    final providerResponse = result['provider_response'] as String?;

    // ─── Campos estruturados de erro ───
    final focusStatusCode = result['focusStatusCode'] as int? ?? result['focus_status_code'] as int?;
    final focusResponse = result['focusResponse'] as String? ?? result['focus_response'] as String?;
    final sefazCode = result['sefazCode'] as String? ?? result['sefaz_code'] as String?;
    final sefazMessage = result['sefazMessage'] as String? ?? result['sefaz_message'] as String?;
    final validationErrors = (result['validationErrors'] as List<dynamic>?)
            ?.cast<String>() ??
        (result['erros_validacao'] as List<dynamic>?)?.cast<String>() ??
        [];

    // ═══ Erro de validação de payload (dados obrigatórios ausentes) ═══
    if (status == 'erro_validacao') {
      final errosValidacao = validationErrors.isNotEmpty
          ? validationErrors
          : ((result['erros_validacao'] as List<dynamic>?)
                  ?.cast<String>() ??
              []);
      final errosStr = errosValidacao.join('\n• ');
      final msgFinal = errosValidacao.isNotEmpty
          ? '$mensagem\n\n• $errosStr'
          : (mensagem ?? erro ?? 'Erro de validação do payload fiscal.');

      return FiscalProviderResult(
        sucesso: false,
        erro: msgFinal,
        mensagem: msgFinal,
        statusEnvio: 'erro_validacao',
        providerResponse: providerResponse,
        focusStatusCode: focusStatusCode,
        focusResponse: focusResponse,
        sefazCode: sefazCode,
        sefazMessage: sefazMessage,
        validationErrors: validationErrors,
      );
    }

    // ═══ Erro de integração ou certificado ═══
    if (status == 'erro_integracao' || status == 'erro_certificado') {
      return FiscalProviderResult(
        sucesso: false,
        erro: mensagem ?? erro ?? 'Erro de integração fiscal.',
        mensagem: mensagem,
        statusEnvio: status,
        providerResponse: providerResponse,
        focusStatusCode: focusStatusCode,
        focusResponse: focusResponse,
        sefazCode: sefazCode,
        sefazMessage: sefazMessage,
        validationErrors: validationErrors,
      );
    }

    // ═══ Erro de comunicação ou genérico ═══
    if (status == 'erro_comunicacao' || status == 'erro') {
      return FiscalProviderResult(
        sucesso: false,
        erro: mensagem ?? erro ?? 'Erro de comunicação.',
        mensagem: mensagem,
        statusEnvio: status,
        providerResponse: providerResponse,
        focusStatusCode: focusStatusCode,
        focusResponse: focusResponse,
        sefazCode: sefazCode,
        sefazMessage: sefazMessage,
        validationErrors: validationErrors,
      );
    }

    // Se ainda estiver processando
    if (status == 'processando' || status == 'pendente') {
      return FiscalProviderResult(
        sucesso: true,
        chaveAcesso: chave,
        numero: numero,
        serie: serie,
        mensagem: mensagem ?? 'NF-e enviada, aguardando processamento.',
        statusEnvio: 'processando',
        providerResponse: providerResponse,
      );
    }

    return FiscalProviderResult(
      sucesso: sucesso,
      chaveAcesso: chave,
      protocolo: protocolo,
      numero: numero,
      serie: serie,
      xmlUrl: xmlUrl,
      pdfUrl: pdfUrl,
      mensagem: mensagem,
      erro: erro,
      statusEnvio: sucesso ? 'autorizada' : 'rejeitada',
      providerResponse: providerResponse,
      focusStatusCode: focusStatusCode,
      focusResponse: focusResponse,
      sefazCode: sefazCode,
      sefazMessage: sefazMessage,
      validationErrors: validationErrors,
    );
  }

  String _mensagemErro(Object e) {
    final msg = e.toString();
    debugPrint('[FocusNFeProvider] _mensagemErro: $msg');

    if (e is CallableHttpException) {
      // Extrai a mensagem real do erro retornado pela Cloud Function
      debugPrint(
        '[FocusNFeProvider] CallableHttpException: code=${e.code} message=${e.message}',
      );
      final m = e.message.trim();
      if (m.isNotEmpty) return m;
      // Se não tiver mensagem, usa o código traduzido
      final c = e.code.toLowerCase();
      if (c.contains('not_found') || c == 'not-found') {
        return 'Integração fiscal não encontrada. Publique as Cloud Functions mais recentes.';
      }
      if (c.contains('unauthenticated') || c == 'unauthenticated') {
        return 'Sessão expirada. Faça login novamente.';
      }
      if (c.contains('permission_denied') ||
          c == 'permission-denied') {
        return 'Você não tem permissão para acessar esta nota fiscal.';
      }
      if (c.contains('invalid_argument') ||
          c == 'invalid-argument') {
        return 'Dados inválidos enviados para o servidor fiscal.';
      }
      if (c.contains('failed_precondition') ||
          c == 'failed-precondition') {
        return 'Pré-condição não atendida: $m';
      }
      if (c.contains('internal')) {
        return 'Erro interno no servidor fiscal. Tente novamente.';
      }
      return 'Erro na Cloud Function: $m';
    }

    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'Tempo limite excedido ao comunicar com o servidor fiscal.';
    }
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'Não foi possível conectar ao servidor fiscal.';
    }
    return 'Erro na emissão: $msg';
  }

  String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Converte regime tributário textual para valor numérico Focus NFe (1-3).
  /// 1 = Simples Nacional / MEI, 2 = Excesso sublimite, 3 = Normal
  static int _calcRegimeFocus(String? regime) {
    final r = regime?.trim().toLowerCase() ?? '';
    // MEI é uma categoria do Simples Nacional na SEFAZ (CRT=1, use CSOSN)
    if (r.isEmpty || r == 'simples nacional' || r == 'simples_nacional' || r == 'simples' || r == 'mei') return 1;
    if (r.contains('normal') || r == '3') return 3;
    if (r == '1') return 1;
    return 1; // fallback
  }

  /// Remove todos os caracteres não-dígitos de uma string.
  static String _apenasDigitos(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  /// Converte forma de pagamento textual para código numérico de 2 dígitos NF-e.
  /// Mapeamento compatível com fiscal_xml_builder.dart e Tabela de Formas de Pagamento SPED.
  static String _codigoFormaPagamento(String forma) {
    switch (forma.trim().toLowerCase()) {
      case 'dinheiro': return '01';
      case 'cheque': return '02';
      case 'credito':
      case 'crédito':
      case 'cartao credito':
      case 'cartão crédito':
      case 'cartão de crédito': return '03';
      case 'debito':
      case 'débito':
      case 'cartao debito':
      case 'cartão débito':
      case 'cartão de débito': return '04';
      case 'credito_loja':
      case 'crédito loja': return '05';
      case 'vale_alimentacao':
      case 'vale alimentação': return '10';
      case 'vale_refeicao':
      case 'vale refeição': return '11';
      case 'boleto':
      case 'boleto bancário': return '15';
      case 'pix': return '17';
      case 'transferencia':
      case 'transferência':
      case 'transferência bancária': return '18';
      case 'sem_pagamento': return '90';
      case 'outros':
      case 'outro': return '99';
      case 'a vista':
      case 'à vista':
      case 'àvista':
      case 'avista': return '01';
      default: return '99'; // Outros
    }
  }
}
