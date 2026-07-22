import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:depertin_web/services/comercial_recebimentos_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/comercial/comercial_enviar_comunicacao_modal.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// TELA PRINCIPAL — Recebimentos (Gestão Comercial)
// =============================================================================

class ComercialRecebimentosScreen extends StatefulWidget {
  const ComercialRecebimentosScreen({super.key});

  @override
  State<ComercialRecebimentosScreen> createState() =>
      _ComercialRecebimentosScreenState();
}

class _ComercialRecebimentosScreenState
    extends State<ComercialRecebimentosScreen> {
  final _buscaCtrl = TextEditingController();

  DateTime _dataInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dataFim = DateTime.now();
  String _filtroForma = 'Todas';
  String _filtroRecebidoPor = 'Todos';
  int _pagina = 1;
  static const int _itensPorPagina = 10;

  List<ComercialRecebimento> _recebimentos = [];
  bool _carregando = true;
  String? _erro;
  String _uidLoja = '';
  StreamSubscription<List<ComercialRecebimento>>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  /// Inicia a stream em tempo real dos recebimentos da loja.
  /// Sempre recria se o lojaId mudar.
  void _initStream(String lojaId) {
    if (lojaId.isEmpty) return;
    if (lojaId == _uidLoja && _subscription != null) return;
    _subscription?.cancel();
    _uidLoja = lojaId;
    _carregando = true;
    _erro = null;
    _subscription =
        ComercialRecebimentosService.streamRecebimentos(lojaId).listen(
      (lista) {
        if (!mounted) return;
        setState(() {
          _recebimentos = lista;
          _carregando = false;
          _erro = null;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _erro = '$e';
          _carregando = false;
        });
      },
    );
  }

  void _forcarRecarga(String lojaId) {
    setState(() {
      _subscription?.cancel();
      _uidLoja = '';
      _carregando = true;
      _erro = null;
    });
    _initStream(lojaId);
  }

  List<ComercialRecebimento> get _itensFiltrados {
    var lista = _recebimentos;
    final q = _buscaCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      lista = lista.where((r) {
        return r.clienteNome.toLowerCase().contains(q) ||
            (r.clienteDocumento ?? '').contains(q) ||
            (r.pedidoId ?? '').toLowerCase().contains(q);
      }).toList();
    }
    if (_filtroForma != 'Todas') {
      lista = lista.where((r) => r.formaPagamento == _filtroForma).toList();
    }
    if (_filtroRecebidoPor != 'Todos' && _filtroRecebidoPor.isNotEmpty) {
      lista = lista.where((r) =>
          (r.recebidoPorNome ?? '')
              .toLowerCase()
              .contains(_filtroRecebidoPor.toLowerCase())).toList();
    }
    // Período
    lista = lista.where((r) {
      final d = DateTime(r.dataRecebimento.year, r.dataRecebimento.month,
          r.dataRecebimento.day);
      return !d.isBefore(_dataInicio) && !d.isAfter(_dataFim);
    }).toList();
    return lista;
  }

  void _limparFiltros() {
    setState(() {
      _buscaCtrl.clear();
      _dataInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
      _dataFim = DateTime.now();
      _filtroForma = 'Todas';
      _filtroRecebidoPor = 'Todos';
      _pagina = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        _initStream(uidLoja);

        if (uidLoja.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8F9FC),
            body: Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            ),
          );
        }

        final resumo = ComercialRecebimentosService.calcularResumo(
            _itensFiltrados);

        return _RecebimentosBody(
          lojaId: uidLoja,
          buscaCtrl: _buscaCtrl,
          dataInicio: _dataInicio,
          dataFim: _dataFim,
          filtroForma: _filtroForma,
          filtroRecebidoPor: _filtroRecebidoPor,
          pagina: _pagina,
          itensPorPagina: _itensPorPagina,
          carregando: _carregando,
          erro: _erro,
          recebimentos: _recebimentos,
          itensFiltrados: _itensFiltrados,
          resumo: resumo,
          onBuscaChanged: (_) => setState(() => _pagina = 1),
          onPeriodoChanged: (i, f) => setState(() {
            _dataInicio = i;
            _dataFim = f;
            _pagina = 1;
          }),
          onFormaChanged: (v) => setState(() {
            _filtroForma = v ?? 'Todas';
            _pagina = 1;
          }),
          onRecebidoPorChanged: (v) => setState(() {
            _filtroRecebidoPor = v ?? 'Todos';
            _pagina = 1;
          }),
          onLimparFiltros: _limparFiltros,
          onPageChanged: (v) => setState(() => _pagina = v),
          onRefresh: () => _forcarRecarga(uidLoja),
        );
      },
    );
  }
}

