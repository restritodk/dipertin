import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fiscal_provider.dart';
import 'fiscal_audit_service.dart';

/// Helpers HTTP para provedores fiscais.
///
/// Encapsula chamadas HTTP comuns com:
/// - Timeout padrao de 60s
/// - Tratamento de erro padrao (SocketException, TimeoutException, HttpException)
/// - Parse de resposta para [FiscalProviderResult]
/// - Log de erro tecnico via [FiscalAuditService]
abstract final class FiscalProviderHttp {
  static const Duration _timeout = Duration(seconds: 60);

  /// POST JSON para uma URL.
  static Future<http.Response> postJson(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final h = _baseHeaders(headers);
    return http
        .post(url, headers: h, body: body is String ? body : jsonEncode(body))
        .timeout(_timeout);
  }

  /// GET para uma URL.
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final h = _baseHeaders(headers);
    return http.get(url, headers: h).timeout(_timeout);
  }

  /// PUT JSON para uma URL.
  static Future<http.Response> putJson(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final h = _baseHeaders(headers);
    return http
        .put(url, headers: h, body: body is String ? body : jsonEncode(body))
        .timeout(_timeout);
  }

  /// DELETE para uma URL.
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final h = _baseHeaders(headers);
    return http.delete(url, headers: h).timeout(_timeout);
  }

  /// Headers base para todas as requisicoes.
  static Map<String, String> _baseHeaders(Map<String, String>? extra) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  /// Converte uma resposta HTTP para [FiscalProviderResult].
  ///
  /// [providerId] ID do provedor para log.
  /// [storeId] ID da loja para log de auditoria.
  /// Se a resposta for 2xx e o body contiver dados validos, retorna sucesso.
  /// Caso contrario, extrai o erro do body.
  static FiscalProviderResult parseResponse(
    http.Response response, {
    FiscalProviderResult Function(Map<String, dynamic> json)? onSuccess,
    String? providerId,
    String? storeId,
    String? acao,
  }) {
    try {
      final body = response.body;
      Map<String, dynamic> json = {};
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        // body pode ser string simples
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (onSuccess != null) {
          return onSuccess(json);
        }
        return FiscalProviderResult(
          sucesso: true,
          chaveAcesso: json['chave_acesso'] as String? ??
              json['chaveAcesso'] as String?,
          protocolo: json['protocolo'] as String? ??
              json['protocol'] as String?,
          numero: json['numero'] as String? ??
              json['number'] as String? ??
              json['numero_nfe']?.toString(),
          serie: json['serie'] as String? ??
              json['series'] as String?,
          xmlUrl: json['xml'] as String? ??
              json['xml_url'] as String?,
          pdfUrl: json['danfe'] as String? ??
              json['pdf_url'] as String? ??
              json['pdf'] as String?,
          mensagem: 'Operacao realizada com sucesso.',
          statusEnvio: 'enviada',
          providerResponse: body,
        );
      }

      // Erro HTTP
      final erroMsg = json['erro'] as String? ??
          json['error'] as String? ??
          json['mensagem'] as String? ??
          json['message'] as String? ??
          _httpStatusError(response.statusCode);

      final codigoRejeicao = json['codigo']?.toString() ??
          json['code']?.toString() ??
          response.statusCode.toString();

      return FiscalProviderResult(
        sucesso: false,
        erro: erroMsg,
        codigoRejeicao: codigoRejeicao,
        statusEnvio: 'erro',
        providerResponse: body,
      );
    } catch (e) {
      return FiscalProviderResult(
        sucesso: false,
        erro: _exceptionMessage(e),
        statusEnvio: 'erro',
        providerResponse: 'Exception: $e',
      );
    }
  }

  /// Traduz excecoes de IO/Timeout para mensagens amigaveis.
  static FiscalProviderResult handleException(
    Object e, {
    String? providerId,
    String? storeId,
    String? acao,
  }) {
    final erro = _exceptionMessage(e);
    return FiscalProviderResult(
      sucesso: false,
      erro: erro,
      statusEnvio: 'erro',
      providerResponse: 'Exception: $e',
    );
  }

  static String _httpStatusError(int status) {
    switch (status) {
      case 400:
        return 'Requisicao invalida. Verifique os dados enviados.';
      case 401:
        return 'Token/API Key invalido ou nao autorizado.';
      case 403:
        return 'Sem permissao para acessar o recurso.';
      case 404:
        return 'Recurso nao encontrado no provedor fiscal.';
      case 422:
        return 'Dados da NF-e rejeitados pela SEFAZ.';
      case 429:
        return 'Muitas requisicoes. Aguarde e tente novamente.';
      case 500:
        return 'Erro interno do provedor fiscal. Tente novamente mais tarde.';
      case 502:
      case 503:
        return 'Provedor fiscal temporariamente indisponivel.';
      default:
        return 'Erro HTTP $status na comunicacao com o provedor fiscal.';
    }
  }

  static String _exceptionMessage(Object e) {
    final msg = e.toString();
    if (msg.contains('TimeoutException')) {
      return 'Tempo limite excedido ao comunicar com o provedor fiscal.';
    }
    if (msg.contains('SocketException')) {
      return 'Nao foi possivel conectar ao provedor fiscal. Verifique sua internet.';
    }
    if (msg.contains('HttpException')) {
      return 'Erro de comunicacao com o provedor fiscal.';
    }
    return 'Erro interno: $e';
  }
}
