import 'dart:async';
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

/// Exceção lançada quando o Firebase App Check não consegue obter um token
/// de segurança válido (ex.: reCAPTCHA v3 falhou, domínio não autorizado).
class AppCheckException implements Exception {
  final String message;
  const AppCheckException(this.message);

  @override
  String toString() => 'AppCheckException: $message';
}

/// Mensagem legível quando uma callable (via HTTP no web) falhar.
String mensagemCallableHttpException(CallableHttpException e) {
  final c = e.code.toLowerCase().replaceAll('_', '-');
  if (c.contains('not-found') || c.contains('not_found')) {
    return 'Serviço não encontrado. Publique as Cloud Functions mais recentes.';
  }
  if (c.contains('internal') || c == 'internal') {
    return 'Erro interno no servidor. Tente novamente ou contate o suporte.';
  }
  if (c.contains('unauthenticated') || c == 'unauthenticated') {
    final m = e.message.trim().toLowerCase();
    if (m.isEmpty || m == 'unauthenticated' || m.contains('unauthenticated')) {
      return 'Não foi possível autenticar a solicitação. '
          'Atualize a página, faça login novamente e tente outra vez.';
    }
  }
  final m = e.message.trim();
  if (m.isNotEmpty) return m;
  return e.code;
}

/// Região do deploy das Cloud Functions principais (`firebase deploy --only functions`).
const String kFirebaseFunctionsRegion = 'us-central1';

/// Região do deploy das Cloud Functions do módulo Gestão Comercial.
const String kFirebaseFunctionsRegionSouth = 'southamerica-east1';

/// Região das Cloud Functions de e-mail transacional (GC).
/// Migradas para us-east1 por quota — ver gestao_comercial_email.js.
const String kFirebaseFunctionsRegionEmailGc = 'us-east1';

/// Projeto Firebase.
const String _kProjectId = 'depertin-f940f';

/// Se esta flag estiver definida em runtime (ex.: via
/// `--dart-define=USE_FIREBASE_EMULATOR=true` no `flutter run`),
/// aponta as funções para o emulador local em vez de produção.
/// Útil para testes locais sem deploy.
const bool _kUsarEmulador = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
const String _kEmuladorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);

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
  final t0 = DateTime.now();
  String trace(String msg) {
    final n = DateTime.now();
    final elapsed = n.difference(t0).inMilliseconds;
    String d2(int v) => v.toString().padLeft(2, '0');
    String d3(int v) => v.toString().padLeft(3, '0');
    final hora =
        '${d2(n.hour)}:${d2(n.minute)}:${d2(n.second)}.${d3(n.millisecond)}';
    final line = '[TRACE_cffs] $hora +${elapsed}ms — $msg';
    debugPrint(line);
    return line;
  }

  trace('callFirebaseFunctionSafe($functionName, region=$region) INÍCIO');

  final Uri uri;
  if (_kUsarEmulador) {
    uri = Uri.parse(
      'http://$_kEmuladorHost:5001/$_kProjectId/$region/$functionName',
    );
    trace('URI (emulador): $uri');
  } else {
    uri = Uri.parse(
      'https://$region-$_kProjectId'
      '.cloudfunctions.net/$functionName',
    );
    trace('URI: $uri');
  }

  final headers = <String, String>{
    'Content-Type': 'application/json',
  };

  final user = FirebaseAuth.instance.currentUser;
  trace('Auth.currentUser = ${user != null ? user.uid.substring(0, 8) : "null"}');

  if (user == null) {
    throw const CallableHttpException(
      'unauthenticated',
      'Sessão expirada. Faça login novamente e tente outra vez.',
    );
  }

  // ID Token do Firebase Auth — OBRIGATÓRIO nas callables (request.auth).
  // Painel web: App Check desabilitado de propósito — NÃO chamar
  // FirebaseAppCheck.getToken() nem enviar X-Firebase-AppCheck.
  // Force-refresh evita Bearer expirado/stale após sessão longa.
  final t1 = DateTime.now();
  String? token;
  try {
    token = await user.getIdToken(true).timeout(const Duration(seconds: 10));
  } on TimeoutException {
    trace('getIdToken(true) TIMEOUT — tentando sem forceRefresh');
  } catch (e) {
    trace('getIdToken(true) FALHOU (${e.runtimeType}) — fallback getIdToken()');
  }
  if (token == null || token.isEmpty) {
    try {
      token = await user.getIdToken().timeout(const Duration(seconds: 8));
    } catch (e) {
      trace('getIdToken() FALHOU — ${e.runtimeType}: $e');
    }
  }
  final elapsed = DateTime.now().difference(t1).inMilliseconds;
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
    final preview = token.length > 20 ? token.substring(0, 20) : token;
    trace('getIdToken OK — ${elapsed}ms, token: $preview… '
        '(sem App Check; Auth Bearer apenas)');
  } else {
    trace('getIdToken indisponível — ${elapsed}ms');
    throw const CallableHttpException(
      'unauthenticated',
      'Não foi possível autenticar a solicitação. '
          'Atualize a página, faça login novamente e tente outra vez.',
    );
  }

  final body = jsonEncode({'data': parameters ?? {}});
  trace('Body JSON pronto (${body.length} bytes). HTTP POST INICIADO');

  final tHttp = DateTime.now();
  http.Response response;
  try {
    response = await http
        .post(uri, headers: headers, body: body)
        .timeout(timeout);
    final httpTime = DateTime.now().difference(tHttp).inMilliseconds;
    trace('HTTP RESPONSE — status=${response.statusCode}, body=${response.body.length} chars, ${httpTime}ms');
  } on TimeoutException {
    final httpTime = DateTime.now().difference(tHttp).inMilliseconds;
    trace('HTTP TIMEOUT — ${httpTime}ms');
    rethrow;
  } catch (e) {
    final httpTime = DateTime.now().difference(tHttp).inMilliseconds;
    trace('HTTP ERROR — ${httpTime}ms — $e');
    rethrow;
  }

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      if (decoded.containsKey('error')) {
        final err = decoded['error'];
        final code = err is Map
            ? (err['status'] ?? err['code'] ?? 'internal').toString()
            : 'internal';
        final message = err is Map
            ? (err['message'] ?? 'Erro no servidor.').toString()
            : err.toString();
        trace('HTTP 200 com error — code=$code — throw');
        throw CallableHttpException(code, message);
      }
      if (decoded.containsKey('result')) {
        final result = decoded['result'];
        if (result is Map) {
          trace('SUCESSO — result com ${result.length} chaves');
          return Map<String, dynamic>.from(result);
        }
        trace('SUCESSO — result não-Map');
        return {};
      }
      trace('HTTP 200 — sem result/error, devolvendo decoded (${decoded.length} chaves)');
      return Map<String, dynamic>.from(decoded);
    }
    trace('HTTP 200 — decoded não é Map');
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
    trace('HTTP ${response.statusCode} — error=$code');
    throw CallableHttpException(code, message);
  }

  if (response.statusCode == 404) {
    trace('HTTP 404 — Function não encontrada');
    throw CallableHttpException(
      'not-found',
      'Função não encontrada no servidor (deploy pendente?).',
    );
  }

  trace('HTTP ${response.statusCode} — sem handler');
  throw CallableHttpException(
    'internal',
    'Erro HTTP ${response.statusCode}',
  );
}
