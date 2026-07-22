import 'dart:convert';
import '../fiscal_payload.dart';
import '../fiscal_provider.dart';
import '../fiscal_provider_http.dart';

/// Provider fiscal generico para API personalizada.
///
/// Permite configurar:
/// - Metodo de autenticacao: Bearer, Basic, API Key (header), OAuth2, ou none
/// - Endpoints de emissao e cancelamento
/// - Headers personalizados
/// - URLs de sandbox e producao
class CustomFiscalProvider implements FiscalProvider {
  @override
  String get id => 'custom';

  @override
  String get nome => 'API Personalizada';

  @override
  FiscalProviderInfo get info => const FiscalProviderInfo(
        id: 'custom',
        nome: 'API Personalizada',
        descricao:
            'Conecte-se a qualquer API fiscal atraves de configuracao '
            'personalizada de endpoints e autenticacao.',
        documentosSuportados: ['nfe', 'nfce', 'nfse'],
        temHomologacao: true,
      );

  @override
  List<String> get documentosSuportados => info.documentosSuportados;

  /// Monta os headers de autenticacao com base na configuracao.
  Map<String, String> _authHeaders(Map<String, dynamic> config) {
    final metodo =
        (config['metodo_autenticacao'] as String? ?? 'bearer').toLowerCase();
    final headers = <String, String>{};

    switch (metodo) {
      case 'bearer':
        final token = config['api_key'] as String?;
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        break;
      case 'basic':
        final username = config['client_id'] as String? ?? '';
        final password = config['client_secret'] as String? ?? '';
        if (username.isNotEmpty || password.isNotEmpty) {
          final credentials = base64Encode(utf8.encode('$username:$password'));
          headers['Authorization'] = 'Basic $credentials';
        }
        break;
      case 'api_key_header':
        final apiKey = config['api_key'] as String?;
        if (apiKey != null && apiKey.isNotEmpty) {
          headers['X-API-Key'] = apiKey;
        }
        break;
      case 'oauth2':
        final accessToken = config['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $accessToken';
        }
        break;
      case 'none':
      default:
        break;
    }

    // Headers personalizados adicionais
    final customHeaders = config['custom_headers'] as Map<String, dynamic>?;
    if (customHeaders != null) {
      customHeaders.forEach((key, value) {
        if (value is String) {
          headers[key] = value;
        }
      });
    }

    return headers;
  }

  /// Resolve a URL base para o ambiente atual.
  String _resolverUrl(Map<String, dynamic> config, String tipo) {
    final env = config['environment'] as String? ?? 'homologacao';
    final endpoints = config['endpoints'] as Map<String, dynamic>?;

    // Tenta endpoint especifico primeiro
    if (endpoints != null) {
      final endpointKey = '$tipo\_$env';
      final url = endpoints[endpointKey] as String?;
      if (url != null && url.isNotEmpty) return url;
    }

    // Fallback para campos diretos
    if (tipo == 'emissao') {
      final url = config['endpoint_emissao'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    if (tipo == 'cancelamento') {
      final url = config['endpoint_cancelamento'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }

    return '';
  }

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

      final urlStr = _resolverUrl(config, 'emissao');
      if (urlStr.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro:
              'Endpoint de emissao nao configurado. Configure a URL de emissao.',
          statusEnvio: 'erro',
        );
      }

      final body = converterParaFormatoProvedor(payload, config);
      final url = Uri.parse(urlStr);

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(config),
        body: jsonEncode(body),
      );

      return FiscalProviderHttp.parseResponse(
        response,
        providerId: id,
        acao: 'emitir',
        onSuccess: (json) {
          return FiscalProviderResult(
            sucesso: true,
            chaveAcesso: json['chave_acesso'] as String? ??
                json['chaveAcesso'] as String?,
            protocolo: json['protocolo'] as String? ??
                json['protocol'] as String?,
            numero: json['numero']?.toString() ??
                json['number']?.toString(),
            serie: json['serie']?.toString() ??
                json['series']?.toString() ??
                payload.serie,
            xmlUrl: json['xml_url'] as String? ??
                json['xmlUrl'] as String?,
            pdfUrl: json['pdf_url'] as String? ??
                json['pdfUrl'] as String?,
            mensagem: 'NF-e emitida com sucesso via API personalizada.',
            statusEnvio: 'enviada',
            providerResponse: response.body,
          );
        },
      );
    } catch (e) {
      return FiscalProviderHttp.handleException(e, providerId: id);
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

      final urlStr = _resolverUrl(config, 'cancelamento');
      if (urlStr.isEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro:
              'Endpoint de cancelamento nao configurado. Configure a URL de cancelamento.',
          statusEnvio: 'erro',
        );
      }

