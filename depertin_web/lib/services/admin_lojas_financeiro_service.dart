import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/services/carteira_lojista_extrato.dart';

/// Loja disponível para busca/autocomplete no painel financeiro.
class LojaCatalogoItem {
  const LojaCatalogoItem({
    required this.id,
    required this.nome,
    required this.cpfDigitos,
    required this.cnpjDigitos,
  });

  final String id;
  final String nome;
  final String cpfDigitos;
  final String cnpjDigitos;

  String get nomeNorm => AdminLojasFinanceiroService.normalizarTexto(nome);

  String get rotuloDocumento {
    final parts = <String>[];
    if (cpfDigitos.length == 11) {
      parts.add('CPF ${AdminLojasFinanceiroService.formatarCpf(cpfDigitos)}');
    }
    if (cnpjDigitos.length == 14) {
      parts.add('CNPJ ${AdminLojasFinanceiroService.formatarCnpj(cnpjDigitos)}');
    }
    return parts.isEmpty ? 'Documento não informado' : parts.join(' · ');
  }
}

/// Período rápido do dashboard financeiro das lojas.
enum LojasFinPeriodoRapido { hoje, semana, mes, personalizado }

/// Filtro de status de pagamento do pedido.
enum LojasFinStatusPagamentoFiltro { todos, pago, aguardando, cancelado }

/// Filtro de repasse (crédito na carteira do lojista após entrega).
enum LojasFinStatusRepasseFiltro { todos, repassado, pendente, cancelado }

/// Linha agregada por loja (tabela + gráficos).
class LojasFinResumoLoja {
  LojasFinResumoLoja({
    required this.lojaId,
    required this.lojaNome,
  });

  final String lojaId;
  final String lojaNome;
  double bruto = 0;
  double liquido = 0;
  double comissaoPlataforma = 0;
  int pedidosPagos = 0;
  double repassado = 0;
  double pendenteRepasse = 0;
}

/// Linha da tabela (um pedido).
class LojasFinLinhaPedido {
  const LojasFinLinhaPedido({
    required this.pedidoId,
    required this.lojaId,
    required this.lojaNome,
    required this.data,
    required this.bruto,
    required this.comissao,
    required this.liquido,
    required this.statusPagamento,
    required this.statusRepasse,
    required this.statusPedido,
  });

  final String pedidoId;
  final String lojaId;
  final String lojaNome;
  final DateTime? data;
  final double bruto;
  final double comissao;
  final double liquido;
  final String statusPagamento;
  final String statusRepasse;
  final String statusPedido;
}

/// KPIs + séries para gráficos.
class LojasFinDashboardSnapshot {
  const LojasFinDashboardSnapshot({
    required this.brutoVendido,
    required this.liquidoLojas,
    required this.valorPlataforma,
    required this.pedidosPagos,
    required this.comissoesPlataforma,
    required this.pendenteRepasse,
    required this.repassadoLojas,
    required this.vendasPorDia,
    required this.lucroPlataformaPorDia,
    required this.porLoja,
    required this.rankingLojas,
    required this.linhasPedidos,
    required this.nomesLojas,
  });

  final double brutoVendido;
  final double liquidoLojas;
  final double valorPlataforma;
  final int pedidosPagos;
  final double comissoesPlataforma;
  final double pendenteRepasse;
  final double repassadoLojas;
  final List<({DateTime dia, double bruto})> vendasPorDia;
  final List<({DateTime dia, double lucro})> lucroPlataformaPorDia;
  final List<LojasFinResumoLoja> porLoja;
  final List<LojasFinResumoLoja> rankingLojas;
  final List<LojasFinLinhaPedido> linhasPedidos;
  final Map<String, String> nomesLojas;

  static const vazio = LojasFinDashboardSnapshot(
    brutoVendido: 0,
    liquidoLojas: 0,
    valorPlataforma: 0,
    pedidosPagos: 0,
    comissoesPlataforma: 0,
    pendenteRepasse: 0,
    repassadoLojas: 0,
    vendasPorDia: [],
    lucroPlataformaPorDia: [],
    porLoja: [],
    rankingLojas: [],
    linhasPedidos: [],
    nomesLojas: {},
  );
}

