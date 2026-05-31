import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_functions_config.dart';

/// Callables de bloqueio / exclusão do perfil de entregador (Área de Perigo).
class EntregadorPerfilOperacionalService {
  EntregadorPerfilOperacionalService._();

  static Future<Map<String, dynamic>> _chamar(
    String nome, {
    Map<String, dynamic>? data,
  }) async {
    final fn = appFirebaseFunctions.httpsCallable(
      nome,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 45),
      ),
    );
    final result = await fn.call(data ?? {});
    final raw = result.data;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  static Future<void> bloquearTemporario({
    int? dias,
    int? meses,
    String? motivo,
  }) async {
    await _chamar('entregadorAutoBloquearTemporario', data: {
      if (dias != null) 'dias': dias,
      if (meses != null) 'meses': meses,
      if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
    });
  }

  static Future<void> bloquearDefinitivo({String? motivo}) async {
    await _chamar('entregadorAutoBloquearDefinitivo', data: {
      if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
    });
  }

  static Future<Map<String, dynamic>> solicitarExclusaoPerfil() async {
    return _chamar('entregadorSolicitarExclusaoPerfil');
  }

  static Future<void> desbloquearConta() async {
    await _chamar('entregadorAutoDesbloquearConta');
  }

  static String mensagemErro(Object e) {
    if (e is FirebaseFunctionsException) {
      return mensagemFirebaseFunctionsException(e);
    }
    return e.toString();
  }
}