      final url = Uri.parse(urlStr);

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(config),
        body: jsonEncode({
          'chave_acesso': chaveAcesso,
          'justificativa': justificativa,
          'protocolo': numeroProtocolo,
        }),
      );

      return FiscalProviderHttp.parseResponse(
        response,
        providerId: id,
        acao: 'cancelar',
        onSuccess: (json) {
          return FiscalProviderResult(
            sucesso: true,
            chaveAcesso: chaveAcesso,
            protocolo: json['protocolo'] as String?,
            mensagem: 'Cancelamento realizado com sucesso.',
            statusEnvio: 'cancelada',
            providerResponse: response.body,
          );
        },
      );
    } catch (e) {
      return FiscalProviderHttp.handleException(e, providerId: id);
    }
  }

  @override
  Future<FiscalProviderResult> enviarCartaCorrecao({
    required String chaveAcesso,
    required String textoCorrecao,
    required int sequencia,
    required Map<String, dynamic> config,
  }) async {
    return FiscalProviderResult(
      sucesso: false,
      erro:
          'Carta de Correcao requer configuracao especifica na API personalizada. '
          'Configure um endpoint de CC-e ou utilize outro provedor.',
      statusEnvio: 'erro',
    );
  }

  @override
  Future<FiscalProviderResult> inutilizarNumeracao({
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    required String justificativa,
    required Map<String, dynamic> config,
  }) async {
    return FiscalProviderResult(
      sucesso: false,
      erro:
          'Inutilizacao de numeracao requer configuracao especifica na API personalizada. '
          'Configure um endpoint de inutilizacao ou utilize outro provedor.',
      statusEnvio: 'erro',
    );
  }

  @override
  Future<bool> testarConexao(Map<String, dynamic> config) async {
    try {
      final apiKey = config['api_key'] as String?;
      if (apiKey == null || apiKey.isEmpty) return false;

      final urlStr = config['endpoint_emissao'] as String?;
      if (urlStr == null || urlStr.isEmpty) return false;

      final url = Uri.parse(urlStr);
      final response = await FiscalProviderHttp.get(
        url,
        headers: _authHeaders(config),
      );

      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  @override
  Map<String, String>? validarConfiguracao(Map<String, dynamic> config) {
    final erros = <String, String>{};
    final metodo =
        (config['metodo_autenticacao'] as String? ?? 'bearer').toLowerCase();

    // Valida credenciais conforme metodo
    switch (metodo) {
      case 'bearer':
      case 'api_key_header':
        if (config['api_key'] == null ||
            (config['api_key'] as String).isEmpty) {
          erros['api_key'] = 'API Key e obrigatoria para este metodo';
        }
        break;
      case 'basic':
        if (config['client_id'] == null ||
            (config['client_id'] as String).isEmpty) {
          erros['client_id'] = 'Username e obrigatorio para Basic Auth';
        }
        break;
      case 'oauth2':
        if (config['access_token'] == null ||
            (config['access_token'] as String).isEmpty) {
          erros['access_token'] =
              'Access Token e obrigatorio para OAuth 2.0';
        }
        break;
    }

    return erros.isEmpty ? null : erros;
  }

  @override
  Map<String, dynamic> converterParaFormatoProvedor(
    FiscalPayload payload,
    Map<String, dynamic> config,
  ) {
    // Formato generico padrao
    return {
      'emitente': {
        'cnpj': payload.emitente.cnpj,
        'razao_social': payload.emitente.razaoSocial,
        if (payload.emitente.nomeFantasia.trim().isNotEmpty)
          'nome_fantasia': payload.emitente.nomeFantasia.trim(),
        'ie': payload.emitente.ie,
      },
      'destinatario': {
        'nome': payload.destinatario.nome,
        if (payload.destinatario.cpfCnpj != null)
          'cpf_cnpj': payload.destinatario.cpfCnpj,
        if (payload.destinatario.email != null)
          'email': payload.destinatario.email,
      },
      'itens': payload.itens.map((item) => {
            'codigo': item.codigoProduto ?? '',
            'descricao': item.descricao,
            'ncm': item.ncm ?? '99999999',
            'quantidade': item.quantidade,
            'valor_unitario': item.valorUnitario,
            'valor_total': item.valorTotal,
          }).toList(),
      'serie': payload.serie ?? '1',
      'numero': payload.numero,
      'valor_total': payload.totais.valorTotal,
      'natureza_operacao':
          payload.naturezaOperacao ?? 'Venda de mercadoria',
      'informacoes_adicionais': payload.informacoesAdicionais,
    };
  }
}
