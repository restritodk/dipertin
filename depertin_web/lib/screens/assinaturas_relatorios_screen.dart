import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/cliente_assinatura_model.dart';
import '../models/cobranca_assinatura_model.dart';
import '../services/relatorios_financeiro_service.dart' as rf;
import '../widgets/premium_dialogs.dart';
import '../widgets/status_badge.dart';

// ─── Tela Principal ─────────────────────────────────────────────────────────

class AssinaturasRelatoriosScreen extends StatefulWidget {
  const AssinaturasRelatoriosScreen({super.key});

  @override
  State<AssinaturasRelatoriosScreen> createState() =>
      _AssinaturasRelatoriosScreenState();
}

class _AssinaturasRelatoriosScreenState
    extends State<AssinaturasRelatoriosScreen> {
  StreamSubscription<rf.RelatorioDadosCompletos>? _sub;
  rf.RelatorioDadosCompletos _dados = rf.RelatorioDadosCompletos.vazio;
  bool _carregando = true;
  String? _erro;
  rf.RelatorioFiltros _filtros = rf.RelatorioFiltros();
  String _search = '';

  // Paginação
  int _paginaAtual = 0;
  static const int _itensPorPagina = 15;

  @override
  void initState() {
    super.initState();
    _sub = rf.RelatoriosFinanceiroService
        .streamRelatorio(filtros: _filtros.temFiltro ? _filtros : null)
        .listen(
          (dados) {
            if (!mounted) return;
            setState(() {
              _dados = dados;
              _carregando = false;
              _erro = null;
            });
          },
          onError: (err) {
            if (!mounted) return;
            setState(() {
              _carregando = false;
              _erro = err.toString();
            });
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Filtros / Dedup ─────────────────────────────────────────────────────

  List<rf.RelatorioDetalheLinha> get _detalhesFiltrados {
    var lista = _dados.detalhes;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      lista = lista.where((d) {
        return d.cliente.storeName.toLowerCase().contains(q) ||
            d.cliente.ownerName.toLowerCase().contains(q) ||
            d.planoNome.toLowerCase().contains(q);
      }).toList();
    }
    // Dedup por loja: manter apenas 1 linha por storeId (a mais recente / atual)
    final vistos = <String>{};
    final unicos = <rf.RelatorioDetalheLinha>[];
    for (final item in lista) {
      final key = item.cliente.storeId.isNotEmpty
          ? item.cliente.storeId
          : item.cliente.id;
      if (!vistos.contains(key)) {
        vistos.add(key);
        unicos.add(item);
      }
    }
    return unicos;
  }

  List<rf.RelatorioDetalheLinha> get _detalhesPagina {
    final start = _paginaAtual * _itensPorPagina;
    final end = start + _itensPorPagina;
    final lista = _detalhesFiltrados;
    if (start >= lista.length) return [];
    return lista.sublist(start, end.clamp(0, lista.length));
  }

  int get _totalPaginas =>
      (_detalhesFiltrados.length / _itensPorPagina).ceil().clamp(1, 999);

  // ── Insights únicos ──────────────────────────────────────────────────────
  List<rf.RelatorioInsight> get _insightsUnicos {
    final vistos = <String>{};
    return _dados.insights.where((i) {
      final ok = !vistos.contains(i.texto);
      vistos.add(i.texto);
      return ok;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return _buildLoading();
    if (_erro != null) return _buildErro();

    final largura = MediaQuery.of(context).size.width;
    final telaPequena = largura < 1200;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildSecaoTitulo('Resumo Financeiro', 'Indicadores do período'),
          const SizedBox(height: 12),
          _buildResumoFinanceiro(),
          const SizedBox(height: 24),
          _buildSecaoTitulo(
              'Situação das Assinaturas', 'Status atual dos contratos'),
          const SizedBox(height: 12),
          _buildSituacaoAssinaturas(),
          const SizedBox(height: 24),
          if (telaPequena)
            Column(
              children: [
                _EvolucaoFinanceiraChart(cobrancas: _dados.cobrancas),
                const SizedBox(height: 16),
                _buildReceitaPorPlano(),
                const SizedBox(height: 16),
                _buildCrescimentoAssinaturas(),
              ],
            )
          else
            SizedBox(
              height: 400,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      flex: 4,
                      child:
                          _EvolucaoFinanceiraChart(cobrancas: _dados.cobrancas)),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: _buildReceitaPorPlano()),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: _buildCrescimentoAssinaturas()),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (telaPequena)
            Column(
              children: [
                _buildRelatoriosRapidos(),
                const SizedBox(height: 16),
                _buildInsightsFinanceiros(),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  flex: 6,
                  child: _buildRelatoriosRapidos(),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 340,
                  height: 420,
                  child: _buildInsightsFinanceiros(),
                ),
              ],
            ),
          const SizedBox(height: 24),
          _buildSecaoTitulo('Detalhamento das Assinaturas',
              'Todas as assinaturas contratadas'),
          const SizedBox(height: 12),
          _buildTabelaDetalhes(),
          const SizedBox(height: 16),
          _buildRodapeFinanceiro(),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF6A1B9A)),
            SizedBox(height: 16),
            Text('Carregando relatórios financeiros...',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: Color(0xFFF04438)),
            const SizedBox(height: 12),
            const Text('Erro ao carregar relatórios',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_erro ?? '',
                style: const TextStyle(color: Color(0xFF64748B)),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildSecaoTitulo(String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text(subtitulo,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
      ],
    );
  }

  Widget _cardWrapper({
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1)),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
    );
  }

  // ── Cabeçalho ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF6A1B9A).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.analytics_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Relatórios Financeiros',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.5)),
              const SizedBox(height: 2),
              const Text(
                  'Centro de Inteligência Financeira do Gestão Comercial',
                  style:
                      TextStyle(fontSize: 14, color: Color(0xFF64748B))),
            ],
          ),
        ),
        _buildPeriodoSelector(),
        const SizedBox(width: 12),
        _buildBtnFiltros(),
      ],
    );
  }

  Widget _buildPeriodoSelector() {
    final fmt = DateFormat('dd/MM/yyyy');
    final inicio =
        _filtros.dataInicio ?? DateTime.now().subtract(const Duration(days: 30));
    final fim = _filtros.dataFim ?? DateTime.now();
    return GestureDetector(
      onTap: _abrirSeletorPeriodo,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.date_range_rounded,
                size: 16, color: Color(0xFF6A1B9A)),
            const SizedBox(width: 8),
            Text('${fmt.format(inicio)} - ${fmt.format(fim)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1A1A2E))),
          ],
        ),
      ),
    );
  }

  void _abrirSeletorPeriodo() {
    showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: _filtros.dataInicio ??
            DateTime.now().subtract(const Duration(days: 30)),
        end: _filtros.dataFim ?? DateTime.now(),
      ),
      locale: const Locale('pt', 'BR'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: const Color(0xFF6A1B9A),
              ),
        ),
        child: child!,
      ),
    ).then((range) {
      if (range != null) {
        setState(() {
          _filtros.dataInicio = range.start;
          _filtros.dataFim = range.end;
        });
        _reiniciarStream();
      }
    });
  }

  Widget _buildBtnFiltros() {
    return OutlinedButton.icon(
      onPressed: _abrirFiltrosAvancados,
      icon: const Icon(Icons.filter_list_rounded, size: 16),
      label: const Text('Filtros avançados',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1A1A2E),
        side: BorderSide(color: Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _abrirFiltrosAvancados() {
    final local = _filtros.copy();
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _FiltrosAvancadosDialog(
        filtros: local,
        onAplicar: (f) {
          setState(() => _filtros = f);
          _reiniciarStream();
        },
      ),
    );
  }

  void _reiniciarStream() {
    _sub?.cancel();
    setState(() => _carregando = true);
    _sub = rf.RelatoriosFinanceiroService
        .streamRelatorio(filtros: _filtros.temFiltro ? _filtros : null)
        .listen(
          (d) {
            if (!mounted) return;
            setState(() {
              _dados = d;
              _carregando = false;
              _erro = null;
            });
          },
          onError: (err) {
            if (!mounted) return;
            setState(() {
              _carregando = false;
              _erro = err.toString();
            });
          },
        );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEÇÃO 1: RESUMO FINANCEIRO
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildResumoFinanceiro() {
    final r = _dados.resumo;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _kpiCard(
          titulo: 'Receita Total',
          valor: r.receitaTotal,
          icone: Icons.account_balance_wallet_rounded,
          corIcone: const Color(0xFF6A1B9A),
          fundoIcone: const Color(0xFFF1E9FF),
          variacao: _variacao(r.receitaTotal, r.receitaTotalAnterior),
        ),
        _kpiCard(
          titulo: 'Receita Recebida',
          valor: r.receitaRecebida,
          icone: Icons.check_circle_rounded,
          corIcone: const Color(0xFF16A34A),
          fundoIcone: const Color(0xFFE8F5E9),
          variacao: _variacao(r.receitaRecebida, r.receitaRecebidaAnterior),
        ),
        _kpiCard(
          titulo: 'Receita a Receber',
          valor: r.receitaAReceber,
          icone: Icons.schedule_rounded,
          corIcone: const Color(0xFFFF8F00),
          fundoIcone: const Color(0xFFFFF3E6),
          variacao: _variacao(r.receitaAReceber, r.receitaAReceberAnterior),
        ),
        _kpiCard(
          titulo: 'Receita em Atraso',
          valor: r.receitaEmAtraso,
          icone: Icons.warning_amber_rounded,
          corIcone: const Color(0xFFF04438),
          fundoIcone: const Color(0xFFFEF2F2),
          variacao: _variacao(r.receitaEmAtraso, r.receitaEmAtrasoAnterior),
        ),
        _kpiCard(
          titulo: 'Receita Recuperada',
          valor: r.receitaRecuperada,
          icone: Icons.trending_up_rounded,
          corIcone: const Color(0xFF0EA5E9),
          fundoIcone: const Color(0xFFE6F6FE),
          variacao: _variacao(r.receitaRecuperada, r.receitaRecuperadaAnterior),
        ),
        _kpiCard(
          titulo: 'Estornos',
          valor: r.estornos,
          icone: Icons.replay_rounded,
          corIcone: const Color(0xFF94A3B8),
          fundoIcone: const Color(0xFFF1F5F9),
          variacao: _variacao(r.estornos, r.estornosAnteriores),
        ),
      ],
    );
  }

  String _variacao(double atual, double anterior) {
    if (anterior <= 0 && atual > 0) return '+100%';
    if (anterior <= 0) return '0%';
    final perc = ((atual - anterior) / anterior * 100);
    return '${perc >= 0 ? '+' : ''}${perc.toStringAsFixed(1)}%';
  }

  Widget _kpiCard({
    required String titulo,
    required double valor,
    required IconData icone,
    required Color corIcone,
    required Color fundoIcone,
    String? variacao,
  }) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final isPositivo =
        variacao == null || (!variacao.startsWith('-') && variacao != '0%');
    return SizedBox(
      width: 220,
      child: _cardWrapper(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fundoIcone,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: corIcone, size: 22),
              ),
              const SizedBox(height: 10),
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: valor),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(
                  fmt.format(v),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.3),
                ),
              ),
              if (variacao != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isPositivo
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 12,
                      color: isPositivo
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFF04438),
                    ),
                    const SizedBox(width: 3),
                    Text(variacao,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isPositivo
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFF04438))),
                    const SizedBox(width: 4),
                    const Text('vs. período anterior',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFF94A3B8))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEÇÃO 2: SITUAÇÃO DAS ASSINATURAS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSituacaoAssinaturas() {
    final s = _dados.situacao;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _miniCard('Total Contratados', '${s.totalContratados}',
            Icons.people_alt_rounded, const Color(0xFF6A1B9A),
            const Color(0xFFF1E9FF)),
        _miniCard('Planos Ativos', '${s.planosAtivos}',
            Icons.check_circle_rounded, const Color(0xFF16A34A),
            const Color(0xFFE8F5E9)),
        _miniCard('Em Dia', '${s.emDia}', Icons.thumb_up_rounded,
            const Color(0xFF16A34A), const Color(0xFFE8F5E9)),
        _miniCard('Vence Hoje', '${s.venceHoje}',
            Icons.event_available_rounded, const Color(0xFFFF8F00),
            const Color(0xFFFFF3E6)),
        _miniCard('A Vencer (7 dias)', '${s.aVencer7dias}',
            Icons.schedule_rounded, const Color(0xFF0EA5E9),
            const Color(0xFFE6F6FE)),
        _miniCard('Vencidos', '${s.vencidos}', Icons.warning_amber_rounded,
            const Color(0xFFF04438), const Color(0xFFFEF2F2)),
        _miniCard('Bloqueados', '${s.bloqueados}', Icons.block_rounded,
            const Color(0xFFF04438), const Color(0xFFFEF2F2)),
        _miniCard('Cancelados', '${s.cancelados}', Icons.cancel_rounded,
            const Color(0xFF94A3B8), const Color(0xFFF1F5F9)),
      ],
    );
  }

  Widget _miniCard(
      String titulo, String valor, IconData icone, Color cor, Color fundo) {
    return SizedBox(
      width: 150,
      child: _cardWrapper(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: fundo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: cor, size: 18),
              ),
              const SizedBox(height: 8),
              Text(valor,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(height: 2),
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEÇÃO 3b: RECEITA POR PLANO (donut)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildReceitaPorPlano() {
    final receita = _dados.receitaPorPlano;
    final total = receita.fold<double>(0, (s, r) => s + r.valor);

    final cores = [
      const Color(0xFF6A1B9A),
      const Color(0xFFFF8F00),
      const Color(0xFF0EA5E9),
      const Color(0xFF16A34A),
      const Color(0xFFF04438),
      const Color(0xFF94A3B8),
      const Color(0xFFEC4899),
    ];

    return _cardWrapper(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Receita por Plano',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            const Text('Distribuição da receita entre os planos',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            Expanded(
              child: receita.isEmpty
                  ? const Center(
                      child: Text('Sem dados',
                          style: TextStyle(color: Color(0xFF94A3B8))))
                  : Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: PieChart(
                            PieChartData(
                              sections: List.generate(receita.length, (i) {
                                final perc =
                                    total > 0 ? (receita[i].valor / total * 100) : 0.0;
                                return PieChartSectionData(
                                  value: perc > 0 ? perc : 1,
                                  color: cores[i % cores.length],
                                  radius: 40,
                                  title: perc > 5
                                      ? '${perc.toStringAsFixed(0)}%'
                                      : '',
                                  titleStyle: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white),
                                );
                              }),
                              sectionsSpace: 2,
                              centerSpaceRadius: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(receita.length, (i) {
                                final perc =
                                    total > 0 ? (receita[i].valor / total * 100) : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                              color: cores[i % cores.length],
                                              borderRadius:
                                                  BorderRadius.circular(2))),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          receita[i].planoNome.length > 14
                                              ? '${receita[i].planoNome.substring(0, 14)}…'
                                              : receita[i].planoNome,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF1A1A2E)),
                                        ),
                                      ),
                                      Text(
                                        '${perc.toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF6A1B9A)),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3c. Crescimento de Assinaturas (barras AGRUPADAS lado a lado) ────────

  Widget _buildCrescimentoAssinaturas() {
    final dados = _dados.crescimento;
    final maxPos = dados.fold<double>(
        0, (m, d) => [m, d.novosContratos.toDouble()].reduce(math.max));
    final maxNeg = dados.fold<double>(
        0, (m, d) => [m, d.cancelamentos.toDouble(), d.bloqueios.toDouble()]
            .reduce(math.max));
    final escala = math.max(maxPos, maxNeg) * 1.4;

    return _cardWrapper(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Crescimento de Assinaturas',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            _legenda('Novos', const Color(0xFF16A34A)),
            const SizedBox(width: 12),
            _legenda('Cancelamentos', const Color(0xFFF04438)),
            const SizedBox(width: 12),
            _legenda('Bloqueios', const Color(0xFFFF8F00)),
            const SizedBox(height: 12),
            Expanded(
              child: dados.isEmpty
                  ? const Center(
                      child: Text('Sem dados',
                          style: TextStyle(color: Color(0xFF94A3B8))))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (v) =>
                              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget: (v, _) => Text(
                                    v >= 1000
                                        ? '${(v / 1000).toStringAsFixed(0)}k'
                                        : v.toStringAsFixed(0),
                                    style: const TextStyle(
                                        fontSize: 9, color: Color(0xFF94A3B8)))),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 20,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= dados.length) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    dados[i].mes.length > 5
                                        ? dados[i].mes.substring(0, 5)
                                        : dados[i].mes,
                                    style: const TextStyle(
                                        fontSize: 8, color: Color(0xFF94A3B8)),
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        groupsSpace: 6,
                        barGroups: List.generate(dados.length, (i) {
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: dados[i].novosContratos.toDouble(),
                                color: const Color(0xFF16A34A),
                                width: 6,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                              BarChartRodData(
                                toY: dados[i].cancelamentos.toDouble(),
                                color: const Color(0xFFF04438),
                                width: 6,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                              BarChartRodData(
                                toY: dados[i].bloqueios.toDouble(),
                                color: const Color(0xFFFF8F00),
                                width: 6,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                            ],
                          );
                        }),
                        maxY: escala > 0 ? escala : 10,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legenda(String label, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: cor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEÇÃO 4: RELATÓRIOS RÁPIDOS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildRelatoriosRapidos() {
    final s = _dados.situacao;
    final r = _dados.resumo;
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final fmtNum = NumberFormat('#,##0', 'pt_BR');
    final receitaPorPlanoPlanos = _dados.receitaPorPlano.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Relatórios Rápidos',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 2),
        const Text('Acesse relatórios com um clique',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _PremiumReportCard(
              icon: Icons.checklist_rounded,
              title: 'Assinaturas Ativas',
              value: fmtNum.format(s.planosAtivos),
              subtitle: 'Assinaturas em funcionamento',
              color: const Color(0xFF6A1B9A),
              onTap: () => _onRapidoTap('Assinaturas Ativas'),
            ),
            _PremiumReportCard(
              icon: Icons.thumb_up_rounded,
              title: 'Assinaturas em Dia',
              value: fmtNum.format(s.emDia),
              subtitle: 'Pagamentos sem atraso',
              color: const Color(0xFF16A34A),
              onTap: () => _onRapidoTap('Assinaturas em Dia'),
            ),
            _PremiumReportCard(
              icon: Icons.schedule_rounded,
              title: 'A Vencer (7 dias)',
              value: fmtNum.format(s.aVencer7dias),
              subtitle: 'Vencimentos próximos',
              color: const Color(0xFF0EA5E9),
              onTap: () => _onRapidoTap('A Vencer (7 dias)'),
            ),
            _PremiumReportCard(
              icon: Icons.warning_amber_rounded,
              title: 'Em Atraso',
              value: fmtNum.format(s.vencidos),
              subtitle: 'Cobranças pendentes',
              color: const Color(0xFFF04438),
              onTap: () => _onRapidoTap('Em Atraso'),
            ),
            _PremiumReportCard(
              icon: Icons.block_rounded,
              title: 'Bloqueados',
              value: fmtNum.format(s.bloqueados),
              subtitle: 'Planos bloqueados',
              color: const Color(0xFFEA580C),
              onTap: () => _onRapidoTap('Bloqueados'),
            ),
            _PremiumReportCard(
              icon: Icons.monetization_on_rounded,
              title: 'Receita Mensal',
              value: fmt.format(r.receitaTotal),
              subtitle: 'Recebimentos do período',
              color: const Color(0xFF059669),
              onTap: () => _onRapidoTap('Receita Mensal'),
            ),
            _PremiumReportCard(
              icon: Icons.pie_chart_rounded,
              title: 'Receita por Plano',
              value: '$receitaPorPlanoPlanos ${receitaPorPlanoPlanos == 1 ? 'plano' : 'planos'}',
              subtitle: 'Distribuição financeira',
              color: const Color(0xFF6A1B9A),
              onTap: () => _onRapidoTap('Receita por Plano'),
            ),
            _PremiumReportCard(
              icon: Icons.location_city_rounded,
              title: 'Cidades Atendidas',
              value: fmtNum.format(_cidadesUnicas()),
              subtitle: 'Regiões com assinaturas',
              color: const Color(0xFFFF8F00),
              onTap: () => _onRapidoTap('Cidades Atendidas'),
            ),
            _PremiumReportCard(
              icon: Icons.history_rounded,
              title: 'Pagamentos',
              value: fmtNum.format(_totalPagamentos()),
              subtitle: 'Histórico de pagamentos',
              color: const Color(0xFF0EA5E9),
              onTap: () => _onRapidoTap('Histórico de Pagamentos'),
            ),
          ],
        ),
      ],
    );
  }

  void _onRapidoTap(String titulo) {
    PremiumResultDialog.mostrarSucesso(
      context,
      titulo: titulo,
      mensagem: 'Relatório "$titulo" será aberto em breve.',
    );
  }

  int _cidadesUnicas() {
    return _dados.detalhes
        .map((d) => d.cliente.addressCity)
        .where((c) => c.isNotEmpty)
        .toSet()
        .length;
  }

  int _estadosUnicos() {
    return _dados.detalhes
        .map((d) => d.cliente.addressState)
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;
  }

  int _totalPagamentos() {
    return _dados.detalhes
        .where((d) => d.ultimoPagamento != null && d.ultimoPagamento != '—')
        .length;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEÇÃO 5: INSIGHTS FINANCEIROS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildInsightsFinanceiros() {
    final insights = _insightsUnicos;
    return _cardWrapper(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 18, color: Color(0xFFFF8F00)),
                SizedBox(width: 8),
                Text('Insights Financeiros',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E))),
              ],
            ),
            const SizedBox(height: 2),
            const Text('Análises automáticas dos seus dados',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            Expanded(
              child: insights.isEmpty
                  ? const Center(
                      child: Text('Nenhum insight disponível',
                          style: TextStyle(color: Color(0xFF94A3B8))))
                  : ListView.separated(
                      itemCount: insights.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final insight = insights[i];
                        final cor = _corFromHex(insight.cor);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: cor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(_iconeFromStr(insight.icone),
                                    size: 16, color: cor),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(insight.texto,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF475569),
                                        height: 1.4)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _corFromHex(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  IconData _iconeFromStr(String s) {
    switch (s) {
      case 'calendar_today':
        return Icons.calendar_today_rounded;
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'pie_chart':
        return Icons.pie_chart_rounded;
      case 'verified':
        return Icons.verified_rounded;
      case 'savings':
        return Icons.savings_rounded;
      case 'store':
        return Icons.store_rounded;
      default:
        return Icons.lightbulb_rounded;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEÇÃO 7: TABELA DE DETALHAMENTO (dedup + modal ao clicar)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTabelaDetalhes() {
    return _cardWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() {
                      _search = v;
                      _paginaAtual = 0;
                    }),
                    decoration: InputDecoration(
                      hintText: 'Buscar por loja, responsável ou plano…',
                      hintStyle: const TextStyle(
                          fontSize: 13, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF8F7FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          _buildTableHeader(),
          const Divider(height: 1),
          SizedBox(
            height: _detalhesPagina.isEmpty
                ? 120
                : (_detalhesPagina.length * 56.0).clamp(100, 900),
            child: _detalhesPagina.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 32, color: Color(0xFF94A3B8)),
                        SizedBox(height: 8),
                        Text('Nenhuma assinatura encontrada',
                            style: TextStyle(color: Color(0xFF94A3B8))),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _detalhesPagina.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) =>
                        _buildTableRow(_detalhesPagina[i]),
                  ),
          ),
          const Divider(height: 1),
          _buildPaginacao(),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: const Color(0xFFF8F7FC),
      child: const Row(
        children: [
          _Th('Loja', 170),
          _Th('Responsável', 140),
          _Th('Plano', 120),
          _Th('Mensalidade', 120),
          _Th('Próx. Venc.', 110),
          _Th('Últ. Pagto.', 110),
          _Th('Situação', 110),
          _Th('Pagamento', 100),
          _Th('Cidade/UF', 120),
          _Th('Cliente há', 90),
        ],
      ),
    );
  }

  Widget _buildTableRow(rf.RelatorioDetalheLinha linha) {
    final c = linha.cliente;
    return InkWell(
      onTap: () => _abrirModalDetalheCliente(linha),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 170,
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        c.storeName.isNotEmpty
                            ? c.storeName.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Color(0xFF6A1B9A),
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.storeName,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E)),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(c.ownerName.isNotEmpty ? c.ownerName : '—',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF475569))),
            ),
            SizedBox(
              width: 120,
              child: Text(linha.planoNome,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF475569))),
            ),
            SizedBox(
              width: 120,
              child: Text(
                  NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                      .format(linha.valorMensalidade),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E))),
            ),
            SizedBox(
              width: 110,
              child: Text(linha.proximoVencimento ?? '—',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF475569))),
            ),
            SizedBox(
              width: 110,
              child: Text(linha.ultimoPagamento ?? '—',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF475569))),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StatusBadge(linha.situacao),
            ),
            SizedBox(
              width: 100,
              child: Text(linha.formaPagamento,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF475569))),
            ),
            SizedBox(
              width: 120,
              child: Text(linha.cidadeUf,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF475569))),
            ),
            SizedBox(
              width: 90,
              child: Text(_formatTempo(linha.tempoComoClienteDias),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF64748B))),
            ),
          ],
        ),
      ),
    );
  }

  // ── Modal premium de detalhes do cliente ──────────────────────────────────

  void _abrirModalDetalheCliente(rf.RelatorioDetalheLinha linha) {
    final c = linha.cliente;
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _ModalDetalheCliente(
        cliente: c,
        linha: linha,
        cobrancas: _dados.cobrancas,
      ),
    );
  }

  String _formatTempo(int dias) {
    if (dias <= 0) return '—';
    if (dias < 30) return '$dias ${dias == 1 ? 'dia' : 'dias'}';
    final meses = (dias / 30).floor();
    if (meses < 12) return '$meses ${meses == 1 ? 'mês' : 'meses'}';
    final anos = (meses / 12).floor();
    return '$anos ${anos == 1 ? 'ano' : 'anos'}';
  }

  Widget _buildPaginacao() {
    final total = _detalhesFiltrados.length;
    final paginas = _totalPaginas;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Text('$total ${total == 1 ? 'registro' : 'registros'}',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: _paginaAtual > 0
                ? () => setState(() => _paginaAtual--)
                : null,
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              disabledForegroundColor: Colors.grey.shade300,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Text('${_paginaAtual + 1} de $paginas',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: _paginaAtual < paginas - 1
                ? () => setState(() => _paginaAtual++)
                : null,
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF64748B),
              disabledForegroundColor: Colors.grey.shade300,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRodapeFinanceiro() {
    final r = _dados.resumo;
    final s = _dados.situacao;
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return _cardWrapper(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            _rodapeItem('Total de Registros', '${s.totalContratados}'),
            _rodapeDivider(),
            _rodapeItem('Valor Recebido', fmt.format(r.receitaRecebida)),
            _rodapeDivider(),
            _rodapeItem('Valor a Receber', fmt.format(r.receitaAReceber)),
            _rodapeDivider(),
            _rodapeItem('Valor em Atraso', fmt.format(r.receitaEmAtraso)),
            _rodapeDivider(),
            _rodapeItem('Receita Líquida',
                fmt.format(r.receitaRecebida - r.estornos)),
          ],
        ),
      ),
    );
  }

  Widget _rodapeItem(String label, String valor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(height: 2),
          Text(valor,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
        ],
      ),
    );
  }

  Widget _rodapeDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFE2E8F0),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GRÁFICO EVOLUÇÃO FINANCEIRA (StatefulWidget independente)
