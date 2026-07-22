import 'dart:convert';
import '../fiscal_payload.dart';
import '../fiscal_provider.dart';
import '../fiscal_provider_http.dart';

/// Provider para Enotas (https://enotas.com.br).
///
/// Plataforma para emissao de notas fiscais de servico (NFS-e) e NF-e.
/// Autenticacao via Bearer Token (API Key).
///
/// Homologacao: https://sandbox.enotas.com.br/v1
/// Producao:    https://api.enotas.com.br/v1
class EnotasProvider implements FiscalProvider {
  @override
  String get id => 'enotas';

  @override
  String get nome => 'Enotas';

  @override
  FiscalProviderInfo get info => const FiscalProviderInfo(
        id: 'enotas',
        nome: 'Enotas',
        descricao:
            'Plataforma para emissao de notas fiscais de servico e NF-e.',
        documentosSuportados: ['nfe', 'nfse'],
        site: 'https://enotas.com.br',
        temHomologacao: true,
      );

  @override
  List<String> get documentosSuportados => info.documentosSuportados;

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
        ? 'https://api.enotas.com.br/v1'
        : 'https://sandbox.enotas.com.br/v1';
  }

  String _empresaId(Map<String, dynamic> config) {
    return config['empresa_id'] as String? ?? '';
  }

  Map<String, String> _authHeaders(Map<String, dynamic> config) {
    final apiKey = config['api_key'] as String? ?? '';
    return {
      'Authorization': 'Bearer $apiKey',
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

      final body = converterParaFormatoProvedor(payload, config);
      final baseUrl = _baseUrl(config);
      final empresaId = _empresaId(config);
      final url = Uri.parse('$baseUrl/empresas/$empresaId/nf-e');

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
          final protocolo = json['protocolo'] as String? ??
              json['numeroProtocolo'] as String?;
          final numero = json['numero']?.toString() ??
              json['numeroNfe']?.toString();
          final xmlUrl = json['xml'] as String? ??
              json['xml_url'] as String?;

          return FiscalProviderResult(
            sucesso: true,
            chaveAcesso: chave,
            protocolo: protocolo,
            numero: numero,
            serie: payload.serie ?? '1',
            xmlUrl: xmlUrl,
            mensagem: 'NF-e emitida com sucesso via Enotas.',
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

      final baseUrl = _baseUrl(config);
      final empresaId = _empresaId(config);
      final url =
          Uri.parse('$baseUrl/empresas/$empresaId/nf-e/$chaveAcesso');

      final response = await FiscalProviderHttp.delete(
        url,
        headers: _authHeaders(config),
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
    // Enotas nao possui endpoint de CC-e documentado publicamente.
    // Retorna erro informativo.
    return FiscalProviderResult(
      sucesso: false,
      erro:
          'Carta de Correcao nao suportada diretamente pela Enotas. '
          'Utilize o painel da Enotas ou outro provedor.',
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
    // Enotas nao possui endpoint de inutilizacao documentado publicamente.
    return FiscalProviderResult(
      sucesso: false,
      erro:
          'Inutilizacao de numeracao nao suportada diretamente pela Enotas. '
          'Utilize o painel da Enotas ou outro provedor.',
      statusEnvio: 'erro',
    );
  }

  @override
  Future<bool> testarConexao(Map<String, dynamic> config) async {
    try {
      final apiKey = config['api_key'] as String?;
      if (apiKey == null || apiKey.isEmpty) return false;

      final baseUrl = _baseUrl(config);
      final url = Uri.parse('$baseUrl/empresas');

      final response = await FiscalProviderHttp.get(
        url,
        headers: _authHeaders(config),
      );

      return response.statusCode == 200;
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
    if (config['empresa_id'] == null ||
        (config['empresa_id'] as String).isEmpty) {
      erros['empresa_id'] = 'ID da empresa na Enotas e obrigatorio';
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
      'modelo': payload.tipoDocumento.codigo == 'nfce' ? '65' : '55',
      'serie': payload.serie ?? '1',
      'numero': payload.numero ??
          DateTime.now().millisecondsSinceEpoch.toString().substring(5),
      'natureza_operacao':
          payload.naturezaOperacao ?? 'Venda de mercadoria',
      'finalidade': payload.finalidade,
      'emitente': {
        'cnpj': payload.emitente.cnpj,
        'razao_social': payload.emitente.razaoSocial,
        if (payload.emitente.nomeFantasia.trim().isNotEmpty)
          'nome_fantasia': payload.emitente.nomeFantasia.trim(),
        'inscricao_estadual': payload.emitente.ie,
        if (payload.emitente.im != null) 'im': payload.emitente.im,
        if (payload.emitente.crt != null)
          'crt': int.tryParse(payload.emitente.crt!),
        'endereco': {
          'logradouro': payload.emitente.logradouro,
          'numero': payload.emitente.numero,
          if (payload.emitente.complemento != null)
            'complemento': payload.emitente.complemento,
          'bairro': payload.emitente.bairro,
          'cidade': payload.emitente.cidade,
          'estado': payload.emitente.uf,
          'cep': payload.emitente.cep,
        },
      },
      'destinatario': {
        if (payload.destinatario.cpfCnpj != null &&
            payload.destinatario.cpfCnpj!.isNotEmpty)
          'cpf_cnpj': payload.destinatario.cpfCnpj,
        'tipo_pessoa': payload.destinatario.cpfCnpj != null &&
                payload.destinatario.cpfCnpj!.length == 14
            ? 'J'
            : 'F',
        'nome': payload.destinatario.nome,
        if (payload.destinatario.email != null)
          'email': payload.destinatario.email,
        if (payload.destinatario.logradouro != null)
          'endereco': {
            'logradouro': payload.destinatario.logradouro,
            if (payload.destinatario.numero != null)
              'numero': payload.destinatario.numero,
            if (payload.destinatario.bairro != null)
              'bairro': payload.destinatario.bairro,
            if (payload.destinatario.cidade != null)
              'cidade': payload.destinatario.cidade,
            if (payload.destinatario.uf != null)
              'uf': payload.destinatario.uf,
            if (payload.destinatario.cep != null)
              'cep': payload.destinatario.cep,
          },
        if (payload.destinatario.ie != null)
          'inscricao_estadual': payload.destinatario.ie,
      },
      'itens': payload.itens.map((item) => {
            'codigo': item.codigoProduto ?? '',
            'descricao': item.descricao,
            'ncm': item.ncm ?? '99999999',
            'cfop': item.cfop ?? '5102',
            if (item.cest != null) 'cest': item.cest,
            if (item.cstIcms != null) 'cst_icms': item.cstIcms,
            'unidade': item.unidade,
            'quantidade': item.quantidade,
            'valor_unitario': item.valorUnitario,
            'valor_total': item.valorTotal,
          }).toList(),
      'totais': {
        'base_calculo_icms': payload.totais.baseCalculoIcms,
        'valor_icms': payload.totais.valorIcms,
        'valor_produtos': payload.totais.valorProdutos,
        'valor_desconto': payload.totais.valorDesconto,
        'valor_frete': payload.totais.valorFrete,
        'valor_total': payload.totais.valorTotal,
      },
      'pagamento': {
        'forma': payload.pagamento.formaPagamento,
        'valor': payload.pagamento.valorPago,
      },
      'informacoes_adicionais': payload.informacoesAdicionais,
    };
  }
}
