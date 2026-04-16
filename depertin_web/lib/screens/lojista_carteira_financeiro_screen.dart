import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:depertin_web/services/carteira_financeiro_pdf.dart';
import 'package:depertin_web/services/carteira_lojista_extrato.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/utils/pdf_download.dart';
import 'package:depertin_web/widgets/botao_suporte_flutuante.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:depertin_web/screens/lojista_carteira_financeiro_theme.dart';
import 'package:depertin_web/screens/lojista_carteira_financeiro_widgets.dart';
import 'package:depertin_web/widgets/carteira_fin_movimentacoes.dart';

/// Snapshot dos mesmos listeners de [LojistaMinhaCarteiraScreen].
class _CarteiraRealtime {
  DocumentSnapshot<Map<String, dynamic>>? user;
  QuerySnapshot<Map<String, dynamic>>? saques;
  QuerySnapshot<Map<String, dynamic>>? pedidosLoja;
  QuerySnapshot<Map<String, dynamic>>? pedidosLojista;
  QuerySnapshot<Map<String, dynamic>>? estornos;
}

enum _PeriodoFinanceiro {
  mesAtual,
  ultimos90,
  anoAtual,
  todo,
  custom,
}

class LojistaCarteiraFinanceiroScreen extends StatefulWidget {
  const LojistaCarteiraFinanceiroScreen({super.key});

  @override
  State<LojistaCarteiraFinanceiroScreen> createState() =>
      _LojistaCarteiraFinanceiroScreenState();
}

