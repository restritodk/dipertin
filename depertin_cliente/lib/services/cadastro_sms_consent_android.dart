import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android — SMS User Consent API (Google Play Services): o utilizador autoriza
/// ler **uma** mensagem; não usa permissão `READ_SMS` permanente.
/// Compatível com SMS da Comtele (sem hash do SMS Retriever).
class CadastroSmsConsentAndroid {
  static const MethodChannel _channel =
      MethodChannel('dipertin.android/cadastro_sms');

  static bool get disponivel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// [regex] no formato Java (`\d{6}`).
  static Future<void> iniciar({
    String regex = r'\d{6}',
    required void Function(String codigo) onCodigo,
  }) async {
    if (!disponivel) return;
    await parar();
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onOtp') return;
      final arg = call.arguments;
      final s = arg is String ? arg : arg?.toString();
      if (s == null || !RegExp(r'^\d{6}$').hasMatch(s)) return;
      onCodigo(s);
    });
    await _channel.invokeMethod<void>('startListen', <String, dynamic>{
      'regex': regex,
    });
  }

  static Future<void> parar() async {
    if (!disponivel) return;
    try {
      await _channel.invokeMethod<void>('stopListen');
    } catch (_) {}
    _channel.setMethodCallHandler(null);
  }
}