// =============================================================================
// BODY PRINCIPAL
// =============================================================================

class _RecebimentosBody extends StatelessWidget {
  const _RecebimentosBody({
    required this.lojaId,
    required this.buscaCtrl,
    required this.dataInicio,
    required this.dataFim,
    required this.filtroForma,
    required this.filtroRecebidoPor,
    required this.pagina,
    required this.itensPorPagina,
    required this.carregando,
    required this.erro,
    required this.recebimentos,
    required this.itensFiltrados,
    required this.resumo,
    required this.onBuscaChanged,
    required this.onPeriodoChanged,
    required this.onFormaChanged,
    required this.onRecebidoPorChanged,
    required this.onLimparFiltros,
    required this.onPageChanged,
    required this.onRefresh,
  });

  final String lojaId;
  final TextEditingController buscaCtrl;
  final DateTime dataInicio, dataFim;
  final String filtroForma, filtroRecebidoPor;
  final int pagina, itensPorPagina;
  final bool carregando;
  final String? erro;
  final List<ComercialRecebimento> recebimentos, itensFiltrados;
  final ComercialRecebimentosResumo resumo;
  final ValueChanged<String> onBuscaChanged;
  final void Function(DateTime, DateTime) onPeriodoChanged;
  final ValueChanged<String?> onFormaChanged;
  final ValueChanged<String?> onRecebidoPorChanged;
  final VoidCallback onLimparFiltros;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final isDesktop = largura > 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              if (carregando && recebimentos.isEmpty && erro == null) _buildSkeleton(),
              if (erro != null && recebimentos.isEmpty) _buildErro(),
              if (!carregando || recebimentos.isNotEmpty) ...[
                _buildSummaryGrid(resumo),
                const SizedBox(height: 20),
                _buildFiltros(),
                const SizedBox(height: 20),
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: _buildTabela(context, resumo),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 320,
                        child: _buildSidebar(resumo),
                      ),
                    ],
                  )
                else ...[
                  _buildTabela(context, resumo),
                  const SizedBox(height: 24),
                  _buildSidebar(resumo),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1E9FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.payments_rounded,
              color: PainelAdminTheme.roxo, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recebimentos',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              Text(
                'Acompanhe todos os recebimentos realizados no período selecionado.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(
          children: [
            const CircularProgressIndicator(color: PainelAdminTheme.roxo),
            const SizedBox(height: 20),
            Text(
              'Carregando recebimentos...',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              'Erro ao carregar recebimentos.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              erro ?? '',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(ComercialRecebimentosResumo r) {
    final cards = [
      _ResumoCard(
        icone: Icons.today_rounded,
        corIcone: const Color(0xFF16A34A),
        corFundoIcone: const Color(0xFFE7F8EE),
        titulo: 'Recebido hoje',
        valor: formatarMoeda(r.recebidoHoje),
        rodape: '${r.quantidadeHoje} recebimentos',
      ),
      _ResumoCard(
        icone: Icons.account_balance_wallet_rounded,
        corIcone: const Color(0xFF6A1B9A),
        corFundoIcone: const Color(0xFFF1E9FF),
        titulo: 'Recebido no mês',
        valor: formatarMoeda(r.recebidoMes),
        rodape: r.variacaoMes >= 0
            ? '+${r.variacaoMes.toStringAsFixed(1)}% vs mês passado'
            : '${r.variacaoMes.toStringAsFixed(1)}% vs mês passado',
      ),
      _ResumoCard(
        icone: Icons.receipt_long_rounded,
        corIcone: const Color(0xFFFF8F00),
        corFundoIcone: const Color(0xFFFFF8E1),
        titulo: 'Parcelas recebidas',
        valor: '${r.parcelasRecebidas}',
        rodape: 'Este mês',
      ),
      _ResumoCard(
        icone: Icons.trending_up_rounded,
        corIcone: const Color(0xFF3B82F6),
        corFundoIcone: const Color(0xFFEFF6FF),
        titulo: 'Ticket médio',
        valor: formatarMoeda(r.ticketMedio),
        rodape: 'Este mês',
      ),
      _ResumoCard(
        icone: Icons.people_rounded,
        corIcone: const Color(0xFF16A34A),
        corFundoIcone: const Color(0xFFE7F8EE),
        titulo: 'Clientes pagantes',
        valor: '${r.clientesPagantes}',
        rodape: 'Este mês',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 3
                : 1;
        final gap = 12.0;
        return Column(
          children: [
            for (var row = 0; row < (cards.length / cols).ceil(); row++)
              Padding(
                padding: EdgeInsets.only(top: row > 0 ? gap : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < cols; col++)
                      if (row * cols + col < cards.length) ...[
                        if (col > 0) SizedBox(width: gap),
                        Expanded(child: cards[row * cols + col]),
                      ]
                      else
                        const Spacer(),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFiltros() {
    final formas = ['Todas', 'PIX', 'Cartão de crédito', 'Cartão de débito', 'Dinheiro', 'Transferência', 'Carteira DiPertin'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: buscaCtrl,
                  onChanged: (v) => onBuscaChanged(v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por cliente...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                ),
              ),
              _filtroDropdown(
                valor: '${dataInicio.day}/${dataInicio.month}/${dataInicio.year} - ${dataFim.day}/${dataFim.month}/${dataFim.year}',
                label: 'Período',
                icone: Icons.date_range_rounded,
                itens: const ['Este mês', 'Mês passado', 'Últimos 30 dias', 'Últimos 90 dias'],
                aoSelecionar: (v) {
                  final hoje = DateTime.now();
                  DateTime i, f;
                  switch (v) {
                    case 'Mês passado':
                      i = DateTime(hoje.year, hoje.month - 1, 1);
                      f = DateTime(hoje.year, hoje.month, 1).subtract(const Duration(days: 1));
                      break;
                    case 'Últimos 30 dias':
                      i = hoje.subtract(const Duration(days: 30));
                      f = hoje;
                      break;
                    case 'Últimos 90 dias':
                      i = hoje.subtract(const Duration(days: 90));
                      f = hoje;
                      break;
                    default:
                      i = DateTime(hoje.year, hoje.month, 1);
                      f = hoje;
                  }
                  onPeriodoChanged(i, f);
                },
              ),
              _filtroDropdown(
                valor: filtroForma,
                label: 'Forma de pagamento',
                icone: Icons.payments_rounded,
                itens: formas,
                aoSelecionar: (v) => onFormaChanged(v),
              ),
              _filtroDropdown(
                valor: filtroRecebidoPor,
                label: 'Recebido por',
                icone: Icons.person_rounded,
                itens: ['Todos'],
                aoSelecionar: (v) => onRecebidoPorChanged(v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onLimparFiltros,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Limpar filtros'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtroDropdown({
    required String valor,
    required String label,
    required IconData icone,
    required List<String> itens,
    required ValueChanged<String> aoSelecionar,
    double width = 210,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        value: itens.contains(valor) ? valor : itens.first,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icone, size: 16),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        items: itens
            .map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: (v) {
          if (v != null) aoSelecionar(v);
        },
        style: GoogleFonts.plusJakartaSans(fontSize: 13),
      ),
    );
  }

  Widget _buildTabela(BuildContext context, ComercialRecebimentosResumo r) {
    final totalPaginas =
        max(1, (itensFiltrados.length / itensPorPagina).ceil());
    final paginaAtual = pagina.clamp(1, totalPaginas);
    final inicio = (paginaAtual - 1) * itensPorPagina;
    final fim = inicio + itensPorPagina;
    final paginaItens = itensFiltrados.isEmpty
        ? const <ComercialRecebimento>[]
        : itensFiltrados.sublist(
            inicio.clamp(0, itensFiltrados.length),
            fim.clamp(0, itensFiltrados.length),
          );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(flex: 3, child: _th('Cliente')),
                Expanded(flex: 2, child: _th('Documento')),
                Expanded(flex: 2, child: _th('Valor recebido')),
                Expanded(flex: 2, child: _th('Valor original')),
                Expanded(flex: 2, child: _th('Multa/Juros')),
                Expanded(flex: 2, child: _th('Desconto')),
                Expanded(flex: 2, child: _th('Forma')),
                Expanded(flex: 2, child: _th('Recebido por')),
                Expanded(flex: 2, child: _th('Data')),
                const SizedBox(width: 44),
              ],
            ),
          ),
          const Divider(height: 16, color: Color(0xFFEEEAF6)),
          if (paginaItens.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1E9FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.payments_rounded,
                          size: 36, color: PainelAdminTheme.roxo),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum recebimento encontrado',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Os pagamentos confirmados aparecerão aqui automaticamente.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFF94A3B8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...paginaItens.map((rec) => _linha(context, rec)),
          // Paginação — sempre visível quando há registros
          if (itensFiltrados.isNotEmpty)
            _buildPaginacao(itensFiltrados.length, paginaAtual, totalPaginas),
        ],
      ),
    );
  }

  Widget _th(String label) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF94A3B8),
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _linha(BuildContext context, ComercialRecebimento rec) {
    final temEncargos = rec.valorMulta > 0.009 || rec.valorJuros > 0.009;
    final estornado = rec.status == 'estornado';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: estornado
                ? const Color(0xFFFEE2E2)
                : const Color(0xFFF1F5F9),
          ),
        ),
        color: estornado
            ? const Color(0xFFFEF2F2).withValues(alpha: 0.3)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: estornado
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFF1E9FF),
                    child: Text(
                      rec.clienteNome.isNotEmpty
                          ? rec.clienteNome[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: estornado
                            ? const Color(0xFFDC2626)
                            : PainelAdminTheme.roxo,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rec.clienteNome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                rec.clienteDocumento?.isNotEmpty == true
                    ? _fmtDoc(rec.clienteDocumento!)
                    : '—',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatarMoeda(rec.valorRecebido),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: estornado
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatarMoeda(rec.valorOriginal),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: temEncargos
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        formatarMoeda(rec.valorMulta + rec.valorJuros),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    )
                  : Text(
                      'R\$ 0,00',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFFCBD5E1),
                      ),
                    ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                rec.valorDesconto > 0.009
                    ? formatarMoeda(rec.valorDesconto)
                    : 'R\$ 0,00',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: rec.valorDesconto > 0.009
                      ? const Color(0xFFDC2626)
                      : const Color(0xFFCBD5E1),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: _formaBadge(rec.formaPagamento),
            ),
            Expanded(
              flex: 2,
              child: Text(
                rec.recebidoPorNome ?? '—',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatarData(rec.dataRecebimento),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    formatarHora(rec.dataRecebimento),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            // Ações
            _acaoMenu(context, rec),
          ],
        ),
      ),
    );
  }

  Widget _formaBadge(String forma) {
    final (icon, cor) = _formaIcone(forma);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            forma,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cor,
            ),
          ),
        ),
      ],
    );
  }

  (IconData, Color) _formaIcone(String forma) {
    switch (forma) {
      case 'PIX':
        return (Icons.pix_rounded, const Color(0xFF16A34A));
      case 'Cartão de crédito':
        return (Icons.credit_card_rounded, const Color(0xFF6A1B9A));
      case 'Cartão de débito':
        return (Icons.credit_card_rounded, const Color(0xFF3B82F6));
      case 'Dinheiro':
        return (Icons.monetization_on_rounded, const Color(0xFFCA8A04));
      case 'Transferência':
        return (Icons.account_balance_rounded, const Color(0xFF64748B));
      default:
        return (Icons.payments_rounded, const Color(0xFF64748B));
    }
  }

  Widget _acaoMenu(BuildContext context, ComercialRecebimento rec) {
    return SizedBox(
      width: 44,
      child: PopupMenuButton<String>(
        offset: const Offset(-180, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        onSelected: (acao) {
          switch (acao) {
            case 'detalhes':
              _abrirDetalhes(context, rec);
              break;
            case 'comprovante':
              _mostrarSnack(context, 'Comprovante do recebimento.');
              break;
            case 'imprimir':
              _imprimirRecibo(context, rec);
              break;
            case 'enviar':
              abrirModalEnviarComunicacao(
                context: context,
                lojaId: lojaId,
                tipo: 'comprovante',
                clienteId: rec.clienteId,
                clienteNome: rec.clienteNome,
                valorExtra: rec.valorRecebido,
                formaPagamentoExtra: rec.formaPagamento,
                dataExtra: rec.dataRecebimento,
              );
              break;
            case 'estornar':
              _abrirEstorno(context, rec);
              break;
          }
        },
        itemBuilder: (_) => [
          _menuItem('detalhes', Icons.visibility_outlined, 'Ver detalhes', null),
          _menuItem('comprovante', Icons.description_outlined, 'Ver comprovante', null),
          _menuItem('imprimir', Icons.print_outlined, 'Imprimir recibo', null),
          _menuItem('enviar', Icons.send_rounded, 'Enviar comprovante', null),
          const PopupMenuDivider(height: 1),
          _menuItem('estornar', Icons.undo_rounded, 'Estornar pagamento', 'vermelho'),
        ],
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.more_horiz_rounded,
              size: 18, color: Color(0xFF64748B)),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, String? corTema) {
    final cor = corTema == 'vermelho'
        ? const Color(0xFFDC2626)
        : const Color(0xFF1A1A2E);
    return PopupMenuItem<String>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cor),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: corTema == 'vermelho' ? cor : const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirDetalhes(BuildContext context, ComercialRecebimento rec) {
    showDialog(
      context: context,
      builder: (ctx) => _DetalhesDialog(rec: rec),
    );
  }

  void _imprimirRecibo(BuildContext context, ComercialRecebimento rec) {
    showDialog(
      context: context,
      builder: (ctx) => _ReciboDialog(rec: rec),
    );
  }

  void _abrirEstorno(BuildContext context, ComercialRecebimento rec) {
    final motivoCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.undo_rounded,
                  color: Color(0xFFDC2626)),
            ),
            const SizedBox(width: 12),
            const Text('Estornar recebimento?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Essa ação irá estornar o recebimento selecionado e reabrir a parcela vinculada.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: motivoCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Motivo do estorno *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (motivoCtrl.text.trim().isEmpty) return;
              try {
                final user = FirebaseAuth.instance.currentUser;
                await ComercialRecebimentosService.estornar(
                  recebimentoId: rec.id,
                  motivo: motivoCtrl.text.trim(),
                  estornadoPor: user?.displayName ?? user?.email ?? 'Lojista',
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _mostrarSnack(context, 'Recebimento estornado com sucesso.');
              } catch (e) {
                _mostrarSnack(context, 'Erro ao estornar: $e');
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Estornar recebimento'),
          ),
        ],
      ),
    );
  }

  void _mostrarSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildPaginacao(int total, int atual, int totalPag) {
    final inicio = (atual - 1) * itensPorPagina;
    final fim = (inicio + itensPorPagina).clamp(0, total);
    final paginas = _paginasVisiveis(atual, totalPag);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 520;
          final info = Text(
            'Mostrando ${inicio + 1}–$fim de $total recebimentos',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF94A3B8),
            ),
          );
          final controles = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pagBtn(
                Icons.chevron_left_rounded,
                atual > 1 ? () => onPageChanged(atual - 1) : null,
              ),
              ...paginas.map((n) => _pagNum(n, atual == n)),
              _pagBtn(
                Icons.chevron_right_rounded,
                atual < totalPag ? () => onPageChanged(atual + 1) : null,
              ),
            ],
          );

          if (compacto) {
            return Column(
              children: [
                info,
                const SizedBox(height: 10),
                controles,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: info),
              controles,
            ],
          );
        },
      ),
    );
  }

  /// Janela de até 5 números de página centrada na página atual.
  List<int> _paginasVisiveis(int atual, int totalPag) {
    if (totalPag <= 5) {
      return List.generate(totalPag, (i) => i + 1);
    }
    var start = atual - 2;
    var end = atual + 2;
    if (start < 1) {
      end += 1 - start;
      start = 1;
    }
    if (end > totalPag) {
      start -= end - totalPag;
      end = totalPag;
    }
    start = start.clamp(1, totalPag);
    return [for (var i = start; i <= end; i++) i];
  }

  Widget _pagBtn(IconData icon, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, size: 16,
                color: onTap != null
                    ? const Color(0xFF1A1A2E)
                    : const Color(0xFFCBD5E1)),
          ),
        ),
      ),
    );
  }

  Widget _pagNum(int num, bool ativo) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: ativo ? PainelAdminTheme.roxo : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onPageChanged(num),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Text(
              '$num',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                color: ativo ? Colors.white : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(ComercialRecebimentosResumo r) {
    return _buildDonutCard(r);
  }

  Widget _buildDonutCard(ComercialRecebimentosResumo r) {
    final total = r.porForma.values.fold<double>(
        0, (s, v) => s + (v['total'] ?? 0));
    final legendas = r.porForma.entries.map((e) {
      final pct = total > 0 ? ((e.value['total'] ?? 0) / total * 100) : 0.0;
      return '${e.key} — ${formatarMoeda(e.value['total'] ?? 0)} (${pct.toStringAsFixed(1)}%)';
    }).toList();

    return _CardLateral(
      titulo: 'Resumo de recebimentos',
      child: Column(
        children: [
          // Donut simples
          SizedBox(
            height: 140,
            child: total > 0
                ? CustomPaint(
                    size: const Size(140, 140),
                    painter: _DonutPainter(r.porForma, total),
                  )
                : Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFE2E8F0), width: 3),
                      ),
                      child: const Icon(Icons.payments_rounded,
                          size: 32, color: Color(0xFFCBD5E1)),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(formatarMoeda(total),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 24, fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.roxo)),
          Text('Total',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: const Color(0xFF64748B))),
          const Divider(height: 20),
          ...legendas.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: const Color(0xFF64748B)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              )),
        ],
      ),
    );
  }
}

