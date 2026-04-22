import 'package:flutter/material.dart';

/// Categoria da Central de Ajuda — código + rótulo amigável + ícone.
class SuporteCategoriaOpcao {
  const SuporteCategoriaOpcao({
    required this.codigo,
    required this.rotulo,
    required this.descricao,
    required this.icone,
  });
  final String codigo;
  final String rotulo;
  final String descricao;
  final IconData icone;
}

/// Categorias do fluxo da Central de Ajuda (chamado em `support_tickets`).
///
/// Códigos persistidos em `categoria_suporte`; rótulo amigável em
/// `categoria_label` (para o painel e histórico).
abstract class SuporteCategorias {
  static const String ajuda = 'ajuda';
  static const String conta = 'conta';
  static const String pedidos = 'pedidos';
  static const String anuncios = 'anuncios';
  static const String eventos = 'eventos';
  static const String outros = 'outros';

  /// Ordem exibida ao cliente com ícone e descrição curta.
  static const List<SuporteCategoriaOpcao> opcoes = [
    SuporteCategoriaOpcao(
      codigo: ajuda,
      rotulo: 'Ajuda',
      descricao: 'Dúvidas e orientações gerais',
      icone: Icons.help_outline_rounded,
    ),
    SuporteCategoriaOpcao(
      codigo: conta,
      rotulo: 'Conta',
      descricao: 'Cadastro, acesso e segurança',
      icone: Icons.person_outline_rounded,
    ),
    SuporteCategoriaOpcao(
      codigo: pedidos,
      rotulo: 'Pedidos',
      descricao: 'Compras, entregas e pagamentos',
      icone: Icons.shopping_bag_outlined,
    ),
    SuporteCategoriaOpcao(
      codigo: anuncios,
      rotulo: 'Anúncios',
      descricao: 'Produtos, vitrine e destaques',
      icone: Icons.campaign_outlined,
    ),
    SuporteCategoriaOpcao(
      codigo: eventos,
      rotulo: 'Eventos',
      descricao: 'Divulgação e inscrições',
      icone: Icons.event_outlined,
    ),
    SuporteCategoriaOpcao(
      codigo: outros,
      rotulo: 'Outros',
      descricao: 'Outro assunto',
      icone: Icons.more_horiz_rounded,
    ),
  ];

  /// Compat: lista simples (code → rótulo) usada por partes legadas.
  static List<MapEntry<String, String>> get opcoesNumeradas => opcoes
      .map((e) => MapEntry(e.codigo, e.rotulo))
      .toList(growable: false);

  static String rotuloPorCodigo(String codigo) {
    final c = codigo.trim().toLowerCase();
    for (final e in opcoes) {
      if (e.codigo == c) return e.rotulo;
    }
    return 'Outros';
  }

  static String? codigoValido(String codigo) {
    final c = codigo.trim().toLowerCase();
    for (final e in opcoes) {
      if (e.codigo == c) return e.codigo;
    }
    return null;
  }
}