class _LojistaCarteiraFinanceiroScreenState
    extends State<LojistaCarteiraFinanceiroScreen> {
  static const _brand = PainelAdminTheme.roxo;

  _PeriodoFinanceiro _periodo = _PeriodoFinanceiro.mesAtual;
  DateTimeRange? _customRange;

  _CarteiraRealtime _live = _CarteiraRealtime();
  Object? _liveErro;
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _streamUid;

  bool _pdfCarregando = false;

  void _pararListeners() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _streamUid = null;
    _live = _CarteiraRealtime();
    _liveErro = null;
  }

  void _garantirListeners(String uid) {
    if (_streamUid == uid && _subs.isNotEmpty) return;
    _pararListeners();
    _streamUid = uid;

    void emitErro(Object e, StackTrace st) {
      _liveErro = e;
      if (mounted) setState(() {});
    }

    void ignorar(String nome, Object e, [StackTrace? st]) {
      debugPrint('[Financeiro] stream $nome: $e ${st ?? ''}');
    }

    void atualizar(void Function() fn) {
      fn();
      _liveErro = null;
      if (mounted) setState(() {});
    }

    _subs.addAll([
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen(
            (s) {
              final d = s.data();
              if (s.exists && d != null && !d.containsKey('saldo')) {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .set({'saldo': 0}, SetOptions(merge: true))
                    .catchError(
                      (Object e, StackTrace st) =>
                          debugPrint('[Financeiro] init saldo: $e'),
                    );
              }
              atualizar(() => _live.user = s);
            },
            onError: emitErro,
          ),
      FirebaseFirestore.instance
          .collection('saques_solicitacoes')
          .where('user_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _live.saques = s),
            onError: (e, st) => ignorar('saques_solicitacoes', e, st),
          ),
      FirebaseFirestore.instance
          .collection('pedidos')
          .where('loja_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _live.pedidosLoja = s),
            onError: (e, st) => ignorar('pedidos_loja_id', e, st),
          ),
      FirebaseFirestore.instance
          .collection('pedidos')
          .where('lojista_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _live.pedidosLojista = s),
            onError: (e, st) => ignorar('pedidos_lojista_id', e, st),
          ),
      FirebaseFirestore.instance
          .collection('estornos')
          .where('loja_id', isEqualTo: uid)
          .snapshots()
          .listen(
            (s) => atualizar(() => _live.estornos = s),
            onError: (e, st) => ignorar('estornos', e, st),
          ),
    ]);
  }

  @override
  void dispose() {
    _pararListeners();
    super.dispose();
  }

  ({DateTime? start, DateTime? end}) _rangePeriodo() {
    final now = DateTime.now();
    switch (_periodo) {
      case _PeriodoFinanceiro.mesAtual:
        return (
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
      case _PeriodoFinanceiro.ultimos90:
        final fim = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return (
          start: fim.subtract(const Duration(days: 89)),
          end: fim,
        );
      case _PeriodoFinanceiro.anoAtual:
        return (
          start: DateTime(now.year, 1, 1),
          end: DateTime(now.year, 12, 31, 23, 59, 59),
        );
      case _PeriodoFinanceiro.todo:
        return (start: null, end: null);
      case _PeriodoFinanceiro.custom:
        final r = _customRange;
        if (r == null) {
          return (
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59),
          );
        }
        return (
          start: DateTime(r.start.year, r.start.month, r.start.day),
          end: DateTime(
            r.end.year,
            r.end.month,
            r.end.day,
            23,
            59,
            59,
          ),
        );
    }
  }

  String _labelPeriodo() {
    final now = DateTime.now();
    final mesFmt = DateFormat.yMMMM('pt_BR');
    switch (_periodo) {
      case _PeriodoFinanceiro.mesAtual:
        return 'Mês atual (${mesFmt.format(now)})';
      case _PeriodoFinanceiro.ultimos90:
        return 'Últimos 90 dias';
      case _PeriodoFinanceiro.anoAtual:
        return 'Ano ${now.year}';
      case _PeriodoFinanceiro.todo:
        return 'Todo o período';
      case _PeriodoFinanceiro.custom:
        final r = _customRange;
        if (r == null) return 'Personalizado';
        final df = DateFormat('dd/MM/yyyy');
        return '${df.format(r.start)} — ${df.format(r.end)}';
    }
  }

  static bool _lancamentoNoPeriodo(
    CarteiraLancamento l,
    DateTime? s,
    DateTime? e,
  ) {
    if (s == null && e == null) return true;
    final t = l.data;
    if (s != null) {
      final si = DateTime(s.year, s.month, s.day);
      final ti = DateTime(t.year, t.month, t.day);
      if (ti.isBefore(si)) return false;
    }
    if (e != null) {
      if (t.isAfter(e)) return false;
    }
    return true;
  }

  static List<CarteiraVendaDia> _pontosGrafico(List<CarteiraVendaDia> raw) {
    if (raw.isEmpty) return [];
    if (raw.length <= 24) return raw;
    final n = raw.length;
    final bucket = (n / 24).ceil();
    final out = <CarteiraVendaDia>[];
    for (var i = 0; i < n; i += bucket) {
      final chunk = raw.sublist(i, math.min(i + bucket, n));
      var soma = 0.0;
      for (final c in chunk) {
        soma += c.valor;
      }
      out.add(
        CarteiraVendaDia(
          data: chunk.last.data,
          valor: soma,
        ),
      );
    }
    return out;
  }

  Future<void> _escolherPeriodoCustom() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 3);
    final r = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _customRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      locale: const Locale('pt', 'BR'),
    );
    if (r != null && mounted) {
      setState(() {
        _periodo = _PeriodoFinanceiro.custom;
        _customRange = r;
      });
    }
  }

  Future<void> _exportarPdf({
    required String nomeLoja,
    required double saldoAtual,
    required CarteiraFinanceiroResumo resumo,
    required List<CarteiraLancamento> lancamentos,
  }) async {
    setState(() => _pdfCarregando = true);
    try {
      final bytes = await gerarCarteiraFinanceiroPdf(
        nomeLoja: nomeLoja,
        periodoLabel: _labelPeriodo(),
        saldoAtual: saldoAtual,
        resumo: resumo,
        lancamentos: lancamentos,
        geradoEm: DateTime.now(),
      );
      final safe = nomeLoja.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final fname =
          'dipertin_financeiro_${safe}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

      if (kIsWeb) {
        downloadPdfFile(bytes, fname);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF gerado — download iniciado.')),
          );
        }
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fname);
      }
    } catch (e, st) {
      debugPrint('_exportarPdf $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfCarregando = false);
    }
  }

  Future<void> _imprimirPdf({
    required String nomeLoja,
    required double saldoAtual,
    required CarteiraFinanceiroResumo resumo,
    required List<CarteiraLancamento> lancamentos,
  }) async {
    setState(() => _pdfCarregando = true);
    try {
      final bytes = await gerarCarteiraFinanceiroPdf(
        nomeLoja: nomeLoja,
        periodoLabel: _labelPeriodo(),
        saldoAtual: saldoAtual,
        resumo: resumo,
        lancamentos: lancamentos,
        geradoEm: DateTime.now(),
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e, st) {
      debugPrint('_imprimirPdf $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfCarregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) {
      return const Scaffold(
        body: Center(child: Text('Não autenticado.')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authUid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Scaffold(
            backgroundColor: CarteiraFinTokens.bg,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final d = snap.data?.data();
        final uid = uidLojaEfetivo(d, authUid);
        if (d != null && !painelMostrarAreaCarteiraEConfig(d)) {
          return painelLojistaSemPermissaoScaffold(
            mensagem:
                'Sua conta não tem permissão para o financeiro da loja.',
          );
        }

    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    _garantirListeners(uid);

    if (_liveErro != null) {
      return Scaffold(
        backgroundColor: CarteiraFinTokens.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erro ao carregar dados.\n$_liveErro',
              textAlign: TextAlign.center,
              style: CarteiraFinTokens.inter(14, FontWeight.w400, CarteiraFinTokens.textSecondary),
            ),
          ),
        ),
      );
    }

    if (_live.user == null) {
      return Scaffold(
        backgroundColor: CarteiraFinTokens.bg,
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _brand.withValues(alpha: 0.8),
            ),
          ),
        ),
      );
    }

    final ud = _live.user!.data();
    final nomeLoja =
        (ud?['loja_nome'] ?? ud?['nome'] ?? 'Loja').toString();
    double saldoAtual = 0;
    if (ud != null) {
      final r = ud['saldo'];
      saldoAtual = r is num ? r.toDouble() : double.tryParse('$r') ?? 0;
    }

    final seenIds = <String>{};
    final pedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in [
      ...(_live.pedidosLoja?.docs ?? []),
      ...(_live.pedidosLojista?.docs ?? []),
    ]) {
      if (seenIds.add(d.id)) pedDocs.add(d);
    }

    final saqDocs = _live.saques?.docs ?? [];
    final estornoDocs = _live.estornos?.docs ?? [];

    final todos = CarteiraLojistaExtrato.buildLancamentos(
      saqDocs,
      pedDocs,
      estornoDocs,
    );

    final range = _rangePeriodo();
    final filtrados = todos
        .where(
          (l) => _lancamentoNoPeriodo(l, range.start, range.end),
        )
        .toList();

    final resumo = CarteiraFinanceiroResumo.fromLancamentos(filtrados);
    final vendasDia = vendasPorDia(filtrados);
    final chartPts = _pontosGrafico(vendasDia);
    final maxY = chartPts.isEmpty
        ? 1.0
        : chartPts.map((e) => e.valor).reduce(math.max) * 1.12;

    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: CarteiraFinTokens.textPrimary.withValues(alpha: 0.04),
        hoverColor: CarteiraFinTokens.textPrimary.withValues(alpha: 0.04),
      ),
      child: Scaffold(
        backgroundColor: CarteiraFinTokens.bg,
        floatingActionButton: const BotaoSuporteFlutuante(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final sw = MediaQuery.sizeOf(context).width;
            final gutter = wide ? 32.0 : 16.0;
            final kpiCardW = wide
                ? (constraints.maxWidth - gutter * 2 - 12 * 5) / 6
                : math.max(148.0, (sw - gutter * 2 - 12) / 2);

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 32),
                      _buildSectionLabel('Período'),
                      const SizedBox(height: 12),
                      _buildPeriodSegment(wide),
                      const SizedBox(height: 8),
                      Text(
                        _labelPeriodo(),
                        style: CarteiraFinTokens.inter(13, FontWeight.w500, CarteiraFinTokens.textSecondary),
                      ),
                      const SizedBox(height: 32),
                      _buildSectionLabel('Visão geral'),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          CarteiraFinKpiCard(
                            label: 'Saldo na carteira',
                            value: moeda.format(saldoAtual),
                            icon: Icons.account_balance_wallet_outlined,
                            valueColor: CarteiraFinTokens.textPrimary,
                            width: kpiCardW,
                          ),
                          CarteiraFinKpiCard(
                            label: 'Entradas',
                            value: moeda.format(resumo.entradas),
                            icon: Icons.arrow_downward_rounded,
                            valueColor: CarteiraFinTokens.green,
                            width: kpiCardW,
                          ),
                          CarteiraFinKpiCard(
                            label: 'Saídas',
                            value: moeda.format(resumo.saidas),
                            icon: Icons.arrow_upward_rounded,
                            valueColor: CarteiraFinTokens.red,
                            width: kpiCardW,
                          ),
                          CarteiraFinKpiCard(
                            label: 'Líquido',
                            value: moeda.format(resumo.liquido),
                            icon: Icons.show_chart_rounded,
                            valueColor: CarteiraFinTokens.textPrimary,
                            width: kpiCardW,
                          ),
                          CarteiraFinKpiCard(
                            label: 'Vendas creditadas',
                            value: '${resumo.qVendasCreditadas}',
                            icon: Icons.receipt_long_outlined,
                            valueColor: CarteiraFinTokens.textPrimary,
                            width: kpiCardW,
                          ),
                          CarteiraFinKpiCard(
                            label: 'Ticket médio',
                            value: resumo.ticketMedioVendas != null
                                ? moeda.format(resumo.ticketMedioVendas!)
                                : '—',
                            icon: Icons.pie_chart_outline_rounded,
                            valueColor: CarteiraFinTokens.textPrimary,
                            width: kpiCardW,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _pdfCarregando
                                ? null
                                : () => _exportarPdf(
                                      nomeLoja: nomeLoja,
                                      saldoAtual: saldoAtual,
                                      resumo: resumo,
                                      lancamentos: filtrados,
                                    ),
                            icon: _pdfCarregando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: Text(
                              kIsWeb ? 'Salvar PDF' : 'Compartilhar PDF',
                              style: CarteiraFinTokens.inter(14, FontWeight.w600, Colors.white),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _brand,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CarteiraFinTokens.rButton),
                              ),
                              elevation: 0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _pdfCarregando
                                ? null
                                : () => _imprimirPdf(
                                      nomeLoja: nomeLoja,
                                      saldoAtual: saldoAtual,
                                      resumo: resumo,
                                      lancamentos: filtrados,
                                    ),
                            icon: Icon(
                              Icons.print_outlined,
                              size: 18,
                              color: CarteiraFinTokens.textPrimary.withValues(alpha: 0.85),
                            ),
                            label: Text(
                              'Imprimir',
                              style: CarteiraFinTokens.inter(
                                14,
                                FontWeight.w600,
                                CarteiraFinTokens.textPrimary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: CarteiraFinTokens.textPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              side: const BorderSide(color: CarteiraFinTokens.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CarteiraFinTokens.rButton),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      _buildSectionLabel('Vendas creditadas por dia'),
                      const SizedBox(height: 8),
                      Text(
                        'Valores creditados na carteira após entrega, no período selecionado.',
                        style: CarteiraFinTokens.inter(13, FontWeight.w400, CarteiraFinTokens.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      CarteiraFinChartPanel(
                        chartPts: chartPts,
                        maxY: maxY,
                        wide: wide,
                        moeda: moeda,
                      ),
                      const SizedBox(height: 40),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          _buildSectionLabel('Movimentações'),
                          const SizedBox(width: 8),
                          Text(
                            '${filtrados.length}',
                            style: CarteiraFinTokens.inter(
                              14,
                              FontWeight.w600,
                              CarteiraFinTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      CarteiraFinMovimentacoesCard(
                        filtrados: filtrados,
                        moeda: moeda,
                        wide: wide,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Financeiro',
                style: CarteiraFinTokens.inter(28, FontWeight.w600, CarteiraFinTokens.textPrimary)
                    .copyWith(letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Receitas, saídas e movimentações no período. Os mesmos dados do extrato em Minha carteira.',
                style: CarteiraFinTokens.inter(15, FontWeight.w400, CarteiraFinTokens.textSecondary)
                    .copyWith(height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        TextButton.icon(
          onPressed: () => context.navegarPainel('/carteira_loja'),
          icon: Icon(
            Icons.wallet_outlined,
            size: 18,
            color: CarteiraFinTokens.textSecondary,
          ),
          label: Text(
            'Minha carteira',
            style: CarteiraFinTokens.inter(14, FontWeight.w600, CarteiraFinTokens.textPrimary),
          ),
          style: TextButton.styleFrom(
            foregroundColor: CarteiraFinTokens.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: CarteiraFinTokens.inter(11, FontWeight.w600, CarteiraFinTokens.textSecondary)
          .copyWith(letterSpacing: 0.6),
    );
  }

  Widget _buildPeriodSegment(bool wide) {
    final items = <({String label, _PeriodoFinanceiro? p, VoidCallback? onTap})>[
      (label: 'Mês atual', p: _PeriodoFinanceiro.mesAtual, onTap: null),
      (label: '90 dias', p: _PeriodoFinanceiro.ultimos90, onTap: null),
      (label: 'Ano', p: _PeriodoFinanceiro.anoAtual, onTap: null),
      (label: 'Todo o período', p: _PeriodoFinanceiro.todo, onTap: null),
      (label: 'Personalizar', p: _PeriodoFinanceiro.custom, onTap: _escolherPeriodoCustom),
    ];

    final content = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CarteiraFinTokens.segmentBg,
        borderRadius: BorderRadius.circular(CarteiraFinTokens.rSegment + 2),
        border: Border.all(color: CarteiraFinTokens.border.withValues(alpha: 0.6)),
      ),
      child: wide
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final it in items)
                  if (it.p != null)
                    _periodPill(
                      label: it.label,
                      selected: _periodo == it.p,
                      onTap: () {
                        if (it.p == _PeriodoFinanceiro.custom) {
                          _escolherPeriodoCustom();
                        } else {
                          setState(() => _periodo = it.p!);
                        }
                      },
                    ),
              ],
            )
          : Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final it in items)
                  if (it.p != null)
                    _periodPill(
                      label: it.label,
                      selected: _periodo == it.p,
                      onTap: () {
                        if (it.p == _PeriodoFinanceiro.custom) {
                          _escolherPeriodoCustom();
                        } else {
                          setState(() => _periodo = it.p!);
                        }
                      },
                    ),
              ],
            ),
    );

    if (wide) return content;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: content,
    );
  }

  Widget _periodPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CarteiraFinTokens.rSegment),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? CarteiraFinTokens.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(CarteiraFinTokens.rSegment),
              boxShadow: selected ? CarteiraFinTokens.pillActiveShadow : null,
              border: Border.all(
                color: selected ? CarteiraFinTokens.border : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: CarteiraFinTokens.inter(
                13,
                selected ? FontWeight.w600 : FontWeight.w500,
                selected ? CarteiraFinTokens.textPrimary : CarteiraFinTokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