// =============================================================================
// CARDS LATERAIS
// =============================================================================

class _CardLateral extends StatelessWidget {
  const _CardLateral({required this.titulo, required this.child});
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E))),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// =============================================================================
// RESULTADO CARD
// =============================================================================

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({
    required this.icone,
    required this.corIcone,
    required this.corFundoIcone,
    required this.titulo,
    required this.valor,
    required this.rodape,
  });

  final IconData icone;
  final Color corIcone, corFundoIcone;
  final String titulo, valor, rodape;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: corFundoIcone,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, color: corIcone, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: const Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(valor,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                Text(rodape,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, color: const Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DIÁLOGO DE DETALHES
// =============================================================================

class _DetalhesDialog extends StatelessWidget {
  const _DetalhesDialog({required this.rec});
  final ComercialRecebimento rec;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1E9FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: PainelAdminTheme.roxo),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Detalhes do recebimento',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),
              _dl('Cliente', rec.clienteNome),
              _dl('Documento', rec.clienteDocumento?.isNotEmpty == true
                  ? _fmtDoc(rec.clienteDocumento!) : '—'),
              if (rec.pedidoId!.isNotEmpty)
                _dl('Pedido', rec.pedidoId!),
              _dl('Valor original', formatarMoeda(rec.valorOriginal)),
              _dl('Multa', rec.valorMulta > 0.009
                  ? formatarMoeda(rec.valorMulta) : 'R\$ 0,00'),
              _dl('Juros', rec.valorJuros > 0.009
                  ? formatarMoeda(rec.valorJuros) : 'R\$ 0,00'),
              _dl('Desconto', rec.valorDesconto > 0.009
                  ? formatarMoeda(rec.valorDesconto) : 'R\$ 0,00'),
              _dl('Valor recebido', formatarMoeda(rec.valorRecebido),
                  destaque: true),
              _dl('Forma de pagamento', rec.formaPagamento),
              _dl('Recebido por', rec.recebidoPorNome ?? '—'),
              _dl('Data/hora', formatarDataHora(rec.dataRecebimento)),
              if (rec.observacao!.isNotEmpty)
                _dl('Observação', rec.observacao!),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Fechar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Imprimir recibo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: PainelAdminTheme.laranja,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dl(String r, String v, {bool destaque = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(r,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: const Color(0xFF64748B))),
            ),
            Expanded(
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: destaque ? 15 : 13,
                    fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
                    color: destaque ? PainelAdminTheme.laranja : null,
                  )),
            ),
          ],
        ),
      );
}

