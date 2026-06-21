import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_dashboard_data.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Agrega métricas comerciais a partir de Firestore (`pedidos`, `produtos`, `clientes_comercial`).
abstract final class ComercialDashboardService {
  static const _statusEntregue = 'entregue';
  static const _limitePedidos = 5000;

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _dataCurta = DateFormat('d MMM', 'pt_BR');
  static final _dataCompleta = DateFormat('dd/MM/yyyy', 'pt_BR');

  /// Carrega e agrega todos os blocos do dashboard.
  static Future<ComercialDashboardData> carregar({
    required String lojaId,
    required String periodoGrafico,
  }) async {
    final db = FirebaseFirestore.instance;
    final agora = DateTime.now();
    final inicioConsulta = agora.subtract(const Duration(days: 395));

    final resultados = await Future.wait([
      db
          .collection('pedidos')
          .where('loja_id', isEqualTo: lojaId)
          .where('status', isEqualTo: _statusEntregue)
          .where('data_pedido', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioConsulta))
          .orderBy('data_pedido')
          .limit(_limitePedidos)
          .get(),
      db.collection('produtos').where('lojista_id', isEqualTo: lojaId).get(),
      db.collection('users').doc(lojaId).collection('clientes_comercial').get(),
    ]);

    final pedidosSnap = resultados[0];
    final produtosSnap = resultados[1];
    final creditoSnap = resultados[2];

    final pedidos = pedidosSnap.docs
        .map((d) => _PedidoComercial.fromDoc(d.id, safeWebDocData(d)))
        .where((p) => p.data != null)
        .toList();

    final produtos = produtosSnap.docs
        .map((d) => _ProdutoComercial.fromDoc(d.id, safeWebDocData(d)))
        .where((p) => p.ativo)
        .toList();

    final clientesCredito = creditoSnap.docs
        .map((d) => _ClienteCredito.fromDoc(safeWebDocData(d)))
        .toList();

    if (pedidos.isEmpty && produtos.isEmpty && clientesCredito.isEmpty) {
      return ComercialDashboardData.vazio();
    }

    final hojeIni = _inicioDia(agora);
    final hojeFim = hojeIni.add(const Duration(days: 1));
    final ontemIni = hojeIni.subtract(const Duration(days: 1));
    final ontemFim = hojeIni;

    final pedidosHoje = pedidos.where((p) => _entre(p.data!, hojeIni, hojeFim)).toList();
    final pedidosOntem = pedidos.where((p) => _entre(p.data!, ontemIni, ontemFim)).toList();

    final vendasHoje = _somaTotal(pedidosHoje);
    final vendasOntem = _somaTotal(pedidosOntem);

    final clientesAtivos = _clientesDistintos(
      pedidos.where((p) => p.data != null && p.data!.isAfter(agora.subtract(const Duration(days: 30)))),
    );
    final clientesAtivosAnterior = _clientesDistintos(
      pedidos.where((p) {
        if (p.data == null) return false;
        final d = p.data!;
        return d.isAfter(agora.subtract(const Duration(days: 60))) &&
            d.isBefore(agora.subtract(const Duration(days: 30)));
      }),
    );

    final resumoCredito = _montarResumoCredito(clientesCredito, agora);
    final pendencias = _montarPendencias(clientesCredito, agora);

    final kpis = ComercialDashboardKpis(
      vendasHoje: vendasHoje,
      vendasOntem: vendasOntem,
      qtdVendasHoje: pedidosHoje.length,
      qtdVendasOntem: pedidosOntem.length,
      clientesAtivos: clientesAtivos.length,
      clientesAtivosAnterior: clientesAtivosAnterior.length,
      creditoUtilizado: resumoCredito.creditoUtilizado,
      creditoUtilizadoAnterior: _creditoUtilizadoEm(clientesCredito, ontemFim),
      pendenciasAberto: pendencias.resumo.emAtraso + pendencias.resumo.vencendoHoje + pendencias.resumo.vencendo7Dias,
      pendenciasAbertoAnterior: pendencias.resumo.emAtraso,
      ticketMedioHoje: pedidosHoje.isEmpty ? 0 : vendasHoje / pedidosHoje.length,
      ticketMedioOntem: pedidosOntem.isEmpty ? 0 : vendasOntem / pedidosOntem.length,
    );

