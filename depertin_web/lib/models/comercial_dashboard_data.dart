import 'package:flutter/material.dart';

/// Snapshot agregado do Dashboard Comercial (Firestore).
class ComercialDashboardData {
  const ComercialDashboardData({
    required this.atualizadoEm,
    required this.kpis,
    required this.resumoCredito,
    required this.clientesStats,
    required this.topClientes,
    required this.pendenciasResumo,
    required this.pendenciasLista,
    required this.formasPagamento,
    required this.insights,
    required this.produtosMaisVendidos,
    required this.produtosSemVenda,
    required this.evolucaoVendas,
  });

  final DateTime atualizadoEm;
  final ComercialDashboardKpis kpis;
  final ComercialResumoCredito resumoCredito;
  final ComercialClientesStats clientesStats;
  final List<ComercialTopCliente> topClientes;
  final ComercialPendenciasResumo pendenciasResumo;
  final List<ComercialPendenciaItem> pendenciasLista;
  final List<ComercialFormaPagamento> formasPagamento;
  final List<ComercialInsight> insights;
  final List<ComercialProdutoRanking> produtosMaisVendidos;
  final List<ComercialProdutoSemVenda> produtosSemVenda;
  final ComercialEvolucaoVendas evolucaoVendas;

  static ComercialDashboardData vazio() {
    return ComercialDashboardData(
      atualizadoEm: DateTime.now(),
      kpis: ComercialDashboardKpis.vazio(),
      resumoCredito: ComercialResumoCredito.vazio(),
      clientesStats: ComercialClientesStats.vazio(),
      topClientes: const [],
      pendenciasResumo: ComercialPendenciasResumo.vazio(),
      pendenciasLista: const [],
      formasPagamento: const [],
      insights: const [
        ComercialInsight(
          texto: 'Nenhuma venda registrada no período consultado.',
          iconColor: Color(0xFF64748B),
          bgColor: Color(0xFFF1F5F9),
        ),
      ],
      produtosMaisVendidos: const [],
      produtosSemVenda: const [],
      evolucaoVendas: ComercialEvolucaoVendas.vazio(),
    );
  }
}

class ComercialDashboardKpis {
  const ComercialDashboardKpis({
    required this.vendasHoje,
    required this.vendasOntem,
    required this.qtdVendasHoje,
    required this.qtdVendasOntem,
    required this.clientesAtivos,
    required this.clientesAtivosAnterior,
    required this.creditoUtilizado,
    required this.creditoUtilizadoAnterior,
    required this.pendenciasAberto,
    required this.pendenciasAbertoAnterior,
    required this.ticketMedioHoje,
    required this.ticketMedioOntem,
  });

  final double vendasHoje;
  final double vendasOntem;
  final int qtdVendasHoje;
  final int qtdVendasOntem;
  final int clientesAtivos;
  final int clientesAtivosAnterior;
  final double creditoUtilizado;
  final double creditoUtilizadoAnterior;
  final double pendenciasAberto;
  final double pendenciasAbertoAnterior;
  final double ticketMedioHoje;
  final double ticketMedioOntem;

  double get variacaoVendas => _pct(vendasHoje, vendasOntem);
  double get variacaoQtd => _pct(qtdVendasHoje.toDouble(), qtdVendasOntem.toDouble());
  double get variacaoClientes => _pct(clientesAtivos.toDouble(), clientesAtivosAnterior.toDouble());
  double get variacaoCredito => _pct(creditoUtilizado, creditoUtilizadoAnterior);
  double get variacaoPendencias => _pct(pendenciasAberto, pendenciasAbertoAnterior);
  double get variacaoTicket => _pct(ticketMedioHoje, ticketMedioOntem);

  static ComercialDashboardKpis vazio() => const ComercialDashboardKpis(
        vendasHoje: 0,
        vendasOntem: 0,
        qtdVendasHoje: 0,
        qtdVendasOntem: 0,
        clientesAtivos: 0,
        clientesAtivosAnterior: 0,
        creditoUtilizado: 0,
        creditoUtilizadoAnterior: 0,
        pendenciasAberto: 0,
        pendenciasAbertoAnterior: 0,
        ticketMedioHoje: 0,
        ticketMedioOntem: 0,
      );

  static double calcularVariacaoPercentual(double atual, double anterior) => _pct(atual, anterior);

