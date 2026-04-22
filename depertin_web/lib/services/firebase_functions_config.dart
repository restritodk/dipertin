import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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

/// Região do deploy das Cloud Functions (`firebase deploy --only functions`).
const String kFirebaseFunctionsRegion = 'us-central1';

/// Projeto Firebase.
const String _kProjectId = 'depertin-f940f';

/// Instância única para callables (evita região errada).
final FirebaseFunctions appFirebaseFunctions = FirebaseFunctions.instanceFor(
  region: kFirebaseFunctionsRegion,
);

/// Chama Cloud Function callable via HTTP direto, contornando o JS interop do
/// dart2js que lança "Int64 accessor not supported by dart2js" ao converter a
/// resposta com `dartify()`.
///
/// No mobile/desktop usa `httpsCallable` normalmente (sem Int64 issues).
/// No web usa HTTP POST + `dart:convert` (sem `dartify`).
Future<Map<String, dynamic>> callFirebaseFunctionSafe(
  String functionName, {
  Map<String, dynamic>? parameters,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (!kIsWeb) {
    final callable = appFirebaseFunctions.httpsCallable(
      functionName,
      options: HttpsCallableOptions(timeout: timeout),
    );
    final result = await callable.call(parameters);
    final raw = result.data;
    if (raw is! Map) return {};
    return Map<String, dynamic>.from(raw);
  }

  final uri = Uri.parse(
    'https://$kFirebaseFunctionsRegion-$_kProjectId'
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
    if (decoded is Map && decoded.containsKey('result')) {
      final result = decoded['result'];
      if (result is Map) return Map<String, dynamic>.from(result);
      return {};
    }
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
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

  throw CallableHttpException(
    'internal',
    'Erro HTTP ${response.statusCode}',
  );
}