    final clientesStats = _montarClientesStats(pedidos, clientesCredito, agora);
    final topClientes = _montarTopClientes(pedidos);
    final formasPagamento = _montarFormasPagamento(pedidosHoje);
    final produtosRank = _montarProdutosMaisVendidos(pedidosHoje);
    final produtosSemVenda = _montarProdutosSemVenda(produtos, pedidos, agora);
    final evolucao = _montarEvolucao(pedidos, periodoGrafico, agora);
    final insights = _montarInsights(
      pedidos: pedidos,
      kpis: kpis,
      resumoCredito: resumoCredito,
      pendencias: pendencias,
      produtosRank: produtosRank,
      agora: agora,
    );

    return ComercialDashboardData(
      atualizadoEm: agora,
      kpis: kpis,
      resumoCredito: resumoCredito,
      clientesStats: clientesStats,
      topClientes: topClientes,
      pendenciasResumo: pendencias.resumo,
      pendenciasLista: pendencias.lista,
      formasPagamento: formasPagamento,
      insights: insights,
      produtosMaisVendidos: produtosRank,
      produtosSemVenda: produtosSemVenda,
      evolucaoVendas: evolucao,
    );
  }

  static String formatarMoeda(double v) => _moeda.format(v);

  static String formatarPercentual(double v, {bool comSinal = true}) {
    final sinal = v > 0 ? '+' : '';
    final texto = NumberFormat('#,##0.0', 'pt_BR').format(v.abs());
    if (!comSinal) return '$texto%';
    if (v == 0) return '0%';
    return '$sinal$texto%';
  }

  static String formatarDataCurta(DateTime d) => _dataCurta.format(d);

  static String formatarDataCompleta(DateTime d) => _dataCompleta.format(d);

  static String rotuloDataHoje(DateTime agora) {
    final hoje = _inicioDia(agora);
    final diff = hoje.difference(_inicioDia(DateTime.now())).inDays;
    if (diff == 0) return 'Hoje, ${DateFormat("d 'de' MMMM", 'pt_BR').format(hoje)}';
    return DateFormat("d 'de' MMMM", 'pt_BR').format(hoje);
  }

  // ─── Pedidos ───

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  static DateTime _inicioDia(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _entre(DateTime d, DateTime ini, DateTime fim) =>
      !d.isBefore(ini) && d.isBefore(fim);

  static double _somaTotal(List<_PedidoComercial> pedidos) =>
      pedidos.fold(0, (s, p) => s + p.total);

  static Set<String> _clientesDistintos(Iterable<_PedidoComercial> pedidos) {
    return pedidos
        .map((p) => p.clienteId)
        .where((id) => id != null && id.isNotEmpty && id != 'venda_balcao')
        .cast<String>()
        .toSet();
  }

  static String _categoriaFormaPagamento(String? raw) {
    final f = (raw ?? '').toLowerCase();
    if (f.contains('dinheiro')) return 'dinheiro';
    if (f.contains('pix')) return 'pix';
    if (f.contains('débito') || f.contains('debito')) return 'cartao_debito';
    if (f.contains('cartão de crédito') ||
        f.contains('cartao de credito') ||
        (f.contains('cartão') && f.contains('crédito')) ||
        (f.contains('cartao') && f.contains('credito'))) {
      return 'cartao_credito';
    }
    if (f.contains('crédito cliente') ||
        f.contains('credito cliente') ||
        f.contains('fiado') ||
        f.contains('crediário') ||
        f.contains('crediario')) {
      return 'credito_cliente';
    }
    if (f.contains('cartão') || f.contains('cartao') || f.contains('crédito') || f.contains('credito')) {
      return 'cartao_credito';
    }
    return 'outros';
  }

  static const _coresForma = {
    'dinheiro': Color(0xFF10B981),
    'pix': Color(0xFF3B82F6),
    'cartao_credito': Color(0xFF8B5CF6),
    'cartao_debito': Color(0xFFF59E0B),
    'credito_cliente': Color(0xFFEF4444),
    'outros': Color(0xFF64748B),
  };

  static const _rotulosForma = {
    'dinheiro': 'Dinheiro',
    'pix': 'PIX',
    'cartao_credito': 'Cartão Crédito',
    'cartao_debito': 'Cartão Débito',
    'credito_cliente': 'Crédito Cliente',
    'outros': 'Outros',
  };

  static List<ComercialFormaPagamento> _montarFormasPagamento(List<_PedidoComercial> pedidosHoje) {
    final map = <String, double>{
      'dinheiro': 0,
      'pix': 0,
      'cartao_credito': 0,
      'cartao_debito': 0,
      'credito_cliente': 0,
    };
    for (final p in pedidosHoje) {
      final cat = _categoriaFormaPagamento(p.formaPagamento);
      if (map.containsKey(cat)) {
        map[cat] = map[cat]! + p.total;
      }
    }
    final total = map.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return [];

    return map.entries
        .where((e) => e.value > 0)
        .map(
          (e) => ComercialFormaPagamento(
            nome: _rotulosForma[e.key] ?? e.key,
            valor: e.value,
            percentual: (e.value / total) * 100,
            cor: _coresForma[e.key] ?? const Color(0xFF64748B),
          ),
        )
        .toList()
      ..sort((a, b) => b.valor.compareTo(a.valor));
  }

  static List<ComercialTopCliente> _montarTopClientes(List<_PedidoComercial> pedidos) {
    final map = <String, _AggCliente>{};
    for (final p in pedidos) {
      final id = p.clienteId;
      if (id == null || id.isEmpty || id == 'venda_balcao') continue;
      final agg = map.putIfAbsent(id, () => _AggCliente(nome: p.clienteNome ?? 'Cliente', telefone: p.clienteTelefone));
      agg.compras++;
      agg.total += p.total;
      if ((p.clienteNome ?? '').trim().isNotEmpty) agg.nome = p.clienteNome!.trim();
    }
    final lista = map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    return lista
        .take(10)
        .map(
          (c) => ComercialTopCliente(
            nome: c.nome,
            compras: c.compras,
            totalGasto: c.total,
            telefone: c.telefone,
          ),
        )
        .toList();
  }

  static ComercialClientesStats _montarClientesStats(
    List<_PedidoComercial> pedidos,
    List<_ClienteCredito> credito,
    DateTime agora,
  ) {
    final primeiroPedido = <String, DateTime>{};
    final ultimoPedido = <String, DateTime>{};
    final pedidos30 = <String, int>{};
    final pedidos30Anterior = <String, int>{};

    final ini30 = agora.subtract(const Duration(days: 30));
    final ini60 = agora.subtract(const Duration(days: 60));

    for (final p in pedidos) {
      final id = p.clienteId;
      if (id == null || id.isEmpty || id == 'venda_balcao' || p.data == null) continue;
      final d = p.data!;
      primeiroPedido.putIfAbsent(id, () => d);
      if (d.isBefore(primeiroPedido[id]!)) primeiroPedido[id] = d;
      ultimoPedido[id] = ultimoPedido[id] == null || d.isAfter(ultimoPedido[id]!) ? d : ultimoPedido[id]!;

      if (!d.isBefore(ini30)) {
        pedidos30[id] = (pedidos30[id] ?? 0) + 1;
      } else if (!d.isBefore(ini60) && d.isBefore(ini30)) {
        pedidos30Anterior[id] = (pedidos30Anterior[id] ?? 0) + 1;
      }
    }

    int novos = 0;
    int novosAnt = 0;
    for (final entry in primeiroPedido.entries) {
      if (!entry.value.isBefore(ini30)) novos++;
      if (!entry.value.isBefore(ini60) && entry.value.isBefore(ini30)) novosAnt++;
    }

    int recorrentes = pedidos30.values.where((c) => c >= 2).length;
    int recorrentesAnt = pedidos30Anterior.values.where((c) => c >= 2).length;

    int inativos = 0;
    int inativosAnt = 0;
    final limiteInativo = agora.subtract(const Duration(days: 60));
    for (final entry in ultimoPedido.entries) {
      if (entry.value.isBefore(limiteInativo)) inativos++;
      if (entry.value.isBefore(limiteInativo.subtract(const Duration(days: 30)))) inativosAnt++;
    }

    final gastos = <String, double>{};
    for (final p in pedidos) {
      final id = p.clienteId;
      if (id == null || id.isEmpty || id == 'venda_balcao') continue;
      gastos[id] = (gastos[id] ?? 0) + p.total;
    }
    final valores = gastos.values.toList()..sort();
    final limiarVip = valores.isEmpty ? double.infinity : valores[(valores.length * 0.8).floor().clamp(0, valores.length - 1)];

    int vip = 0;
    for (final c in credito) {
      if (c.vip) vip++;
    }
    if (vip == 0) {
      vip = gastos.entries.where((e) => e.value >= limiarVip && e.value > 0).length;
    }

    final comPend = credito.where((c) => c.pendenciasAbertas > 0).length;

    return ComercialClientesStats(
      novosClientes: novos,
      novosClientesAnterior: novosAnt,
      recorrentes: recorrentes,
      recorrentesAnterior: recorrentesAnt,
      inativos: inativos,
      inativosAnterior: inativosAnt,
      vip: vip,
      vipAnterior: vip,
      comPendencia: comPend,
      comPendenciaAnterior: comPend,
    );
  }

  static List<ComercialProdutoRanking> _montarProdutosMaisVendidos(List<_PedidoComercial> pedidosHoje) {
    final map = <String, _AggProduto>{};
    for (final p in pedidosHoje) {
      for (final item in p.itens) {
        final id = item.produtoId ?? item.nome;
        final agg = map.putIfAbsent(id, () => _AggProduto(nome: item.nome));
        agg.qtd += item.quantidade;
        agg.faturamento += item.valorTotal;
      }
    }
    final lista = map.values.toList()..sort((a, b) => b.faturamento.compareTo(a.faturamento));
    return lista
        .take(5)
        .map(
          (p) => ComercialProdutoRanking(
            nome: p.nome,
            quantidade: p.qtd,
            faturamento: p.faturamento,
          ),
        )
        .toList();
  }

  static List<ComercialProdutoSemVenda> _montarProdutosSemVenda(
    List<_ProdutoComercial> produtos,
    List<_PedidoComercial> pedidos,
    DateTime agora,
  ) {
    final limite = agora.subtract(const Duration(days: 30));
    final ultimaVenda = <String, DateTime>{};

    for (final p in pedidos) {
      if (p.data == null) continue;
      for (final item in p.itens) {
        final id = item.produtoId;
        if (id == null) continue;
        final atual = ultimaVenda[id];
        if (atual == null || p.data!.isAfter(atual)) ultimaVenda[id] = p.data!;
      }
    }

    final semVenda = <ComercialProdutoSemVenda>[];
    for (final prod in produtos) {
      final ultima = ultimaVenda[prod.id];
      if (ultima != null && !ultima.isBefore(limite)) continue;
      semVenda.add(
        ComercialProdutoSemVenda(
          nome: prod.nome,
          estoque: prod.estoque,
          ultimaVenda: ultima,
        ),
      );
    }
    semVenda.sort((a, b) {
      if (a.ultimaVenda == null && b.ultimaVenda == null) return a.nome.compareTo(b.nome);
      if (a.ultimaVenda == null) return -1;
      if (b.ultimaVenda == null) return 1;
      return a.ultimaVenda!.compareTo(b.ultimaVenda!);
    });
    return semVenda.take(5).toList();
  }

  static ComercialEvolucaoVendas _montarEvolucao(
    List<_PedidoComercial> pedidos,
    String periodo,
    DateTime agora,
  ) {
    final categorias = ['dinheiro', 'pix', 'cartao_credito', 'cartao_debito', 'credito_cliente'];
    final series = {for (final c in categorias) c: <double>[]};
    final rotulos = <String>[];

    if (periodo == '12 meses') {
      for (var i = 11; i >= 0; i--) {
        final mesRef = DateTime(agora.year, agora.month - i, 1);
        final proxMes = DateTime(mesRef.year, mesRef.month + 1, 1);
        rotulos.add(DateFormat('MMM/yy', 'pt_BR').format(mesRef));
        final bucket = {for (final c in categorias) c: 0.0};
        for (final p in pedidos) {
          if (p.data == null) continue;
          if (p.data!.isBefore(mesRef) || !p.data!.isBefore(proxMes)) continue;
          final cat = _categoriaFormaPagamento(p.formaPagamento);
          if (bucket.containsKey(cat)) bucket[cat] = bucket[cat]! + p.total;
        }
        for (final c in categorias) {
          series[c]!.add(bucket[c] ?? 0);
        }
      }
    } else {
      final dias = periodo == '30 dias' ? 30 : 7;
      for (var i = dias - 1; i >= 0; i--) {
        final dia = _inicioDia(agora.subtract(Duration(days: i)));
        final fim = dia.add(const Duration(days: 1));
        rotulos.add(_dataCurta.format(dia));
        final bucket = {for (final c in categorias) c: 0.0};
        for (final p in pedidos) {
          if (p.data == null || !_entre(p.data!, dia, fim)) continue;
          final cat = _categoriaFormaPagamento(p.formaPagamento);
          if (bucket.containsKey(cat)) bucket[cat] = bucket[cat]! + p.total;
        }
        for (final c in categorias) {
          series[c]!.add(bucket[c] ?? 0);
        }
      }
    }

    var maxValor = 0.0;
    for (final valores in series.values) {
      for (final v in valores) {
        if (v > maxValor) maxValor = v;
      }
    }

    return ComercialEvolucaoVendas(
      rotulos: rotulos,
      series: series,
      maxValor: maxValor,
    );
  }

  // ─── Crédito / pendências ───

  static double _creditoUtilizadoEm(List<_ClienteCredito> clientes, DateTime ref) {
    // Sem histórico diário: usa snapshot atual como aproximação.
    return clientes.fold(0.0, (s, c) => s + c.creditoUtilizado);
  }

  static ComercialResumoCredito _montarResumoCredito(
    List<_ClienteCredito> clientes,
    DateTime agora,
  ) {
    var limite = 0.0;
    var utilizado = 0.0;
    var inadimplentes = 0;
    var atraso = 0.0;
    var comCredito = 0;

    for (final c in clientes) {
      limite += c.limiteCredito;
      utilizado += c.creditoUtilizado;
      if (c.limiteCredito > 0 || c.creditoUtilizado > 0) comCredito++;
      if (c.valorAtraso > 0) {
        inadimplentes++;
        atraso += c.valorAtraso;
      }
    }

    return ComercialResumoCredito(
      limiteTotal: limite,
      creditoUtilizado: utilizado,
      creditoDisponivel: (limite - utilizado).clamp(0, double.infinity),
      clientesComCredito: comCredito,
      clientesInadimplentes: inadimplentes,
      valorEmAtraso: atraso,
    );
  }

  static ({ComercialPendenciasResumo resumo, List<ComercialPendenciaItem> lista}) _montarPendencias(
    List<_ClienteCredito> clientes,
    DateTime agora,
  ) {
    final hoje = _inicioDia(agora);
    final fim7 = hoje.add(const Duration(days: 7));
    final ini30 = hoje.subtract(const Duration(days: 30));

    var vencendoHoje = 0.0;
    var vencendo7 = 0.0;
    var emAtraso = 0.0;
    var recuperadas = 0.0;
    final lista = <ComercialPendenciaItem>[];

    for (final c in clientes) {
      for (final pend in c.pendencias) {
        if (pend.paga) {
          if (pend.pagoEm != null && !pend.pagoEm!.isBefore(ini30)) {
            recuperadas += pend.valor;
          }
          continue;
        }

        final venc = _inicioDia(pend.vencimento);
        if (venc == hoje) {
          vencendoHoje += pend.valor;
        } else if (venc.isAfter(hoje) && venc.isBefore(fim7)) {
          vencendo7 += pend.valor;
        } else if (venc.isBefore(hoje)) {
          emAtraso += pend.valor;
          lista.add(
            ComercialPendenciaItem(
              cliente: c.nome,
              valor: pend.valor,
              vencimento: pend.vencimento,
              diasAtraso: hoje.difference(venc).inDays,
              telefone: c.telefone,
            ),
          );
        }
      }
    }

    lista.sort((a, b) => b.diasAtraso.compareTo(a.diasAtraso));

    return (
      resumo: ComercialPendenciasResumo(
        vencendoHoje: vencendoHoje,
        vencendo7Dias: vencendo7,
        emAtraso: emAtraso,
        recuperadas30Dias: recuperadas,
      ),
      lista: lista.take(10).toList(),
    );
  }

  static List<ComercialInsight> _montarInsights({
    required List<_PedidoComercial> pedidos,
    required ComercialDashboardKpis kpis,
    required ComercialResumoCredito resumoCredito,
    required ({ComercialPendenciasResumo resumo, List<ComercialPendenciaItem> lista}) pendencias,
    required List<ComercialProdutoRanking> produtosRank,
    required DateTime agora,
  }) {
    final insights = <ComercialInsight>[];

    if (kpis.vendasOntem > 0 || kpis.vendasHoje > 0) {
      final v = kpis.variacaoVendas;
      insights.add(
        ComercialInsight(
          texto: v >= 0
              ? 'Vendas aumentaram ${formatarPercentual(v)} comparado a ontem.'
              : 'Vendas caíram ${formatarPercentual(v.abs(), comSinal: false)} comparado a ontem.',
          iconColor: v >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          bgColor: v >= 0 ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
        ),
      );
    }

    final proximosLimite = resumoCredito.limiteTotal > 0
        ? (resumoCredito.creditoUtilizado / resumoCredito.limiteTotal)
        : 0.0;
    if (proximosLimite >= 0.7) {
      insights.add(
        ComercialInsight(
          texto: 'Crédito da loja está ${formatarPercentual(proximosLimite * 100, comSinal: false)} utilizado.',
          iconColor: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFEF3C7),
        ),
      );
    }

    if (pendencias.resumo.emAtraso > 0) {
      insights.add(
        ComercialInsight(
          texto: '${formatarMoeda(pendencias.resumo.emAtraso)} em pendências vencidas.',
          iconColor: const Color(0xFFEF4444),
          bgColor: const Color(0xFFFEE2E2),
        ),
      );
    }

    final ultimoPorCliente = <String, _PedidoComercial>{};
    for (final p in pedidos) {
      final id = p.clienteId;
      if (id == null || id.isEmpty || id == 'venda_balcao' || p.data == null) continue;
      final atual = ultimoPorCliente[id];
      if (atual == null || p.data!.isAfter(atual.data!)) ultimoPorCliente[id] = p;
    }
    if (ultimoPorCliente.isNotEmpty) {
      var maisAntigo = ultimoPorCliente.values.first;
      for (final p in ultimoPorCliente.values) {
        if (p.data!.isBefore(maisAntigo.data!)) maisAntigo = p;
      }
      final dias = agora.difference(maisAntigo.data!).inDays;
      if (dias >= 30) {
        insights.add(
          ComercialInsight(
            texto: 'Cliente ${maisAntigo.clienteNome ?? 'sem nome'} não compra há $dias dias.',
            iconColor: const Color(0xFF3B82F6),
            bgColor: const Color(0xFFDBEAFE),
          ),
        );
      }
    }

    if (produtosRank.isNotEmpty) {
      insights.add(
        ComercialInsight(
          texto: 'Produto líder hoje: ${produtosRank.first.nome} (${produtosRank.first.quantidade} un.).',
          iconColor: const Color(0xFF10B981),
          bgColor: const Color(0xFFD1FAE5),
        ),
      );
    }

    if (insights.isEmpty) {
      insights.add(
        const ComercialInsight(
          texto: 'Sem insights suficientes — registre vendas no PDV para alimentar o dashboard.',
          iconColor: Color(0xFF64748B),
          bgColor: Color(0xFFF1F5F9),
        ),
      );
    }

    return insights.take(5).toList();
  }
}

