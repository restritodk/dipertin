import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// Exceção lançada pelo [callFirebaseFunctionSafe] quando a Cloud Function
/// retorna erro via HTTP. Compatível com catch blocks que usam `.code`/`.message`.
class CallableHttpException implements Exception {
  final String code;
  final String message;
  final dynamic details;
  const CallableHttpException(this.code, this.message, {this.details});

  @override
  String toString() => 'CallableHttpException($code, $message)';
}

/// Mensagem legível quando uma callable (via HTTP no web) falhar.
String mensagemCallableHttpException(CallableHttpException e) {
  final c = e.code.toLowerCase();
  if (c.contains('not_found') || c == 'not-found') {
    return 'Serviço não encontrado. Publique as Cloud Functions mais recentes.';
  }
  if (c.contains('internal') || c == 'internal') {
    return 'Erro interno no servidor. Tente novamente ou contate o suporte.';
  }
  final m = e.message.trim();
  if (m.isNotEmpty) return m;
  return e.code;
}

/// Região do deploy das Cloud Functions principais (`firebase deploy --only functions`).
const String kFirebaseFunctionsRegion = 'us-central1';

/// Região do deploy das Cloud Functions do módulo Gestão Comercial.
const String kFirebaseFunctionsRegionSouth = 'southamerica-east1';

/// Projeto Firebase.
const String _kProjectId = 'depertin-f940f';

/// Chama Cloud Function callable via HTTP POST direto em TODAS as plataformas,
/// contornando o JS interop do dart2js que lança "Int64 accessor not supported
/// by dart2js" e o bug "No such function method" do cloud_functions_web.
///
/// [region] permite escolher a região: 'us-central1' (padrão) ou 'southamerica-east1'.
Future<Map<String, dynamic>> callFirebaseFunctionSafe(
  String functionName, {
  Map<String, dynamic>? parameters,
  Duration timeout = const Duration(seconds: 60),
  String region = kFirebaseFunctionsRegion,
}) async {
  final uri = Uri.parse(
    'https://$region-$_kProjectId'
    '.cloudfunctions.net/$functionName',
  );

  final headers = <String, String>{
    'Content-Type': 'application/json',
  };

  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    try {
      final token = await user.getIdToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      debugPrint('callFirebaseFunctionSafe: getIdToken falhou: $e');
    }
  }

  final body = jsonEncode({'data': parameters ?? {}});

  final response = await http
      .post(uri, headers: headers, body: body)
      .timeout(timeout);

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      // v2 callable retorna HTTP 200 mesmo em erro: {"error": {"status":"...","message":"..."}}
      if (decoded.containsKey('error')) {
        final err = decoded['error'];
        final code = err is Map
            ? (err['status'] ?? err['code'] ?? 'internal').toString()
            : 'internal';
        final message = err is Map
            ? (err['message'] ?? 'Erro no servidor.').toString()
            : err.toString();
        throw CallableHttpException(code, message);
      }
      if (decoded.containsKey('result')) {
        final result = decoded['result'];
        if (result is Map) return Map<String, dynamic>.from(result);
        return {};
      }
      // Se não tem result nem error, retorna o decoded como resultado
      return Map<String, dynamic>.from(decoded);
    }
    return {};
  }

  Map<String, dynamic>? decoded;
  try {
    decoded = jsonDecode(response.body) as Map<String, dynamic>?;
  } catch (_) {}

  if (decoded != null && decoded.containsKey('error')) {
    final err = decoded['error'];
    final code = err is Map
        ? (err['status'] ?? err['code'] ?? 'internal').toString()
        : 'internal';
    final message = err is Map
        ? (err['message'] ?? 'Erro no servidor.').toString()
        : err.toString();
    throw CallableHttpException(code, message);
  }

  if (response.statusCode == 404) {
    throw CallableHttpException(
      'not-found',
      'Função não encontrada no servidor (deploy pendente?).',
    );
  }

  throw CallableHttpException(
    'internal',
    'Erro HTTP ${response.statusCode}',
  );
}