/// Agrega pedidos e lojas para o painel admin.
abstract final class AdminLojasFinanceiroService {
  static const Set<String> _statusCancelados = {
    'cancelado',
    'cancelado_pelo_cliente',
    'cancelado_pelo_lojista',
    'cancelado_lojista',
    'recusado',
    'expirado',
    'pix_expirado',
  };

  static const Set<String> _statusRepassado = {
    'entregue',
    'concluido',
    'finalizado',
  };

  static double _num(dynamic v) => CarteiraLojistaExtrato.numDyn(v);

  static String _nomeLoja(Map<String, dynamic> u) {
    for (final k in ['loja_nome', 'nome_loja', 'nome_fantasia', 'nome']) {
      final t = (u[k] ?? '').toString().trim();
      if (t.isNotEmpty && t != 'null') return t;
    }
    return 'Loja';
  }

  static String _resolverLojaId(Map<String, dynamic> p) {
    final a = (p['loja_id'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    return (p['lojista_id'] ?? '').toString().trim();
  }

  static DateTime? _dataPedido(Map<String, dynamic> p) {
    for (final k in [
      'data_pedido',
      'data_entregue',
      'data_entrega',
      'data_criacao',
    ]) {
      final ts = p[k];
      if (ts is Timestamp) return ts.toDate();
    }
    return null;
  }

  static double _brutoPedido(Map<String, dynamic> p) =>
      CarteiraLojistaExtrato.valorProdutosPedido(p);

  static double _comissaoPedido(Map<String, dynamic> p) =>
      _num(p['taxa_plataforma']);

  static double _liquidoPedido(Map<String, dynamic> p) =>
      CarteiraLojistaExtrato.creditoLoja(p);

  static double _plataformaPedido(Map<String, dynamic> p) {
    final vp = _num(p['valor_plataforma']);
    if (vp > 0) return vp;
    return _comissaoPedido(p) + _num(p['taxa_entregador']);
  }

  static String _statusPagamento(String status) {
    if (status == 'aguardando_pagamento') return 'aguardando';
    if (_statusCancelados.contains(status)) return 'cancelado';
    return 'pago';
  }

  static String _statusRepasse(String status) {
    if (_statusCancelados.contains(status)) return 'cancelado';
    if (_statusRepassado.contains(status)) return 'repassado';
    if (status == 'aguardando_pagamento') return 'cancelado';
    return 'pendente';
  }

  static String _rotuloPagamento(String cod) {
    switch (cod) {
      case 'aguardando':
        return 'Aguardando pagamento';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Pago';
    }
  }

  static String _rotuloRepasse(String cod) {
    switch (cod) {
      case 'repassado':
        return 'Repassado';
      case 'pendente':
        return 'Pendente repasse';
      case 'cancelado':
        return 'Cancelado';
      default:
        return cod;
    }
  }

  static ({DateTime start, DateTime end}) intervaloPeriodo({
    required LojasFinPeriodoRapido rapido,
    DateTime? inicioCustom,
    DateTime? fimCustom,
  }) {
    final now = DateTime.now();
    final fimHoje = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (rapido) {
      case LojasFinPeriodoRapido.hoje:
        return (
          start: DateTime(now.year, now.month, now.day),
          end: fimHoje,
        );
      case LojasFinPeriodoRapido.semana:
        return (
          start: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 6)),
          end: fimHoje,
        );
      case LojasFinPeriodoRapido.mes:
        return (
          start: DateTime(now.year, now.month, 1),
          end: fimHoje,
        );
      case LojasFinPeriodoRapido.personalizado:
        final i = inicioCustom ?? DateTime(now.year, now.month, 1);
        final f = fimCustom ?? fimHoje;
        return (
          start: DateTime(i.year, i.month, i.day),
          end: DateTime(f.year, f.month, f.day, 23, 59, 59),
        );
    }
  }

  static bool _dentroIntervalo(DateTime? dt, DateTime start, DateTime end) {
    if (dt == null) return false;
    return !dt.isBefore(start) && !dt.isAfter(end);
  }

  static String _soDigitos(String? v) =>
      (v ?? '').toString().replaceAll(RegExp(r'\D'), '');

  static String normalizarTexto(String entrada) {
    final t = entrada.trim().toLowerCase();
    return t
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c');
  }