  static double _pct(double atual, double anterior) {
    if (anterior <= 0) return atual > 0 ? 100 : 0;
    return ((atual - anterior) / anterior) * 100;
  }
}

class ComercialResumoCredito {
  const ComercialResumoCredito({
    required this.limiteTotal,
    required this.creditoUtilizado,
    required this.creditoDisponivel,
    required this.clientesComCredito,
    required this.clientesInadimplentes,
    required this.valorEmAtraso,
  });

  final double limiteTotal;
  final double creditoUtilizado;
  final double creditoDisponivel;
  final int clientesComCredito;
  final int clientesInadimplentes;
  final double valorEmAtraso;

  static ComercialResumoCredito vazio() => const ComercialResumoCredito(
        limiteTotal: 0,
        creditoUtilizado: 0,
        creditoDisponivel: 0,
        clientesComCredito: 0,
        clientesInadimplentes: 0,
        valorEmAtraso: 0,
      );
}

class ComercialClientesStats {
  const ComercialClientesStats({
    required this.novosClientes,
    required this.novosClientesAnterior,
    required this.recorrentes,
    required this.recorrentesAnterior,
    required this.inativos,
    required this.inativosAnterior,
    required this.vip,
    required this.vipAnterior,
    required this.comPendencia,
    required this.comPendenciaAnterior,
  });

  final int novosClientes;
  final int novosClientesAnterior;
  final int recorrentes;
  final int recorrentesAnterior;
  final int inativos;
  final int inativosAnterior;
  final int vip;
  final int vipAnterior;
  final int comPendencia;
  final int comPendenciaAnterior;

  static ComercialClientesStats vazio() => const ComercialClientesStats(
        novosClientes: 0,
        novosClientesAnterior: 0,
        recorrentes: 0,
        recorrentesAnterior: 0,
        inativos: 0,
        inativosAnterior: 0,
        vip: 0,
        vipAnterior: 0,
        comPendencia: 0,
        comPendenciaAnterior: 0,
      );
}

class ComercialTopCliente {
  const ComercialTopCliente({
    required this.nome,
    required this.compras,
    required this.totalGasto,
    this.telefone,
  });

  final String nome;
  final int compras;
  final double totalGasto;
  final String? telefone;
}

class ComercialPendenciasResumo {
  const ComercialPendenciasResumo({
    required this.vencendoHoje,
    required this.vencendo7Dias,
    required this.emAtraso,
    required this.recuperadas30Dias,
  });

  final double vencendoHoje;
  final double vencendo7Dias;
  final double emAtraso;
  final double recuperadas30Dias;

  static ComercialPendenciasResumo vazio() => const ComercialPendenciasResumo(
        vencendoHoje: 0,
        vencendo7Dias: 0,
        emAtraso: 0,
        recuperadas30Dias: 0,
      );
}

class ComercialPendenciaItem {
  const ComercialPendenciaItem({
    required this.cliente,
    required this.valor,
    required this.vencimento,
    required this.diasAtraso,
    this.telefone,
  });

  final String cliente;
  final double valor;
  final DateTime vencimento;
  final int diasAtraso;
  final String? telefone;
}

class ComercialFormaPagamento {
  const ComercialFormaPagamento({
    required this.nome,
    required this.valor,
    required this.percentual,
    required this.cor,
  });

  final String nome;
  final double valor;
  final double percentual;
  final Color cor;
}

class ComercialInsight {
  const ComercialInsight({
    required this.texto,
    required this.iconColor,
    required this.bgColor,
  });

  final String texto;
  final Color iconColor;
  final Color bgColor;
}

class ComercialProdutoRanking {
  const ComercialProdutoRanking({
    required this.nome,
    required this.quantidade,
    required this.faturamento,
  });

  final String nome;
  final int quantidade;
  final double faturamento;
}

class ComercialProdutoSemVenda {
  const ComercialProdutoSemVenda({
    required this.nome,
    required this.estoque,
    this.ultimaVenda,
  });

  final String nome;
  final int estoque;
  final DateTime? ultimaVenda;
}

class ComercialEvolucaoVendas {
  const ComercialEvolucaoVendas({
    required this.rotulos,
    required this.series,
    required this.maxValor,
  });

  final List<String> rotulos;
  final Map<String, List<double>> series;
  final double maxValor;

  static ComercialEvolucaoVendas vazio() => const ComercialEvolucaoVendas(
        rotulos: [],
        series: {},
        maxValor: 0,
      );
}
