// Arquivo: lib/constants/tipos_entrega.dart
//
// Cópia literal de depertin_cliente/lib/constants/tipos_entrega.dart.
// Mantenha as duas versões em sincronia — o projeto não usa import
// cross-project por ser builds separadas (mobile vs. web).
//
// Tipos canônicos de veículo/entrega aceitos por uma loja. Cada loja decide
// quais tipos são compatíveis com seus produtos; o carrinho calcula o frete
// usando o tipo de MAIOR hierarquia aceito pela loja (maior = mais caro), e
// o backend filtra entregadores pelo tipo do veículo ativo deles.
//
// Hierarquia: bicicleta (1) < moto (2) < carro (3) < carro_frete (4)

import 'package:cloud_firestore/cloud_firestore.dart';

enum TipoEntrega {
  bicicleta,
  moto,
  carro,
  carroFrete,
}

class TiposEntrega {
  TiposEntrega._();

  static const String codBicicleta = 'bicicleta';
  static const String codMoto = 'moto';
  static const String codCarro = 'carro';
  static const String codCarroFrete = 'carro_frete';

  static const List<String> ordemCanonica = <String>[
    codBicicleta,
    codMoto,
    codCarro,
    codCarroFrete,
  ];

  static const Map<String, int> hierarquia = <String, int>{
    codBicicleta: 1,
    codMoto: 2,
    codCarro: 3,
    codCarroFrete: 4,
  };

  static const Map<String, String> tabelaFretePorTipo = <String, String>{
    codBicicleta: 'padrao',
    codMoto: 'padrao',
    codCarro: 'carro',
    codCarroFrete: 'carro_frete',
  };

  static const Map<String, List<String>> cadeiaFallbackTabela =
      <String, List<String>>{
    codCarroFrete: <String>['carro_frete', 'carro', 'padrao'],
    codCarro: <String>['carro', 'padrao'],
    codMoto: <String>['padrao'],
    codBicicleta: <String>['padrao'],
  };

  static const Map<String, double> raioKmRecomendado = <String, double>{
    codBicicleta: 2.0,
    codMoto: 15.0,
    codCarro: 25.0,
    codCarroFrete: 100.0,
  };

  static String rotulo(String codigo) {
    switch (codigo) {
      case codBicicleta:
        return 'Bicicleta';
      case codMoto:
        return 'Moto';
      case codCarro:
        return 'Carro popular';
      case codCarroFrete:
        return 'Carro frete';
      default:
        return codigo;
    }
  }

  static String descricaoCurta(String codigo) {
    switch (codigo) {
      case codBicicleta:
        return 'Entregas pequenas até ~2 km da loja.';
      case codMoto:
        return 'Ideal para refeições, encomendas leves.';
      case codCarro:
        return 'Carros de passeio (volumes médios).';
      case codCarroFrete:
        return 'Utilitários: Fiorino, Montana, pick-ups, Kombi.';
      default:
        return '';
    }
  }

  static List<String> normalizarLista(dynamic raw) {
    if (raw is! Iterable) return const <String>[];
    final set = <String>{};
    for (final v in raw) {
      final s = v?.toString().trim().toLowerCase();
      if (s != null && hierarquia.containsKey(s)) set.add(s);
    }
    final lista = set.toList()
      ..sort((a, b) => (hierarquia[a] ?? 0).compareTo(hierarquia[b] ?? 0));
    return lista;
  }

  static String? maiorTipoDaLista(List<String> tipos) {
    if (tipos.isEmpty) return null;
    String? melhor;
    var maior = -1;
    for (final t in tipos) {
      final h = hierarquia[t] ?? -1;
      if (h > maior) {
        maior = h;
        melhor = t;
      }
    }
    return melhor;
  }

  static bool compativel(String tipoVeiculoEntregador, List<String> aceitos) {
    if (aceitos.isEmpty) return true;
    return aceitos.contains(tipoVeiculoEntregador);
  }

  /// Normaliza um rótulo livre de veículo (ex: `"Moto"`, `"Carro de Frete"`,
  /// `"Fiorino"`, `"bike"`) para um código canônico. Paridade com
  /// `functions/tipos_entrega.js#normalizarTipoVeiculo`.
  static String normalizarTipoVeiculo(dynamic raw) {
    final s = (raw?.toString() ?? '').trim().toLowerCase();
    if (s.isEmpty) return '';
    if (s.contains('frete') ||
        s.contains('fiorino') ||
        s.contains('pick') ||
        s.contains('kombi') ||
        s.contains('utilitário') ||
        s.contains('utilitario') ||
        s.contains('van') ||
        s == codCarroFrete) {
      return codCarroFrete;
    }
    if (s.contains('carro')) return codCarro;
    if (s.contains('moto') ||
        s.contains('scooter') ||
        s.contains('motocicleta')) {
      return codMoto;
    }
    if (s.contains('bike') || s.contains('bicicleta') || s.contains('bicy')) {
      return codBicicleta;
    }
    return '';
  }

  /// Normaliza `tipo_entrega_solicitado` — categoria escolhida pelo lojista
  /// no momento do clique em "Solicitar entregador" (string única). Aceita
  /// código canônico direto ou variação livre.
  static String normalizarTipoSolicitado(dynamic raw) {
    final s = (raw?.toString() ?? '').trim().toLowerCase();
    if (s.isEmpty) return '';
    if (hierarquia.containsKey(s)) return s;
    return normalizarTipoVeiculo(s);
  }

  /// Categoria efetivamente buscada pro pedido — ver doc em
  /// `functions/tipos_entrega.js#categoriaEfetivaPedido`.
  static String? categoriaEfetivaPedido(
    Map<String, dynamic>? pedido,
    List<String>? tiposAceitosLoja,
  ) {
    final explicito = normalizarTipoSolicitado(
      pedido == null ? null : pedido['tipo_entrega_solicitado'],
    );
    if (explicito.isNotEmpty) return explicito;
    final aceitos = tiposAceitosLoja == null
        ? const <String>[]
        : normalizarLista(tiposAceitosLoja);
    if (aceitos.length == 1) return aceitos.first;
    return null;
  }

  static List<String> defaultLegado({
    required bool temProdutoRequerVeiculoGrande,
  }) {
    if (temProdutoRequerVeiculoGrande) {
      return const <String>[codCarro, codCarroFrete];
    }
    return const <String>[codMoto];
  }

  static List<String> paraFirestore(List<String> tipos) =>
      normalizarLista(tipos);

  static List<String> lerDeDoc(
    Map<String, dynamic>? data, {
    String campo = 'tipos_entrega_permitidos',
  }) {
    if (data == null) return const <String>[];
    return normalizarLista(data[campo]);
  }
}

class TiposEntregaLoja {
  TiposEntregaLoja({
    required this.lojaId,
    required this.tiposAceitos,
    required this.atualizadoEm,
  });

  final String lojaId;
  final List<String> tiposAceitos;
  final Timestamp? atualizadoEm;

  String? get maiorTipo => TiposEntrega.maiorTipoDaLista(tiposAceitos);

  factory TiposEntregaLoja.deDoc(
    String lojaId,
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      return TiposEntregaLoja(
        lojaId: lojaId,
        tiposAceitos: const <String>[],
        atualizadoEm: null,
      );
    }
    return TiposEntregaLoja(
      lojaId: lojaId,
      tiposAceitos: TiposEntrega.lerDeDoc(data),
      atualizadoEm: data['tipos_entrega_atualizado_em'] as Timestamp?,
    );
  }

  bool get estaConfigurada => tiposAceitos.isNotEmpty;
}