// =============================================================================
// RECIBO DIALOG
// =============================================================================

class _ReciboDialog extends StatelessWidget {
  const _ReciboDialog({required this.rec});
  final ComercialRecebimento rec;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_rounded,
                  size: 48, color: PainelAdminTheme.roxo.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('RECIBO DE PAGAMENTO',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const Divider(height: 24),
              _reciboLinha('Cliente', rec.clienteNome),
              _reciboLinha('Documento',
                  rec.clienteDocumento?.isNotEmpty == true
                      ? _fmtDoc(rec.clienteDocumento!) : '—'),
              _reciboLinha('Valor', formatarMoeda(rec.valorRecebido)),
              _reciboLinha('Forma', rec.formaPagamento),
              _reciboLinha('Data', formatarData(rec.dataRecebimento)),
              _reciboLinha('Hora', formatarHora(rec.dataRecebimento)),
              _reciboLinha('Operador', rec.recebidoPorNome ?? '—'),
              if (rec.pedidoId!.isNotEmpty)
                _reciboLinha('Pedido', rec.pedidoId!),
              const Divider(height: 24),
              Text('DiPertin Gestão Comercial',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        _mostrarSnackGlobal(context, 'Recibo enviado para impressão.');
                      },
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Imprimir'),
                      style: FilledButton.styleFrom(
                        backgroundColor: PainelAdminTheme.laranja,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reciboLinha(String r, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(r,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: const Color(0xFF64748B))),
            ),
            Expanded(
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  void _mostrarSnackGlobal(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// =============================================================================
// DONUT PAINTER
// =============================================================================

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.dados, this.total);
  final Map<String, Map<String, double>> dados;
  final double total;

  static const _cores = [
    Color(0xFF16A34A),
    Color(0xFF6A1B9A),
    Color(0xFFFF8F00),
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var startAngle = -pi / 2;

    final entries = dados.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final pct = (entries[i].value['total'] ?? 0) / total;
      final sweep = pct * 2 * pi;
      final paint = Paint()
        ..color = _cores[i % _cores.length]
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }
    // Buraco no meio
    canvas.drawCircle(center, radius * 0.55, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.total != total;
}

// =============================================================================
// HELPERS
// =============================================================================

String _fmtDoc(String doc) {
  final d = doc.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11) {
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }
  if (d.length == 14) {
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12)}';
  }
  return doc;
}