// ─── Modelos internos ───

class _PedidoComercial {
  _PedidoComercial({
    required this.total,
    required this.formaPagamento,
    required this.clienteId,
    required this.clienteNome,
    required this.clienteTelefone,
    required this.data,
    required this.itens,
  });

  final double total;
  final String? formaPagamento;
  final String? clienteId;
  final String? clienteNome;
  final String? clienteTelefone;
  final DateTime? data;
  final List<_ItemPedido> itens;

  factory _PedidoComercial.fromDoc(String id, Map<String, dynamic> d) {
    final ts = d['data_pedido'] ?? d['data_entrega'] ?? d['data_entregue'] ?? d['created_at'];
    DateTime? data;
    if (ts is Timestamp) data = ts.toDate();

    final itensRaw = d['itens'];
    final itens = <_ItemPedido>[];
    if (itensRaw is List) {
      for (final raw in itensRaw) {
        if (raw is Map) {
          final m = Map<String, dynamic>.from(raw);
          itens.add(
            _ItemPedido(
              produtoId: m['produto_id']?.toString(),
              nome: (m['nome'] ?? 'Produto').toString(),
              quantidade: (m['quantidade'] is num) ? (m['quantidade'] as num).toInt() : int.tryParse('${m['quantidade']}') ?? 1,
              valorTotal: ComercialDashboardService._num(m['valor_total'] ?? m['preco']),
            ),
          );
        }
      }
    }

    return _PedidoComercial(
      total: ComercialDashboardService._num(d['total']),
      formaPagamento: d['forma_pagamento']?.toString(),
      clienteId: d['cliente_id']?.toString(),
      clienteNome: d['cliente_nome']?.toString(),
      clienteTelefone: d['cliente_telefone']?.toString(),
      data: data,
      itens: itens,
    );
  }
}

