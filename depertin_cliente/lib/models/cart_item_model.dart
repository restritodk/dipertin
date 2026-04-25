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

  CartItemModel({
    required this.id,
    required this.nome,
    required this.preco,
    required this.lojaId,
    required this.lojaNome,
    required this.imagem,
    this.quantidade = 1,
    this.requerVeiculoGrande = false,
  });

  Map<String, dynamic> toJson() {
    // Proteção contra hot-reload: instâncias antigas podem não ter o slot
    // de `requerVeiculoGrande` e acessá-lo lança TypeError. Se falhar,
    // assume padrão (moto/bike).
    bool veiculoGrande = false;
    try {
      veiculoGrande = requerVeiculoGrande;
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
    };
  }

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      id: json['id'],
      nome: json['nome'],
      preco: (json['preco'] as num).toDouble(),
      lojaId: json['lojaId'],
      lojaNome: json['lojaNome'],
      imagem: json['imagem'],
      quantidade: json['quantidade'],
      requerVeiculoGrande: json['requerVeiculoGrande'] == true,
    );
  }
}
