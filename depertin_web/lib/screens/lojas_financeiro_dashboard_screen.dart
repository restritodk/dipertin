import 'dart:math' as math;

import 'package:depertin_web/services/admin_lojas_financeiro_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/codigo_pedido.dart';
import 'package:depertin_web/widgets/lojas_financeiro_busca_loja_field.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Dashboard financeiro de todas as lojas (admin).
class LojasFinanceiroDashboardScreen extends StatefulWidget {
  const LojasFinanceiroDashboardScreen({super.key});

  @override
  State<LojasFinanceiroDashboardScreen> createState() =>
      _LojasFinanceiroDashboardScreenState();
}

class _LojasFinanceiroDashboardScreenState
    extends State<LojasFinanceiroDashboardScreen> {
  static final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _fmtData = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  LojasFinPeriodoRapido _periodo = LojasFinPeriodoRapido.mes;
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String? _lojaId;
  final _buscaCtrl = TextEditingController();
  String _buscaAplicada = '';
  List<LojaCatalogoItem> _catalogoLojas = [];
  bool _catalogoCarregando = true;
  LojasFinStatusPagamentoFiltro _filtroPagamento =
      LojasFinStatusPagamentoFiltro.todos;
  LojasFinStatusRepasseFiltro _filtroRepasse =
      LojasFinStatusRepasseFiltro.todos;

  late Future<LojasFinDashboardSnapshot> _future;
  int _paginaTabela = 0;
  static const _itensPorPagina = 12;

  @override
  void initState() {
    super.initState();
    _future = _recarregar();
    _carregarCatalogoLojas();
  }

  Future<void> _carregarCatalogoLojas() async {
    try {
      final lista = await AdminLojasFinanceiroService.carregarCatalogoLojas();
      if (!mounted) return;
      setState(() {
        _catalogoLojas = lista;
        _catalogoCarregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _catalogoCarregando = false);
    }
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<LojasFinDashboardSnapshot> _recarregar() {
    return AdminLojasFinanceiroService.carregar(
      periodoRapido: _periodo,
      dataInicio: _dataInicio,
      dataFim: _dataFim,
      lojaIdFiltro: _lojaId,
      buscaNomeLoja: _buscaAplicada,
      filtroPagamento: _filtroPagamento,
      filtroRepasse: _filtroRepasse,
    );
  }

  void _prepararBuscaAntesDeAplicar() {
    if (_lojaId != null) {
      _buscaAplicada = '';
      return;
    }
    final texto = _buscaCtrl.text.trim();
    if (texto.isEmpty) {
      _buscaAplicada = '';
      return;
    }
    final idDoc = AdminLojasFinanceiroService.resolverLojaIdPorDocumento(
      _catalogoLojas,
      texto,
    );
    if (idDoc != null) {
      _lojaId = idDoc;
      _buscaAplicada = '';
      final loja = _lojaCatalogoPorId(idDoc);
      if (loja != null) _buscaCtrl.text = loja.nome;
      return;
    }
    _buscaAplicada = texto;
  }

  void _aplicarFiltros({bool resetPagina = true}) {
    _prepararBuscaAntesDeAplicar();
    setState(() {
      if (resetPagina) _paginaTabela = 0;
      _future = _recarregar();
    });
  }

  void _selecionarLojaBusca(LojaCatalogoItem? loja) {
    setState(() {
      if (loja == null) {
        _lojaId = null;
        _buscaAplicada = '';
      } else {
        _lojaId = loja.id;
        _buscaAplicada = '';
        _buscaCtrl.text = loja.nome;
      }
    });
    _aplicarFiltros();
  }

  LojaCatalogoItem? _lojaCatalogoPorId(String id) {
    for (final l in _catalogoLojas) {
      if (l.id == id) return l;
    }
    return null;
  }

  void _sincronizarTextoComLojaId() {
    if (_lojaId == null) return;
    final loja = _lojaCatalogoPorId(_lojaId!);
    if (loja != null && _buscaCtrl.text != loja.nome) {
      _buscaCtrl.text = loja.nome;
    }
  }

  Future<void> _escolherPeriodoPersonalizado() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dataInicio != null && _dataFim != null
          ? DateTimeRange(start: _dataInicio!, end: _dataFim!)
          : null,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      helpText: 'Período personalizado',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final maxW = math.min(420.0, mq.size.width - 48);
        final maxH = math.min(460.0, mq.size.height * 0.58);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: PainelAdminTheme.roxo,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: PainelAdminTheme.dashboardInk,
              secondary: PainelAdminTheme.laranja,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: PainelAdminTheme.roxo,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: PainelAdminTheme.roxo,
                foregroundColor: Colors.white,
                textStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.white,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PainelAdminTheme.dashboardBorder),
                  boxShadow: PainelAdminTheme.sombraCardSuave(),
                ),
                clipBehavior: Clip.antiAlias,
                child: child!,
              ),
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _periodo = LojasFinPeriodoRapido.personalizado;
      _dataInicio = picked.start;
      _dataFim = picked.end;
    });
    _aplicarFiltros();
  }

  void _mostrarDetalhePedido(LojasFinLinhaPedido linha) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Pedido ${CodigoPedido.gerar(linha.pedidoId)}',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _detalheLinha('Loja', linha.lojaNome),
              _detalheLinha(
                'Data',
                linha.data != null ? _fmtDataHora.format(linha.data!) : '—',
              ),
              _detalheLinha('Total vendido', _brl.format(linha.bruto)),
              _detalheLinha('Comissão plataforma', _brl.format(linha.comissao)),
              _detalheLinha('Líquido loja', _brl.format(linha.liquido)),
              _detalheLinha('Pagamento', linha.statusPagamento),
              _detalheLinha('Repasse', linha.statusRepasse),
              _detalheLinha('Status pedido', linha.statusPedido),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _detalheLinha(String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              rotulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: PainelAdminTheme.textoSecundario,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E1B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: FutureBuilder<LojasFinDashboardSnapshot>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Erro ao carregar financeiro: ${snap.error}',
                style: const TextStyle(color: Color(0xFFDC2626)),
              ),
            );
          }
          final dados = snap.data ?? LojasFinDashboardSnapshot.vazio;
          return LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1100;
              final extraWide = c.maxWidth >= 1400;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _cabecalho()),
                  SliverToBoxAdapter(child: _barraFiltros(dados, wide)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _gradeKpis(dados, wide, extraWide),
                        const SizedBox(height: 24),
                        _secaoGraficos(dados, wide),
                        const SizedBox(height: 24),
                        _rankingLojas(dados),
                        const SizedBox(height: 24),
                        _tabelaResumoPorLoja(dados, wide),
                        const SizedBox(height: 24),
                        _tabelaFinanceira(dados, wide),
                      ]),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PainelAdminTheme.roxo.withValues(alpha: 0.08),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PainelAdminTheme.roxo.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: PainelAdminTheme.roxo,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financeiro das Lojas',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E1B4B),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Visão consolidada de vendas, comissões, repasses e performance por loja.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: PainelAdminTheme.textoSecundario,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar dados',
            onPressed: _aplicarFiltros,
            icon: const Icon(Icons.refresh_rounded),
            color: PainelAdminTheme.roxo,
          ),
        ],
      ),
    );
  }

  Widget _barraFiltros(LojasFinDashboardSnapshot dados, bool wide) {
    final lojaItens = dados.nomesLojas.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E4F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipPeriodo('Hoje', LojasFinPeriodoRapido.hoje),
              _chipPeriodo('Semana', LojasFinPeriodoRapido.semana),
              _chipPeriodo('Mês', LojasFinPeriodoRapido.mes),
              ActionChip(
                label: Text(
                  _periodo == LojasFinPeriodoRapido.personalizado &&
                          _dataInicio != null
                      ? '${_fmtData.format(_dataInicio!)} – ${_fmtData.format(_dataFim ?? _dataInicio!)}'
                      : 'Personalizado',
                ),
                avatar: Icon(
                  Icons.date_range_rounded,
                  size: 18,
                  color: _periodo == LojasFinPeriodoRapido.personalizado
                      ? Colors.white
                      : PainelAdminTheme.roxo,
                ),
                backgroundColor:
                    _periodo == LojasFinPeriodoRapido.personalizado
                    ? PainelAdminTheme.roxo
                    : Colors.grey.shade100,
                labelStyle: TextStyle(
                  color: _periodo == LojasFinPeriodoRapido.personalizado
                      ? Colors.white
                      : const Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                ),
                onPressed: _escolherPeriodoPersonalizado,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, lc) {
              final row = lc.maxWidth >= 900;
              final buscaField = _catalogoCarregando
                  ? TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Buscar loja',
                        hintText: 'Carregando lojas…',
                        prefixIcon: const SizedBox(
                          width: 24,
                          height: 24,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : LojasFinanceiroBuscaLojaField(
                      catalogo: _catalogoLojas,
                      controller: _buscaCtrl,
                      lojaIdSelecionada: _lojaId,
                      onLojaSelecionada: _selecionarLojaBusca,
                      onSubmitted: _aplicarFiltros,
                    );
              final lojaDropdown = DropdownButtonFormField<String?>(
                initialValue: _lojaId,
                decoration: InputDecoration(
                  labelText: 'Loja',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas as lojas'),
                  ),
                  ...lojaItens.map(
                    (e) => DropdownMenuItem<String?>(
                      value: e.key,
                      child: Text(
                        e.value,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _lojaId = v;
                    if (v == null) {
                      _buscaCtrl.clear();
                    } else {
                      _sincronizarTextoComLojaId();
                    }
                  });
                  _aplicarFiltros();
                },
              );
              final pagamentoDropdown =
                  DropdownButtonFormField<LojasFinStatusPagamentoFiltro>(
                    initialValue: _filtroPagamento,
                    decoration: InputDecoration(
                      labelText: 'Status pagamento',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: LojasFinStatusPagamentoFiltro.todos,
                        child: Text('Todos'),
                      ),
                      DropdownMenuItem(
                        value: LojasFinStatusPagamentoFiltro.pago,
                        child: Text('Pago'),
                      ),
                      DropdownMenuItem(
                        value: LojasFinStatusPagamentoFiltro.aguardando,
                        child: Text('Aguardando'),
                      ),
                      DropdownMenuItem(
                        value: LojasFinStatusPagamentoFiltro.cancelado,
                        child: Text('Cancelado'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _filtroPagamento = v);
                      _aplicarFiltros();
                    },
                  );
              final repasseDropdown =
                  DropdownButtonFormField<LojasFinStatusRepasseFiltro>(
                    initialValue: _filtroRepasse,
                    decoration: InputDecoration(
                      labelText: 'Status repasse',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: LojasFinStatusRepasseFiltro.todos,
                        child: Text('Todos'),
                      ),
                      DropdownMenuItem(
                        value: LojasFinStatusRepasseFiltro.repassado,
                        child: Text('Repassado'),
                      ),
                      DropdownMenuItem(
                        value: LojasFinStatusRepasseFiltro.pendente,
                        child: Text('Pendente'),
                      ),
                      DropdownMenuItem(
                        value: LojasFinStatusRepasseFiltro.cancelado,
                        child: Text('Cancelado'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _filtroRepasse = v);
                      _aplicarFiltros();
                    },
                  );
              if (row) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: buscaField),
                    const SizedBox(width: 12),
                    Expanded(child: lojaDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: pagamentoDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: repasseDropdown),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buscaField,
                  const SizedBox(height: 12),
                  lojaDropdown,
                  const SizedBox(height: 12),
                  pagamentoDropdown,
                  const SizedBox(height: 12),
                  repasseDropdown,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {
                _buscaAplicada = _buscaCtrl.text;
                _aplicarFiltros();
              },
              icon: const Icon(Icons.filter_alt_rounded, size: 18),
              label: const Text('Aplicar filtros'),
              style: FilledButton.styleFrom(
                backgroundColor: PainelAdminTheme.roxo,
              ),
            ),
          ),
          if (_lojaId != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: PainelAdminTheme.laranja.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: PainelAdminTheme.laranja.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.storefront, color: PainelAdminTheme.laranja),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exibindo apenas: ${dados.nomesLojas[_lojaId] ?? "Loja selecionada"}',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _lojaId = null);
                      _aplicarFiltros();
                    },
                    child: const Text('Ver todas'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipPeriodo(String label, LojasFinPeriodoRapido valor) {
    final sel = _periodo == valor;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) {
        setState(() => _periodo = valor);
        _aplicarFiltros();
      },
      selectedColor: PainelAdminTheme.roxo,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: sel ? Colors.white : const Color(0xFF334155),
      ),
    );
  }

  Widget _gradeKpis(
    LojasFinDashboardSnapshot d,
    bool wide,
    bool extraWide,
  ) {
    final cards = [
      _KpiCard(
        'Valor bruto vendido',
        _brl.format(d.brutoVendido),
        Icons.payments_outlined,
        const Color(0xFF2563EB),
      ),
      _KpiCard(
        'Valor líquido das lojas',
        _brl.format(d.liquidoLojas),
        Icons.storefront_outlined,
        const Color(0xFF059669),
      ),
      _KpiCard(
        'Valor pago à plataforma',
        _brl.format(d.valorPlataforma),
        Icons.hub_outlined,
        PainelAdminTheme.roxo,
      ),
      _KpiCard(
        'Pedidos pagos',
        '${d.pedidosPagos}',
        Icons.receipt_long_rounded,
        const Color(0xFF0D9488),
      ),
      _KpiCard(
        'Comissões recebidas',
        _brl.format(d.comissoesPlataforma),
        Icons.percent_rounded,
        PainelAdminTheme.laranja,
      ),
      _KpiCard(
        'Pendente de repasse',
        _brl.format(d.pendenteRepasse),
        Icons.schedule_rounded,
        const Color(0xFFD97706),
      ),
      _KpiCard(
        'Já repassado às lojas',
        _brl.format(d.repassadoLojas),
        Icons.check_circle_outline_rounded,
        const Color(0xFF16A34A),
      ),
    ];
    final cols = extraWide ? 4 : (wide ? 3 : 2);
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: wide ? 2.4 : 2.1,
      children: cards,
    );
  }

  Widget _secaoGraficos(LojasFinDashboardSnapshot d, bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Análise gráfica',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1E1B4B),
          ),
        ),
        const SizedBox(height: 14),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChartCard(
                  titulo: 'Vendas por período',
                  subtitulo: 'Valor bruto (produtos)',
                  child: _lineChartVendas(d.vendasPorDia),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _ChartCard(
                  titulo: 'Lucro da plataforma',
                  subtitulo: 'Comissões no período',
                  child: _lineChartLucro(d.lucroPlataformaPorDia),
                ),
              ),
            ],
          )
        else ...[
          _ChartCard(
            titulo: 'Vendas por período',
            subtitulo: 'Valor bruto (produtos)',
            child: _lineChartVendas(d.vendasPorDia),
          ),
          const SizedBox(height: 14),
          _ChartCard(
            titulo: 'Lucro da plataforma',
            subtitulo: 'Comissões no período',
            child: _lineChartLucro(d.lucroPlataformaPorDia),
          ),
        ],
        const SizedBox(height: 14),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChartCard(
                  titulo: 'Valores por loja',
                  subtitulo: 'Top 8 — bruto vendido',
                  child: _barChartPorLoja(d.porLoja.take(8).toList()),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _ChartCard(
                  titulo: 'Bruto × líquido × comissão',
                  subtitulo: 'Totais consolidados',
                  child: _barChartComparativo(d),
                ),
              ),
            ],
          )
        else ...[
          _ChartCard(
            titulo: 'Valores por loja',
            subtitulo: 'Top 8 — bruto vendido',
            child: _barChartPorLoja(d.porLoja.take(8).toList()),
          ),
          const SizedBox(height: 14),
          _ChartCard(
            titulo: 'Bruto × líquido × comissão',
            subtitulo: 'Totais consolidados',
            child: _barChartComparativo(d),
          ),
        ],
      ],
    );
  }

  Widget _rankingLojas(LojasFinDashboardSnapshot d) {
    final top = d.rankingLojas.take(10).toList();
    return _ChartCard(
      titulo: 'Ranking — lojas que mais venderam',
      subtitulo: 'Por valor bruto no período',
      child: top.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Sem vendas no período selecionado.'),
            )
          : Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: i < 3
                              ? PainelAdminTheme.laranja.withValues(alpha: 0.2)
                              : Colors.grey.shade200,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: i < 3
                                  ? PainelAdminTheme.laranja
                                  : Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            top[i].lojaNome,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _brl.format(top[i].bruto),
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.roxo,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${top[i].pedidosPagos} ped.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: PainelAdminTheme.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  String _statusRepasseLoja(LojasFinResumoLoja l) {
    if (l.pendenteRepasse > 0.009 && l.repassado > 0.009) {
      return 'Parcial';
    }
    if (l.pendenteRepasse > 0.009) return 'Pendente repasse';
    if (l.repassado > 0.009) return 'Repassado';
    return '—';
  }

  void _filtrarPorLoja(String lojaId) {
    setState(() {
      _lojaId = lojaId;
      _sincronizarTextoComLojaId();
    });
    _aplicarFiltros();
  }

  Widget _tabelaResumoPorLoja(LojasFinDashboardSnapshot d, bool wide) {
    final lojas = d.porLoja;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Resumo por loja',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (lojas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nenhuma loja com vendas no período.')),
            )
          else if (wide)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  PainelAdminTheme.laranja.withValues(alpha: 0.08),
                ),
                columns: const [
                  DataColumn(label: Text('Loja')),
                  DataColumn(label: Text('Total vendido')),
                  DataColumn(label: Text('Comissão')),
                  DataColumn(label: Text('Líquido')),
                  DataColumn(label: Text('Pedidos')),
                  DataColumn(label: Text('Repasse')),
                  DataColumn(label: Text('')),
                ],
                rows: lojas.map((l) {
                  return DataRow(
                    cells: [
                      DataCell(Text(l.lojaNome)),
                      DataCell(Text(_brl.format(l.bruto))),
                      DataCell(Text(_brl.format(l.comissaoPlataforma))),
                      DataCell(Text(_brl.format(l.liquido))),
                      DataCell(Text('${l.pedidosPagos}')),
                      DataCell(_badgeRepasse(_statusRepasseLoja(l))),
                      DataCell(
                        TextButton(
                          onPressed: () => _filtrarPorLoja(l.lojaId),
                          child: const Text('Ver detalhes'),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: lojas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final l = lojas[i];
                return ListTile(
                  title: Text(l.lojaNome),
                  subtitle: Text(
                    '${l.pedidosPagos} pedidos · ${_statusRepasseLoja(l)}',
                  ),
                  trailing: TextButton(
                    onPressed: () => _filtrarPorLoja(l.lojaId),
                    child: Text(_brl.format(l.bruto)),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _tabelaFinanceira(LojasFinDashboardSnapshot d, bool wide) {
    final linhas = d.linhasPedidos;
    final totalPaginas = math.max(1, (linhas.length / _itensPorPagina).ceil());
    final pagina = _paginaTabela.clamp(0, totalPaginas - 1);
    final inicio = pagina * _itensPorPagina;
    final fim = math.min(inicio + _itensPorPagina, linhas.length);
    final slice = linhas.sublist(
      inicio > linhas.length ? 0 : inicio,
      fim,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              'Pedidos no período',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (linhas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nenhum pedido no filtro atual.')),
            )
          else if (wide)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  PainelAdminTheme.roxo.withValues(alpha: 0.06),
                ),
                columns: const [
                  DataColumn(label: Text('Loja')),
                  DataColumn(label: Text('Vendido')),
                  DataColumn(label: Text('Comissão')),
                  DataColumn(label: Text('Líquido')),
                  DataColumn(label: Text('Pedidos')),
                  DataColumn(label: Text('Repasse')),
                  DataColumn(label: Text('Data')),
                  DataColumn(label: Text('')),
                ],
                rows: slice.map((l) {
                  return DataRow(
                    cells: [
                      DataCell(Text(l.lojaNome)),
                      DataCell(Text(_brl.format(l.bruto))),
                      DataCell(Text(_brl.format(l.comissao))),
                      DataCell(Text(_brl.format(l.liquido))),
                      DataCell(const Text('1')),
                      DataCell(_badgeRepasse(l.statusRepasse)),
                      DataCell(Text(
                        l.data != null ? _fmtData.format(l.data!) : '—',
                      )),
                      DataCell(
                        TextButton(
                          onPressed: () => _mostrarDetalhePedido(l),
                          child: const Text('Detalhes'),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: slice.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final l = slice[i];
                return ListTile(
                  title: Text(l.lojaNome),
                  subtitle: Text(
                    '${l.data != null ? _fmtData.format(l.data!) : "—"} · ${l.statusRepasse}',
                  ),
                  trailing: TextButton(
                    onPressed: () => _mostrarDetalhePedido(l),
                    child: Text(_brl.format(l.liquido)),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  linhas.isEmpty
                      ? '0 registros'
                      : 'Mostrando ${inicio + 1}–$fim de ${linhas.length}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: pagina > 0
                          ? () => setState(() => _paginaTabela--)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Página ${pagina + 1} de $totalPaginas'),
                    IconButton(
                      onPressed: pagina < totalPaginas - 1
                          ? () => setState(() => _paginaTabela++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeRepasse(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Repassado':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      case 'Pendente repasse':
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFC2410C);
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _lineChartVendas(List<({DateTime dia, double bruto})> pts) {
    if (pts.isEmpty) return _chartVazio();
    final maxY = pts.map((e) => e.bruto).reduce(math.max) * 1.15;
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 10 : maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, _) => Text(
                  'R\$${v.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: math.max(1, (pts.length / 5).floorToDouble()),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= pts.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('dd/MM').format(pts[i].dia),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < pts.length; i++)
                  FlSpot(i.toDouble(), pts[i].bruto),
              ],
              isCurved: true,
              color: PainelAdminTheme.roxo,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: PainelAdminTheme.roxo.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineChartLucro(List<({DateTime dia, double lucro})> pts) {
    if (pts.isEmpty) return _chartVazio();
    final maxY = pts.map((e) => e.lucro).reduce(math.max) * 1.15;
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 10 : maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, _) => Text(
                  'R\$${v.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: math.max(1, (pts.length / 5).floorToDouble()),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= pts.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('dd/MM').format(pts[i].dia),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < pts.length; i++)
                  FlSpot(i.toDouble(), pts[i].lucro),
              ],
              isCurved: true,
              color: PainelAdminTheme.laranja,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: PainelAdminTheme.laranja.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barChartPorLoja(List<LojasFinResumoLoja> lojas) {
    if (lojas.isEmpty) return _chartVazio();
    final maxY = lojas.map((e) => e.bruto).reduce(math.max) * 1.2;
    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 10 : maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(
                  '${(v / 1000).toStringAsFixed(0)}k',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= lojas.length) {
                    return const SizedBox.shrink();
                  }
                  final nome = lojas[i].lojaNome;
                  final curto = nome.length > 10
                      ? '${nome.substring(0, 10)}…'
                      : nome;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      curto,
                      style: const TextStyle(fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < lojas.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: lojas[i].bruto,
                    color: PainelAdminTheme.roxo,
                    width: 18,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _barChartComparativo(LojasFinDashboardSnapshot d) {
    final vals = [d.brutoVendido, d.liquidoLojas, d.comissoesPlataforma];
    final maxY = vals.reduce(math.max) * 1.2;
    final labels = ['Bruto', 'Líquido', 'Comissão'];
    final cores = [
      const Color(0xFF2563EB),
      const Color(0xFF059669),
      PainelAdminTheme.laranja,
    ];
    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 10 : maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (v, _) => Text(
                  'R\$${(v / 1000).toStringAsFixed(1)}k',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < vals.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: vals[i],
                    color: cores[i],
                    width: 36,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _chartVazio() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: Text(
          'Sem dados para exibir no período.',
          style: TextStyle(color: PainelAdminTheme.textoSecundario),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E4F0)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: PainelAdminTheme.textoSecundario,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.titulo,
    required this.subtitulo,
    required this.child,
  });

  final String titulo;
  final String subtitulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            subtitulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
