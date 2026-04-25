// Arquivo: lib/constants/tipos_entrega.dart
//
// Tipos canônicos de veículo/entrega aceitos por uma loja. Cada loja decide
// quais tipos são compatíveis com seus produtos; o carrinho calcula o frete
// usando o tipo de MAIOR hierarquia aceito pela loja (maior = mais caro), e
// o backend filtra entregadores pelo tipo do veículo ativo deles.
//
// Regras de hierarquia:
//   bicicleta (1) < moto (2) < carro (3) < carro_frete (4)
//
// Exemplos:
//   - Loja aceita ["bicicleta","moto","carro"]  → frete calculado como CARRO
//   - Loja aceita ["moto","carro"]              → frete calculado como CARRO
//   - Loja aceita ["carro_frete"]               → frete calculado como CARRO_FRETE
//   - Loja aceita ["bicicleta"]                 → frete calculado como BICICLETA
//                                                 (usa tabela `padrao` com
//                                                 aviso de limite de ~2 km)
//
// Cliente NUNCA escolhe o tipo de veículo — isso é decisão interna do
// sistema a partir da config da loja.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Enum canônico dos 4 tipos aceitos pelo sistema.
enum TipoEntrega {
  bicicleta,
  moto,
  carro,
  carroFrete,
}

/// Helpers estáticos e tabela de hierarquia.
class TiposEntrega {
  TiposEntrega._();

  /// Código persistido no Firestore (snake_case estável).
  static const String codBicicleta = 'bicicleta';
  static const String codMoto = 'moto';
  static const String codCarro = 'carro';
  static const String codCarroFrete = 'carro_frete';

  /// Ordem canônica para listagem em UI (bike → moto → carro → carro frete).
  static const List<String> ordemCanonica = <String>[
    codBicicleta,
    codMoto,
    codCarro,
    codCarroFrete,
  ];

  /// Hierarquia logística. Maior = frete mais caro / carga maior / veículo
  /// mais robusto. Usado pra decidir a tabela de frete quando a loja aceita
  /// mais de um tipo.
  static const Map<String, int> hierarquia = <String, int>{
    codBicicleta: 1,
    codMoto: 2,
    codCarro: 3,
    codCarroFrete: 4,
  };

  /// Tabela `tabela_fretes` a consultar. `bicicleta` e `moto` compartilham
  /// `padrao`. Se futuramente quiser tabela própria de bike, basta trocar.
  static const Map<String, String> tabelaFretePorTipo = <String, String>{
    codBicicleta: 'padrao',
    codMoto: 'padrao',
    codCarro: 'carro',
    codCarroFrete: 'carro_frete',
  };

  /// Cadeia de fallback se a tabela primária não existir para a cidade.
  /// Ordem: preferida primeiro. Se nenhuma for encontrada, o cálculo cai
  /// em `_taxaBaseFallback` da UI.
  static const Map<String, List<String>> cadeiaFallbackTabela =
      <String, List<String>>{
    codCarroFrete: <String>['carro_frete', 'carro', 'padrao'],
    codCarro: <String>['carro', 'padrao'],
    codMoto: <String>['padrao'],
    codBicicleta: <String>['padrao'],
  };

  /// Raio km recomendado (aviso na UI; NUNCA bloqueia compra por distância).
  static const Map<String, double> raioKmRecomendado = <String, double>{
    codBicicleta: 2.0,
    codMoto: 15.0,
    codCarro: 25.0,
    codCarroFrete: 100.0,
  };

  /// Rótulo amigável para UI.
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

  /// Descrição curta pra card/checkbox no painel do lojista.
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

  /// Normaliza lista vinda do Firestore:
  /// - descarta valores fora do set canônico
  /// - remove duplicatas
  /// - ordena por hierarquia ascendente (bike→moto→carro→frete)
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

  /// Retorna o tipo de MAIOR hierarquia da lista. Usado pra decidir a
  /// tabela de frete. Se lista vazia, retorna `null` (caller decide
  /// fallback para default legado).
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

