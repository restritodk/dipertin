import 'dart:async';

import 'package:depertin_web/models/comercial_pendencia_data.dart';
import 'package:depertin_web/services/comercial_config_service.dart';
import 'package:depertin_web/services/comercial_pendencias_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/comercial/comercial_acoes_rapidas_modals.dart';
import 'package:depertin_web/widgets/comercial/comercial_debt_chart_card.dart';
import 'package:depertin_web/widgets/comercial/comercial_enviar_comunicacao_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_financial_filters.dart';
import 'package:depertin_web/widgets/comercial/comercial_financial_summary_card.dart';
import 'package:depertin_web/widgets/comercial/comercial_financial_table.dart';
import 'package:depertin_web/widgets/comercial/comercial_quick_actions_card.dart';
import 'package:depertin_web/widgets/comercial/comercial_todas_pendencias_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_top_debtors_card.dart';
import 'package:depertin_web/widgets/comercial_cliente_recebimento_modal.dart';
import 'package:depertin_web/widgets/comercial/comercial_renegociar_divida_modal.dart';
import 'package:depertin_web/widgets/dipertin_feedback_premium_modal.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela SaaS de Pendência Financeira — Gestão Comercial.
///
/// Exibe parcelas AGRUPADAS por cliente.
/// "Receber pagamento" reusa o modal de recebimento da tela Crédito de Cliente.
class ComercialPendenciasScreen extends StatefulWidget {
  const ComercialPendenciasScreen({super.key});

  @override
  State<ComercialPendenciasScreen> createState() =>
      _ComercialPendenciasScreenState();
}

class _ComercialPendenciasScreenState extends State<ComercialPendenciasScreen> {
  final _buscaCtrl = TextEditingController();
  final _moedaFmt = ComercialPendenciasService.formatarMoeda;

  String _filtroStatus = 'Todos';
  String _filtroVencimento = 'Todos';
  int _pagina = 1;
  int _itensPorPagina = 10;

  PendenciaFinanceiraResumo _resumo = PendenciaFinanceiraResumo.vazio;

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  List<PendenciaFinanceiraCliente> get _itensFiltrados {
    var lista = _resumo.itens;
    final q = _buscaCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      lista = lista.where((i) {
        return i.clienteNome.toLowerCase().contains(q) ||
            i.codigoVenda.toLowerCase().contains(q);
      }).toList();
    }
    if (_filtroStatus != 'Todos') {
      lista = lista.where((i) {
        switch (_filtroStatus) {
          case 'Vencido':
            return i.status == 'vencido';
          case 'Vence hoje':
            return i.status == 'vence_hoje';
          case 'Vence em breve':
            return i.status == 'vence_em_breve';
          case 'Em dia':
            return i.status == 'em_dia';
          default:
            return true;
        }
      }).toList();
    }
    if (_filtroVencimento != 'Todos') {
      final hoje = DateTime.now();
      final hojeClean = DateTime(hoje.year, hoje.month, hoje.day);
      lista = lista.where((i) {
        final venc = DateTime(
          i.dataVencimentoReferencia.year,
          i.dataVencimentoReferencia.month,
          i.dataVencimentoReferencia.day,
        );
        switch (_filtroVencimento) {
          case 'Vencidos':
            return venc.isBefore(hojeClean) && i.valorTotalEmAberto > 0.009;
          case 'Vence hoje':
            return venc.isAtSameMomentAs(hojeClean);
          case 'Próximos 7 dias':
            final lim = hojeClean.add(const Duration(days: 7));
            return venc.isAfter(hojeClean) &&
                (venc.isBefore(lim) || venc.isAtSameMomentAs(lim));
          case 'Próximos 30 dias':
            final lim = hojeClean.add(const Duration(days: 30));
            return venc.isAfter(hojeClean) &&
                (venc.isBefore(lim) || venc.isAtSameMomentAs(lim));
          default:
            return true;
        }
      }).toList();
    }
    return lista;
  }

  void _limparFiltros() {
    setState(() {
      _buscaCtrl.clear();
      _filtroStatus = 'Todos';
      _filtroVencimento = 'Todos';
      _pagina = 1;
    });
  }

  Future<void> _excluir(PendenciaFinanceiraCliente item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir lançamento'),
        content: Text(
          'Tem certeza que deseja excluir as pendências de ${item.clienteNome}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar == true && mounted) {
      await mostrarDiPertinFeedbackPremium(
        context,
        sucesso: true,
        titulo: 'Lançamento excluído',
        mensagem: 'O lançamento foi excluído com sucesso.',
      );
    }
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

        final lojaNome = (dadosUsuario?['loja_nome'] ??
                dadosUsuario?['nome'] ??
                dadosUsuario?['nome_loja'] ??
                'Loja')
            .toString();

        return _PendenciasBody(
          lojaId: uidLoja,
          lojaNome: lojaNome,
          buscaCtrl: _buscaCtrl,
          filtroStatus: _filtroStatus,
          filtroVencimento: _filtroVencimento,
          pagina: _pagina,
          itensPorPagina: _itensPorPagina,
          resumo: _resumo,
          itensFiltrados: _itensFiltrados,
          moedaFmt: _moedaFmt,
          onBuscaChanged: (_) => setState(() => _pagina = 1),
          onStatusChanged: (v) => setState(() {
            _filtroStatus = v ?? 'Todos';
            _pagina = 1;
          }),
          onVencimentoChanged: (v) => setState(() {
            _filtroVencimento = v ?? 'Todos';
            _pagina = 1;
          }),
          onLimparFiltros: _limparFiltros,
          onPageChanged: (v) => setState(() => _pagina = v),
          onItensPorPaginaChanged: (v) => setState(() {
            _itensPorPagina = v;
            _pagina = 1;
          }),
          onResumoLoaded: (r) {
            if (mounted) setState(() => _resumo = r);
          },
          onActionExcluir: (item) => _excluir(item),
        );
      },
    );
  }
}

