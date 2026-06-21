import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../navigation/painel_navigation_scope.dart';
import '../theme/painel_admin_theme.dart';
import '../utils/admin_perfil.dart';
import '../utils/lojista_painel_context.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Color diPertinRoxo = PainelAdminTheme.roxo;
  final Color diPertinLaranja = PainelAdminTheme.laranja;

  static const Color _kpiClienteCor = Color(0xFF0EA5E9);
  static const Color _kpiEntregadorCor = Color(0xFF6366F1);

  // Staff KPIs
  int _lojasPendentes = 0;
  int _entregadoresPendentes = 0;
  int _kpiTotal = 0;
  int _kpiCliente = 0;
  int _kpiLojista = 0;
  int _kpiEntregador = 0;

  // Lojista Metrics
  String _uidLoja = '';
  int _pedidosHojeLoja = 0;
  double _faturamentoHojeLoja = 0;
  double _ratingLoja = 0;
  int _totalAvaliacoesLoja = 0;
  List<QueryDocumentSnapshot> _pedidosRecentesLoja = [];
  bool _carregandoMetricasLojista = false;

  bool _dashboardReady = false;
  String? _erroCarregamento;
  bool _refreshing = false;
  bool _modoDashboardLojista = false;

  String _perfil = 'master';
  DateTime? _ultimaAtualizacao;

  static const Duration _timeoutDashboard = Duration(seconds: 30);

  Future<List<int>>? _graficoFuture;

  @override
  void initState() {
    super.initState();
    unawaited(_carregarDashboard());
  }

  Future<int?> _aggregateCountSeguro(
    Future<AggregateQuerySnapshot> Function() query,
  ) async {
    for (var tentativa = 0; tentativa < 2; tentativa++) {
      try {
        final snap = await query().timeout(_timeoutDashboard);
        return snap.count ?? 0;
      } on TimeoutException {
        rethrow;
      } catch (_) {
        if (tentativa == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }
    return null;
  }

  Future<void> _yieldEntreQueriesFirestoreWeb() async {
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
  }

  Future<void> _carregarDashboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Map<String, dynamic>? dadosUser;
    try {
      final docUser = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(_timeoutDashboard);
      if (docUser.exists) dadosUser = docUser.data();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _dashboardReady = true;
        _modoDashboardLojista = false;
        _erroCarregamento = 'Tempo esgotado ao carregar o perfil. Verifique a rede.';
        _ultimaAtualizacao = DateTime.now();
      });
      return;
    } catch (_) {}

    final dados = dadosUser;
    if (dados != null && mounted) {
      setState(() {
        _perfil = perfilAdministrativo(dados);
      });
    }

    final perfilPainel = dados != null ? perfilAdministrativoPainel(dados) : 'cliente';
    
    if (perfilPainel == 'lojista') {
      if (!mounted) return;
      final uLoja = uidLojaEfetivo(dados, user.uid);
      setState(() {
        _modoDashboardLojista = true;
        _uidLoja = uLoja;
        _dashboardReady = true;
        _erroCarregamento = null;
        _ultimaAtualizacao = DateTime.now();
        if (dados != null) {
          _ratingLoja = (dados['rating_media'] ?? 0).toDouble();
          _totalAvaliacoesLoja = dados['total_avaliacoes'] ?? 0;
        }
        _graficoFuture = _contarPedidosPorDiaLoja(uLoja);
      });
      unawaited(_carregarMetricasLojista(uLoja));
      return;
    }

    final db = FirebaseFirestore.instance;
    final erros = <String>[];

    try {
      final lojasP = await _aggregateCountSeguro(
        () => db.collection('users').where('role', isEqualTo: 'lojista').where('status_loja', isEqualTo: 'pendente').count().get(),
      );
      if (lojasP == null) erros.add('Lojas pendentes');
      await _yieldEntreQueriesFirestoreWeb();

      final entP = await _aggregateCountSeguro(
        () => db.collection('users').where('role', isEqualTo: 'entregador').where('entregador_status', isEqualTo: 'pendente').count().get(),
      );
      if (entP == null) erros.add('Entregadores pendentes');
      await _yieldEntreQueriesFirestoreWeb();

      final cli = await _aggregateCountSeguro(() => db.collection('users').where('role', isEqualTo: 'cliente').count().get());
      if (cli == null) erros.add('Clientes');
      await _yieldEntreQueriesFirestoreWeb();

      final loj = await _aggregateCountSeguro(() => db.collection('users').where('role', isEqualTo: 'lojista').count().get());
      if (loj == null) erros.add('Lojistas');
      await _yieldEntreQueriesFirestoreWeb();

      final ent = await _aggregateCountSeguro(() => db.collection('users').where('role', isEqualTo: 'entregador').count().get());
      if (ent == null) erros.add('Entregadores');

      if (!mounted) return;
      setState(() {
        _lojasPendentes = lojasP ?? 0;
        _entregadoresPendentes = entP ?? 0;
        final nc = cli ?? 0;
        final nl = loj ?? 0;
        final ne = ent ?? 0;
        _kpiCliente = nc;
        _kpiLojista = nl;
        _kpiEntregador = ne;
        _kpiTotal = nc + nl + ne;
        _dashboardReady = true;
        if (erros.isEmpty) {
          _erroCarregamento = null;
        } else {
          _erroCarregamento = 'Alguns totais podem estar incompletos: ${erros.join(", ")}.';
        }
        _ultimaAtualizacao = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dashboardReady = true;
        _erroCarregamento = e.toString();
        _ultimaAtualizacao = DateTime.now();
      });
    }
  }

  Future<void> _carregarMetricasLojista(String uidLoja) async {
    if (!mounted) return;
    setState(() => _carregandoMetricasLojista = true);

    final db = FirebaseFirestore.instance;
    final hoje = DateTime.now();
    final inicioHoje = Timestamp.fromDate(DateTime(hoje.year, hoje.month, hoje.day));
    final fimHoje = Timestamp.fromDate(DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59));

    try {
      final countHoje = await db.collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .where('data_pedido', isGreaterThanOrEqualTo: inicioHoje)
          .where('data_pedido', isLessThanOrEqualTo: fimHoje)
          .count().get();

      final statusPagos = ['pendente', 'aceito', 'em_preparo', 'aguardando_entregador', 'entregador_indo_loja', 'saiu_entrega', 'entregue', 'pronto'];

      final queryFaturamento = await db.collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .where('data_pedido', isGreaterThanOrEqualTo: inicioHoje)
          .where('data_pedido', isLessThanOrEqualTo: fimHoje)
          .where('status', whereIn: statusPagos)
          .get();

      double fat = 0;
      for (final doc in queryFaturamento.docs) {
        fat += (doc.data()['valor_total'] ?? 0).toDouble();
      }

      final recentes = await db.collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .orderBy('data_pedido', descending: true)
          .limit(5).get();

      if (!mounted) return;
      setState(() {
        _pedidosHojeLoja = countHoje.count ?? 0;
        _faturamentoHojeLoja = fat;
        _pedidosRecentesLoja = recentes.docs;
        _carregandoMetricasLojista = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar métricas lojista: $e');
      if (mounted) setState(() => _carregandoMetricasLojista = false);
    }
  }

  Future<void> _refreshDashboard() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _carregarDashboard();
    if (_modoDashboardLojista && _uidLoja.isNotEmpty) {
      await _carregarMetricasLojista(_uidLoja);
    }
    if (mounted) setState(() => _refreshing = false);
  }

  String get _tituloPrincipal {
    switch (_perfil) {
      case 'lojista': return 'Sua loja no DiPertin';
      case 'master_city': return 'Painel regional';
      case 'master': return 'Painel DiPertin';
      default: return 'Painel DiPertin';
    }
  }

  String get _subtituloPagina {
    switch (_perfil) {
      case 'lojista': return 'Gerencie pedidos, produtos e carteira pelo menu ou pelos atalhos abaixo.';
      case 'master_city': return 'Acompanhe sua região e as aprovações do ecossistema.';
      default: return 'Bem-vindo ao centro de comando do DiPertin.';
    }
  }

  String _horaAtualizacao() {
    final t = _ultimaAtualizacao;
    if (t == null) return '';
    return 'Dados atualizados às ${DateFormat('HH:mm').format(t)}';
  }

  String _saudacaoOperador() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Olá';
    final email = user.email ?? '';
    if (email.isEmpty) return 'Olá';
    final nome = email.split('@').first;
    return 'Olá, ${nome[0].toUpperCase()}${nome.substring(1)}';
  }

  String _dataHojePtBr() {
    final d = DateTime.now();
    const dias = ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado', 'domingo'];
    const meses = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
    return '${dias[d.weekday - 1]}, ${d.day} de ${meses[d.month - 1]}';
  }

  Future<List<String>> getCidadesCadastradas(String? tipo) async {
    try {
      Query query = FirebaseFirestore.instance.collection('users');
      if (tipo != null) query = query.where('role', isEqualTo: tipo);
      final QuerySnapshot snapshot = await query.get(const GetOptions(source: Source.server));
      final Set<String> cidades = {};
      for (final doc in snapshot.docs) {
        final Map<String, dynamic>? dados = doc.data() as Map<String, dynamic>?;
        if (dados != null) {
          final String? nomeCidade = dados['cidade']?.toString() ?? dados['Cidade']?.toString();
          if (nomeCidade != null && nomeCidade.trim().isNotEmpty) {
            String cid = nomeCidade.trim();
            cidades.add(cid[0].toUpperCase() + cid.substring(1).toLowerCase());
          }
        }
      }
      return cidades.toList()..sort();
    } catch (e) { return []; }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: LayoutBuilder(
        builder: (context, outer) {
          final mq = MediaQuery.sizeOf(context);
          final padH = mq.width < 600 ? 20.0 : 32.0;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padH, 40, padH, 100),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroHeader(textTheme),
                        const SizedBox(height: 28),

                        if (!_dashboardReady) ...[
                          const SizedBox(
                            height: 400,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Preparando seu painel...'),
                                ],
                              ),
                            ),
                          ),
                        ] else if (_modoDashboardLojista) ...[
                          _buildSectionHeading('Visão geral', 'Resumo de desempenho da sua loja hoje.', icon: Icons.insights_rounded),
                          const SizedBox(height: 20),
                          _buildLojistaKpiGrid(maxW),
                          const SizedBox(height: 40),
                          _buildAnalyticsLojistaLayout(maxW),
                          const SizedBox(height: 40),
                          _buildSectionHeading('Atalhos rápidos', 'Navegação direta para as principais funções.', icon: Icons.auto_awesome_motion_rounded),
                          const SizedBox(height: 20),
                          _buildDashboardLojistaAtalhos(maxW),
                          const SizedBox(height: 48),
                        ] else ...[
                          if (_erroCarregamento != null) ...[
                            _buildErroCard(),
                            const SizedBox(height: 20),
                          ],
                          _buildStaffDashboard(maxW),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErroCard() {
    return Material(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Não foi possível carregar o dashboard: $_erroCarregamento',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF9F1239)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffDashboard(double maxW) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lojasPendentes > 0 || _entregadoresPendentes > 0) ...[
          _buildAvisoPendencias(),
          const SizedBox(height: 16),
          _buildPendenciasRow(maxW),
          const SizedBox(height: 36),
        ] else ...[
          _buildTudoEmDiaCard(),
          const SizedBox(height: 28),
        ],
        _buildSectionHeading('Desempenho e rankings', 'Visão consolidada de usuários por perfil.', icon: Icons.insights_rounded),
        const SizedBox(height: 20),
        _buildAnalyticsLayout(maxW),
        const SizedBox(height: 36),
        _buildSectionHeading('Módulo financeiro', 'Receitas e movimentações do ecossistema.', icon: Icons.account_balance_wallet_rounded),
        const SizedBox(height: 18),
        _buildFinanceiroCard(),
      ],
    );
  }

  Widget _buildAvisoPendencias() {
    return IntrinsicHeight(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: diPertinLaranja),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: PainelAdminTheme.dashboardCard(),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: diPertinLaranja.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.notifications_active_rounded, color: diPertinLaranja, size: 28),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Atenção requerida', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFC2410C), fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text('Existem aprovações pendentes aguardando sua análise.', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9A3412), fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceiroCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.navegarPainel('/financeiro'),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: PainelAdminTheme.dashboardCard(borderColor: const Color(0xFF059669).withValues(alpha: 0.2)),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.account_balance_rounded, color: Color(0xFF059669), size: 30),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Visão financeira', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17, color: const Color(0xFF047857))),
                      const SizedBox(height: 6),
                      Text('Gerencie receitas de destaques, vitrine e telefones premium.', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF065F46), fontSize: 14)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Color(0xFF059669), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsLojistaLayout(double maxW) {
    final pedidosRecentes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading('Pedidos recentes', 'Últimas movimentações da sua loja.', icon: Icons.history_rounded),
        const SizedBox(height: 16),
        _buildPedidosRecentesLojista(),
      ],
    );

    final grafico = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading('Desempenho semanal', 'Volume de pedidos nos últimos 7 dias.', icon: Icons.bar_chart_rounded),
        const SizedBox(height: 16),
        _buildGraficoPedidosLoja(),
      ],
    );

    if (maxW >= 1100) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 60, child: pedidosRecentes),
          const SizedBox(width: 24),
          Expanded(flex: 40, child: grafico),
        ],
      );
    }

    return Column(
      children: [
        pedidosRecentes,
        const SizedBox(height: 32),
        grafico,
      ],
    );
  }

  Widget _buildLojistaKpiGrid(double maxW) {
    const gap = 18.0;
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    final c1 = _DashboardKpiCard(
      titulo: 'Pedidos hoje',
      cor: diPertinRoxo,
      icone: Icons.receipt_long_rounded,
      count: _pedidosHojeLoja,
      pronto: !_carregandoMetricasLojista,
    );
    final c2 = _DashboardKpiCard(
      titulo: 'Faturamento hoje',
      cor: const Color(0xFF059669),
      icone: Icons.payments_rounded,
      count: 0,
      pronto: !_carregandoMetricasLojista,
      customValor: fmt.format(_faturamentoHojeLoja),
    );
    final c3 = _DashboardKpiCard(
      titulo: 'Avaliação média',
      cor: diPertinLaranja,
      icone: Icons.star_rounded,
      count: 0,
      pronto: true,
      customValor: _ratingLoja.toStringAsFixed(1),
      subtitle: '$_totalAvaliacoesLoja avaliações',
    );

    if (maxW >= 900) {
      return Row(
        children: [
          Expanded(child: c1),
          const SizedBox(width: gap),
          Expanded(child: c2),
          const SizedBox(width: gap),
          Expanded(child: c3),
        ],
      );
    }
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: c1),
            const SizedBox(width: gap),
            Expanded(child: c2),
          ],
        ),
        const SizedBox(height: gap),
        c3,
      ],
    );
  }

  Widget _buildPedidosRecentesLojista() {
    if (_carregandoMetricasLojista) {
      return Container(height: 200, decoration: PainelAdminTheme.dashboardCard(), child: const Center(child: CircularProgressIndicator()));
    }
    if (_pedidosRecentesLoja.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: PainelAdminTheme.dashboardCard(),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Nenhum pedido encontrado', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Container(
      decoration: PainelAdminTheme.dashboardCard(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ..._pedidosRecentesLoja.map((d) {
            final m = d.data() as Map<String, dynamic>;
            final valor = (m['valor_total'] ?? 0).toDouble();
            final data = (m['data_pedido'] as Timestamp?)?.toDate() ?? DateTime.now();
            final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
            final status = m['status'] ?? 'pendente';
            
            return ListTile(
              onTap: () => context.navegarPainel('/meus_pedidos'),
              leading: CircleAvatar(backgroundColor: diPertinRoxo.withValues(alpha: 0.1), child: Icon(Icons.receipt_outlined, color: diPertinRoxo, size: 20)),
              title: Row(
                children: [
                  Text(m['cliente_nome'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  Text(fmt.format(valor), style: TextStyle(fontWeight: FontWeight.bold, color: diPertinRoxo, fontSize: 14)),
                ],
              ),
              subtitle: Text('${DateFormat('dd/MM HH:mm').format(data)} • ${status.toString().toUpperCase()}', style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
            );
          }).toList(),
          TextButton(onPressed: () => context.navegarPainel('/meus_pedidos'), child: const Text('Ver todos os pedidos')),
        ],
      ),
    );
  }

  Widget _buildGraficoPedidosLoja() {
    return FutureBuilder<List<int>>(
      future: _graficoFuture,
      builder: (context, snap) {
        if (_uidLoja.isEmpty) return const SizedBox(height: 240, child: Center(child: Text('Carregando ID da loja...')));

        final counts = snap.data ?? List.filled(7, 0);
        final totalSemana = counts.fold<int>(0, (a, b) => a + b);
        final maxY = counts.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
        final yMax = maxY < 5 ? 5.0 : (maxY * 1.2).ceilToDouble();
        final carregando = snap.connectionState == ConnectionState.waiting;

        if (snap.hasError) {
          return Container(
            height: 240,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.orange, size: 32),
                const SizedBox(height: 12),
                Text(
                  'Erro ao carregar gráfico.\nPode ser necessário criar um índice no Firebase.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.orange.shade900),
                ),
                TextButton(
                  onPressed: () => setState(() => _graficoFuture = _contarPedidosPorDiaLoja(_uidLoja)),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: PainelAdminTheme.dashboardCard(),
          child: SizedBox(
            height: 240,
            child: carregando
                ? const Center(child: CircularProgressIndicator())
                : BarChart(
                    BarChartData(
                      maxY: yMax,
                      barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: counts[i].toDouble(), color: diPertinRoxo, width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))])),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (x, _) {
                          final d = DateTime.now().subtract(Duration(days: 6 - x.toInt()));
                          return Padding(padding: const EdgeInsets.only(top: 8), child: Text(DateFormat('dd/MM').format(d), style: const TextStyle(fontSize: 10, color: Colors.grey)));
                        })),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<List<int>> _contarPedidosPorDiaLoja(String uidLoja) async {
    final db = FirebaseFirestore.instance;
    final results = <int>[];
    final hoje = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final dia = DateTime(hoje.year, hoje.month, hoje.day - i);
      final inicio = Timestamp.fromDate(dia);
      final fim = Timestamp.fromDate(DateTime(dia.year, dia.month, dia.day, 23, 59, 59));
      try {
        final snap = await db.collection('pedidos')
            .where('loja_id', isEqualTo: uidLoja)
            .where('data_pedido', isGreaterThanOrEqualTo: inicio)
            .where('data_pedido', isLessThanOrEqualTo: fim)
            .count().get();
        results.add(snap.count ?? 0);
      } catch (e) {
        debugPrint('Erro no gráfico: $e');
        rethrow;
      }
    }
    return results;
  }

  Widget _buildHeroHeader(TextTheme textTheme) {
    final pendencias = _lojasPendentes + _entregadoresPendentes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7B1FA2), Color(0xFF6A1B9A), Color(0xFF4A148C)]),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.28))), child: const Icon(Icons.hub_rounded, color: Colors.white, size: 26)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_saudacaoOperador(), style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85))),
                    Text(_tituloPrincipal, style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Colors.white, fontSize: 28)),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _refreshing ? null : _refreshDashboard,
                icon: _refreshing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh_rounded, size: 20),
                label: Text(_refreshing ? 'Atualizando…' : 'Atualizar'),
                style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.18)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(_subtituloPagina, style: textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.88))),
          const SizedBox(height: 6),
          Text(_dataHojePtBr(), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
          if (_ultimaAtualizacao != null) ...[
            const SizedBox(height: 6),
            Text(_horaAtualizacao(), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.7))),
          ],
          if (!_modoDashboardLojista) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                _chipResumoHero(icon: Icons.groups_rounded, label: 'Usuários', valor: _kpiTotal.toString()),
                _chipResumoHero(icon: Icons.pending_actions_rounded, label: 'Pendências', valor: pendencias.toString(), destaque: pendencias > 0 ? const Color(0xFFFFD27A) : const Color(0xFF86EFAC)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDashboardLojistaAtalhos(double maxW) {
    final gap = 16.0;
    final c1 = _atalhoLojistaCard(titulo: 'Meus pedidos', descricao: 'Acompanhe e gerencie seus pedidos.', icon: Icons.receipt_long_rounded, cor: diPertinRoxo, rota: '/meus_pedidos');
    final c2 = _atalhoLojistaCard(titulo: 'Meus produtos', descricao: 'Gerencie seu catálogo e estoque.', icon: Icons.inventory_2_rounded, cor: diPertinLaranja, rota: '/meu_cardapio');
    final c3 = _atalhoLojistaCard(titulo: 'Minha carteira', descricao: 'Acompanhe seu saldo e repasses.', icon: Icons.account_balance_wallet_rounded, cor: const Color(0xFF059669), rota: '/carteira_loja');

    if (maxW < 700) {
      return Column(children: [c1, SizedBox(height: gap), c2, SizedBox(height: gap), c3]);
    }
    return Row(children: [Expanded(child: c1), SizedBox(width: gap), Expanded(child: c2), SizedBox(width: gap), Expanded(child: c3)]);
  }

  Widget _atalhoLojistaCard({required String titulo, required String descricao, required IconData icon, required Color cor, required String rota}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.navegarPainel(rota),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: PainelAdminTheme.dashboardCard(),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: cor, size: 24)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(descricao, style: TextStyle(color: PainelAdminTheme.textoSecundario, fontSize: 13)),
                ])),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeading(String title, String subtitle, {IconData? icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 20, decoration: BoxDecoration(color: diPertinRoxo, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 12),
            if (icon != null) ...[Icon(icon, size: 18, color: diPertinRoxo), const SizedBox(width: 8)],
            Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: PainelAdminTheme.dashboardInk)),
          ],
        ),
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.only(left: 16), child: Text(subtitle, style: TextStyle(fontSize: 13, color: PainelAdminTheme.textoSecundario))),
      ],
    );
  }

  Widget _buildTudoEmDiaCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: PainelAdminTheme.dashboardCard(),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFDCFCE7), shape: BoxShape.circle), child: const Icon(Icons.check_circle_rounded, color: Color(0xFF15803D))),
          const SizedBox(width: 16),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tudo em dia', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF166534))),
            Text('Nenhuma aprovação pendente no momento.', style: TextStyle(color: Color(0xFF15803D))),
          ])),
        ],
      ),
    );
  }

  Widget _chipResumoHero({required IconData icon, required String label, required String valor, Color? destaque}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: destaque ?? Colors.white),
          const SizedBox(width: 8),
          Text('$label: $valor', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAnalyticsLayout(double maxW) {
    if (maxW >= 1000) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: _buildKpiGrid(maxW * 0.6)),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: _buildGraficoPedidos()),
        ],
      );
    }
    return Column(children: [_buildKpiGrid(maxW), const SizedBox(height: 20), _buildGraficoPedidos()]);
  }

  Widget _buildKpiGrid(double maxW) {
    final gap = 16.0;
    final c1 = _DashboardKpiCard(titulo: 'Total usuários', cor: diPertinRoxo, icone: Icons.groups_rounded, count: _kpiTotal, pronto: _dashboardReady, onTap: () => _dialogSelecionarCidade('Total usuários', null));
    final c2 = _DashboardKpiCard(titulo: 'Clientes', cor: _kpiClienteCor, icone: Icons.person_rounded, count: _kpiCliente, pronto: _dashboardReady, onTap: () => _dialogSelecionarCidade('Clientes', 'cliente'));
    final c3 = _DashboardKpiCard(titulo: 'Lojistas', cor: diPertinLaranja, icone: Icons.storefront_rounded, count: _kpiLojista, pronto: _dashboardReady, onTap: () => _dialogSelecionarCidade('Lojistas', 'lojista'));
    final c4 = _DashboardKpiCard(titulo: 'Entregadores', cor: _kpiEntregadorCor, icone: Icons.delivery_dining_rounded, count: _kpiEntregador, pronto: _dashboardReady, onTap: () => _dialogSelecionarCidade('Entregadores', 'entregador'));

    return Column(
      children: [
        Row(children: [Expanded(child: c1), SizedBox(width: gap), Expanded(child: c2)]),
        SizedBox(height: gap),
        Row(children: [Expanded(child: c3), SizedBox(width: gap), Expanded(child: c4)]),
      ],
    );
  }

  Widget _buildPendenciasRow(double maxW) {
    final gap = 16.0;
    final c1 = _buildPendenciaCard(context, title: 'Lojas pendentes', count: _lojasPendentes, icon: Icons.store_outlined, rota: '/lojas');
    final c2 = _buildPendenciaCard(context, title: 'Entregadores pendentes', count: _entregadoresPendentes, icon: Icons.two_wheeler_outlined, rota: '/entregadores');

    if (maxW < 600) return Column(children: [c1, SizedBox(height: gap), c2]);
    return Row(children: [Expanded(child: c1), SizedBox(width: gap), Expanded(child: c2)]);
  }

  Widget _buildPendenciaCard(BuildContext context, {required String title, required int count, required IconData icon, required String rota}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.navegarPainel(rota),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: PainelAdminTheme.dashboardCard(borderColor: diPertinLaranja.withValues(alpha: 0.3)),
          child: Row(
            children: [
              Icon(icon, color: diPertinLaranja, size: 24),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
              Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: diPertinLaranja)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGraficoPedidos() {
    final hoje = DateTime.now();
    final diasLabel = List.generate(7, (i) => DateTime(hoje.year, hoje.month, hoje.day - (6 - i)));

    return FutureBuilder<List<int>>(
      future: _contarPedidosPorDia(diasLabel),
      builder: (context, snap) {
        final counts = snap.data ?? List.filled(7, 0);
        final maxY = counts.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
        final yMax = maxY < 5 ? 5.0 : (maxY * 1.2).ceilToDouble();
        final carregando = snap.connectionState == ConnectionState.waiting;

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: PainelAdminTheme.dashboardCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: diPertinRoxo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.bar_chart_rounded, color: diPertinRoxo, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Volume semanal', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 200,
                child: carregando
                    ? const Center(child: CircularProgressIndicator())
                    : BarChart(
                        BarChartData(
                          maxY: yMax,
                          barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: counts[i].toDouble(), color: diPertinLaranja, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))])),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)))),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (x, _) {
                              final d = diasLabel[x.toInt()];
                              return Padding(padding: const EdgeInsets.only(top: 8), child: Text(DateFormat('dd/MM').format(d), style: const TextStyle(fontSize: 10, color: Colors.grey)));
                            })),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<int>> _contarPedidosPorDia(List<DateTime> dias) async {
    final db = FirebaseFirestore.instance;
    final result = <int>[];
    for (final dia in dias) {
      final inicio = Timestamp.fromDate(dia);
      final fim = Timestamp.fromDate(DateTime(dia.year, dia.month, dia.day, 23, 59, 59));
      try {
        final count = await db.collection('pedidos').where('data_pedido', isGreaterThanOrEqualTo: inicio).where('data_pedido', isLessThanOrEqualTo: fim).count().get();
        result.add(count.count ?? 0);
      } catch (_) { result.add(0); }
    }
    return result;
  }

  Future<void> _dialogSelecionarCidade(String titulo, String? tipo) async {
    showDialog<void>(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    final cidades = await getCidadesCadastradas(tipo);
    if (!mounted) return;
    Navigator.pop(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: cidades.isEmpty ? const Text('Nenhuma cidade encontrada.') : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filtrar $titulo', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  DropdownMenu<String>(
                    width: 360,
                    enableFilter: true,
                    label: const Text('Cidade'),
                    dropdownMenuEntries: cidades.map((c) => DropdownMenuEntry<String>(value: c, label: c)).toList(),
                    onSelected: (sel) { if (sel != null) { Navigator.pop(ctx); _mostrarRanking(sel, tipo ?? 'cliente'); } },
                  ),
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarRanking(String cidade, String tipo) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [Expanded(child: Text('Ranking — $cidade', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: tipo).get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final users = snapshot.data!.docs.where((doc) => (doc.data() as Map)['cidade']?.toString().toLowerCase() == cidade.toLowerCase()).toList();
                      if (users.isEmpty) return const Center(child: Text('Nenhum usuário nesta cidade.'));
                      users.sort((a, b) => (b.data() as Map)['totalConcluido']?.compareTo((a.data() as Map)['totalConcluido'] ?? 0) ?? 0);
                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, i) {
                          final u = users[i].data() as Map;
                          return ListTile(
                            leading: CircleAvatar(child: Text('${i+1}')),
                            title: Text(u['nome'] ?? 'Sem nome'),
                            subtitle: Text('Concluídos: ${u['totalConcluido'] ?? 0}'),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardKpiCard extends StatefulWidget {
  const _DashboardKpiCard({
    required this.titulo,
    required this.cor,
    required this.icone,
    required this.count,
    required this.pronto,
    this.onTap,
    this.customValor,
    this.subtitle,
  });

  final String titulo;
  final Color cor;
  final IconData icone;
  final int count;
  final bool pronto;
  final VoidCallback? onTap;
  final String? customValor;
  final String? subtitle;

  @override
  State<_DashboardKpiCard> createState() => _DashboardKpiCardState();
}

class _DashboardKpiCardState extends State<_DashboardKpiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final valor = widget.customValor ?? (widget.pronto ? widget.count.toString() : '…');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.only(bottom: _hover ? 2 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: _hover ? PainelAdminTheme.sombraCardSuave() : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Ink(
              decoration: PainelAdminTheme.dashboardCard(),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: widget.cor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(widget.icone, color: widget.cor, size: 20)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(widget.titulo, style: TextStyle(color: PainelAdminTheme.textoSecundario, fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(valor, style: GoogleFonts.plusJakartaSans(fontSize: 28, color: widget.cor, fontWeight: FontWeight.w800)),
                    if (widget.subtitle != null) Text(widget.subtitle!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (widget.onTap != null) ...[
                      const SizedBox(height: 12),
                      Row(children: [Text('Ver detalhes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: PainelAdminTheme.roxo)), Icon(Icons.arrow_forward_ios_rounded, size: 10, color: PainelAdminTheme.roxo)]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