  static String formatarCpf(String d) {
    if (d.length != 11) return d;
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  static String formatarCnpj(String d) {
    if (d.length != 14) return d;
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
        '${d.substring(8, 12)}-${d.substring(12)}';
  }

  /// Catálogo de lojistas para autocomplete (nome, CPF, CNPJ).
  static Future<List<LojaCatalogoItem>> carregarCatalogoLojas() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'lojista')
        .get();
    final lista = <LojaCatalogoItem>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      lista.add(
        LojaCatalogoItem(
          id: doc.id,
          nome: _nomeLoja(d),
          cpfDigitos: _soDigitos(d['cpf']?.toString()),
          cnpjDigitos: _soDigitos(d['cnpj']?.toString()),
        ),
      );
    }
    lista.sort((a, b) => a.nome.compareTo(b.nome));
    return lista;
  }

  static Future<Map<String, String>> _mapaNomesLojas() async {
    final catalogo = await carregarCatalogoLojas();
    return {for (final l in catalogo) l.id: l.nome};
  }

  /// Sugestões para o campo de busca (mín. 3 caracteres ou 3 dígitos).
  static List<LojaCatalogoItem> filtrarCatalogoLojas(
    List<LojaCatalogoItem> catalogo,
    String consulta, {
    int limite = 12,
  }) {
    final bruto = consulta.trim();
    if (bruto.isEmpty) return [];

    final digitos = _soDigitos(bruto);
    final soDocumento =
        digitos.length >= 3 && RegExp(r'^[\d.\-/\s]+$').hasMatch(bruto);

    Iterable<LojaCatalogoItem> base = catalogo;

    if (soDocumento) {
      if (digitos.length < 3) return [];
      base = catalogo.where(
        (l) =>
            (l.cpfDigitos.isNotEmpty && l.cpfDigitos.contains(digitos)) ||
            (l.cnpjDigitos.isNotEmpty && l.cnpjDigitos.contains(digitos)),
      );
    } else {
      final norm = normalizarTexto(bruto);
      if (norm.length < 3) return [];
      base = catalogo.where((l) => l.nomeNorm.contains(norm));
    }

    return base.take(limite).toList();
  }

  /// Resolve loja única por CPF/CNPJ completo (11 ou 14 dígitos).
  static String? resolverLojaIdPorDocumento(
    List<LojaCatalogoItem> catalogo,
    String consulta,
  ) {
    final digitos = _soDigitos(consulta);
    if (digitos.length != 11 && digitos.length != 14) return null;
    final matches = catalogo
        .where(
          (l) => l.cpfDigitos == digitos || l.cnpjDigitos == digitos,
        )
        .toList();
    return matches.length == 1 ? matches.first.id : null;
  }

  static Future<LojasFinDashboardSnapshot> carregar({
    required LojasFinPeriodoRapido periodoRapido,
    DateTime? dataInicio,
    DateTime? dataFim,
    String? lojaIdFiltro,
    String buscaNomeLoja = '',
    LojasFinStatusPagamentoFiltro filtroPagamento =
        LojasFinStatusPagamentoFiltro.todos,
    LojasFinStatusRepasseFiltro filtroRepasse =
        LojasFinStatusRepasseFiltro.todos,
  }) async {
    final nomes = await _mapaNomesLojas();
    final intervalo = intervaloPeriodo(
      rapido: periodoRapido,
      inicioCustom: dataInicio,
      fimCustom: dataFim,
    );
    final busca = buscaNomeLoja.trim().toLowerCase();

    final pedidosSnap =
        await FirebaseFirestore.instance.collection('pedidos').get();

    final porLojaMap = <String, LojasFinResumoLoja>{};
    final vendasDia = <String, double>{};
    final lucroDia = <String, double>{};
    final linhas = <LojasFinLinhaPedido>[];

    double brutoTotal = 0;
    double liquidoTotal = 0;
    double plataformaTotal = 0;
    double comissaoTotal = 0;
    double repassadoTotal = 0;
    double pendenteTotal = 0;
    var qtdPagos = 0;

    for (final doc in pedidosSnap.docs) {
      final p = doc.data();
      final lojaId = _resolverLojaId(p);
      if (lojaId.isEmpty) continue;

      if (lojaIdFiltro != null &&
          lojaIdFiltro.isNotEmpty &&
          lojaId != lojaIdFiltro) {
        continue;
      }

      final nomeLoja = nomes[lojaId] ?? 'Loja';
      if (busca.isNotEmpty && !nomeLoja.toLowerCase().contains(busca)) {
        continue;
      }

      final status = (p['status'] ?? 'pendente').toString();
      final stPag = _statusPagamento(status);
      final stRep = _statusRepasse(status);

      if (filtroPagamento == LojasFinStatusPagamentoFiltro.pago &&
          stPag != 'pago') {
        continue;
      }
      if (filtroPagamento == LojasFinStatusPagamentoFiltro.aguardando &&
          stPag != 'aguardando') {
        continue;
      }
      if (filtroPagamento == LojasFinStatusPagamentoFiltro.cancelado &&
          stPag != 'cancelado') {
        continue;
      }
      if (filtroRepasse == LojasFinStatusRepasseFiltro.repassado &&
          stRep != 'repassado') {
        continue;
      }
      if (filtroRepasse == LojasFinStatusRepasseFiltro.pendente &&
          stRep != 'pendente') {
        continue;
      }
      if (filtroRepasse == LojasFinStatusRepasseFiltro.cancelado &&
          stRep != 'cancelado') {
        continue;
      }

      final data = _dataPedido(p);
      if (!_dentroIntervalo(data, intervalo.start, intervalo.end)) continue;

      if (stPag != 'pago') continue;

      final bruto = _brutoPedido(p);
      final comissao = _comissaoPedido(p);
      final liquido = _liquidoPedido(p);
      final plataforma = _plataformaPedido(p);

      brutoTotal += bruto;
      liquidoTotal += liquido;
      comissaoTotal += comissao;
      plataformaTotal += plataforma;
      qtdPagos++;

      if (stRep == 'repassado') {
        repassadoTotal += liquido;
      } else if (stRep == 'pendente') {
        pendenteTotal += liquido;
      }

      final lojaResumo = porLojaMap.putIfAbsent(
        lojaId,
        () => LojasFinResumoLoja(lojaId: lojaId, lojaNome: nomeLoja),
      );
      lojaResumo.bruto += bruto;
      lojaResumo.liquido += liquido;
      lojaResumo.comissaoPlataforma += comissao;
      lojaResumo.pedidosPagos++;
      if (stRep == 'repassado') {
        lojaResumo.repassado += liquido;
      } else if (stRep == 'pendente') {
        lojaResumo.pendenteRepasse += liquido;
      }

      if (data != null) {
        final chave =
            '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
        vendasDia[chave] = (vendasDia[chave] ?? 0) + bruto;
        lucroDia[chave] = (lucroDia[chave] ?? 0) + comissao;
      }

      linhas.add(
        LojasFinLinhaPedido(
          pedidoId: doc.id,
          lojaId: lojaId,
          lojaNome: nomeLoja,
          data: data,
          bruto: bruto,
          comissao: comissao,
          liquido: liquido,
          statusPagamento: _rotuloPagamento(stPag),
          statusRepasse: _rotuloRepasse(stRep),
          statusPedido: status,
        ),
      );
    }

    linhas.sort((a, b) {
      final da = a.data;
      final db = b.data;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    final vendasPorDia = vendasDia.entries.map((e) {
      final parts = e.key.split('-');
      final dia = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      return (dia: dia, bruto: e.value);
    }).toList()
      ..sort((a, b) => a.dia.compareTo(b.dia));

    final lucroPlataformaPorDia = lucroDia.entries.map((e) {
      final parts = e.key.split('-');
      final dia = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      return (dia: dia, lucro: e.value);
    }).toList()
      ..sort((a, b) => a.dia.compareTo(b.dia));

    final porLoja = porLojaMap.values.toList()
      ..sort((a, b) => b.bruto.compareTo(a.bruto));
    final ranking = List<LojasFinResumoLoja>.from(porLoja);

    return LojasFinDashboardSnapshot(
      brutoVendido: brutoTotal,
      liquidoLojas: liquidoTotal,
      valorPlataforma: plataformaTotal,
      pedidosPagos: qtdPagos,
      comissoesPlataforma: comissaoTotal,
      pendenteRepasse: pendenteTotal,
      repassadoLojas: repassadoTotal,
      vendasPorDia: vendasPorDia,
      lucroPlataformaPorDia: lucroPlataformaPorDia,
      porLoja: porLoja,
      rankingLojas: ranking,
      linhasPedidos: linhas,
      nomesLojas: nomes,
    );
  }
}
