import 'package:depertin_web/models/comercial_dashboard_data.dart';
import 'package:depertin_web/services/comercial_dashboard_service.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:depertin_web/utils/lojista_painel_context.dart';
import 'package:depertin_web/widgets/comercial/comercial_dashboard_acoes.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Tela de Dashboard Comercial SaaS Premium para lojistas do DiPertin.
/// Desenvolvida com design de alto padrão, grids responsivos e gráficos sofisticados.
class LojistaComercialDashboardScreen extends StatefulWidget {
  const LojistaComercialDashboardScreen({super.key});

  @override
  State<LojistaComercialDashboardScreen> createState() => _LojistaComercialDashboardScreenState();
}

class _LojistaComercialDashboardScreenState extends State<LojistaComercialDashboardScreen> {
  String _periodoSelecionado = '7 dias';
  String? _lojaId;
  bool _carregando = true;
  String? _erro;
  ComercialDashboardData? _dados;

  @override
  Widget build(BuildContext context) {
    return LojistaUidLojaBuilder(
      builder: (context, authUid, uidLoja, dadosUsuario) {
        if (_lojaId != uidLoja) {
          _lojaId = uidLoja;
          WidgetsBinding.instance.addPostFrameCallback((_) => _carregar(uidLoja));
        }

        if (_carregando && _dados == null) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(child: CircularProgressIndicator(color: PainelAdminTheme.roxo)),
          );
        }

        if (_erro != null && _dados == null) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_erro!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => _carregar(uidLoja), child: const Text('Tentar novamente')),
                ],
              ),
            ),
          );
        }

        final dados = _dados ?? ComercialDashboardData.vazio();

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, dados, uidLoja),
                  const SizedBox(height: 24),
                  _buildKpiGrid(context, dados),
                  const SizedBox(height: 24),
                  _buildSalesAndCreditSection(context, dados),
                  const SizedBox(height: 24),
                  _buildClientsAndPendingSection(context, dados),
                  const SizedBox(height: 24),
                  _buildPaymentAndProductsAndInsightsSection(context, dados),
                  const SizedBox(height: 24),
                  _buildQuickActions(context, uidLoja),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _carregar(String lojaId) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await ComercialDashboardService.carregar(
        lojaId: lojaId,
        periodoGrafico: _periodoSelecionado,
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _dados = dados;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar o dashboard: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _atualizarPeriodoGrafico(String periodo, String lojaId) async {
    setState(() => _periodoSelecionado = periodo);
    await _carregar(lojaId);
  }

  String _fmtPct(double v) =>
      ComercialDashboardService.formatarPercentual(v);

  bool _pctPositivo(double v, {bool invertido = false}) =>
      invertido ? v <= 0 : v >= 0;

  // ==========================================
  // SEÇÃO: TOPO / HEADER
  // ==========================================
  Widget _buildHeader(BuildContext context, ComercialDashboardData dados, String lojaId) {
    final rotuloData = ComercialDashboardService.rotuloDataHoje(dados.atualizadoEm);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard Comercial',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E1B4B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Visão geral da sua operação comercial',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // Filtro de período e Botão Atualizar
        Row(
          children: [
            // Filtro de data
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text(
                    rotuloData,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Comparador
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Text(
                    'Comparar com: ',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    'Ontem',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Atualizar
            OutlinedButton.icon(
              onPressed: _carregando ? null : () => _carregar(lojaId),
              icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF1E1B4B)),
              label: Text(
                'Atualizar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E1B4B),
                ),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // SEÇÃO: GRID DE KPIs (6 cards horizontais)
  // ==========================================
  Widget _buildKpiGrid(BuildContext context, ComercialDashboardData dados) {
    final k = dados.kpis;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 1400 ? 6 : (constraints.maxWidth > 900 ? 3 : 2);
        final cardWidth = (constraints.maxWidth - (cols - 1) * 16) / cols;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildKpiCard(
              title: 'Vendas Hoje',
              value: ComercialDashboardService.formatarMoeda(k.vendasHoje),
              percentage: _fmtPct(k.variacaoVendas),
              vsLabel: 'vs ontem',
              icon: Icons.attach_money_rounded,
              iconColor: const Color(0xFF10B981),
              bgColor: const Color(0xFFD1FAE5),
              width: cardWidth,
              isPercentagePositive: _pctPositivo(k.variacaoVendas),
            ),
            _buildKpiCard(
              title: 'Quantidade de Vendas',
              value: '${k.qtdVendasHoje}',
              percentage: _fmtPct(k.variacaoQtd),
              vsLabel: 'vs ontem',
              icon: Icons.shopping_cart_rounded,
              iconColor: const Color(0xFF3B82F6),
              bgColor: const Color(0xFFDBEAFE),
              width: cardWidth,
              isPercentagePositive: _pctPositivo(k.variacaoQtd),
            ),
            _buildKpiCard(
              title: 'Clientes Ativos',
              value: '${k.clientesAtivos}',
              percentage: _fmtPct(k.variacaoClientes),
              vsLabel: 'vs mês ant.',
              icon: Icons.people_alt_rounded,
              iconColor: const Color(0xFF8B5CF6),
              bgColor: const Color(0xFFEDE9FE),
              width: cardWidth,
              isPercentagePositive: _pctPositivo(k.variacaoClientes),
            ),
            _buildKpiCard(
              title: 'Crédito Utilizado',
              value: ComercialDashboardService.formatarMoeda(k.creditoUtilizado),
              percentage: _fmtPct(k.variacaoCredito),
              vsLabel: 'vs ontem',
              icon: Icons.credit_card_rounded,
              iconColor: const Color(0xFFF59E0B),
              bgColor: const Color(0xFFFEF3C7),
              width: cardWidth,
              isPercentagePositive: _pctPositivo(k.variacaoCredito),
            ),
            _buildKpiCard(
              title: 'Pendências em Aberto',
              value: ComercialDashboardService.formatarMoeda(k.pendenciasAberto),
              percentage: _fmtPct(k.variacaoPendencias),
              isPercentagePositive: _pctPositivo(k.variacaoPendencias, invertido: true),
              vsLabel: 'vs ontem',
              icon: Icons.warning_amber_rounded,
              iconColor: const Color(0xFFEF4444),
              bgColor: const Color(0xFFFEE2E2),
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Ticket Médio',
              value: ComercialDashboardService.formatarMoeda(k.ticketMedioHoje),
              percentage: _fmtPct(k.variacaoTicket),
              vsLabel: 'vs ontem',
              icon: Icons.analytics_rounded,
              iconColor: const Color(0xFF06B6D4),
              bgColor: const Color(0xFFCFFAFE),
              width: cardWidth,
              isPercentagePositive: _pctPositivo(k.variacaoTicket),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String percentage,
    required String vsLabel,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required double width,
    bool isPercentagePositive = true,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // Ícone em bolha colorida
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          // Valores
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E1B4B),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isPercentagePositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 14,
                      color: isPercentagePositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      percentage,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPercentagePositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      vsLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                      ),
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

  // ==========================================
  // SEÇÃO: EVOLUÇÃO DAS VENDAS & RESUMO FINANCEIRO
  // ==========================================
  Widget _buildSalesAndCreditSection(BuildContext context, ComercialDashboardData dados) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLarge = constraints.maxWidth > 1100;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LADO ESQUERDO: Gráfico Evolução das Vendas (Flex 3 se desktop)
            Expanded(
              flex: isLarge ? 3 : 1,
              child: _buildEvolucaoVendas(context, dados),
            ),
            if (isLarge) const SizedBox(width: 24),
            // LADO DIREITO: Resumo Financeiro (Flex 2 se desktop)
            if (isLarge)
              Expanded(
                flex: 2,
                child: _buildResumoFinanceiroCredito(context, dados),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEvolucaoVendas(BuildContext context, ComercialDashboardData dados) {
    final lojaId = _lojaId ?? '';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linha de Título, Filtro do Gráfico e Períodos
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Evolução das Vendas',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E1B4B),
                      ),
                    ),
                  ],
                ),
              ),
              // Períodos (7 dias, 30 dias, 12 meses)
              Row(
                children: [
                  _buildPeriodChip('7 dias', ativo: _periodoSelecionado == '7 dias', lojaId: lojaId),
                  const SizedBox(width: 6),
                  _buildPeriodChip('30 dias', ativo: _periodoSelecionado == '30 dias', lojaId: lojaId),
                  const SizedBox(width: 6),
                  _buildPeriodChip('12 meses', ativo: _periodoSelecionado == '12 meses', lojaId: lojaId),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Legendas do Gráfico
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem('Dinheiro', const Color(0xFF10B981)),
              _buildLegendItem('PIX', const Color(0xFF3B82F6)),
              _buildLegendItem('Cartão Crédito', const Color(0xFF8B5CF6)),
              _buildLegendItem('Cartão Débito', const Color(0xFFF59E0B)),
              _buildLegendItem('Crédito Cliente', const Color(0xFFEF4444)),
            ],
          ),
          const SizedBox(height: 32),

          // Gráfico Custom Painter sofisticado
          SizedBox(
            height: 220,
            width: double.infinity,
            child: CustomPaint(
              painter: _SalesChartPainter(
                rotulos: dados.evolucaoVendas.rotulos,
                series: dados.evolucaoVendas.series,
                maxValor: dados.evolucaoVendas.maxValor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String text, {required bool ativo, required String lojaId}) {
    return InkWell(
      onTap: lojaId.isEmpty ? null : () => _atualizarPeriodoGrafico(text, lojaId),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? const Color(0xFF6A1B9A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: ativo ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildResumoFinanceiroCredito(BuildContext context, ComercialDashboardData dados) {
    final c = dados.resumoCredito;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumo Financeiro - Crédito dos Clientes',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 24),
          // Grid 2x3 para métricas de crédito
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.4,
            children: [
              _buildCreditSubCard('Limite Total Concedido', ComercialDashboardService.formatarMoeda(c.limiteTotal), Icons.wallet_rounded, const Color(0xFF3B82F6), const Color(0xFFDBEAFE)),
              _buildCreditSubCard('Crédito Utilizado', ComercialDashboardService.formatarMoeda(c.creditoUtilizado), Icons.credit_card_rounded, const Color(0xFFF59E0B), const Color(0xFFFEF3C7)),
              _buildCreditSubCard('Crédito Disponível', ComercialDashboardService.formatarMoeda(c.creditoDisponivel), Icons.check_circle_outline_rounded, const Color(0xFF10B981), const Color(0xFFD1FAE5)),
              _buildCreditSubCard('Clientes com Crédito', '${c.clientesComCredito}', Icons.people_outline_rounded, const Color(0xFF8B5CF6), const Color(0xFFEDE9FE)),
              _buildCreditSubCard('Clientes Inadimplentes', '${c.clientesInadimplentes}', Icons.person_remove_outlined, const Color(0xFFEF4444), const Color(0xFFFEE2E2)),
              _buildCreditSubCard('Valor em Atraso', ComercialDashboardService.formatarMoeda(c.valorEmAtraso), Icons.money_off_rounded, const Color(0xFFEF4444), const Color(0xFFFEE2E2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditSubCard(String title, String value, IconData icon, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF1E1B4B)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SEÇÃO: CLIENTES, TOP CLIENTES & PENDÊNCIAS
  // ==========================================
  Widget _buildClientsAndPendingSection(BuildContext context, ComercialDashboardData dados) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLarge = constraints.maxWidth > 1200;

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CARD CLIENTES (Estatísticas rápidas)
                Expanded(
                  flex: isLarge ? 2 : 1,
                  child: _buildClientesStatsCard(context, dados),
                ),
                const SizedBox(width: 24),
                // CARD TOP CLIENTES (Tabela de vendas)
                Expanded(
                  flex: isLarge ? 3 : 1,
                  child: _buildTopClientesCard(context, dados),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // CARD PENDÊNCIAS FINANCEIRAS (Larga inteira)
            _buildPendenciasFinanceirasCard(context, dados),
          ],
        );
      },
    );
  }

  Widget _buildClientesStatsCard(BuildContext context, ComercialDashboardData dados) {
    final s = dados.clientesStats;
    return Container(
      height: 330,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clientes',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildClienteStatRow('Novos Clientes', '${s.novosClientes}', _fmtPct(ComercialDashboardKpis.calcularVariacaoPercentual(s.novosClientes.toDouble(), s.novosClientesAnterior.toDouble())), s.novosClientes >= s.novosClientesAnterior),
                _buildClienteStatRow('Clientes Recorrentes', '${s.recorrentes}', _fmtPct(ComercialDashboardKpis.calcularVariacaoPercentual(s.recorrentes.toDouble(), s.recorrentesAnterior.toDouble())), s.recorrentes >= s.recorrentesAnterior),
                _buildClienteStatRow('Clientes Inativos', '${s.inativos}', _fmtPct(ComercialDashboardKpis.calcularVariacaoPercentual(s.inativos.toDouble(), s.inativosAnterior.toDouble())), s.inativos <= s.inativosAnterior),
                _buildClienteStatRow('Clientes VIP', '${s.vip}', _fmtPct(ComercialDashboardKpis.calcularVariacaoPercentual(s.vip.toDouble(), s.vipAnterior.toDouble())), s.vip >= s.vipAnterior),
                _buildClienteStatRow('Clientes com Pendência', '${s.comPendencia}', _fmtPct(ComercialDashboardKpis.calcularVariacaoPercentual(s.comPendencia.toDouble(), s.comPendenciaAnterior.toDouble())), s.comPendencia <= s.comPendenciaAnterior),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteStatRow(String label, String value, String percent, bool isPositive) {
    final color = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E1B4B),
              ),
            ),
            Row(
              children: [
                Icon(icon, size: 10, color: color),
                const SizedBox(width: 2),
                Text(
                  percent,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopClientesCard(BuildContext context, ComercialDashboardData dados) {
    final topClientes = dados.topClientes;

    return Container(
      height: 330,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top 10 Clientes (por faturamento)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: topClientes.isEmpty
                ? Center(
                    child: Text(
                      'Nenhuma venda com cliente identificado ainda.',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B), fontSize: 13),
                    ),
                  )
                : Table(
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('#', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Cliente', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Compras', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Total Gasto', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)), textAlign: TextAlign.right)),
                  ],
                ),
                ...List.generate(topClientes.length, (index) {
                  final cli = topClientes[index];
                  return TableRow(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
                    children: [
                      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('${index + 1}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)))),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(cli.nome, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)))),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('${cli.compras}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)))),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(ComercialDashboardService.formatarMoeda(cli.totalGasto), style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF6A1B9A)), textAlign: TextAlign.right)),
                    ],
                  );
                }),
              ],
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                'Ver todos os clientes',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF6A1B9A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendenciasFinanceirasCard(BuildContext context, ComercialDashboardData dados) {
    final pendentes = dados.pendenciasLista;
    final resumo = dados.pendenciasResumo;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pendências Financeiras',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 18),

          // Chips indicadores de pendências (Vencendo Hoje, 7 dias, em atraso, etc)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildPendencyIndicator('Vencendo Hoje', ComercialDashboardService.formatarMoeda(resumo.vencendoHoje), const Color(0xFFF59E0B)),
              _buildPendencyIndicator('Vencendo em 7 dias', ComercialDashboardService.formatarMoeda(resumo.vencendo7Dias), const Color(0xFF3B82F6)),
              _buildPendencyIndicator('Em atraso', ComercialDashboardService.formatarMoeda(resumo.emAtraso), const Color(0xFFEF4444)),
              _buildPendencyIndicator('Recuperadas (30 dias)', ComercialDashboardService.formatarMoeda(resumo.recuperadas30Dias), const Color(0xFF10B981)),
            ],
          ),
          const SizedBox(height: 24),

          // Tabela de Devedores
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.2),
              4: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Cliente', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Valor', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Vencimento', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Dias em atraso', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Ações', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)), textAlign: TextAlign.right)),
                ],
              ),
              ...List.generate(pendentes.length, (index) {
                final item = pendentes[index];
                return TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(item.cliente, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(ComercialDashboardService.formatarMoeda(item.valor), style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(ComercialDashboardService.formatarDataCompleta(item.vencimento), style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)))),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                        child: Text('${item.diasAtraso} dias', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.chat_rounded, size: 14, color: Color(0xFF10B981)),
                          label: Text('Cobrar', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            side: const BorderSide(color: Color(0xFF10B981)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            foregroundColor: const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                'Ver todas as pendências',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF6A1B9A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendencyIndicator(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SEÇÃO: FORMAS DE PAGAMENTO & INSIGHTS & PRODUTOS
  // ==========================================
  Widget _buildPaymentAndProductsAndInsightsSection(BuildContext context, ComercialDashboardData dados) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLarge = constraints.maxWidth > 1200;

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CARD FORMAS DE PAGAMENTO (Donut)
                Expanded(
                  flex: isLarge ? 2 : 1,
                  child: _buildFormasPagamentoCard(context, dados),
                ),
                const SizedBox(width: 24),
                // CARD INSIGHTS COMERCIAIS
                Expanded(
                  flex: isLarge ? 3 : 1,
                  child: _buildInsightsComerciaisCard(context, dados),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // CARDS PRODUTOS (Mais Vendidos e Sem Venda lado a lado)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildProdutosMaisVendidosCard(context, dados),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildProdutosSemVendaCard(context, dados),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildFormasPagamentoCard(BuildContext context, ComercialDashboardData dados) {
    final formas = dados.formasPagamento;

    return Container(
      height: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formas de Pagamento',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                // Donut Chart Custom Painter
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: _DonutChartPainter(fatias: formas),
                  ),
                ),
                const SizedBox(width: 16),
                // Legends and details
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: formas.isEmpty
                        ? [
                            Text(
                              'Sem vendas hoje para exibir.',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B)),
                            ),
                          ]
                        : formas.map((f) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(color: f.cor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                f.nome,
                                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${NumberFormat('#0.0', 'pt_BR').format(f.percentual)}% (${ComercialDashboardService.formatarMoeda(f.valor)})',
                              style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsComerciaisCard(BuildContext context, ComercialDashboardData dados) {
    final insights = dados.insights;
    return Container(
      height: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insights Comerciais',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: insights
                  .map((i) => _buildInsightRow(i.texto, i.iconColor, i.bgColor))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightRow(String text, Color iconColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(Icons.circle_rounded, color: iconColor, size: 8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E1B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProdutosMaisVendidosCard(BuildContext context, ComercialDashboardData dados) {
    final maisVendidos = dados.produtosMaisVendidos;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Produtos Mais Vendidos (Hoje)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Produto', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Quantidade', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Faturamento', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)), textAlign: TextAlign.right)),
                ],
              ),
              ...maisVendidos.map((item) {
                return TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(item.nome, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('${item.quantidade}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(ComercialDashboardService.formatarMoeda(item.faturamento), style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)), textAlign: TextAlign.right)),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                'Ver relatório completo',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: const Color(0xFF6A1B9A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProdutosSemVendaCard(BuildContext context, ComercialDashboardData dados) {
    final semVenda = dados.produtosSemVenda;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Produtos Sem Venda (Últimos 30 dias)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Produto', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Estoque', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Última Venda', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8)), textAlign: TextAlign.right)),
                ],
              ),
              ...semVenda.map((item) {
                final ultimaTxt = item.ultimaVenda == null
                    ? 'Nunca'
                    : ComercialDashboardService.formatarDataCompleta(item.ultimaVenda!);
                return TableRow(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
                  children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(item.nome, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('${item.estoque}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)))),
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(ultimaTxt, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)), textAlign: TextAlign.right)),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {},
              child: Text(
                'Ver todos os produtos',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: const Color(0xFF6A1B9A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SEÇÃO: AÇÕES RÁPIDAS
  // ==========================================
  Widget _buildQuickActions(BuildContext context, String lojaId) {
    Future<void> aposModal(Future<void> Function() acao) async {
      await acao();
      if (mounted) await _carregar(lojaId);
    }

    Future<void> aposModalBool(Future<bool> Function() acao) async {
      await acao();
      if (mounted) await _carregar(lojaId);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ações Rápidas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E1B4B),
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 1200 ? 8 : (constraints.maxWidth > 800 ? 4 : 2);
              final btnWidth = (constraints.maxWidth - (cols - 1) * 16) / cols;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildQuickActionBtn('Nova Venda', Icons.shopping_basket_rounded, const Color(0xFF10B981), const Color(0xFFD1FAE5), btnWidth, () {
                    ComercialDashboardAcoes.novaVenda(context);
                  }),
                  _buildQuickActionBtn('Novo Cliente', Icons.person_add_rounded, const Color(0xFF3B82F6), const Color(0xFFDBEAFE), btnWidth, () {
                    aposModalBool(() => ComercialDashboardAcoes.novoCliente(context, lojaId: lojaId));
                  }),
                  _buildQuickActionBtn('Conceder Crédito', Icons.wallet_rounded, const Color(0xFF8B5CF6), const Color(0xFFEDE9FE), btnWidth, () {
                    aposModalBool(() => ComercialDashboardAcoes.concederCredito(context, lojaId: lojaId));
                  }),
                  _buildQuickActionBtn('Ver Pendências', Icons.warning_amber_rounded, const Color(0xFFEF4444), const Color(0xFFFEE2E2), btnWidth, () {
                    aposModal(() => ComercialDashboardAcoes.verPendencias(context, lojaId: lojaId));
                  }),
                  _buildQuickActionBtn('Receber Pagamento', Icons.payments_rounded, const Color(0xFF10B981), const Color(0xFFD1FAE5), btnWidth, () {
                    aposModalBool(() => ComercialDashboardAcoes.receberPagamento(context, lojaId: lojaId));
                  }),
                  _buildQuickActionBtn('Relatórios', Icons.analytics_rounded, const Color(0xFF06B6D4), const Color(0xFFCFFAFE), btnWidth, () {
                    ComercialDashboardAcoes.relatorios(context);
                  }),
                  _buildQuickActionBtn('Histórico de Vendas', Icons.history_rounded, const Color(0xFFF59E0B), const Color(0xFFFEF3C7), btnWidth, () {
                    ComercialDashboardAcoes.historicoVendas(context, lojaId: lojaId);
                  }),
                  _buildQuickActionBtn('Exportar Relatório', Icons.file_upload_rounded, const Color(0xFFE2E8F0), const Color(0xFFF1F5F9), btnWidth, () {
                    ComercialDashboardAcoes.exportarRelatorio(context, lojaId: lojaId);
                  }, isLight: true),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn(String label, IconData icon, Color iconColor, Color bgColor, double width, VoidCallback onTap, {bool isLight = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        height: 100,
        decoration: BoxDecoration(
          color: isLight ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: isLight ? const Color(0xFF64748B) : iconColor, size: 22),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B4B)),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// CUSTOM PAINTER: GRÁFICO DE EVOLUÇÃO DAS VENDAS
// ==========================================
class _SalesChartPainter extends CustomPainter {
  _SalesChartPainter({
    required this.rotulos,
    required this.series,
    required this.maxValor,
  });

  final List<String> rotulos;
  final Map<String, List<double>> series;
  final double maxValor;

  static const _coresOrdem = [
    Color(0xFF10B981),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
  ];

  static const _chavesOrdem = [
    'dinheiro',
    'pix',
    'cartao_credito',
    'cartao_debito',
    'credito_cliente',
  ];

  String _fmtEixoY(double v) {
    if (v >= 1000) return 'R\$ ${(v / 1000).toStringAsFixed(0)}k';
    return 'R\$ ${v.toStringAsFixed(0)}';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (rotulos.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Sem dados no período',
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
      return;
    }

    final paintLine = Paint()
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintDot = Paint()..style = PaintingStyle.fill;

    final paintGrid = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    const ySegments = 5;
    final pontos = rotulos.length;
    final xSegments = pontos > 1 ? pontos - 1 : 1;
    final wSegment = size.width / xSegments;
    final hSegment = size.height / ySegments;
    final maxY = maxValor <= 0 ? 1.0 : maxValor * 1.1;

    final textPainterX = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < pontos; i++) {
      final x = i * wSegment;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
      textPainterX.text = TextSpan(
        text: rotulos[i],
        style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600),
      );
      textPainterX.layout();
      textPainterX.paint(canvas, Offset(x - textPainterX.width / 2, size.height + 8));
    }

    final textPainterY = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= ySegments; i++) {
      final y = size.height - (i * hSegment);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
      final valor = maxY * (i / ySegments);
      textPainterY.text = TextSpan(
        text: _fmtEixoY(valor),
        style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold),
      );
      textPainterY.layout();
      textPainterY.paint(canvas, Offset(-textPainterY.width - 12, y - textPainterY.height / 2));
    }

    for (var c = 0; c < _chavesOrdem.length; c++) {
      final chave = _chavesOrdem[c];
      final valores = series[chave] ?? [];
      if (valores.isEmpty) continue;

      final cor = _coresOrdem[c];
      paintLine.color = cor;
      paintDot.color = cor;

      final path = Path();
      for (var i = 0; i < valores.length; i++) {
        final x = i * wSegment;
        final norm = (valores[i] / maxY).clamp(0.0, 1.0);
        final y = size.height - (norm * size.height);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          final xAnt = (i - 1) * wSegment;
          final normAnt = (valores[i - 1] / maxY).clamp(0.0, 1.0);
          final yAnt = size.height - (normAnt * size.height);
          path.cubicTo(
            xAnt + wSegment / 2, yAnt,
            x - wSegment / 2, y,
            x, y,
          );
        }
      }
      canvas.drawPath(path, paintLine);

      for (var i = 0; i < valores.length; i++) {
        final x = i * wSegment;
        final norm = (valores[i] / maxY).clamp(0.0, 1.0);
        final y = size.height - (norm * size.height);
        canvas.drawCircle(Offset(x, y), 4, paintDot);
        canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.white..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SalesChartPainter oldDelegate) =>
      oldDelegate.rotulos != rotulos ||
      oldDelegate.maxValor != maxValor ||
      oldDelegate.series != series;
}

// ==========================================
// CUSTOM PAINTER: GRÁFICO DE PIZZA / DONUT
// ==========================================
class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.fatias});

  final List<ComercialFormaPagamento> fatias;

  @override
  void paint(Canvas canvas, Size size) {
    final paintSlice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.butt;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - paintSlice.strokeWidth) / 2;

    if (fatias.isEmpty) return;

    final total = fatias.fold(0.0, (s, f) => s + f.valor);
    if (total <= 0) return;

    var startAngle = -1.5708;

    for (final fatia in fatias) {
      final sweepAngle = (fatia.valor / total) * 2 * 3.14159265;
      paintSlice.color = fatia.cor;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paintSlice,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) => oldDelegate.fatias != fatias;
}