/// Body separado para evitar rebuilds desnecessários do LojistaUidLojaBuilder.
class _PendenciasBody extends StatefulWidget {
  const _PendenciasBody({
    required this.lojaId,
    required this.lojaNome,
    required this.buscaCtrl,
    required this.filtroStatus,
    required this.filtroVencimento,
    required this.pagina,
    required this.itensPorPagina,
    required this.resumo,
    required this.itensFiltrados,
    required this.moedaFmt,
    required this.onBuscaChanged,
    required this.onStatusChanged,
    required this.onVencimentoChanged,
    required this.onLimparFiltros,
    required this.onPageChanged,
    required this.onItensPorPaginaChanged,
    required this.onResumoLoaded,
    required this.onActionExcluir,
  });

  final String lojaId;
  final String lojaNome;
  final TextEditingController buscaCtrl;
  final String filtroStatus, filtroVencimento;
  final int pagina, itensPorPagina;
  final PendenciaFinanceiraResumo resumo;
  final List<PendenciaFinanceiraCliente> itensFiltrados;
  final String Function(double) moedaFmt;
  final ValueChanged<String> onBuscaChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onVencimentoChanged;
  final VoidCallback onLimparFiltros;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onItensPorPaginaChanged;
  final void Function(PendenciaFinanceiraResumo) onResumoLoaded;
  final void Function(PendenciaFinanceiraCliente) onActionExcluir;

  @override
  State<_PendenciasBody> createState() => _PendenciasBodyState();
}

class _PendenciasBodyState extends State<_PendenciasBody> {
  bool _carregando = true;
  StreamSubscription<PendenciaFinanceiraResumo>? _resumoSub;

  @override
  void initState() {
    super.initState();
    _iniciarStream();
  }

  @override
  void didUpdateWidget(_PendenciasBody old) {
    super.didUpdateWidget(old);
    if (old.lojaId != widget.lojaId) {
      _resumoSub?.cancel();
      setState(() => _carregando = true);
      _iniciarStream();
    }
  }

  @override
  void dispose() {
    _resumoSub?.cancel();
    super.dispose();
  }

  void _iniciarStream() {
    _resumoSub?.cancel();
    _resumoSub = ComercialPendenciasService
        .streamResumo(widget.lojaId)
        .listen((r) {
      if (!mounted) return;
      widget.onResumoLoaded(r);
      setState(() => _carregando = false);
    });
  }

  Future<void> _receberPagamento(PendenciaFinanceiraCliente item) async {
    final config =
        await ComercialConfigService.carregarJurosMultaConfig(widget.lojaId);
    if (!mounted) return;
    await mostrarComercialClienteRecebimentoModal(
      context,
      lojaId: widget.lojaId,
      cliente: item.toComercialCliente(),
      lojaNome: widget.lojaNome,
      configJurosMulta: config,
    );
    // O stream escuta mudanças nas parcelas, então ao pagar (ou ao criar nova
    // venda no PDV) os dados serão refletidos automaticamente sem recarregar.
  }

  Future<void> _negociarDivida(PendenciaFinanceiraCliente item) async {
    if (item.parcelas.isEmpty) return;
    final config =
        await ComercialConfigService.carregarJurosMultaConfig(widget.lojaId);
    if (!mounted) return;
    await mostrarRenegociarDividaModal(
      context,
      lojaId: widget.lojaId,
      divida: item,
      parcelas: item.parcelas,
      configJuros: config,
    );
  }

  Future<void> _enviarCobranca(PendenciaFinanceiraCliente item) async {
    await abrirModalEnviarComunicacao(
      context: context,
      lojaId: widget.lojaId,
      tipo: 'cobranca',
      clienteId: item.clienteId,
      clienteNome: item.clienteNome,
      clienteTelefone: item.clienteTelefone,
      valorExtra: item.valorTotalEmAberto,
      dataExtra: item.dataVencimentoReferencia,
    );
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final isDesktop = largura > 1200;

    final resumo = widget.resumo;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),