  /// Verifica se o veículo do entregador é compatível com a lista de tipos
  /// aceitos pela loja. Usado no backend pra filtrar a fila de despacho.
  static bool compativel(String tipoVeiculoEntregador, List<String> aceitos) {
    if (aceitos.isEmpty) return true; // loja legada sem config → não filtra
    return aceitos.contains(tipoVeiculoEntregador);
  }

  /// Normaliza um rótulo livre de veículo (ex: `"Moto"`, `"Carro de Frete"`,
  /// `"Fiorino"`, `"bike"`) para um código canônico do set. Replica a
  /// heurística do backend (`functions/tipos_entrega.js#normalizarTipoVeiculo`)
  /// para manter 100% de paridade entre o filtro client-side do radar e o
  /// filtro server-side do despacho. Retorna string vazia se não reconhecer.
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

  /// Deriva default para lojas legado que ainda não configuraram o campo.
  ///
  /// Política conservadora (abr/2026): preserva o comportamento de cobrança
  /// anterior à migração, pra lojas legado não surpreenderem clientes com
  /// aumento súbito de frete.
  ///
  /// - `temProdutoRequerVeiculoGrande=true` → `["carro","carro_frete"]`
  ///   (produto volumoso existia no carrinho; antes já calculava como
  ///   "carro", agora mantém e abre porta para `carro_frete` via fallback
  ///   na tabela).
  /// - `false` → `["moto"]` apenas. Bicicleta e carro são **opt-in
  ///   explícito** do lojista — não entram em default.
  static List<String> defaultLegado({
    required bool temProdutoRequerVeiculoGrande,
  }) {
    if (temProdutoRequerVeiculoGrande) {
      return const <String>[codCarro, codCarroFrete];
    }
    return const <String>[codMoto];
  }

  /// Converte para `List<String>` pronto para gravar no Firestore.
  static List<String> paraFirestore(List<String> tipos) =>
      normalizarLista(tipos);

  /// Lê da estrutura de documento (mapa ou snapshot.data()). Retorna lista
  /// vazia se o campo não existir.
  static List<String> lerDeDoc(
    Map<String, dynamic>? data, {
    String campo = 'tipos_entrega_permitidos',
  }) {
    if (data == null) return const <String>[];
    return normalizarLista(data[campo]);
  }

  /// Normaliza `tipo_entrega_solicitado` — a categoria **escolhida pelo
  /// lojista no momento do clique** em "Solicitar entregador". Diferente
  /// de [lerDeDoc], aqui o campo é uma string única (não lista). Aceita
  /// código canônico direto ou variações livres (ex: "Carro Popular",
  /// "Fiorino"); devolve string vazia se não reconhecer.
  static String normalizarTipoSolicitado(dynamic raw) {
    final s = (raw?.toString() ?? '').trim().toLowerCase();
    if (s.isEmpty) return '';
    if (hierarquia.containsKey(s)) return s;
    return normalizarTipoVeiculo(s);
  }

  /// Categoria efetivamente buscada para o pedido.
  ///
  /// Ordem de precedência:
  ///   1. `pedido.tipo_entrega_solicitado` — escolha explícita do lojista.
  ///   2. Lista aceita com **apenas um tipo** → tipo implícito.
  ///   3. `null` quando a loja aceita múltiplos tipos e ainda não houve
  ///      decisão (bloqueia despacho) ou quando a loja é legado sem config.
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
}

/// Container com snapshot carregado do Firestore — facilita passar entre
/// camadas (cart_screen, checkout, pedido).
class TiposEntregaLoja {
  TiposEntregaLoja({
    required this.lojaId,
    required this.tiposAceitos,
    required this.atualizadoEm,
  });

  final String lojaId;
  final List<String> tiposAceitos;
  final Timestamp? atualizadoEm;

  /// Atalho pra saber o alvo de frete.
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
