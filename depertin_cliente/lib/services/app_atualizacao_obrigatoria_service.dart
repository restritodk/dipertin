import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// Lê [configuracoes/atualizacao_app] no Firestore (painel / Console).
///
/// Campos opcionais:
/// - `versao_minima_android` (string, ex.: `2.0.0`) — abaixo disso, bloqueia no Android.
/// - `versao_minima_ios` (string) — idem no iOS.
/// - `url_loja_android` — link Play Store (se vazio, monta com o package do app).
/// - `url_loja_ios` — link App Store (recomendado quando forçar iOS).
/// - `mensagem` — texto extra no diálogo (opcional).
///
/// Documento inexistente ou versões mínimas vazias: não bloqueia (fail-open).
/// Falha de rede/timeout: não bloqueia para não travar o app offline.
class AppAtualizacaoObrigatoriaService {
  AppAtualizacaoObrigatoriaService._();

  static const Duration _timeoutLeitura = Duration(seconds: 10);

  /// Compara [a] e [b] como semver simples (1.2.3). Retorna negativo se a < b.
  static int compararVersao(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    final len = math.max(pa.length, pb.length);
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va < vb) return -1;
      if (va > vb) return 1;
    }
    return 0;
  }

  static Future<AppAtualizacaoVerificacao> verificar() async {
    if (kIsWeb) {
      return AppAtualizacaoVerificacao.ok();
    }

    PackageInfo info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (e) {
      debugPrint('[atualizacao_app] PackageInfo falhou: $e');
      return AppAtualizacaoVerificacao.ok();
    }

    final atual = info.version.trim();
    if (atual.isEmpty) return AppAtualizacaoVerificacao.ok();

    Map<String, dynamic>? data;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('configuracoes')
          .doc('atualizacao_app')
          .get()
          .timeout(_timeoutLeitura);
      if (snap.exists) {
        data = snap.data();
      }
    } catch (e) {
      debugPrint('[atualizacao_app] Firestore/timeout (seguindo sem bloquear): $e');
      return AppAtualizacaoVerificacao.ok();
    }

    if (data == null) return AppAtualizacaoVerificacao.ok();

    final bool isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final bool isIos = defaultTargetPlatform == TargetPlatform.iOS;

    String? minRaw;
    if (isAndroid) {
      minRaw = data['versao_minima_android']?.toString().trim();
    } else if (isIos) {
      minRaw = data['versao_minima_ios']?.toString().trim();
    } else {
      return AppAtualizacaoVerificacao.ok();
    }

    if (minRaw == null || minRaw.isEmpty) {
      return AppAtualizacaoVerificacao.ok();
    }

    if (compararVersao(atual, minRaw) >= 0) {
      return AppAtualizacaoVerificacao.ok();
    }

    final mensagem = data['mensagem']?.toString().trim();
    String urlLoja;
    if (isAndroid) {
      final custom = data['url_loja_android']?.toString().trim();
      if (custom != null && custom.isNotEmpty) {
        urlLoja = custom;
      } else {
        final id = info.packageName;
        urlLoja = 'https://play.google.com/store/apps/details?id=$id';
      }
    } else {
      final custom = data['url_loja_ios']?.toString().trim();
      if (custom == null || custom.isEmpty) {
        debugPrint(
          '[atualizacao_app] iOS: defina url_loja_ios em Firestore para bloquear versões antigas.',
        );
        return AppAtualizacaoVerificacao.ok();
      }
      urlLoja = custom;
    }

    return AppAtualizacaoVerificacao.bloqueado(
      versaoAtual: atual,
      versaoMinima: minRaw,
      urlLoja: urlLoja,
      mensagem: mensagem,
    );
  }
}

class AppAtualizacaoVerificacao {
  AppAtualizacaoVerificacao._({
    required this.bloqueado,
    this.versaoAtual,
    this.versaoMinima,
    this.urlLoja,
    this.mensagem,
  });

  final bool bloqueado;
  final String? versaoAtual;
  final String? versaoMinima;
  final String? urlLoja;
  final String? mensagem;

  factory AppAtualizacaoVerificacao.ok() =>
      AppAtualizacaoVerificacao._(bloqueado: false);

  factory AppAtualizacaoVerificacao.bloqueado({
    required String versaoAtual,
    required String versaoMinima,
    required String urlLoja,
    String? mensagem,
  }) =>
      AppAtualizacaoVerificacao._(
        bloqueado: true,
        versaoAtual: versaoAtual,
        versaoMinima: versaoMinima,
        urlLoja: urlLoja,
        mensagem: mensagem,
      );
}
