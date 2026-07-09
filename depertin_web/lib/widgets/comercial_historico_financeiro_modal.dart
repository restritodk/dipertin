import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/comercial_cliente.dart';
import 'package:depertin_web/models/comercial_cliente_lancamento.dart';
import 'package:depertin_web/models/comercial_credito.dart';
import 'package:depertin_web/services/comercial_clientes_service.dart';
import 'package:depertin_web/services/comercial_credito_service.dart';
import 'package:depertin_web/utils/firestore_web_safe.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Modal premium e read-only do histórico financeiro do cliente.
Future<void> mostrarHistoricoFinanceiroModal(
  BuildContext context, {
  required String lojaId,
  required ComercialCliente cliente,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _ClientFinancialHistoryModal(
      lojaId: lojaId,
      cliente: cliente,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// CORES
// ══════════════════════════════════════════════════════════════════

const Color _roxo = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _laranja = Color(0xFFFF8F00);
const Color _texto = Color(0xFF1E1B4B);
const Color _muted = Color(0xFF64748B);
const Color _borda = Color(0xFFE2E8F0);
const Color _fundo = Color(0xFFF8F9FC);
const Color _sucesso = Color(0xFF10B981);
const Color _erro = Color(0xFFEF4444);
const Color _bgStatusAberto = Color(0xFFFFF3E0);
const Color _bgStatusPago = Color(0xFFD1FAE5);
const Color _bgStatusVencido = Color(0xFFFEE2E2);

// ══════════════════════════════════════════════════════════════════
// MODAL PRINCIPAL
// ══════════════════════════════════════════════════════════════════

class _ClientFinancialHistoryModal extends StatefulWidget {
  const _ClientFinancialHistoryModal({
    required this.lojaId,
    required this.cliente,
  });

  final String lojaId;
  final ComercialCliente cliente;

  @override
  State<_ClientFinancialHistoryModal> createState() =>
      _ClientFinancialHistoryModalState();
}

class _ClientFinancialHistoryModalState
    extends State<_ClientFinancialHistoryModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');

  // Dados carregados
  List<ComercialClienteLancamento> _lancamentos = [];
  List<ComercialParcelaCliente> _parcelas = [];
  List<ComercialVendaCredito> _vendasCredito = [];
  List<ComercialRecebimentoCliente> _recebimentos = [];
  bool _carregando = true;
  String? _erroCarregamento;

  // Filtros
  String _filtroStatus = 'Todos';
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _carregarDados();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erroCarregamento = null;
    });

    // Carrega cada fonte de dados de forma independente — se uma falhar
    // (ex.: índice composto ausente), as demais continuam.
    List<ComercialClienteLancamento> lancamentos = [];
    List<ComercialParcelaCliente> parcelas = [];
    List<ComercialVendaCredito> vendas = [];
    List<ComercialRecebimentoCliente> recebimentos = [];

    try {
      lancamentos = await ComercialClientesService.carregarLancamentosCliente(
        lojaId: widget.lojaId,
        cliente: widget.cliente,
        limite: 200,
      );
    } catch (_) {
      // fallback: lançamentos vazios
    }

    try {
      parcelas = await ComercialCreditoService.carregarParcelasCliente(
        widget.lojaId,
        widget.cliente.id,
      );
    } catch (_) {
      // fallback: parcelas vazias
    }

    try {
      vendas = await ComercialCreditoService.carregarVendasCreditoCliente(
        widget.lojaId,
        widget.cliente.id,
      );
    } catch (_) {
      // fallback: vendas vazias
    }

    try {
      recebimentos = await _carregarRecebimentos();
    } catch (_) {
      // fallback: recebimentos vazios
    }

    if (!mounted) return;
    setState(() {
      _lancamentos = lancamentos;
      _parcelas = parcelas;
      _vendasCredito = vendas;
      _recebimentos = recebimentos;
      _carregando = false;
    });
  }

  Future<List<ComercialRecebimentoCliente>> _carregarRecebimentos() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojaId)
          .collection('recebimentos_cliente')
          .where('cliente_id', isEqualTo: widget.cliente.id)
          .orderBy('data_pagamento', descending: true)
          .limit(200)
          .get();
      return snap.docs
          .map(
            (d) => ComercialRecebimentoCliente.fromDoc(
              d.id,
              safeWebDocData(d),
            ),
          )
          .toList();
    } catch (_) {
      // Fallback: sem orderBy (índice composto pode não existir)
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.lojaId)
          .collection('recebimentos_cliente')
          .where('cliente_id', isEqualTo: widget.cliente.id)
          .limit(200)
          .get();
      final lista = snap.docs
          .map(
            (d) => ComercialRecebimentoCliente.fromDoc(
              d.id,
              safeWebDocData(d),
            ),
          )
          .toList();
      lista.sort((a, b) => b.dataPagamento.compareTo(a.dataPagamento));
      return lista;
    }
  }

  // ── Cálculos agregados ──────────────────────────────────────

  double get _totalComprado {
    double t = 0;
    for (final l in _lancamentos) {
      if (ComercialClienteLancamento.statusContaComoCompra(l.status)) {
        t += l.total;
      }
    }
    return t;
  }

  double get _totalPago {
    double t = 0;
    for (final l in _lancamentos) {
      if (l.status == 'entregue' && !l.ehVendaCredito) {
        t += l.total;
      }
    }
    for (final p in _recebimentos) {
      t += p.valorPago;
    }
    // evitar dupla contagem se recebimento já cobre
    return t;
  }

  double get _totalEmAberto {
    double t = 0;
    for (final p in _parcelas) {
      t += p.valorEmAberto;
    }
    return t;
  }

  double get _totalVencido {
    double t = 0;
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    for (final p in _parcelas) {
      final v = DateTime(
        p.dataVencimento.year,
        p.dataVencimento.month,
        p.dataVencimento.day,
      );
      if (p.valorEmAberto > 0.009 && v.isBefore(h)) {
        t += p.valorEmAberto;
      }
    }
    return t;
  }

  int get _quantidadeCompras {
    int q = 0;
    for (final l in _lancamentos) {
      if (ComercialClienteLancamento.statusContaComoCompra(l.status)) {
        q++;
      }
    }
    return q;
  }

  DateTime? get _ultimaCompra {
    DateTime? ult;
    for (final l in _lancamentos) {
      if (ComercialClienteLancamento.statusContaComoCompra(l.status)) {
        if (l.dataHora != null &&
            (ult == null || l.dataHora!.isAfter(ult))) {
          ult = l.dataHora;
        }
      }
    }
    return ult;
  }

  List<ComercialClienteLancamento> get _lancamentosFiltrados {
    var lista = _lancamentos.where(
      (l) => ComercialClienteLancamento.statusContaComoCompra(l.status),
    ).toList();

    final q = _buscaCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      lista = lista.where((l) {
        if (l.codigoExibicao.toLowerCase().contains(q)) return true;
        for (final item in l.itens) {
          if (item.nome.toLowerCase().contains(q)) return true;
        }
        return false;
      }).toList();
    }

    return lista;
  }

  List<ComercialParcelaCliente> get _parcelasFiltradas {
    return _parcelas;
  }

  List<ComercialRecebimentoCliente> get _recebimentosFiltrados {
    return _recebimentos;
  }

  List<ComercialParcelaCliente> get _pendencias {
    return _parcelas.where((p) => p.valorEmAberto > 0.009).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isMobile = mq.size.width < 768;
    final isTablet = mq.size.width >= 768 && mq.size.width < 1100;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 12 : 24,
      ),
      child: Container(
        width: isMobile ? mq.size.width - 24 : (isTablet ? 800 : 1100),
        constraints: BoxConstraints(
          maxHeight: isMobile ? mq.size.height - 24 : mq.size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _carregando
              ? _buildLoading()
              : _erroCarregamento != null
                  ? _buildError()
                  : _buildContent(isMobile, isTablet),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _roxo),
          SizedBox(height: 16),
          Text('Carregando histórico financeiro...'),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: _erro),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar dados',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _texto,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erroCarregamento ?? '',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _carregarDados,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isMobile, bool isTablet) {
    return Column(
      children: [
        // Header fixo
        _buildHeader(isMobile),
        // Summary cards
        _buildSummaryCards(isMobile),
        // Tabs
        Container(
          color: _fundo,
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: isMobile ? TabAlignment.start : TabAlignment.center,
            labelColor: _roxo,
            unselectedLabelColor: _muted,
            indicatorColor: _roxo,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            unselectedLabelStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'Resumo'),
              Tab(text: 'Compras'),
              Tab(text: 'Parcelas'),
              Tab(text: 'Pagamentos'),
              Tab(text: 'Pendências'),
            ],
          ),
        ),
        // Conteúdo das abas
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildResumoTab(isMobile),
              _buildComprasTab(isMobile),
              _buildParcelasTab(isMobile),
              _buildPagamentosTab(isMobile),
              _buildPendenciasTab(isMobile),
            ],
          ),
        ),
        // Footer
        _buildFooter(isMobile),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════════

  Widget _buildHeader(bool isMobile) {
    final c = widget.cliente;
    final disp = c.creditoDisponivel;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF5F3FF), Color(0xFFFFF8F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: _borda)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: título + fechar
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_roxo, _roxoClaro],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _roxo.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.account_balance_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Histórico financeiro do cliente',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.w800,
                        color: _texto,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Resumo completo de compras, pagamentos e pendências.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child:
                        Icon(Icons.close_rounded, size: 20, color: _muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Info do cliente
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _borda.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _roxo.withValues(alpha: 0.10),
                  child: Text(
                    _iniciais(c.nome),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _roxo,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _infoChip(Icons.person_rounded, c.nome),
                      if (c.cpf != null && c.cpf!.isNotEmpty)
                        _infoChip(
                            Icons.badge_rounded,
                            ComercialClientesService.formatarCpfExibicao(
                                c.cpf)),
                      if (c.telefone != null)
                        _infoChip(Icons.phone_rounded, c.telefone!),
                      _badgeStatus(c.statusExibicao),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Mini cards crédito
          Row(
            children: [
              _miniCardCredito(
                'Limite',
                _moeda.format(c.limiteCredito),
                _roxo,
                Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(width: 8),
              _miniCardCredito(
                'Usado',
                _moeda.format(c.creditoUtilizado),
                _laranja,
                Icons.trending_up_rounded,
              ),
              const SizedBox(width: 8),
              _miniCardCredito(
                'Disponível',
                _moeda.format(disp),
                disp >= 0 ? _sucesso : _erro,
                Icons.savings_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _texto,
          ),
        ),
      ],
    );
  }

  Widget _miniCardCredito(
      String label, String value, Color cor, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borda.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: cor),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: cor,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: _muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SUMMARY CARDS
  // ══════════════════════════════════════════════════════════════

  Widget _buildSummaryCards(bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 14 : 20, 14, isMobile ? 14 : 20, 8),
      child: isMobile
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _summaryCard('Total comprado', _moeda.format(_totalComprado),
                    _roxo, Icons.shopping_cart_rounded),
                _summaryCard('Total pago', _moeda.format(_totalPago), _sucesso,
                    Icons.check_circle_rounded),
                _summaryCard('Em aberto', _moeda.format(_totalEmAberto),
                    _laranja, Icons.pending_actions_rounded),
                _summaryCard('Vencido', _moeda.format(_totalVencido), _erro,
                    Icons.warning_amber_rounded),
                _summaryCard('Compras', '$_quantidadeCompras', _roxo,
                    Icons.receipt_long_rounded),
                _summaryCard(
                    'Última compra',
                    _ultimaCompra != null
                        ? _dataFmt.format(_ultimaCompra!)
                        : '—',
                    _muted,
                    Icons.calendar_today_rounded),
              ],
            )
          : Row(
              children: [
                Expanded(
                    child: _summaryCard('Total comprado',
                        _moeda.format(_totalComprado), _roxo, Icons.shopping_cart_rounded)),
                const SizedBox(width: 8),
                Expanded(
                    child: _summaryCard('Total pago',
                        _moeda.format(_totalPago), _sucesso, Icons.check_circle_rounded)),
                const SizedBox(width: 8),
                Expanded(
                    child: _summaryCard('Em aberto',
                        _moeda.format(_totalEmAberto), _laranja, Icons.pending_actions_rounded)),
                const SizedBox(width: 8),
                Expanded(
                    child: _summaryCard('Vencido',
                        _moeda.format(_totalVencido), _erro, Icons.warning_amber_rounded)),
                const SizedBox(width: 8),
                Expanded(
                    child: _summaryCard('Compras', '$_quantidadeCompras', _roxo,
                        Icons.receipt_long_rounded)),
                const SizedBox(width: 8),
                Expanded(
                    child: _summaryCard(
                        'Última compra',
                        _ultimaCompra != null
                            ? _dataFmt.format(_ultimaCompra!)
                            : '—',
                        _muted,
                        Icons.calendar_today_rounded)),
              ],
            ),
    );
  }

  Widget _summaryCard(
      String label, String value, Color cor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: _muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ABA RESUMO
  // ══════════════════════════════════════════════════════════════

  Widget _buildResumoTab(bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grid de visão geral
          Text(
            'Visão geral financeira',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _texto,
            ),
          ),
          const SizedBox(height: 16),
          if (isMobile)
            _buildOverviewGridMobile()
          else
            _buildOverviewGrid(),
          const SizedBox(height: 24),
          // Barra de uso do crédito
          _buildCreditBar(),
          const SizedBox(height: 24),
          // Vendas a crédito recentes
          if (_vendasCredito.isNotEmpty) ...[
            Text(
              'Compras a crédito',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _texto,
              ),
            ),
            const SizedBox(height: 12),
            ..._vendasCredito.take(5).map(_buildVendaCreditoCard),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewGrid() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _overviewItem('Total comprado', _moeda.format(_totalComprado),
                  _roxo, Icons.shopping_cart_rounded),
              const SizedBox(height: 12),
              _overviewItem(
                  'Total pago', _moeda.format(_totalPago), _sucesso, Icons.payments_rounded),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _overviewItem('Em aberto', _moeda.format(_totalEmAberto),
                  _laranja, Icons.pending_actions_rounded),
              const SizedBox(height: 12),
              _overviewItem('Vencido', _moeda.format(_totalVencido), _erro,
                  Icons.warning_amber_rounded),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _overviewItem('Limite atual',
                  _moeda.format(widget.cliente.limiteCredito), _roxo, Icons.account_balance_wallet_outlined),
              const SizedBox(height: 12),
              _overviewItem('Limite usado',
                  _moeda.format(widget.cliente.creditoUtilizado), _laranja, Icons.trending_up_rounded),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _overviewItem('Limite disponível',
                  _moeda.format(widget.cliente.creditoDisponivel),
                  widget.cliente.creditoDisponivel >= 0 ? _sucesso : _erro,
                  Icons.savings_outlined),
              const SizedBox(height: 12),
              _overviewItem(
                  'Quantidade de compras',
                  '$_quantidadeCompras',
                  _roxo,
                  Icons.receipt_long_rounded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewGridMobile() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _overviewItem('Total comprado',
                    _moeda.format(_totalComprado), _roxo, Icons.shopping_cart_rounded)),
            const SizedBox(width: 8),
            Expanded(
                child: _overviewItem('Total pago',
                    _moeda.format(_totalPago), _sucesso, Icons.payments_rounded)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _overviewItem('Em aberto',
                    _moeda.format(_totalEmAberto), _laranja, Icons.pending_actions_rounded)),
            const SizedBox(width: 8),
            Expanded(
                child: _overviewItem('Vencido',
                    _moeda.format(_totalVencido), _erro, Icons.warning_amber_rounded)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _overviewItem('Limite',
                    _moeda.format(widget.cliente.limiteCredito), _roxo, Icons.account_balance_wallet_outlined)),
            const SizedBox(width: 8),
            Expanded(
                child: _overviewItem('Usado',
                    _moeda.format(widget.cliente.creditoUtilizado), _laranja, Icons.trending_up_rounded)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _overviewItem(
                    'Disponível',
                    _moeda.format(widget.cliente.creditoDisponivel),
                    widget.cliente.creditoDisponivel >= 0 ? _sucesso : _erro,
                    Icons.savings_outlined)),
            const SizedBox(width: 8),
            Expanded(
                child: _overviewItem('Compras', '$_quantidadeCompras', _roxo,
                    Icons.receipt_long_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _overviewItem(
      String label, String value, Color cor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borda),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: cor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: cor,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: _muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditBar() {
    final c = widget.cliente;
    if (c.limiteCredito <= 0) return const SizedBox.shrink();

    final pct = (c.creditoUtilizado / c.limiteCredito).clamp(0.0, 1.0);
    final pctDisplay = (pct * 100).toStringAsFixed(0);
    final cor = pct >= 0.9
        ? _erro
        : pct >= 0.7
            ? _laranja
            : _sucesso;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Uso do limite de crédito',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: _texto,
                ),
              ),
              Text(
                '$pctDisplay% utilizado',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: cor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 12,
              backgroundColor: _borda,
              valueColor: AlwaysStoppedAnimation<Color>(cor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Usado: ${_moeda.format(c.creditoUtilizado)}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
              ),
              Text(
                'Disponível: ${_moeda.format(c.creditoDisponivel)}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVendaCreditoCard(ComercialVendaCredito v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borda),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.codigoVenda.isNotEmpty ? v.codigoVenda : 'Venda #${v.vendaId.length >= 4 ? v.vendaId.substring(v.vendaId.length - 4).toUpperCase() : v.vendaId}',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _texto,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${v.quantidadeParcelas}x de ${_moeda.format(v.valorTotal / v.quantidadeParcelas)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _moeda.format(v.valorTotal),
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _roxo,
                ),
              ),
              if (v.dataCompra != null)
                Text(
                  _dataFmt.format(v.dataCompra!),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: _muted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ABA COMPRAS
  // ══════════════════════════════════════════════════════════════

  Widget _buildComprasTab(bool isMobile) {
    final lista = _lancamentosFiltrados;
    return Column(
      children: [
        _buildFiltrosBar(isMobile),
        Expanded(
          child: lista.isEmpty
              ? _emptyState('Nenhuma compra encontrada.',
                  Icons.shopping_bag_outlined)
              : isMobile
                  ? _buildComprasMobile(lista)
                  : _buildComprasDesktop(lista),
        ),
      ],
    );
  }

  Widget _buildFiltrosBar(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borda)),
      ),
      child: isMobile
          ? Column(
              children: [
                TextField(
                  controller: _buscaCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar venda ou produto...',
                    hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _buscaCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar por código da venda ou produto...',
                      hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildFilterDropdown(
                  'Status',
                  _filtroStatus,
                  ['Todos', 'Pago', 'Em dias', 'Atrasada', 'Cancelado'],
                  (v) => setState(() => _filtroStatus = v!),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged, {
    double width = 140,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: _muted, fontWeight: FontWeight.w600),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _fundo,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borda),
          ),
          child: SizedBox(
            width: width,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                isDense: true,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w600, color: _texto),
                items: options
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComprasDesktop(List<ComercialClienteLancamento> lista) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(1),
          5: FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: _borda.withValues(alpha: 0.5)),
          bottom: BorderSide(color: _borda),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: _fundo),
            children: [
              _tableHeader('Data'),
              _tableHeader('Venda'),
              _tableHeader('Produtos'),
              _tableHeader('Pagamento'),
              _tableHeader('Valor'),
              _tableHeader('Status'),
            ],
          ),
          ...lista.map((l) => TableRow(
                children: [
                  _tableCell(l.dataHora != null
                      ? _dataFmt.format(l.dataHora!)
                      : '—'),
                  _tableCell(l.codigoExibicao, bold: true),
                  _tableCell(l.itens.take(3).map((i) => i.nome).join(', ')),
                  _tableCell(l.formaPagamento),
                  _tableCell(_moeda.format(l.total), cor: _roxo, bold: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _badgeStatusLancamento(l.statusRotulo),
                  ),
                ],
              )),
        ],
      ),
    );
  }

  Widget _buildComprasMobile(List<ComercialClienteLancamento> lista) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: lista.map((l) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borda),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l.codigoExibicao,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _texto,
                    ),
                  ),
                  _badgeStatusLancamento(l.statusRotulo),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l.dataHora != null ? _dataFmt.format(l.dataHora!) : '—',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 4),
              if (l.itens.isNotEmpty)
                Text(
                  l.itens.take(2).map((i) => i.nome).join(', '),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: _muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l.formaPagamento,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: _muted),
                  ),
                  Text(
                    _moeda.format(l.total),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _roxo,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ABA PARCELAS
  // ══════════════════════════════════════════════════════════════

  Widget _buildParcelasTab(bool isMobile) {
    final lista = _parcelasFiltradas;
    if (lista.isEmpty) {
      return _emptyState(
          'Nenhuma parcela encontrada.', Icons.credit_score_rounded);
    }
    return isMobile
        ? _buildParcelasMobile(lista)
        : _buildParcelasDesktop(lista);
  }

  Widget _buildParcelasDesktop(List<ComercialParcelaCliente> lista) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(0.8),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1),
          4: FlexColumnWidth(1),
          5: FlexColumnWidth(1),
          6: FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: _borda.withValues(alpha: 0.5)),
          bottom: BorderSide(color: _borda),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: _fundo),
            children: [
              _tableHeader('Parcela'),
              _tableHeader('Venda'),
              _tableHeader('Vencimento'),
              _tableHeader('Valor'),
              _tableHeader('Valor pago'),
              _tableHeader('Restante'),
              _tableHeader('Status'),
            ],
          ),
          ...lista.map((p) => TableRow(
                children: [
                  _tableCell('${p.numeroParcela}ª', bold: true),
                  _tableCell(p.codigoVenda.isNotEmpty
                      ? p.codigoVenda
                      : '—'),
                  _tableCell(_dataFmt.format(p.dataVencimento)),
                  _tableCell(_moeda.format(p.valorParcela)),
                  _tableCell(_moeda.format(p.valorPago)),
                  _tableCell(_moeda.format(p.valorEmAberto)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _badgeStatusParcela(p),
                  ),
                ],
              )),
        ],
      ),
    );
  }

  Widget _buildParcelasMobile(List<ComercialParcelaCliente> lista) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: lista.map((p) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borda),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${p.numeroParcela}ª Parcela',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _texto,
                    ),
                  ),
                  _badgeStatusParcela(p),
                ],
              ),
              const SizedBox(height: 6),
              rowInfo('Venda', p.codigoVenda.isNotEmpty ? p.codigoVenda : '—'),
              rowInfo('Vencimento', _dataFmt.format(p.dataVencimento)),
              const Divider(height: 14),
              rowInfo('Valor', _moeda.format(p.valorParcela)),
              rowInfo('Valor pago', _moeda.format(p.valorPago)),
              rowInfo('Restante', _moeda.format(p.valorEmAberto)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ABA PAGAMENTOS
  // ══════════════════════════════════════════════════════════════

  Widget _buildPagamentosTab(bool isMobile) {
    final lista = _recebimentosFiltrados;
    if (lista.isEmpty) {
      return _emptyState(
          'Nenhum pagamento registrado.', Icons.payments_rounded);
    }
    return isMobile
        ? _buildPagamentosMobile(lista)
        : _buildPagamentosDesktop(lista);
  }

  Widget _buildPagamentosDesktop(List<ComercialRecebimentoCliente> lista) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(1.2),
          5: FlexColumnWidth(1.2),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: _borda.withValues(alpha: 0.5)),
          bottom: BorderSide(color: _borda),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: _fundo),
            children: [
              _tableHeader('Data'),
              _tableHeader('Valor'),
              _tableHeader('Forma'),
              _tableHeader('Venda'),
              _tableHeader('Responsável'),
              _tableHeader('Observação'),
            ],
          ),
          ...lista.map((r) => TableRow(
                children: [
                  _tableCell(
                      _dataFmt.format(r.dataPagamento),
                      bold: true),
                  _tableCell(_moeda.format(r.valorPago),
                      cor: _sucesso, bold: true),
                  _tableCell(r.formaPagamento),
                  _tableCell(r.codigoVenda ?? '—'),
                  _tableCell(r.usuarioNome ?? '—'),
                  _tableCell(r.observacao ?? '—'),
                ],
              )),
        ],
      ),
    );
  }

  Widget _buildPagamentosMobile(List<ComercialRecebimentoCliente> lista) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: lista.map((r) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borda),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _dataFmt.format(r.dataPagamento),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _texto,
                    ),
                  ),
                  Text(
                    _moeda.format(r.valorPago),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _sucesso,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              rowInfo('Forma', r.formaPagamento),
              rowInfo('Venda', r.codigoVenda ?? '—'),
              rowInfo('Responsável', r.usuarioNome ?? '—'),
              if (r.observacao != null && r.observacao!.isNotEmpty)
                rowInfo('Obs', r.observacao!),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ABA PENDÊNCIAS
  // ══════════════════════════════════════════════════════════════

  Widget _buildPendenciasTab(bool isMobile) {
    final lista = _pendencias;
    if (lista.isEmpty) {
      return _emptyPremiumPendencias();
    }
    return isMobile
        ? _buildPendenciasMobile(lista)
        : _buildPendenciasDesktop(lista);
  }

  Widget _buildPendenciasDesktop(List<ComercialParcelaCliente> lista) {
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(0.8),
          4: FlexColumnWidth(1),
          5: FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: _borda.withValues(alpha: 0.5)),
          bottom: BorderSide(color: _borda),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: _fundo),
            children: [
              _tableHeader('Venda'),
              _tableHeader('Parcela'),
              _tableHeader('Vencimento'),
              _tableHeader('Dias'),
              _tableHeader('Valor'),
              _tableHeader('Status'),
            ],
          ),
          ...lista.map((p) {
            final venc = DateTime(p.dataVencimento.year,
                p.dataVencimento.month, p.dataVencimento.day);
            final dias = h.difference(venc).inDays;
            return TableRow(
              children: [
                _tableCell(
                    p.codigoVenda.isNotEmpty ? p.codigoVenda : '—'),
                _tableCell('${p.numeroParcela}ª', bold: true),
                _tableCell(_dataFmt.format(p.dataVencimento)),
                _tableCell(
                  dias > 0 ? '$dias dias' : '${dias.abs()} dias',
                  cor: dias > 0 ? _erro : _laranja,
                  bold: true,
                ),
                _tableCell(_moeda.format(p.valorEmAberto),
                    cor: _erro, bold: true),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: _badgeStatusParcela(p),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPendenciasMobile(List<ComercialParcelaCliente> lista) {
    final hoje = DateTime.now();
    final h = DateTime(hoje.year, hoje.month, hoje.day);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: lista.map((p) {
        final venc = DateTime(p.dataVencimento.year,
            p.dataVencimento.month, p.dataVencimento.day);
        final dias = h.difference(venc).inDays;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: dias > 0 ? _erro.withValues(alpha: 0.3) : _laranja.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${p.numeroParcela}ª Parcela',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _texto,
                    ),
                  ),
                  _badgeStatusParcela(p),
                ],
              ),
              const SizedBox(height: 6),
              rowInfo('Venda',
                  p.codigoVenda.isNotEmpty ? p.codigoVenda : '—'),
              rowInfo('Vencimento', _dataFmt.format(p.dataVencimento)),
              rowInfo(
                'Dias em atraso',
                dias > 0 ? '$dias dias' : '${dias.abs()} dias',
                cor: dias > 0 ? _erro : _laranja,
              ),
              const Divider(height: 14),
              rowInfo('Valor devido', _moeda.format(p.valorEmAberto),
                  cor: _erro, bold: true),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _emptyPremiumPendencias() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _sucesso.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  size: 40, color: _sucesso),
            ),
            const SizedBox(height: 20),
            Text(
              'Tudo em dia!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _texto,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Este cliente não possui pendências financeiras.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _muted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FOOTER
  // ══════════════════════════════════════════════════════════════

  Widget _buildFooter(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borda.withValues(alpha: 0.5))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Material(
            color: _laranja.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded,
                        size: 16, color: _laranja),
                    const SizedBox(width: 6),
                    Text(
                      'Fechar',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _laranja,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ══════════════════════════════════════════════════════════════
  // UTILITÁRIOS
  // ══════════════════════════════════════════════════════════════

  Widget _emptyState(String msg, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: _muted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              msg,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: _muted,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _muted,
        ),
      ),
    );
  }

  Widget _tableCell(
    String text, {
    bool bold = false,
    Color? cor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: cor ?? _texto,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget rowInfo(
    String label,
    String value, {
    Color? cor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: _muted, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: cor ?? _texto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeStatus(String status) {
    final ativo = status == 'ativo';
    final pend = status == 'com_pendencia';
    final label = pend ? 'Com pendência' : (ativo ? 'Ativo' : 'Bloqueado');
    final cor =
        pend ? _laranja : (ativo ? _sucesso : _muted);
    final bg =
        pend ? _bgStatusAberto : (ativo ? _bgStatusPago : const Color(0xFFF1F5F9));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }

  Widget _badgeStatusLancamento(String rotulo) {
    final isPago = rotulo == 'Pago';
    final isAtrasada = rotulo == 'Atrasada';
    final isCancelado = rotulo == 'Cancelado';
    late Color cor, bg;
    if (isCancelado) {
      cor = _muted;
      bg = const Color(0xFFF1F5F9);
    } else if (isAtrasada) {
      cor = _erro;
      bg = _bgStatusVencido;
    } else if (isPago) {
      cor = _sucesso;
      bg = _bgStatusPago;
    } else {
      cor = _laranja;
      bg = _bgStatusAberto;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        rotulo,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }

  Widget _badgeStatusParcela(ComercialParcelaCliente p) {
    late String label;
    late Color cor, bg;
    if (p.status == ComercialParcelaStatus.pago) {
      label = 'Paga';
      cor = _sucesso;
      bg = _bgStatusPago;
    } else if (p.status == ComercialParcelaStatus.vencido) {
      label = 'Vencida';
      cor = _erro;
      bg = _bgStatusVencido;
    } else if (p.status == ComercialParcelaStatus.parcialmentePago) {
      label = 'Parcial';
      cor = _laranja;
      bg = _bgStatusAberto;
    } else {
      label = 'Em aberto';
      cor = _laranja;
      bg = _bgStatusAberto;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }

  static String _iniciais(String nome) {
    final p = nome.trim().split(RegExp(r'\s+'));
    if (p.length >= 2) return (p[0][0] + p[1][0]).toUpperCase();
    return p.first.isNotEmpty ? p.first[0].toUpperCase() : 'C';
  }
}
