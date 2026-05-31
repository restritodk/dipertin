import 'firebase_functions_config.dart';

/// Registra login no audit_logs (callable [registrarEventoAuditoriaApp]).
Future<void> registrarLoginPainelAuditoria(String metodo) async {
  try {
    await callFirebaseFunctionSafe(
      'registrarEventoAuditoriaApp',
      timeout: const Duration(seconds: 12),
      parameters: <String, dynamic>{
        'evento': 'login_sessao_painel_web',
        'categoria': 'sessao',
        'plataforma': 'painel_web',
        'detalhe': <String, dynamic>{
          'canal': 'painel_web',
          'metodo': metodo,
        },
      },
    );
  } catch (_) {}
}
