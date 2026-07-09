import 'dart:convert';
import '../fiscal_payload.dart';
import '../fiscal_provider.dart';
import '../fiscal_provider_http.dart';

/// Provider para Nuvem Fiscal (https://nuvemfiscal.com.br).
///
/// API completa para NF-e, NFC-e, NFS-e, CT-e, MDF-e.
/// Autenticacao via OAuth 2.0 (client_credentials).
/// Token obtido com Client ID + Client Secret, com cache em memoria de 1h.
///
/// Homologacao: https://sandbox-api.nuvemfiscal.com.br
/// Producao:    https://api.nuvemfiscal.com.br
class NuvemFiscalProvider implements FiscalProvider {
  @override
  String get id => 'nuvem_fiscal';

  @override
  String get nome => 'Nuvem Fiscal';

  @override
  FiscalProviderInfo get info => const FiscalProviderInfo(
        id: 'nuvem_fiscal',
        nome: 'Nuvem Fiscal',
        descricao:
            'API completa para NF-e, NFC-e, NFS-e, CT-e e MDF-e com OAuth 2.0.',
        documentosSuportados: ['nfe', 'nfce', 'nfse', 'cte', 'mdfe'],
        site: 'https://nuvemfiscal.com.br',
        temHomologacao: true,
      );

  @override
  List<String> get documentosSuportados => info.documentosSuportados;

  /// Cache do access token em memoria.
  String? _accessToken;
  DateTime? _tokenExpiresAt;

  String _baseUrl(Map<String, dynamic> config) {
    final env = config['environment'] as String? ?? 'homologacao';
    final sandbox = config['base_url_sandbox'] as String?;
    final production = config['base_url_production'] as String?;
    if (env == 'producao' && production != null && production.isNotEmpty) {
      return production;
    }
    if (env != 'producao' && sandbox != null && sandbox.isNotEmpty) {
      return sandbox;
    }
    return env == 'producao'
        ? 'https://api.nuvemfiscal.com.br'
        : 'https://sandbox-api.nuvemfiscal.com.br';
  }

  /// Obtem um access token via OAuth 2.0 (client_credentials).
  ///
  /// Faz cache do token em memoria com validade de 1 hora.
  /// Se o token estiver proximo do vencimento (5 min de margem),
  /// renova automaticamente.
  Future<String?> _obterAccessToken(Map<String, dynamic> config) async {
    // Verifica cache
    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        DateTime.now().isBefore(
            _tokenExpiresAt!.subtract(const Duration(minutes: 5)))) {
      return _accessToken;
    }

    final clientId = config['client_id'] as String?;
    final clientSecret = config['client_secret'] as String?;

    if (clientId == null ||
        clientId.isEmpty ||
        clientSecret == null ||
        clientSecret.isEmpty) {
      return null;
    }

