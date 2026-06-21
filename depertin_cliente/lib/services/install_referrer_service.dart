import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/produto_link.dart';

/// Deferred deep link (Android): quando o usuário toca em um link de produto,
/// não tem o app instalado e baixa pela Play Store, o `referrer` configurado
/// na página web (`/p/produto-link.js`) chega via Install Referrer API.
///
/// Aqui lemos esse referrer **uma única vez** após a instalação e devolvemos o
/// ID do produto para o app abrir a tela de detalhes automaticamente.
class InstallReferrerService {
  InstallReferrerService._();
  static final InstallReferrerService instance = InstallReferrerService._();

  static const String _chaveProcessado = 'install_referrer_processado_v1';

  bool _jaTentou = false;

  /// Retorna o ID do produto vindo do referrer de instalação, ou `null`.
  /// Só roda uma vez por instalação (controle via SharedPreferences).
  Future<String?> obterProdutoIdSeNovo() async {
    if (_jaTentou) return null;
    _jaTentou = true;

    if (kIsWeb || !Platform.isAndroid) return null;

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }

    if (prefs.getBool(_chaveProcessado) == true) return null;

    try {
      final ReferrerDetails detalhes =
          await PlayInstallReferrer.installReferrer;
      // Marca como processado sempre que conseguimos consultar (evita repetir).
      await prefs.setBool(_chaveProcessado, true);

      final bruto = detalhes.installReferrer;
      if (bruto == null || bruto.trim().isEmpty) return null;

      return _extrairProdutoId(bruto.trim());
    } catch (_) {
      // Sem Google Play Services, primeira execução sem dados, etc.
      // Não marca como processado para permitir nova tentativa futura.
      return null;
    }
  }

  /// O referrer chega como uma query string, ex.: `produto=ABC123&utm_source=...`.
  String? _extrairProdutoId(String referrer) {
    try {
      final params = Uri.splitQueryString(referrer);
      for (final chave in const ['produto', 'id', 'produto_id', 'produtoId']) {
        final v = params[chave]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
    } catch (_) {
      // ignora referrer malformado
    }

    // Fallback: tenta interpretar como URI completa de produto.
    try {
      final uri = Uri.tryParse(referrer);
      if (uri != null) return ProdutoLink.extrairProdutoId(uri);
    } catch (_) {}

    return null;
  }
}