class _ItemPedido {
  _ItemPedido({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.valorTotal,
  });

  final String? produtoId;
  final String nome;
  final int quantidade;
  final double valorTotal;
}

class _ProdutoComercial {
  _ProdutoComercial({required this.id, required this.nome, required this.estoque, required this.ativo});

  final String id;
  final String nome;
  final int estoque;
  final bool ativo;

  factory _ProdutoComercial.fromDoc(String id, Map<String, dynamic> d) {
    return _ProdutoComercial(
      id: id,
      nome: (d['nome'] ?? d['titulo'] ?? 'Produto').toString(),
      estoque: (d['estoque_qtd'] is num) ? (d['estoque_qtd'] as num).toInt() : int.tryParse('${d['estoque_qtd']}') ?? 0,
      ativo: d['ativo'] != false,
    );
  }
}

class _ClienteCredito {
  _ClienteCredito({
    required this.nome,
    required this.telefone,
    required this.limiteCredito,
    required this.creditoUtilizado,
    required this.vip,
    required this.pendencias,
    required this.pendenciasAbertas,
    required this.valorAtraso,
  });

  final String nome;
  final String? telefone;
  final double limiteCredito;
  final double creditoUtilizado;
  final bool vip;
  final List<_PendenciaCredito> pendencias;
  final int pendenciasAbertas;
  final double valorAtraso;

