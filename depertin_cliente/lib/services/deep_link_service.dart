import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import '../app_navigator_key.dart';
import '../utils/abrir_produto_por_id.dart';
import '../utils/produto_link.dart';
import 'install_referrer_service.dart';

/// Trata a abertura do app por deep link (link inteligente do produto).
///
/// - App aberto: navega na hora.
/// - Cold start: guarda o produto pendente e navega assim que a vitrine
///   estiver pronta (`appPronto()` chamado após ir para `/home`).
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _produtoPendente;
  bool _pronto = false;
  bool _iniciado = false;

  /// Inicia a escuta de links. Idempotente.
  Future<void> iniciar() async {
    if (_iniciado) return;
    _iniciado = true;

    _sub = _appLinks.uriLinkStream.listen(
      _tratarUri,
      onError: (_) {},
    );

    try {
      final inicial = await _appLinks.getInitialLink();
      if (inicial != null) _tratarUri(inicial);
    } catch (_) {
      // sem link inicial
    }

    // Deferred deep link: se não veio link direto, tenta o referrer de
    // instalação (usuário baixou o app a partir do link de um produto).
    if (_produtoPendente == null) {
      try {
        final id = await InstallReferrerService.instance.obterProdutoIdSeNovo();
        if (id != null && id.isNotEmpty) {
          _produtoPendente = id;
          _navegarSeHouver();
        }
      } catch (_) {
        // referrer indisponível
      }
    }
  }

  /// Sinaliza que a navegação principal (vitrine) já está disponível.
  void appPronto() {
    _pronto = true;
    _navegarSeHouver();
  }

  void _tratarUri(Uri uri) {
    final id = ProdutoLink.extrairProdutoId(uri);
    if (id == null || id.isEmpty) return;
    _produtoPendente = id;
    _navegarSeHouver();
  }

  void _navegarSeHouver() {
    if (!_pronto) return;
    final id = _produtoPendente;
    if (id == null) return;

    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navegarSeHouver());
      return;
    }

    _produtoPendente = null;
    abrirProdutoPorId(ctx, id);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
