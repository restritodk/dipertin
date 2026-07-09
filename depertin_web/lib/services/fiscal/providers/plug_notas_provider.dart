import 'dart:convert';
import '../fiscal_payload.dart';
import '../fiscal_provider.dart';
import '../fiscal_provider_http.dart';

/// Provider para PlugNotas / TecnoSpeed (https://plugnotas.com.br).
///
/// API para emissao de NF-e, NFC-e e NFS-e.
/// Autenticacao via API Key no header X-API-Key.
///
/// Endpoint unico: https://api.plugnotas.com.br
class PlugNotasProvider implements FiscalProvider {
  @override
  String get id => 'plug_notas';

  @override
  String get nome => 'PlugNotas / TecnoSpeed';

  @override
  FiscalProviderInfo get info => const FiscalProviderInfo(
        id: 'plug_notas',
        nome: 'PlugNotas / TecnoSpeed',
        descricao: 'API para emissao de NF-e, NFC-e e NFS-e.',
        documentosSuportados: ['nfe', 'nfce', 'nfse'],
        site: 'https://plugnotas.com.br',
        temHomologacao: true,
      );

  @override
  List<String> get documentosSuportados => info.documentosSuportados;

  static const String _baseUrl = 'https://api.plugnotas.com.br';

  Map<String, String> _authHeaders(Map<String, dynamic> config) {
    final apiKey = config['api_key'] as String? ?? '';
    return {'X-API-Key': apiKey};
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

      final body = converterParaFormatoProvedor(payload, config);
      final url = Uri.parse('$_baseUrl/nfe');

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
          final chave = json['chaveAcesso'] as String? ??
              json['chave_acesso'] as String?;
          final protocolo = json['protocolo'] as String?;
          final numero = json['numero']?.toString() ??
              json['numeroNfe']?.toString();
          final xmlUrl = json['xml'] as String? ??
              json['xml_url'] as String?;
          final danfeUrl = json['danfe'] as String? ??
              json['danfe_url'] as String?;
          final status = json['status'] as String?;

          final sucesso = status == 'autorizado' ||
              status == 'aprovado' ||
              (response.statusCode >= 200 && response.statusCode < 300);

          return FiscalProviderResult(
            sucesso: sucesso,
            chaveAcesso: chave,
            protocolo: protocolo,
            numero: numero,
            serie: payload.serie ?? '1',
            xmlUrl: xmlUrl,
            pdfUrl: danfeUrl,
            mensagem: sucesso
                ? 'NF-e emitida com sucesso via PlugNotas.'
                : 'Falha na emissao.',
            statusEnvio: sucesso ? 'autorizada' : 'rejeitada',
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

      final url = Uri.parse('$_baseUrl/nfe/cancelar');

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(config),
        body: jsonEncode({
          'chave': chaveAcesso,
          'motivo': justificativa,
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

      final url = Uri.parse('$_baseUrl/nfe/carta-correcao');

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(config),
        body: jsonEncode({
          'chave': chaveAcesso,
          'correcao': textoCorrecao,
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
    try {
      final erros = validarConfiguracao(config);
      if (erros != null && erros.isNotEmpty) {
        return FiscalProviderResult(
          sucesso: false,
          erro: 'Configuracao invalida: ${erros.values.join(', ')}',
          statusEnvio: 'erro',
        );
      }

      final url = Uri.parse('$_baseUrl/nfe/inutilizar');

      final response = await FiscalProviderHttp.postJson(
        url,
        headers: _authHeaders(config),
        body: jsonEncode({
          'ambiente': config['environment'] ?? 'homologacao',
          'serie': serie,
          'numeroInicial': numeroInicial,
          'numeroFinal': numeroFinal,
          'justificativa': justificativa,
        }),
      );

      return FiscalProviderHttp.parseResponse(
        response,
        providerId: id,
        acao: 'inutilizar',
        onSuccess: (json) {
          return FiscalProviderResult(
            sucesso: true,
            protocolo: json['protocolo'] as String?,
            mensagem:
                'Numeracao Serie $serie: $numeroInicial-$numeroFinal inutilizada com sucesso.',
            statusEnvio: 'numeracao_inutilizada',
            providerResponse: response.body,
          );
        },
      );
    } catch (e) {
      return FiscalProviderHttp.handleException(e, providerId: id);
    }
  }

  @override
  Future<bool> testarConexao(Map<String, dynamic> config) async {
    try {
      final apiKey = config['api_key'] as String?;
      if (apiKey == null || apiKey.isEmpty) return false;

      final url = Uri.parse('$_baseUrl/nfe');
      final response = await FiscalProviderHttp.get(
        url,
        headers: _authHeaders(config),
      );

      return response.statusCode == 200 || response.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  @override
  Map<String, String>? validarConfiguracao(Map<String, dynamic> config) {
    final erros = <String, String>{};
    if (config['api_key'] == null ||
        (config['api_key'] as String).isEmpty) {
      erros['api_key'] = 'API Key e obrigatoria';
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
      'emitente': {
        'cnpj': payload.emitente.cnpj,
        'razao_social': payload.emitente.razaoSocial,
        'inscricao_estadual': payload.emitente.ie,
        'endereco': {
          'logradouro': payload.emitente.logradouro,
          'numero': payload.emitente.numero,
          'bairro': payload.emitente.bairro,
          'cidade': payload.emitente.cidade,
          'uf': payload.emitente.uf,
          'cep': payload.emitente.cep,
        },
      },
      'destinatario': {
        'nome': payload.destinatario.nome,
        if (payload.destinatario.cpfCnpj != null &&
            payload.destinatario.cpfCnpj!.isNotEmpty)
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
            'unidade': item.unidade,
          }).toList(),
      'valor_total': payload.totais.valorTotal,
      'formas_pagamento': [
        {
          'forma': payload.pagamento.formaPagamento,
          'valor': payload.pagamento.valorPago,
        }
      ],
    };
  }
}
