// Arquivo: lib/models/cart_item_model.dart

class CartItemModel {
  final String id;
  final String nome;
  final double preco;
  final String lojaId;
  final String lojaNome;
  final String imagem;
  int quantidade;

  /// LEGADO (Fase 2 — abr/2026). Substituído por `tipos_entrega_permitidos`
  /// configurado no PERFIL DA LOJA (não mais por produto). Mantemos o campo
  /// no modelo e no JSON apenas para:
  ///   1. Compatibilidade com carrinhos serializados em SharedPreferences
  ///      antes da migração.
  ///   2. Fallback em `_lerTiposEntregaAceitos` no `cart_screen.dart` quando
  ///      a loja ainda não configurou `tipos_entrega_permitidos` em
  ///      `lojas_public/{uid}` — se algum item tem `true`, o carrinho deriva
  ///      default `["carro","carro_frete"]` via `TiposEntrega.defaultLegado`.
  ///
  /// NÃO USE ESTE CAMPO PARA NOVAS REGRAS. Use `tipos_entrega_permitidos`
  /// da loja (`lojas_public/{lojaId}.tipos_entrega_permitidos`).
  final bool requerVeiculoGrande;

  /// Produto com `tipo_venda == encomenda` (negociação + entrada via fluxo dedicado).
  final bool ehEncomenda;

  /// Variações escolhidas pelo cliente para este item.
  /// Ex.: {'cor': 'Azul', 'tamanho': 'G'} ou {'cor': 'Preto', 'tamanho': '42'}.
  final Map<String, String> variacoesSelecionadas;

  CartItemModel({
    required this.id,
    required this.nome,
    required this.preco,
    required this.lojaId,
    required this.lojaNome,
    required this.imagem,
    this.quantidade = 1,
    this.requerVeiculoGrande = false,
    this.ehEncomenda = false,
    Map<String, String>? variacoesSelecionadas,
  }) : variacoesSelecionadas = variacoesSelecionadas ?? const {};

  String get chaveCarrinho {
    final partes =
        variacoesSelecionadas.entries
            .where((e) => e.value.trim().isNotEmpty)
            .map((e) => '${e.key}:${e.value.trim().toLowerCase()}')
            .toList()
          ..sort();
    return partes.isEmpty ? id : '$id|${partes.join('|')}';
  }

  String get variacoesResumo {
    final cor = variacoesSelecionadas['cor']?.trim() ?? '';
    final tamanho = variacoesSelecionadas['tamanho']?.trim() ?? '';
    final partes = <String>[
      if (cor.isNotEmpty) 'Cor: $cor',
      if (tamanho.isNotEmpty) 'Tamanho: $tamanho',
    ];
    return partes.join(' • ');
  }

  Map<String, dynamic> toJson() {
    // Proteção contra hot-reload: instâncias antigas podem não ter o slot
    // de `requerVeiculoGrande` e acessá-lo lança TypeError. Se falhar,
    // assume padrão (moto/bike).
    bool veiculoGrande = false;
    try {
      veiculoGrande = requerVeiculoGrande;
    } catch (_) {}
    bool encomenda = false;
    try {
      encomenda = ehEncomenda;
    } catch (_) {}
    Map<String, String> variacoes = const {};
    try {
      variacoes = variacoesSelecionadas;
    } catch (_) {}
    return {
      'id': id,
      'nome': nome,
      'preco': preco,
      'lojaId': lojaId,
      'lojaNome': lojaNome,
      'imagem': imagem,
      'quantidade': quantidade,
      'requerVeiculoGrande': veiculoGrande,
      'ehEncomenda': encomenda,
      'variacoesSelecionadas': variacoes,
      'variacoes_resumo': variacoesResumo,
      'chaveCarrinho': chaveCarrinho,
    };
  }

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    final rawVariacoes = json['variacoesSelecionadas'] ?? json['variacoes'];
    final variacoes = <String, String>{};
    if (rawVariacoes is Map) {
      rawVariacoes.forEach((key, value) {
        final k = key.toString().trim();
        final v = value.toString().trim();
        if (k.isNotEmpty && v.isNotEmpty) variacoes[k] = v;
      });
    }
    return CartItemModel(
      id: json['id'],
      nome: json['nome'],
      preco: (json['preco'] as num).toDouble(),
      lojaId: json['lojaId'],
      lojaNome: json['lojaNome'],
      imagem: json['imagem'],
      quantidade: json['quantidade'],
      requerVeiculoGrande: json['requerVeiculoGrande'] == true,
      ehEncomenda: json['ehEncomenda'] == true,
      variacoesSelecionadas: variacoes,
    );
  }
}
