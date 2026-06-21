/// Geração e leitura de links inteligentes (deep links) de produto.
///
/// Formato canônico do link compartilhado (HTTPS — App Links):
///   https://www.dipertin.com.br/p/?produto={produtoId}
///
/// Também aceitamos, na leitura:
///   - https://www.dipertin.com.br/p/{produtoId}
///   - https://www.dipertin.com.br/produto?id={produtoId} (legado/site)
///   - dipertin://produto?id={produtoId} (esquema interno / fallback web)
library;

class ProdutoLink {
  ProdutoLink._();

  /// Domínio público do marketplace.
  static const String host = 'www.dipertin.com.br';

  /// Esquema interno usado como fallback pela página web (intent://).
  static const String esquemaApp = 'dipertin';

  /// Monta o link HTTPS único e compartilhável de um produto.
  static String gerar(String produtoId) {
    final id = produtoId.trim();
    return 'https://$host/p/?produto=$id';
  }

  /// Tenta extrair o ID do produto de uma URI de deep link.
  /// Retorna `null` se a URI não for um link de produto reconhecido.
  static String? extrairProdutoId(Uri uri) {
    // Query params comuns: ?produto= / ?id= / ?produto_id=
    final q = uri.queryParameters;
    for (final chave in const ['produto', 'id', 'produto_id', 'produtoId']) {
      final v = q[chave]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }

    // Esquema interno: dipertin://produto/{id} ou dipertin://produto?id=
    if (uri.scheme == esquemaApp) {
      final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (uri.host == 'produto' && segs.isNotEmpty) return segs.first.trim();
      if (segs.length >= 2 && segs.first == 'produto') return segs[1].trim();
      if (segs.length == 1 && uri.host.isEmpty) return segs.first.trim();
    }

    // HTTPS por caminho: /p/{id} ou /produto/{id}
    final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    final idx = segs.indexWhere((s) => s == 'p' || s == 'produto');
    if (idx >= 0 && idx + 1 < segs.length) {
      final cand = segs[idx + 1].trim();
      if (cand.isNotEmpty) return cand;
    }

    return null;
  }

  /// `true` se a URI aparenta ser um link de produto do DiPertin.
  static bool ehLinkDeProduto(Uri uri) => extrairProdutoId(uri) != null;
}