    try {
      final baseUrl = _baseUrl(config);
      final url = Uri.parse('$baseUrl/oauth/token');

      final credentials = base64Encode(
        utf8.encode('$clientId:$clientSecret'),
      );

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = json['access_token'] as String?;
        final expiresIn = json['expires_in'] as int? ?? 3600;
        _tokenExpiresAt =
            DateTime.now().add(Duration(seconds: expiresIn));
        return _accessToken;
      }
    } catch (_) {
      // Falha silenciosa - tenta novamente na proxima chamada
    }

    return null;
  }

  Map<String, String> _authHeaders(String? token) {
    return {
      'Authorization': 'Bearer $token',
    };
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

      final token = await _obterAccessToken(config);
      if (token == null) {
        return FiscalProviderResult(
          sucesso: false,
          erro:
              'Falha ao obter token OAuth 2.0. Verifique Client ID e Client Secret.',
          statusEnvio: 'erro',
        );
      }

      final body = converterParaFormatoProvedor(payload, config);
      final baseUrl = _baseUrl(config);
      final url = Uri.parse('$baseUrl/nfe');

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(token),
        body: jsonEncode(body),
      );

      return FiscalProviderHttp.parseResponse(
        response,
        providerId: id,
        acao: 'emitir',
        onSuccess: (json) {
          final chave = json['chave_acesso'] as String?;
          final protocolo = json['protocolo'] as String?;
          final numero = json['numero']?.toString() ??
              json['numero_nfe']?.toString();
          final status = json['status'] as String?;

          final sucesso = status == 'autorizado' ||
              status == 'aprovado' ||
              status == 'concluido';

          return FiscalProviderResult(
            sucesso: sucesso,
            chaveAcesso: chave,
            protocolo: protocolo,
            numero: numero,
            serie: payload.serie ?? '1',
            mensagem: sucesso
                ? 'NF-e emitida com sucesso via Nuvem Fiscal.'
                : 'NF-e enviada para processamento.',
            statusEnvio:
                sucesso ? 'autorizada' : (status ?? 'processando'),
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

      final token = await _obterAccessToken(config);
      if (token == null) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Falha ao obter token OAuth 2.0.',
          statusEnvio: 'erro',
        );
      }

      final baseUrl = _baseUrl(config);
      // Nuvem Fiscal usa o ID interno da nota, nao chave de acesso
      final documentoId = config['documento_id'] as String? ?? chaveAcesso;
      final url = Uri.parse('$baseUrl/nfe/$documentoId/cancelamento');

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(token),
        body: jsonEncode({
          'justificativa': justificativa,
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
    try {
      final erros = validarConfiguracao(config);
      if (erros != null && erros.isNotEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuracao invalida: ${erros.values.join(', ')}',
          statusEnvio: 'erro',
        );
      }

      final token = await _obterAccessToken(config);
      if (token == null) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Falha ao obter token OAuth 2.0.',
          statusEnvio: 'erro',
        );
      }

      final baseUrl = _baseUrl(config);
      final documentoId = config['documento_id'] as String? ?? chaveAcesso;
      final url = Uri.parse('$baseUrl/nfe/$documentoId/carta-correcao');

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(token),
        body: jsonEncode({
          'correcao': textoCorrecao,
          'sequencia': sequencia,
        }),
      );

      return FiscalProviderHttp.parseResponse(
        response,
        providerId: id,
        acao: 'carta_correcao',
        onSuccess: (json) {
          return FiscalProviderResult(
            sucesso: true,
            chaveAcesso: chaveAcesso,
            protocolo: json['protocolo'] as String?,
            mensagem:
                'Carta de Correcao #$sequencia enviada com sucesso.',
            statusEnvio: 'carta_correcao_enviada',
            providerResponse: response.body,
          );
        },
      );
    } catch (e) {
      return FiscalProviderHttp.handleException(e, providerId: id);
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
    return FiscalProviderResult(
      sucesso: false,
      erro:
          'Inutilizacao de numeracao via Nuvem Fiscal requer configuracao especifica. '
          'Utilize o painel da Nuvem Fiscal.',
      statusEnvio: 'erro',
    );
  }

  @override
  Future<bool> testarConexao(Map<String, dynamic> config) async {
    try {
      final token = await _obterAccessToken(config);
      if (token == null) return false;

      final baseUrl = _baseUrl(config);
      final url = Uri.parse('$baseUrl/nfe');
      final response = await FiscalProviderHttp.get(
        url,
        headers: _authHeaders(token),
      );

      return response.statusCode == 200 || response.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  @override
  Map<String, String>? validarConfiguracao(Map<String, dynamic> config) {
    final erros = <String, String>{};
    if (config['client_id'] == null ||
        (config['client_id'] as String).isEmpty) {
      erros['client_id'] = 'Client ID (Client ID) e obrigatorio';
    }
    if (config['client_secret'] == null ||
        (config['client_secret'] as String).isEmpty) {
      erros['client_secret'] =
          'Client Secret (Client Secret) e obrigatorio';
    }
    return erros.isEmpty ? null : erros;
  }

  @override
  Map<String, dynamic> converterParaFormatoProvedor(
    FiscalPayload payload,
    Map<String, dynamic> config,
  ) {
    final ambiente =
        config['environment'] == 'producao' ? 'producao' : 'homologacao';
    return {
      'ambiente': ambiente,
      'serie': int.tryParse(payload.serie ?? '1') ?? 1,
      'numero': payload.numero ??
          DateTime.now().millisecondsSinceEpoch.toString().substring(5),
      'natureza_operacao':
          payload.naturezaOperacao ?? 'Venda de mercadoria',
      'emitente': {
        'cnpj': payload.emitente.cnpj,
        'x_nome': payload.emitente.razaoSocial,
        'x_fantasia': payload.emitente.nomeFantasia,
        'ie': payload.emitente.ie,
        if (payload.emitente.crt != null)
          'CRT': int.tryParse(payload.emitente.crt!) ?? 3,
        'ender_emit': {
          'x_lgr': payload.emitente.logradouro,
          'nro': payload.emitente.numero,
          if (payload.emitente.complemento != null)
            'x_cpl': payload.emitente.complemento,
          'x_bairro': payload.emitente.bairro,
          'x_mun': payload.emitente.cidade,
          'uf': payload.emitente.uf,
          'cep': payload.emitente.cep,
          if (payload.emitente.codigoCidade != null)
            'c_mun': payload.emitente.codigoCidade,
        },
      },
      'destinatario': {
        if (payload.destinatario.cpfCnpj != null &&
            payload.destinatario.cpfCnpj!.isNotEmpty)
          'cnpj_cpf': payload.destinatario.cpfCnpj,
        'x_nome': payload.destinatario.nome,
        if (payload.destinatario.email != null)
          'email': payload.destinatario.email,
        if (payload.destinatario.logradouro != null)
          'ender_dest': {
            'x_lgr': payload.destinatario.logradouro,
            'nro': payload.destinatario.numero ?? 'S/N',
            if (payload.destinatario.bairro != null)
              'x_bairro': payload.destinatario.bairro,
            if (payload.destinatario.cidade != null)
              'x_mun': payload.destinatario.cidade,
            if (payload.destinatario.uf != null)
              'uf': payload.destinatario.uf,
            if (payload.destinatario.cep != null)
              'cep': payload.destinatario.cep,
          },
      },
      'items': payload.itens.map((item) => {
            'cProd': item.codigoProduto ?? '',
            'xProd': item.descricao,
            'NCM': item.ncm ?? '99999999',
            'CFOP': item.cfop ?? '5102',
            if (item.cest != null) 'CEST': item.cest,
            'uCom': item.unidade,
            'qCom': item.quantidade,
            'vUnCom': item.valorUnitario,
            'vProd': item.valorTotal,
          }).toList(),
      'total': {
        'ICMSTot': {
          'vBC': payload.totais.baseCalculoIcms,
          'vICMS': payload.totais.valorIcms,
          'vProd': payload.totais.valorProdutos,
          'vDesc': payload.totais.valorDesconto,
          'vFrete': payload.totais.valorFrete,
          'vNF': payload.totais.valorTotal,
        },
      },
      'pagamento': {
        'detPag': [
          {
            'tPag': payload.pagamento.formaPagamento,
            'vPag': payload.pagamento.valorPago,
          }
        ],
      },
      'infAdFisco': payload.informacoesAdicionais,
    };
  }
}
