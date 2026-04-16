import 'package:cloud_functions/cloud_functions.dart';

import 'firebase_functions_config.dart';

/// Chamadas HTTPS às Cloud Functions de recuperação de senha (OTP + SMTP).
class RecuperacaoSenhaService {
  RecuperacaoSenhaService._();

  static final FirebaseFunctions _fn = appFirebaseFunctions;

  /// [tokenId] vem da resposta de [solicitarCodigo] (ID do documento no Firestore).
  static Future<Map<String, String>> solicitarCodigo(String email) async {
    final callable = _fn.httpsCallable('recuperacaoSenhaSolicitar');
    final res = await callable.call<Map<String, dynamic>>({
      'email': email.trim(),
    });
    final map = Map<String, dynamic>.from(res.data as Map);
    return {
      'mensagem': map['mensagem'] as String? ??
          'Se o e-mail estiver cadastrado, receberá um código em breve.',
      'tokenId': map['tokenId'] as String? ?? '',
    };
  }

  /// Após OTP válido, o servidor devolve [sessionId] (sem custom token).
  static Future<String> verificarOtpObterSessionId({
    required String email,
    required String otp,
    required String tokenId,
  }) async {
    final callable = _fn.httpsCallable('recuperacaoSenhaVerificarOtp');
    final res = await callable.call<Map<String, dynamic>>({
      'email': email.trim(),
      'otp': otp.replaceAll(RegExp(r'\D'), ''),
      'tokenId': tokenId.trim(),
    });
    final map = Map<String, dynamic>.from(res.data as Map);
    final t = map['sessionId'] as String?;
    if (t == null || t.isEmpty) {
      throw Exception('Resposta inválida do servidor.');
    }
    return t;
  }

  /// Define a nova senha no Firebase Auth via Admin SDK (servidor).
  static Future<void> definirNovaSenha({
    required String sessionId,
    required String newPassword,
  }) async {
    final callable = _fn.httpsCallable('recuperacaoSenhaDefinirNovaSenha');
    await callable.call<Map<String, dynamic>>({
      'sessionId': sessionId.trim(),
      'newPassword': newPassword,
    });
  }
}