  factory _ClienteCredito.fromDoc(Map<String, dynamic> d) {
    final pendentesRaw = d['pendencias'];
    final pendencias = <_PendenciaCredito>[];
    if (pendentesRaw is List) {
      for (final raw in pendentesRaw) {
        if (raw is Map) {
          pendencias.add(_PendenciaCredito.fromMap(Map<String, dynamic>.from(raw)));
        }
      }
    }

    final hoje = ComercialDashboardService._inicioDia(DateTime.now());
    var abertas = 0;
    var atraso = 0.0;
    for (final p in pendencias) {
      if (p.paga) continue;
      abertas++;
      if (ComercialDashboardService._inicioDia(p.vencimento).isBefore(hoje)) {
        atraso += p.valor;
      }
    }

    return _ClienteCredito(
      nome: (d['cliente_nome'] ?? d['nome'] ?? 'Cliente').toString(),
      telefone: d['telefone']?.toString(),
      limiteCredito: ComercialDashboardService._num(d['limite_credito']),
      creditoUtilizado: ComercialDashboardService._num(d['credito_utilizado']),
      vip: d['vip'] == true,
      pendencias: pendencias,
      pendenciasAbertas: abertas,
      valorAtraso: atraso,
    );
  }
}

class _PendenciaCredito {
  _PendenciaCredito({
    required this.valor,
    required this.vencimento,
    required this.paga,
    required this.pagoEm,
  });

  final double valor;
  final DateTime vencimento;
  final bool paga;
  final DateTime? pagoEm;

  factory _PendenciaCredito.fromMap(Map<String, dynamic> m) {
    DateTime parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    }

    final status = (m['status'] ?? '').toString().toLowerCase();
    return _PendenciaCredito(
      valor: ComercialDashboardService._num(m['valor']),
      vencimento: parseTs(m['vencimento']),
      paga: status == 'paga' || status == 'pago' || m['pago'] == true,
      pagoEm: m['pago_em'] != null ? parseTs(m['pago_em']) : null,
    );
  }
}

class _AggCliente {
  _AggCliente({required this.nome, this.telefone});

  String nome;
  String? telefone;
  int compras = 0;
  double total = 0;
}

class _AggProduto {
  _AggProduto({required this.nome});

  final String nome;
  int qtd = 0;
  double faturamento = 0;
}
