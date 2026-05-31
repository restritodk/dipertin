import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_functions_config.dart';

/// Envia eventos à coleção `audit_logs` via callable [registrarEventoAuditoriaApp]
/// (painel web → Centro de operações lê em tempo real).
///
/// Não substitui Firebase Crashlytics / Cloud Logging; serve visão operacional unificada.
class AuditLogAppService {
  AuditLogAppService._();
  static final AuditLogAppService instancia = AuditLogAppService._();

  DateTime? _ultimoErroEnviado;

  Future<void> registrarEvento(
    String evento, {
    Object? detalhe,
    String? categoria,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await appFirebaseFunctions.httpsCallable('registrarEventoAuditoriaApp').call(
        <String, dynamic>{
          'evento': evento,
          ...?detalhe != null ? <String, dynamic>{'detalhe': detalhe} : null,
          ...?categoria != null && categoria.isNotEmpty
              ? <String, dynamic>{'categoria': categoria}
              : null,
          'plataforma': kIsWeb ? 'flutter_web' : defaultTargetPlatform.name,
        },
      );
    } catch (_) {}
  }

  /// Login bem-sucedido no app móvel (cliente / lojista / entregador).
  Future<void> registrarLoginSessaoMobile(String metodo) {
    return registrarEvento(
      'login_sessao_app',
      detalhe: <String, dynamic>{
        'canal': 'app_mobile',
        'metodo': metodo,
      },
      categoria: 'sessao',
    );
  }

  /// Erros Flutter globais — limitado a 1 envio / 45 s para não saturar a fila.
  Future<void> registrarErroCapturado(String mensagem, [String? stack]) async {
    final agora = DateTime.now();
    final u = _ultimoErroEnviado;
    if (u != null && agora.difference(u).inSeconds < 45) return;
    _ultimoErroEnviado = agora;
    final curto =
        mensagem.length > 500 ? '${mensagem.substring(0, 500)}…' : mensagem;
    await registrarEvento(
      'flutter_erro_nao_tratado',
      detalhe: <String, dynamic>{
        'mensagem': curto,
        if (stack != null && stack.isNotEmpty)
          'stack': stack.length > 1200 ? stack.substring(0, 1200) : stack,
      },
      categoria: 'erro_app',
    );
  }
}