// ═══════════════════════════════════════════════════════════════════════════

class _EvolucaoFinanceiraChart extends StatefulWidget {
  final List<CobrancaAssinatura> cobrancas;
  const _EvolucaoFinanceiraChart({required this.cobrancas});

  @override
  State<_EvolucaoFinanceiraChart> createState() =>
      _EvolucaoFinanceiraChartState();
}

class _EvolucaoFinanceiraChartState extends State<_EvolucaoFinanceiraChart> {
  rf.PeriodoEvolucao _periodo = rf.PeriodoEvolucao.mes;

  List<rf.RelatorioEvolucaoFinanceira> get _evolucao =>
      rf.RelatoriosFinanceiroService.calcularEvolucao(
          widget.cobrancas, _periodo);

  @override
  Widget build(BuildContext context) {
    final evolucao = _evolucao;
    return _cardWrapper(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Evolução Financeira',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E))),
                const Spacer(),
                _periodoChip('Dia', rf.PeriodoEvolucao.dia),
                const SizedBox(width: 4),
                _periodoChip('Sem.', rf.PeriodoEvolucao.semana),
                const SizedBox(width: 4),
                _periodoChip('Mês', rf.PeriodoEvolucao.mes),
                const SizedBox(width: 4),
                _periodoChip('Ano', rf.PeriodoEvolucao.ano),
              ],
            ),
            const SizedBox(height: 4),
            _legendaLinha('Receita Recebida', const Color(0xFF16A34A)),
            const SizedBox(width: 12),
            _legendaLinha('Receita Prevista', const Color(0xFF0EA5E9)),
            const SizedBox(width: 12),
            _legendaLinha('Receita em Atraso', const Color(0xFFF04438)),
            const SizedBox(height: 12),
            Expanded(
              child: evolucao.isEmpty
                  ? const Center(
                      child: Text('Sem dados para o período',
                          style: TextStyle(color: Color(0xFF94A3B8))))
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _calcInterval(evolucao),
                          getDrawingHorizontalLine: (v) =>
                              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 50,
                                getTitlesWidget: (v, _) =>
                                    Text(_formatValor(v),
                                        style: const TextStyle(
                                            fontSize: 9,
                                            color: Color(0xFF94A3B8)))),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              interval: 1,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i < 0 || i >= evolucao.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    evolucao[i].rotulo.length > 5
                                        ? evolucao[i].rotulo.substring(0, 5)
                                        : evolucao[i].rotulo,
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF94A3B8)),
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        minY: 0,
                        lineBarsData: [
                          _linhaDado(evolucao,
                              (e) => e.receitaRecebida,
                              const Color(0xFF16A34A)),
                          _linhaDado(evolucao,
                              (e) => e.receitaPrevista,
                              const Color(0xFF0EA5E9)),
                          _linhaDado(evolucao,
                              (e) => e.receitaEmAtraso,
                              const Color(0xFFF04438)),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double _calcInterval(List<rf.RelatorioEvolucaoFinanceira> dados) {
    final maxVal = dados.fold<double>(0, (m, e) => [
          m,
          e.receitaRecebida,
          e.receitaPrevista,
          e.receitaEmAtraso
        ].reduce(math.max));
    if (maxVal <= 100) return 20;
    if (maxVal <= 500) return 100;
    if (maxVal <= 2000) return 500;
    if (maxVal <= 10000) return 2000;
    return (maxVal / 5).ceilToDouble();
  }

  String _formatValor(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  Widget _legendaLinha(String label, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: cor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        ],
      ),
    );
  }

  LineChartBarData _linhaDado(
    List<rf.RelatorioEvolucaoFinanceira> dados,
    double Function(rf.RelatorioEvolucaoFinanceira) getter,
    Color cor,
  ) {
    return LineChartBarData(
      spots: List.generate(
          dados.length, (i) => FlSpot(i.toDouble(), getter(dados[i]))),
      isCurved: true,
      preventCurveOverShooting: true,
      color: cor,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
          show: true, color: cor.withValues(alpha: 0.08)),
    );
  }

  Widget _periodoChip(String label, rf.PeriodoEvolucao periodo) {
    final ativo = _periodo == periodo;
    return GestureDetector(
      onTap: () => setState(() => _periodo = periodo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ativo
              ? const Color(0xFF6A1B9A)
              : const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: ativo
                    ? Colors.white
                    : const Color(0xFF64748B))),
      ),
    );
  }
}

