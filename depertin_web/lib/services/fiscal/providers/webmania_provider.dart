import 'package:cloud_functions/cloud_functions.dart';
import '../fiscal_payload.dart';
import '../fiscal_provider.dart';

/// Provider para WebmaniaBR (https://webmaniabr.com).
///
/// API REST para emissao de NF-e e NFC-e.
/// Autenticacao via OAuth 1.0a (Consumer Key + Consumer Secret + Access Token + Access Token Secret).
///
/// ⚠️ OAuth 1.0a requer assinatura HMAC-SHA1 complexa no backend.
/// Este provider chama a Cloud Function `proxyWebmaniaNFe` que faz a
/// assinatura OAuth 1.0a no servidor, mantendo as credenciais seguras.
class WebmaniaProvider implements FiscalProvider {
  @override
  String get id => 'webmania_br';

  @override
  String get nome => 'WebmaniaBR';

  @override
  FiscalProviderInfo get info => const FiscalProviderInfo(
        id: 'webmania_br',
        nome: 'WebmaniaBR',
        descricao: 'API REST para emissao de NF-e e NFC-e.',
        documentosSuportados: ['nfe', 'nfce'],
        site: 'https://webmaniabr.com',
        temHomologacao: true,
      );

  @override
  List<String> get documentosSuportados => info.documentosSuportados;

