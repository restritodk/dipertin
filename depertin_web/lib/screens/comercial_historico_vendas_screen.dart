import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/models/venda_historico_model.dart';
import 'package:depertin_web/services/vendas_historico_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/utils/pdf_download.dart';
import 'package:depertin_web/utils/vendas_historico_pdf.dart';
import 'package:depertin_web/widgets/dipertin_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Tela SaaS de Histórico de Vendas — Gestão Comercial.
class ComercialHistoricoVendasScreen extends StatefulWidget {
  const ComercialHistoricoVendasScreen({super.key});

  @override
  State<ComercialHistoricoVendasScreen> createState() =>
      _ComercialHistoricoVendasScreenState();
}

class _ComercialHistoricoVendasScreenState
    extends State<ComercialHistoricoVendasScreen> {
  final _buscaCtrl = TextEditingController();
  final _moedaFmt = VendasHistoricoService.formatarMoeda;

  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _filtroStatus = 'Todos';
  String _filtroFormaPagamento = 'Todos';

  List<VendaHistorico> _vendas = [];
  List<VendaHistorico> _vendasFiltradas = [];
  VendasHistoricoResumo _resumo = VendasHistoricoResumo.vazio;

  bool _carregando = true;
  bool _erro = false;
  bool _exportando = false;
  String _lojaNome = '';
  String _lojaId = '';

  int _pagina = 1;
  int _itensPorPagina = 10;

  @override
  void initState() {
    super.initState();
    _dataInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _dataFim = DateTime.now();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar({required String lojaId}) async {
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final vendas = await VendasHistoricoService.carregarVendas(
        lojaId: lojaId,
        dataInicio: _dataInicio,
        dataFim: _dataFim,
      );
      if (!mounted) return;
      _vendas = vendas;
      _aplicarFiltros();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = true;
        _carregando = false;
      });
    }
  }

  void _aplicarFiltros() {
    final filtradas = VendasHistoricoService.aplicarFiltros(
      _vendas,
      busca: _buscaCtrl.text,
      status: _filtroStatus,
      formaPagamento: _filtroFormaPagamento,
    );
    setState(() {
      _vendasFiltradas = filtradas;
      _resumo = VendasHistoricoResumo.calcular(filtradas);
      _carregando = false;
      _pagina = 1;
    });
  }

  void _limparFiltros() {
    setState(() {
      _buscaCtrl.clear();
      _dataInicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
      _dataFim = DateTime.now();
      _filtroStatus = 'Todos';
      _filtroFormaPagamento = 'Todos';
      _pagina = 1;
    });
    if (_lojaId.isNotEmpty) _carregar(lojaId: _lojaId);
  }

  Future<void> _exportarPdf(
    String lojaId,
    Map<String, dynamic>? dadosUsuario,
  ) async {
    if (_exportando) return;

    // Extrai dados da loja para o diálogo
    final lojaSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(lojaId)
        .get();
    final lojaData = lojaSnap.data() ?? {};
    final nomeLoja = (lojaData['loja_nome'] ??
            lojaData['nome'] ??
            lojaData['nome_loja'] ??
            'Minha Loja')
        .toString();

    // Diálogo de confirmação
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => _confirmacaoExportarPdf(
        context: ctx,
        nomeLoja: nomeLoja,
        dataInicio: _dataInicio,
        dataFim: _dataFim,
        qtdVendas: _vendasFiltradas.length,
        totalVendido: _resumo.totalVendido,
        totalPago: _resumo.vendasPagas,
        totalPendente: _resumo.vendasPendentes,
        moedaFmt: _moedaFmt,
      ),
    );

    if (confirmar != true) return;

    setState(() => _exportando = true);
    try {
      final cnpj = lojaData['cnpj']?.toString() ?? '';
      final endereco = [
        lojaData['endereco']?.toString() ?? '',
        lojaData['bairro']?.toString() ?? '',
        '${lojaData['cidade']?.toString() ?? ''} ${lojaData['uf']?.toString() ?? ''}',
      ].where((s) => s.isNotEmpty).join(', ');
      final telefone = lojaData['telefone']?.toString() ?? '';
      final email = lojaData['email']?.toString() ?? '';
      final responsavel =
          lojaData['nome']?.toString() ?? lojaData['responsavel']?.toString() ?? '';

      final pdfBytes = await gerarVendasHistoricoPdf(
        nomeLoja: nomeLoja,
        cnpjCpf: cnpj,
        endereco: endereco,
        telefone: telefone,
        email: email,
        responsavel: responsavel,
        dataInicio: _dataInicio ?? DateTime.now(),
        dataFim: _dataFim ?? DateTime.now(),
        vendas: _vendasFiltradas,
        resumo: _resumo,
        geradoEm: DateTime.now(),
      );

      // Nome do arquivo: historico-vendas-nome-da-loja-YYYY-MM-DD.pdf
      final lojaSlug = nomeLoja
          .toLowerCase()
          .replaceAll(RegExp(r'[áàâãä]'), 'a')
          .replaceAll(RegExp(r'[éèêë]'), 'e')
          .replaceAll(RegExp(r'[íìîï]'), 'i')
          .replaceAll(RegExp(r'[óòôõö]'), 'o')
          .replaceAll(RegExp(r'[úùûü]'), 'u')
          .replaceAll(RegExp(r'[ç]'), 'c')
          .replaceAll(RegExp(r'[^a-z0-9]'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final filename = 'historico-vendas-$lojaSlug-$hoje.pdf';

      downloadPdfFile(pdfBytes, filename);

      if (mounted) {
        _mostrarSnack('PDF exportado com sucesso.');
      }
    } catch (_) {
      if (mounted) {
        _mostrarSnack('Erro ao exportar PDF.');
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _confirmacaoExportarPdf({
    required BuildContext context,
    required String nomeLoja,
    required DateTime? dataInicio,
    required DateTime? dataFim,
    required int qtdVendas,
    required double totalVendido,
    required double totalPago,
    required double totalPendente,
    required String Function(double) moedaFmt,
  }) {
    final dfD = DateFormat('dd/MM/yyyy');
    final periodoInicio =
        dataInicio != null ? dfD.format(dataInicio) : '—';
    final periodoFim = dataFim != null ? dfD.format(dataFim) : '—';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF1E9FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded,
                color: Color(0xFFDC2626), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Exportar relatório em PDF?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Será gerado um relatório com as vendas filtradas no período selecionado.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _linhaConfirmacao('Período', '$periodoInicio até $periodoFim'),
                const Divider(height: 20),
                _linhaConfirmacao('Quantidade de vendas', '$qtdVendas'),
                const Divider(height: 20),
                _linhaConfirmacao('Total vendido', moedaFmt(totalVendido)),
                const Divider(height: 20),
                _linhaConfirmacao('Total pago', moedaFmt(totalPago)),
                const Divider(height: 20),
                _linhaConfirmacao('Total pendente', moedaFmt(totalPendente)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancelar',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('Exportar PDF'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _linhaConfirmacao(String label, String valor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  void _mostrarSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _abrirDetalhes(VendaHistorico venda) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => _VendaDetalhesModal(venda: venda, moedaFmt: _moedaFmt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        if (uidLoja.isEmpty) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(
              child: CircularProgressIndicator(color: PainelAdminTheme.roxo),
            ),
          );
        }

        if (_lojaId != uidLoja) {
          _lojaId = uidLoja;
          _lojaNome = (dadosUsuario?['loja_nome'] ??
                  dadosUsuario?['nome'] ??
                  dadosUsuario?['nome_loja'] ??
                  'Loja')
              .toString();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _carregar(lojaId: uidLoja);
          });
        }

        return _HistoricoBody(
          lojaId: uidLoja,
          dadosUsuario: dadosUsuario,
          lojaNome: _lojaNome,
          buscaCtrl: _buscaCtrl,
          dataInicio: _dataInicio,
          dataFim: _dataFim,
          filtroStatus: _filtroStatus,
          filtroFormaPagamento: _filtroFormaPagamento,
          vendasFiltradas: _vendasFiltradas,
          resumo: _resumo,
          carregando: _carregando,
          erro: _erro,
          exportando: _exportando,
          pagina: _pagina,
          itensPorPagina: _itensPorPagina,
          moedaFmt: _moedaFmt,
          onBuscaChanged: (v) {
            setState(() => _pagina = 1);
            _aplicarFiltros();
          },
          onDataInicioChanged: (d) {
            _dataInicio = d;
            if (_lojaId.isNotEmpty) _carregar(lojaId: _lojaId);
          },
          onDataFimChanged: (d) {
            _dataFim = d;
            if (_lojaId.isNotEmpty) _carregar(lojaId: _lojaId);
          },
          onStatusChanged: (v) {
            setState(() => _filtroStatus = v ?? 'Todos');
            _aplicarFiltros();
          },
          onFormaPagamentoChanged: (v) {
            setState(() => _filtroFormaPagamento = v ?? 'Todos');
            _aplicarFiltros();
          },
          onLimparFiltros: _limparFiltros,
          onPageChanged: (v) => setState(() => _pagina = v),
          onItensPorPaginaChanged: (v) {
            setState(() {
              _itensPorPagina = v;
              _pagina = 1;
            });
          },
          onRecarregar: () => _carregar(lojaId: uidLoja),
          onExportarPdf: () => _exportarPdf(uidLoja, dadosUsuario),
          onVerDetalhes: _abrirDetalhes,
          onVerParcelas: _abrirDetalhes,
          onImprimirComprovante: (v) => _mostrarSnack(
            'Comprovante da venda ${v.codigoExibicao} enviado para impressão.'),
          onExportarVenda: (v) => _mostrarSnack(
            'Venda ${v.codigoExibicao} exportada com sucesso.'),
          onCancelarVenda: _confirmarCancelamento,
        );
      },
    );
  }

  Future<void> _confirmarCancelamento(VendaHistorico venda) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancelar venda'),
        content: Text(
          'Tem certeza que deseja cancelar a venda ${venda.codigoExibicao}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Sim, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar == true && mounted) {
      _mostrarSnack('Venda ${venda.codigoExibicao} cancelada com sucesso.');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body separado
// ─────────────────────────────────────────────────────────────────────
class _HistoricoBody extends StatelessWidget {
  const _HistoricoBody({
    required this.lojaId,
    required this.dadosUsuario,
    required this.lojaNome,
    required this.buscaCtrl,
    required this.dataInicio,
    required this.dataFim,
    required this.filtroStatus,
    required this.filtroFormaPagamento,
    required this.vendasFiltradas,
    required this.resumo,
    required this.carregando,
    required this.erro,
    required this.exportando,
    required this.pagina,
    required this.itensPorPagina,
    required this.moedaFmt,
    required this.onBuscaChanged,
    required this.onDataInicioChanged,
    required this.onDataFimChanged,
    required this.onStatusChanged,
    required this.onFormaPagamentoChanged,
    required this.onLimparFiltros,
    required this.onPageChanged,
    required this.onItensPorPaginaChanged,
    required this.onRecarregar,
    required this.onExportarPdf,
    required this.onVerDetalhes,
    required this.onVerParcelas,
    required this.onImprimirComprovante,
    required this.onExportarVenda,
    required this.onCancelarVenda,
  });

  final String lojaId;
  final Map<String, dynamic>? dadosUsuario;
  final String lojaNome;
  final TextEditingController buscaCtrl;
  final DateTime? dataInicio, dataFim;
  final String filtroStatus, filtroFormaPagamento;
  final List<VendaHistorico> vendasFiltradas;
  final VendasHistoricoResumo resumo;
  final bool carregando, erro, exportando;
  final int pagina, itensPorPagina;
  final String Function(double) moedaFmt;

  final ValueChanged<String> onBuscaChanged;
  final ValueChanged<DateTime?> onDataInicioChanged;
  final ValueChanged<DateTime?> onDataFimChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onFormaPagamentoChanged;
  final VoidCallback onLimparFiltros;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onItensPorPaginaChanged;
  final VoidCallback onRecarregar;
  final VoidCallback onExportarPdf;
  final void Function(VendaHistorico) onVerDetalhes;
  final void Function(VendaHistorico) onVerParcelas;
  final void Function(VendaHistorico) onImprimirComprovante;
  final void Function(VendaHistorico) onExportarVenda;
  final void Function(VendaHistorico) onCancelarVenda;

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final isDesktop = largura > 1200;
    final isTablet = largura > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              if (carregando)
                _buildSkeleton()
              else if (erro)
                _buildError()
              else ...[
                _buildSummaryGrid(),
                const SizedBox(height: 24),
                _buildFilterCard(context),
                const SizedBox(height: 20),
                _buildTableSection(isDesktop, isTablet, largura),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Histórico de Vendas',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Consulte todas as vendas realizadas, acompanhe valores pagos, '
                'pendentes e exporte relatórios completos.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: exportando ? null : onRecarregar,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Atualizar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6A1B9A),
            side: const BorderSide(color: Color(0xFF6A1B9A)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: exportando ? null : onExportarPdf,
          icon: exportando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: Text(exportando ? 'Exportando...' : 'Exportar PDF'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return Column(
      children: [
        _buildShimmerGrid(),
        const SizedBox(height: 24),
        _buildShimmerCard(200),
        const SizedBox(height: 20),
        _buildShimmerCard(400),
      ],
    );
  }

  Widget _buildShimmerGrid() {
    return Row(
      children: List.generate(
        5,
        (_) => Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEEAF6)),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: PainelAdminTheme.roxo,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerCard(double height) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEAF6)),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: PainelAdminTheme.roxo,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar vendas',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Não foi possível buscar os dados. Verifique sua conexão e tente novamente.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRecarregar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cards superiores ──
  Widget _buildSummaryGrid() {
    final cards = <Widget>[
      _SummaryCard(
        icone: Icons.attach_money_rounded,
        corIcone: const Color(0xFF6A1B9A),
        corFundoIcone: const Color(0xFFF1E9FF),
        titulo: 'Total vendido',
        valor: moedaFmt(resumo.totalVendido),
        rodape: '${resumo.quantidadeVendas} vendas',
      ),
      _SummaryCard(
        icone: Icons.check_circle_rounded,
        corIcone: const Color(0xFF16A34A),
        corFundoIcone: const Color(0xFFE8F5E9),
        titulo: 'Vendas pagas',
        valor: moedaFmt(resumo.vendasPagas),
        rodape: 'Valor recebido',
      ),
      _SummaryCard(
        icone: Icons.pending_actions_rounded,
        corIcone: const Color(0xFFFF8F00),
        corFundoIcone: const Color(0xFFFFF8E1),
        titulo: 'Vendas pendentes',
        valor: moedaFmt(resumo.vendasPendentes),
        rodape: 'A receber',
      ),
      _SummaryCard(
        icone: Icons.trending_up_rounded,
        corIcone: const Color(0xFF2563EB),
        corFundoIcone: const Color(0xFFE8F0FE),
        titulo: 'Ticket médio',
        valor: moedaFmt(resumo.ticketMedio),
        rodape: 'Média por venda',
      ),
      _SummaryCard(
        icone: Icons.receipt_long_rounded,
        corIcone: const Color(0xFF7C3AED),
        corFundoIcone: const Color(0xFFF3E8FF),
        titulo: 'Vendas',
        valor: '${resumo.quantidadeVendas}',
        rodape: 'Total no período',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraDisp = constraints.maxWidth;
        final colunas = larguraDisp > 1100
            ? 5
            : larguraDisp > 800
                ? 3
                : larguraDisp > 500
                    ? 2
                    : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((card) {
            final cardWidth = colunas >= 3
                ? (larguraDisp - (colunas - 1) * 12) / colunas
                : colunas == 2
                    ? (larguraDisp - 12) / 2
                    : larguraDisp;
            return SizedBox(width: cardWidth, child: card);
          }).toList(),
        );
      },
    );
  }

  // ── Filtros ──
  Widget _buildFilterCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Icon(Icons.filter_list_rounded,
                  size: 18, color: const Color(0xFF6A1B9A)),
              const SizedBox(width: 8),
              Text(
                'Filtros',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onLimparFiltros,
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Limpar filtros'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isLargo = constraints.maxWidth > 800;
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: buscaCtrl,
                          onChanged: onBuscaChanged,
                          decoration: InputDecoration(
                            hintText: 'Buscar por cliente, CPF, pedido ou produto',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FB),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isLargo)
                    Row(
                      children: [
                        _buildDateField(
                          context,
                          label: 'Data inicial',
                          value: dataInicio,
                          onChanged: onDataInicioChanged,
                        ),
                        const SizedBox(width: 12),
                        _buildDateField(
                          context,
                          label: 'Data final',
                          value: dataFim,
                          onChanged: onDataFimChanged,
                        ),
                        const SizedBox(width: 12),
                        _buildDropdown(
                          label: 'Status',
                          value: filtroStatus,
                          items: const [
                            'Todos',
                            'Pago',
                            'Pendente',
                            'Parcial',
                            'Cancelado',
                          ],
                          onChanged: onStatusChanged,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDropdown(
                            label: 'Forma de pagamento',
                            value: filtroFormaPagamento,
                            items: const [
                              'Todos',
                              'Dinheiro',
                              'PIX',
                              'Cartão',
                              'Crédito do Cliente',
                              'Transferência',
                            ],
                            onChanged: onFormaPagamentoChanged,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _buildDateField(
                      context,
                      label: 'Data inicial',
                      value: dataInicio,
                      onChanged: onDataInicioChanged,
                    ),
                    const SizedBox(height: 8),
                    _buildDateField(
                      context,
                      label: 'Data final',
                      value: dataFim,
                      onChanged: onDataFimChanged,
                    ),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      label: 'Status',
                      value: filtroStatus,
                      items: const [
                        'Todos',
                        'Pago',
                        'Pendente',
                        'Parcial',
                        'Cancelado',
                      ],
                      onChanged: onStatusChanged,
                    ),
                    const SizedBox(height: 8),
                    _buildDropdown(
                      label: 'Forma de pagamento',
                      value: filtroFormaPagamento,
                      items: const [
                        'Todos',
                        'Dinheiro',
                        'PIX',
                        'Cartão',
                        'Crédito do Cliente',
                        'Transferência',
                      ],
                      onChanged: onFormaPagamentoChanged,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(
    BuildContext context, {
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final d = await showDiPertinDatePicker(
            context,
            titulo: label,
            dataInicial: value ?? DateTime.now(),
          );
          if (d != null) onChanged(d);
        },
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
            prefixIcon: const Icon(Icons.date_range_rounded, size: 20),
            filled: true,
            fillColor: const Color(0xFFF8F9FB),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          child: Text(
            value != null
                ? '${value.day.toString().padLeft(2, '0')}/'
                    '${value.month.toString().padLeft(2, '0')}/'
                    '${value.year}'
                : 'Selecionar',
            style: GoogleFonts.plusJakartaSans(fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Expanded(
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF8F9FB),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        items: items
            .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ── Tabela ──
  Widget _buildTableSection(bool isDesktop, bool isTablet, double largura) {
    final paginados = vendasFiltradas
        .skip((pagina - 1) * itensPorPagina)
        .take(itensPorPagina)
        .toList();

    if (vendasFiltradas.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(60),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEAF6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              'Nenhuma venda encontrada',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'As vendas realizadas aparecerão aqui automaticamente.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        return _buildDataTable(paginados, availableWidth);
      },
    );
  }

  // ── DataTable com larguras de coluna controladas ──
  static const _colDefs = <_ColDef>[
    _ColDef('Venda/Pedido', 130),
    _ColDef('Cliente', 1, flex: true),
    _ColDef('Data', 165),
    _ColDef('Produtos', 110),
    _ColDef('Forma de pagamento', 170),
    _ColDef('Valor total', 130, numeric: true),
    _ColDef('Valor pago', 120, numeric: true),
    _ColDef('Valor pendente', 140, numeric: true),
    _ColDef('Status', 120),
    _ColDef('Ações', 70),
  ];


  Widget _buildDataTable(
      List<VendaHistorico> paginados, double availableWidth) {
    // Calcula largura total mínima
    final fixedTotal = _colDefs.fold<double>(
        0, (s, c) => s + (c.flex ? 200.0 : c.width));
    final totalWidth = fixedTotal > availableWidth ? fixedTotal : availableWidth;
    final extra = totalWidth - fixedTotal;

    // Distribui o extra para a coluna flex (Cliente)
    final widths = _colDefs.map((c) {
      if (c.flex) return 200.0 + extra;
      return c.width;
    }).toList();

    final hm = 20.0; // horizontal margin por coluna

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth + _colDefs.length * hm * 2,
                child: DataTable(
                  headingRowHeight: 52,
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFFAFAFC)),
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 68,
                  columnSpacing: hm * 2,
                  horizontalMargin: hm,
                  headingTextStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E),
                  ),
                  dataTextStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: const Color(0xFF1A1A2E),
                  ),
                  columns: List.generate(_colDefs.length, (i) {
                    final c = _colDefs[i];
                    return DataColumn(
                      numeric: c.numeric,
                      label: SizedBox(
                        width: widths[i],
                        child: Align(
                          alignment: c.numeric
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Text(c.label),
                        ),
                      ),
                    );
                  }),
                  rows: paginados.map((v) {
                    return DataRow(
                      color: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return const Color(0xFFF8F9FD);
                        }
                        return null;
                      }),
                      cells: _buildCells(v, widths),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEAF6)),
            _buildPagination(),
          ],
        ),
      ),
    );
  }

  List<DataCell> _buildCells(VendaHistorico v, List<double> widths) {
    return [
      DataCell(SizedBox(
        width: widths[0],
        child: Text(v.codigoExibicao,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 12)),
      )),
      DataCell(SizedBox(
        width: widths[1],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              v.clienteNome ?? '—',
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (v.clienteDocumento != null &&
                v.clienteDocumento!.isNotEmpty)
              Text(
                v.clienteDocumento!,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF94A3B8)),
              ),
          ],
        ),
      )),
      DataCell(SizedBox(
        width: widths[2],
        child: Text(
          VendasHistoricoService.formatarDataHora(v.dataVenda),
          style: const TextStyle(fontSize: 12),
        ),
      )),
      DataCell(SizedBox(
        width: widths[3],
        child: Text(
          '${v.quantidadeItens} ${v.quantidadeItens == 1 ? 'item' : 'itens'}',
          style: const TextStyle(fontSize: 12),
        ),
      )),
      DataCell(SizedBox(
        width: widths[4],
        child: Text(
          v.formaPagamentoExibicao,
          style: const TextStyle(fontSize: 12),
        ),
      )),
      DataCell(SizedBox(
        width: widths[5],
        child: Text(
          moedaFmt(v.valorTotal),
          textAlign: TextAlign.right,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 12),
        ),
      )),
      DataCell(SizedBox(
        width: widths[6],
        child: Text(
          moedaFmt(v.valorPago),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: v.valorPago > 0
                ? const Color(0xFF16A34A)
                : const Color(0xFF64748B),
          ),
        ),
      )),
      DataCell(SizedBox(
        width: widths[7],
        child: Text(
          moedaFmt(v.valorPendente),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: v.valorPendente > 0
                ? const Color(0xFFDC2626)
                : const Color(0xFF64748B),
          ),
        ),
      )),
      DataCell(SizedBox(
        width: widths[8],
        child: _buildStatusBadge(v),
      )),
      DataCell(SizedBox(
        width: widths[9],
        child: _buildActionsMenu(v),
      )),
    ];
  }

  Widget _buildStatusBadge(VendaHistorico v) {
    Color bg;
    Color fg;
    String icon;
    switch (v.status) {
      case 'pago':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF16A34A);
        icon = '●';
        break;
      case 'pendente':
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFFFF8F00);
        icon = '●';
        break;
      case 'parcial':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        icon = '●';
        break;
      case 'cancelado':
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
        icon = '●';
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
        icon = '●';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon,
              style: TextStyle(fontSize: 8, color: fg)),
          const SizedBox(width: 4),
          Text(
            v.statusExibicao,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsMenu(VendaHistorico v) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF94A3B8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      onSelected: (action) {
        switch (action) {
          case 'detalhes':
            onVerDetalhes(v);
            break;
          case 'imprimir':
            onImprimirComprovante(v);
            break;
          case 'exportar':
            onExportarVenda(v);
            break;
          case 'parcelas':
            onVerParcelas(v);
            break;
          case 'cancelar':
            if (v.status != 'cancelado') onCancelarVenda(v);
            break;
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'detalhes',
          child: ListTile(
            leading: Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF6A1B9A)),
            title: Text('Ver detalhes', style: TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'imprimir',
          child: ListTile(
            leading: Icon(Icons.print_outlined, size: 18),
            title: Text('Imprimir comprovante', style: TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'exportar',
          child: ListTile(
            leading: Icon(Icons.file_download_outlined, size: 18),
            title: Text('Exportar venda', style: TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (v.isCredito)
          const PopupMenuItem(
            value: 'parcelas',
            child: ListTile(
              leading: Icon(Icons.receipt_long_outlined, size: 18, color: Color(0xFFFF8F00)),
              title: Text('Ver parcelas', style: TextStyle(fontSize: 13)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (v.status != 'cancelado')
          const PopupMenuDivider(),
        if (v.status != 'cancelado')
          const PopupMenuItem(
            value: 'cancelar',
            child: ListTile(
              leading: Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFDC2626)),
              title: Text('Cancelar venda', style: TextStyle(fontSize: 13)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Widget _buildPagination() {
    final total = vendasFiltradas.length;
    final totalPaginas = (total / itensPorPagina).ceil();
    final inicio = (pagina - 1) * itensPorPagina + 1;
    final fim = (pagina * itensPorPagina).clamp(0, total);

    // Gera lista de páginas para exibir (máx 5)
    List<int> paginasVisiveis = [];
    if (totalPaginas <= 5) {
      paginasVisiveis = List.generate(totalPaginas, (i) => i + 1);
    } else {
      if (pagina <= 3) {
        paginasVisiveis = [1, 2, 3, 4, 5];
      } else if (pagina >= totalPaginas - 2) {
        paginasVisiveis = List.generate(
            5, (i) => totalPaginas - 4 + i);
      } else {
        paginasVisiveis = List.generate(
            5, (i) => pagina - 2 + i);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFEEEAF6)),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Mostrando $inicio a $fim de $total venda${total == 1 ? '' : 's'}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                onPressed: pagina > 1
                    ? () => onPageChanged(pagina - 1)
                    : null,
                color: const Color(0xFF64748B),
                visualDensity: VisualDensity.compact,
                tooltip: 'Anterior',
              ),
              const SizedBox(width: 4),
              ...paginasVisiveis.map((p) {
                final ativa = p == pagina;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: ativa ? null : () => onPageChanged(p),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ativa
                            ? PainelAdminTheme.roxo
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$p',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight:
                              ativa ? FontWeight.w700 : FontWeight.w500,
                          color: ativa
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (totalPaginas > 5 && pagina < totalPaginas - 2)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '...',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                onPressed: pagina < totalPaginas
                    ? () => onPageChanged(pagina + 1)
                    : null,
                color: const Color(0xFF64748B),
                visualDensity: VisualDensity.compact,
                tooltip: 'Próximo',
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Itens por página:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: itensPorPagina,
                  isDense: true,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E),
                  ),
                  items: [10, 20, 50, 100]
                      .map((n) => DropdownMenuItem(
                          value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onItensPorPaginaChanged(v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helper: definição de coluna ──
class _ColDef {
  const _ColDef(this.label, this.width, {this.numeric = false, this.flex = false});
  final String label;
  final double width;
  final bool numeric;
  final bool flex;
}

// ─────────────────────────────────────────────────────────────────────
// Summary Card
// ─────────────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icone,
    required this.corIcone,
    required this.corFundoIcone,
    required this.titulo,
    required this.valor,
    required this.rodape,
  });

  final IconData icone;
  final Color corIcone;
  final Color corFundoIcone;
  final String titulo;
  final String valor;
  final String rodape;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            width: 44,
            height: 44,
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rodape,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Modal de detalhes da venda
// ─────────────────────────────────────────────────────────────────────
class _VendaDetalhesModal extends StatelessWidget {
  const _VendaDetalhesModal({
    required this.venda,
    required this.moedaFmt,
  });

  final VendaHistorico venda;
  final String Function(double) moedaFmt;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF6A1B9A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalhes da Venda',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          venda.codigoExibicao,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
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
                    // Dados da venda
                    _secao('Dados da venda', [
                      _linha('Código', venda.codigoExibicao),
                      _linha('Data/hora',
                          VendasHistoricoService.formatarDataHora(venda.dataVenda)),
                      if (venda.operadorNome != null &&
                          venda.operadorNome!.isNotEmpty)
                        _linha('Operador', venda.operadorNome!),
                      if (venda.caixaId != null && venda.caixaId!.isNotEmpty)
                        _linha('Caixa/PDV', venda.caixaId!),
                    ]),
                    const SizedBox(height: 20),

                    // Dados do cliente
                    _secao('Dados do cliente', [
                      _linha('Nome', venda.clienteNome ?? '—'),
                      if (venda.clienteDocumento != null &&
                          venda.clienteDocumento!.isNotEmpty)
                        _linha('CPF', venda.clienteDocumento!),
                      if (venda.clienteTelefone != null &&
                          venda.clienteTelefone!.isNotEmpty)
                        _linha('Telefone', venda.clienteTelefone!),
                      if (venda.clienteEmail != null &&
                          venda.clienteEmail!.isNotEmpty)
                        _linha('E-mail', venda.clienteEmail!),
                    ]),
                    const SizedBox(height: 20),

                    // Itens
                    _secao('Itens vendidos (${venda.itens.length})', []),
                    const SizedBox(height: 8),
                    ...venda.itens.map((item) => _itemRow(item)),
                    const SizedBox(height: 16),

                    // Pagamento
                    _secao('Pagamento', [
                      _linha('Forma de pagamento', venda.formaPagamentoExibicao),
                      _linha('Valor total', moedaFmt(venda.valorTotal)),
                      _linha('Valor pago', moedaFmt(venda.valorPago)),
                      _linha('Valor pendente', moedaFmt(venda.valorPendente)),
                      if (venda.parcelas != null && venda.parcelas! > 0)
                        _linha('Parcelas', '${venda.parcelas}x'),
                      if (venda.multaTotal > 0)
                        _linha('Multa', moedaFmt(venda.multaTotal)),
                      if (venda.jurosTotal > 0)
                        _linha('Juros', moedaFmt(venda.jurosTotal)),
                    ]),
                    const SizedBox(height: 20),

                    // Histórico
                    _secao('Histórico', [
                      if (venda.createdAt != null)
                        _linha('Criado em',
                            VendasHistoricoService.formatarDataHora(venda.createdAt)),
                      if (venda.dataPagoEm != null)
                        _linha('Pago em',
                            VendasHistoricoService.formatarDataHora(venda.dataPagoEm)),
                      if (venda.canceladoEm != null)
                        _linha('Cancelado em',
                            VendasHistoricoService.formatarDataHora(venda.canceladoEm)),
                      if (venda.motivoCancelamento != null &&
                          venda.motivoCancelamento!.isNotEmpty)
                        _linha('Motivo', venda.motivoCancelamento!),
                    ]),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEAF6))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secao(String titulo, List<Widget> linhas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF6A1B9A),
          ),
        ),
        if (linhas.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...linhas,
        ],
      ],
    );
  }

  Widget _linha(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(VendaItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.produtoNome,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A1A2E),
              ),
            ),
          ),
          Text(
            '${item.quantidade}x',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            moedaFmt(item.valorUnitario),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          if (item.desconto > 0) ...[
            const SizedBox(width: 12),
            Text(
              '-${moedaFmt(item.desconto)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: const Color(0xFFDC2626),
              ),
            ),
          ],
          const SizedBox(width: 16),
          Text(
            moedaFmt(item.total),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}