              if (_carregando)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(60),
                    child: CircularProgressIndicator(
                      color: PainelAdminTheme.roxo,
                    ),
                  ),
                )
              else ...[
                _buildSummaryGrid(resumo),
                const SizedBox(height: 24),

                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: _buildMainContent(resumo),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 320,
                        child: _buildSidebar(resumo),
                      ),
                    ],
                  )
                else ...[
                  _buildMainContent(resumo),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pendência Financeira',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Acompanhe todos os valores em aberto, vencidos ou próximos do vencimento dos clientes.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryGrid(PendenciaFinanceiraResumo r) {
    final cards = <Widget>[
      FinancialSummaryCard(
        icone: Icons.warning_rounded,
        corIcone: const Color(0xFFDC2626),
        corFundoIcone: const Color(0xFFFEF2F2),
        titulo: 'Vencidas',
        valor: widget.moedaFmt(r.totalVencidas),
        rodape: '${r.quantidadeVencidas} cobranças',
      ),
      FinancialSummaryCard(
        icone: Icons.schedule_rounded,
        corIcone: const Color(0xFFFF8F00),
        corFundoIcone: const Color(0xFFFFF8E1),
        titulo: 'A vencer hoje',
        valor: widget.moedaFmt(r.totalVenceHoje),
        rodape: '${r.quantidadeVenceHoje} cobranças',
      ),
      FinancialSummaryCard(
        icone: Icons.date_range_rounded,
        corIcone: const Color(0xFFCA8A04),
        corFundoIcone: const Color(0xFFFFFBEB),
        titulo: 'Vencendo em 7 dias',
        valor: widget.moedaFmt(r.totalVence7Dias),
        rodape: '${r.quantidadeVence7Dias} cobranças',
      ),
      FinancialSummaryCard(
        icone: Icons.account_balance_wallet_rounded,
        corIcone: const Color(0xFF6A1B9A),
        corFundoIcone: const Color(0xFFF1E9FF),
        titulo: 'Total em aberto',
        valor: widget.moedaFmt(r.totalEmAberto),
        rodape: '${r.quantidadeEmAberto} cobranças',
      ),
      FinancialSummaryCard(
        icone: Icons.trending_up_rounded,
        corIcone: const Color(0xFF16A34A),
        corFundoIcone: const Color(0xFFE8F5E9),
        titulo: 'Total pago (mês)',
        valor: widget.moedaFmt(r.totalPagoMes),
        rodape: 'vs mês passado',
        variacao:
            ComercialPendenciasService.formatarPercentual(r.variacaoPagoMes),
        variacaoPositiva: r.variacaoPagoMes >= 0,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraDisponivel = constraints.maxWidth;
        final colunas = larguraDisponivel > 900
            ? 3
            : larguraDisponivel > 600
                ? 2
                : 1;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((card) {
            final cardWidth = colunas == 3
                ? (larguraDisponivel - 32) / 3
                : colunas == 2
                    ? (larguraDisponivel - 16) / 2
                    : larguraDisponivel;
            return SizedBox(width: cardWidth, child: card);
          }).toList(),
        );
      },
    );
  }

  Widget _buildMainContent(PendenciaFinanceiraResumo r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinancialFilters(
          buscaController: widget.buscaCtrl,
          filtroStatus: widget.filtroStatus,
          filtroPlano: 'Todos',
          filtroVencimento: widget.filtroVencimento,
          onBuscaChanged: (v) => widget.onBuscaChanged(v),
          onStatusChanged: widget.onStatusChanged,
          onVencimentoChanged: widget.onVencimentoChanged,
          onLimpar: widget.onLimparFiltros,
        ),
        const SizedBox(height: 20),
        FinancialTable(
          itens: widget.itensFiltrados,
          pagina: widget.pagina,
          itensPorPagina: widget.itensPorPagina,
          totalItens: widget.itensFiltrados.length,
          onPageChanged: widget.onPageChanged,
          onItensPorPaginaChanged: widget.onItensPorPaginaChanged,
          onActionReceber: _receberPagamento,
          onActionEnviarCobranca: _enviarCobranca,
          onActionNegociar: _negociarDivida,
          onActionExcluir: widget.onActionExcluir,
        ),
      ],
    );
  }

  Widget _buildSidebar(PendenciaFinanceiraResumo r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DebtChartCard(
          vencidas: r.totalVencidas,
          venceHoje: r.totalVenceHoje,
          vence7Dias: r.totalVence7Dias,
          totalEmAberto: r.totalEmAberto,
        ),
        const SizedBox(height: 16),
        QuickActionsCard(
          onEnviarLembretes: () => abrirModalEnviarLembretes(
            context: context,
            lojaId: widget.lojaId,
            itens: r.itens,
          ),
          onGerarCobrancas: () => abrirModalGerarCobrancas(
            context: context,
            lojaId: widget.lojaId,
            itens: r.itens,
          ),
        ),
        const SizedBox(height: 16),
        TopDebtorsCard(
          debtors: r.topDebtors,
          onVerTodos: () => abrirModalTodasPendencias30Dias(
            context: context,
            lojaId: widget.lojaId,
            itens: r.itens,
          ),
        ),
      ],
    );
  }
}