  @override
  Future<FiscalProviderResult> emitirNota(
    FiscalPayload payload,
    Map<String, dynamic> config,
  ) async {
    try {
      final erros = validarConfiguracao(config);
      if (erros != null && erros.isNotEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuracao invalida: ${erros.values.join(', ')}',
          statusEnvio: 'erro',
        );
      }

      final body = converterParaFormatoProvedor(payload, config);
      final credentials = _extrairCredentials(config);

      return await _chamarFunctionProxy(
        'proxyWebmaniaEmitirNota',
        {
          'credentials': credentials,
          'payload': body,
        },
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: 'Erro ao emitir NF-e via WebmaniaBR: $e',
        statusEnvio: 'erro',
        providerResponse: 'Exception: $e',
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

      final credentials = _extrairCredentials(config);

      return await _chamarFunctionProxy(
        'proxyWebmaniaCancelarNota',
        {
          'credentials': credentials,
          'chave_acesso': chaveAcesso,
          'motivo': justificativa,
        },
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: 'Erro ao cancelar NF-e via WebmaniaBR: $e',
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

      final credentials = _extrairCredentials(config);

      return await _chamarFunctionProxy(
        'proxyWebmaniaCartaCorrecao',
        {
          'credentials': credentials,
          'chave_acesso': chaveAcesso,
          'correcao': textoCorrecao,
          'sequencia': sequencia,
        },
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: 'Erro ao enviar Carta de Correcao via WebmaniaBR: $e',
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

      final credentials = _extrairCredentials(config);

      return await _chamarFunctionProxy(
        'proxyWebmaniaInutilizar',
        {
          'credentials': credentials,
          'serie': serie,
          'numero_inicial': numeroInicial,
          'numero_final': numeroFinal,
          'justificativa': justificativa,
        },
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: 'Erro ao inutilizar numeracao via WebmaniaBR: $e',
        statusEnvio: 'erro',
      );
    }
  }

  @override
  Future<bool> testarConexao(Map<String, dynamic> config) async {
    try {
      final consumerKey = config['consumer_key'] as String?;
      final consumerSecret = config['consumer_secret'] as String?;
      final accessToken = config['access_token'] as String?;
      final accessTokenSecret = config['access_token_secret'] as String?;

      if (consumerKey == null || consumerKey.isEmpty) return false;
      if (consumerSecret == null || consumerSecret.isEmpty) return false;
      if (accessToken == null || accessToken.isEmpty) return false;
      if (accessTokenSecret == null || accessTokenSecret.isEmpty) return false;

      final credentials = _extrairCredentials(config);

      final result = await _chamarFunctionProxy(
        'proxyWebmaniaTestarConexao',
        {'credentials': credentials},
      );

      return result.sucesso;
    } catch (_) {
      return false;
    }
  }

  @override
  Map<String, String>? validarConfiguracao(Map<String, dynamic> config) {
    final erros = <String, String>{};
    if (config['consumer_key'] == null ||
        (config['consumer_key'] as String).isEmpty) {
      erros['consumer_key'] = 'Consumer Key e obrigatorio';
    }
    if (config['consumer_secret'] == null ||
        (config['consumer_secret'] as String).isEmpty) {
      erros['consumer_secret'] = 'Consumer Secret e obrigatorio';
    }
    if (config['access_token'] == null ||
        (config['access_token'] as String).isEmpty) {
      erros['access_token'] = 'Access Token e obrigatorio';
    }
    if (config['access_token_secret'] == null ||
        (config['access_token_secret'] as String).isEmpty) {
      erros['access_token_secret'] = 'Access Token Secret e obrigatorio';
    }
    return erros.isEmpty ? null : erros;
  }

  @override
  Map<String, dynamic> converterParaFormatoProvedor(
    FiscalPayload payload,
    Map<String, dynamic> config,
  ) {
    return {
      'ambiente': config['environment'] ?? 'homologacao',
      'serie': payload.serie ?? '1',
      'numero': payload.numero ??
          DateTime.now().millisecondsSinceEpoch.toString().substring(5),
      'natureza_operacao':
          payload.naturezaOperacao ?? 'Venda de mercadoria',
      'modelo': payload.tipoDocumento.codigo == 'nfce' ? '65' : '55',
      'finalidade': payload.finalidade,
      'operacao': payload.tipoOperacao,
      'destinatario': {
        'cpf_cnpj': payload.destinatario.cpfCnpj ?? '000.000.000-00',
        'nome': payload.destinatario.nome,
        'ie': payload.destinatario.ie ?? '',
        'endereco': payload.destinatario.logradouro ?? '',
        'numero': payload.destinatario.numero ?? '',
        'bairro': payload.destinatario.bairro ?? '',
        'cidade': payload.destinatario.cidade ?? '',
        'uf': payload.destinatario.uf ?? '',
        'cep': payload.destinatario.cep ?? '',
      },
      'produtos': payload.itens.map((item) => {
            'codigo': item.codigoProduto ?? '',
            'nome': item.descricao,
            'ncm': item.ncm ?? '99999999',
            'quantidade': item.quantidade,
            'valor_unitario': item.valorUnitario,
            'valor_total': item.valorTotal,
            'unidade': item.unidade,
          }).toList(),
      'pedido': {
        'valor': payload.totais.valorTotal,
        'origem': payload.pedidoId ?? '',
      },
      'transporte': {
        'frete': payload.totais.valorFrete > 0
            ? 'por_conta_destinatario'
            : 'sem_frete',
      },
    };
  }

  /// Extrai as credenciais OAuth 1.0a da configuracao, removendo
  /// dados sensiveis do payload que vai para o frontend.
  Map<String, dynamic> _extrairCredentials(Map<String, dynamic> config) {
    return {
      'consumer_key': config['consumer_key'] ?? '',
      'consumer_secret': config['consumer_secret'] ?? '',
      'access_token': config['access_token'] ?? '',
      'access_token_secret': config['access_token_secret'] ?? '',
      'environment': config['environment'] ?? 'homologacao',
    };
  }

  /// Chama a Cloud Function proxy que faz a assinatura OAuth 1.0a.
  ///
  /// As credenciais sao enviadas criptografadas e a Function as
  /// descriptografa no backend para fazer a chamada a API da WebmaniaBR.
  static Future<FiscalProviderResult> _chamarFunctionProxy(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(functionName)
          .call(data);

      final response =
          result.data as Map<String, dynamic>;

      return FiscalProviderResult(
        sucesso: response['sucesso'] as bool? ?? false,
        chaveAcesso: response['chave_acesso'] as String?,
        protocolo: response['protocolo'] as String?,
        numero: response['numero']?.toString(),
        serie: response['serie']?.toString(),
        xmlUrl: response['xml_url'] as String?,
        pdfUrl: response['pdf_url'] as String?,
        mensagem: response['mensagem'] as String?,
        erro: response['erro'] as String?,
        statusEnvio: response['status'] as String? ?? 'processando',
        codigoRejeicao: response['codigo_rejeicao'] as String?,
        providerResponse: response['provider_response'] as String?,
      );
    } catch (e) {
      String erroMsg;
      if (e is FirebaseFunctionsException) {
        erroMsg = e.message ?? 'Erro na Cloud Function proxy';
      } else {
        erroMsg = 'Erro de comunicacao com o servidor: $e';
      }
      return FiscalProviderResult(
        sucesso: false,
        erro: erroMsg,
        statusEnvio: 'erro',
        providerResponse: 'FirebaseFunctionsException: $e',
      );
    }
  }
}