// ─── Helpers estáticos de card wrapper ────────────────────────────────────

Widget _cardWrapper({
  required Widget child,
  EdgeInsetsGeometry margin = EdgeInsets.zero,
}) {
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4)),
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1)),
      ],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
  );
}

// ─── Widget auxiliar: cabeçalho de coluna ─────────────────────────────────

class _Th extends StatelessWidget {
  final String label;
  final double width;
  const _Th(this.label, this.width);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              letterSpacing: 0.3)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// MODAL PREMIUM DE DETALHES DO CLIENTE
// ══════════════════════════════════════════════════════════════════════════

class _ModalDetalheCliente extends StatelessWidget {
  final ClienteAssinaturaModel cliente;
  final rf.RelatorioDetalheLinha linha;
  final List<CobrancaAssinatura> cobrancas;

  const _ModalDetalheCliente({
    required this.cliente,
    required this.linha,
    required this.cobrancas,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final fmtData = DateFormat('dd/MM/yyyy', 'pt_BR');

    // Cobranças deste cliente
    final cobrancasCliente = cobrancas
        .where((c) =>
            c.clienteNome.toLowerCase() ==
                cliente.storeName.toLowerCase() ||
            c.clienteEmail == cliente.email)
        .toList()
      ..sort((a, b) => b.vencimento.compareTo(a.vencimento));

    // Timeline: eventos do cliente
    final timeline = <_TimelineEvento>[];
    if (cliente.createdAt != null) {
      timeline.add(_TimelineEvento(
        icone: Icons.person_add_rounded,
        cor: const Color(0xFF6A1B9A),
        titulo: 'Contratação do plano',
        subtitulo:
            'Plano ${linha.planoNome} contratado em ${fmtData.format(cliente.createdAt!.toDate())}',
        data: cliente.createdAt!.toDate(),
      ));
    }
    for (final c in cobrancasCliente) {
      switch (c.status) {
        case StatusCobranca.paga:
          timeline.add(_TimelineEvento(
            icone: Icons.check_circle_rounded,
            cor: const Color(0xFF16A34A),
            titulo: 'Pagamento realizado',
            subtitulo:
                '${fmt.format(c.valor)} — Vencimento ${c.vencimentoExibicao}',
            data: c.vencimento,
          ));
          break;
        case StatusCobranca.vencida:
          timeline.add(_TimelineEvento(
            icone: Icons.warning_amber_rounded,
            cor: const Color(0xFFF04438),
            titulo: 'Vencimento em atraso',
            subtitulo:
                '${fmt.format(c.valor)} — Venceu em ${c.vencimentoExibicao}',
            data: c.vencimento,
          ));
          break;
        case StatusCobranca.cancelada:
          timeline.add(_TimelineEvento(
            icone: Icons.cancel_rounded,
            cor: const Color(0xFF94A3B8),
            titulo: 'Cobrança cancelada',
            subtitulo:
                '${fmt.format(c.valor)} — Cancelada em ${c.vencimentoExibicao}',
            data: c.vencimento,
          ));
          break;
        default:
          break;
      }
    }
    if (cliente.status == 'suspenso') {
      timeline.add(_TimelineEvento(
        icone: Icons.block_rounded,
        cor: const Color(0xFFF04438),
        titulo: 'Bloqueio por inadimplência',
        subtitulo:
            'Acesso ao Gestão Comercial suspenso',
        data: DateTime.now(),
      ));
    }
    if (cliente.status == 'cancelado') {
      timeline.add(_TimelineEvento(
        icone: Icons.cancel_outlined,
        cor: const Color(0xFF94A3B8),
        titulo: 'Cancelamento do plano',
        subtitulo: 'Plano cancelado',
        data: cliente.nextBillingDate?.toDate() ?? DateTime.now(),
      ));
    }
    timeline.sort((a, b) => b.data.compareTo(a.data));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        cliente.storeName.isNotEmpty
                            ? cliente.storeName.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cliente.storeName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('Detalhes da assinatura',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Informações do cliente
                    _buildSecaoInfo(
                        'Informações da Loja', const Color(0xFF6A1B9A)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _infoField(
                                'Nome da Loja', cliente.storeName)),
                        Expanded(
                            child: _infoField(
                                'Responsável', cliente.ownerName)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _infoField(
                                'CPF/CNPJ',
                                cliente.cpfCnpj ?? '—')),
                        Expanded(
                            child: _infoField('E-mail', cliente.email)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _infoField(
                                'Telefone', cliente.phone.isNotEmpty ? cliente.phone : '—')),
                        Expanded(
                            child: _infoField(
                                'Cidade/UF', linha.cidadeUf)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    // Informações do plano
                    _buildSecaoInfo(
                        'Informações do Plano', const Color(0xFFFF8F00)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _infoField(
                                'Plano Contratado', linha.planoNome)),
                        Expanded(
                            child: _infoField(
                                'Valor da Mensalidade',
                                fmt.format(linha.valorMensalidade))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _infoField(
                                'Status Atual', linha.situacao)),
                        Expanded(
                            child: _infoField(
                                'Forma de Pagamento', linha.formaPagamento)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: _infoField(
                                'Próximo Vencimento',
                                linha.proximoVencimento ?? '—')),
                        Expanded(
                            child: _infoField(
                                'Último Pagamento',
                                linha.ultimoPagamento ?? '—')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _infoField('Tempo como Cliente',
                        _formatTempoStatic(linha.tempoComoClienteDias)),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    // Timeline
                    _buildSecaoInfo(
                        'Histórico da Assinatura',
                        const Color(0xFF6A1B9A)),
                    const SizedBox(height: 12),
                    if (timeline.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Nenhum histórico disponível',
                            style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontStyle: FontStyle.italic)),
                      )
                    else
                      ...timeline.map((t) => _buildTimelineItem(t)),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecaoInfo(String titulo, Color cor) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(titulo,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E))),
      ],
    );
  }

  Widget _infoField(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(valor,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E))),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(_TimelineEvento evento) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: evento.cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: evento.cor.withValues(alpha: 0.3)),
                ),
                child: Icon(evento.icone, size: 16, color: evento.cor),
              ),
              Container(
                width: 2,
                height: 28,
                color: const Color(0xFFE2E8F0),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(evento.titulo,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 2),
                  Text(evento.subtitulo,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTempoStatic(int dias) {
    if (dias <= 0) return '—';
    if (dias < 30) return '$dias ${dias == 1 ? 'dia' : 'dias'}';
    final meses = (dias / 30).floor();
    if (meses < 12) return '$meses ${meses == 1 ? 'mês' : 'meses'}';
    final anos = (meses / 12).floor();
    return '$anos ${anos == 1 ? 'ano' : 'anos'}';
  }
}

class _TimelineEvento {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String subtitulo;
  final DateTime data;

  const _TimelineEvento({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
    required this.data,
  });
}

// ─── Modal de filtros avançados ────────────────────────────────────────────

class _FiltrosAvancadosDialog extends StatefulWidget {
  final rf.RelatorioFiltros filtros;
  final void Function(rf.RelatorioFiltros) onAplicar;

  const _FiltrosAvancadosDialog({
    required this.filtros,
    required this.onAplicar,
  });

  @override
  State<_FiltrosAvancadosDialog> createState() =>
      _FiltrosAvancadosDialogState();
}

class _FiltrosAvancadosDialogState extends State<_FiltrosAvancadosDialog> {
  late rf.RelatorioFiltros _local;

  @override
  void initState() {
    super.initState();
    _local = widget.filtros.copy();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.filter_list_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Filtros avançados',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E))),
                      Text('Refine os dados dos relatórios financeiros',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Período
            Row(
              children: [
                Expanded(
                  child: _campoData('Data início', (dt) {
                    setState(() => _local.dataInicio = dt);
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _campoData('Data fim', (dt) {
                    setState(() => _local.dataFim = dt);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown('Status', _local.status,
                      ['', 'ativo', 'em_atraso', 'suspenso', 'cancelado'],
                      ['Todos', 'Ativo', 'Em atraso', 'Suspenso', 'Cancelado'],
                      (v) => setState(() => _local.status = v!)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown('Plano', _local.plano,
                      ['', 'Starter', 'Professional', 'Enterprise'],
                      ['Todos', 'Starter', 'Professional', 'Enterprise'],
                      (v) => setState(() => _local.plano = v!)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown('Pagamento', _local.formaPagamento,
                      ['', 'Mercado Pago', 'PIX', 'Boleto'],
                      ['Todas', 'Mercado Pago', 'PIX', 'Boleto'],
                      (v) => setState(() => _local.formaPagamento = v!)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _local.cidade = v),
                    decoration: _inputDec('Cidade', Icons.location_city_rounded),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              onChanged: (v) => setState(() => _local.estado = v),
              decoration: _inputDec('Estado (UF)', Icons.map_rounded),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _local.limpar()),
                  child: const Text('Limpar filtros',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancelar',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFF1A1A2E))),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    widget.onAplicar(_local);
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6A1B9A),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Aplicar filtros',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: const Color(0xFFF8F7FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      isDense: true,
    );
  }

  Widget _campoData(String label, void Function(DateTime) onSelect) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
          locale: const Locale('pt', 'BR'),
        );
        if (picked != null) onSelect(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7FC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: Color(0xFF6A1B9A)),
            const SizedBox(width: 8),
            Text(label,
                style:
                    const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String current, List<String> values,
      List<String> labels, void Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: current.isNotEmpty ? current : null,
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFFF8F7FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
      dropdownColor: Colors.white,
      items: List.generate(values.length, (i) {
        return DropdownMenuItem(
          value: values[i].isNotEmpty ? values[i] : null,
          child: Text(labels[i]),
        );
      }),
      onChanged: onChanged,
    );
  }
}

// PREMIUM REPORT CARD — Componente reutilizável
// ══════════════════════════════════════════════════════════════════════════

class _PremiumReportCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _PremiumReportCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  State<_PremiumReportCard> createState() => _PremiumReportCardState();
}

class _PremiumReportCardState extends State<_PremiumReportCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 290,
          height: 140,
          transform: _hovering
              ? (Matrix4.identity()..translate(0, -3))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hovering
                  ? widget.color.withValues(alpha: 0.25)
                  : const Color(0xFFE8E6F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovering
                    ? widget.color.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: _hovering ? 20 : 12,
                offset: Offset(0, _hovering ? 6 : 4),
              ),
              BoxShadow(
                color: _hovering
                    ? widget.color.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: _hovering ? 8 : 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // Gradiente lateral esquerdo
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.color,
                          widget.color.withValues(alpha: 0.6),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // Gradiente sutíl no topo
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 140,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topRight,
                        radius: 1.2,
                        colors: [
                          widget.color.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Conteúdo
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ícone + valor
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: widget.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.icon,
                              size: 20,
                              color: widget.color,
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.value,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: widget.color,
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Título
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // Subtítulo
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
