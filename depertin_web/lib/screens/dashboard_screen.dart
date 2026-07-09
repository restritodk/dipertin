import 'dart:async';
import 'dart:ui' show ImageFilter;

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

// ═══════════════════════════════════════════════════════════════════
// CONSTANTES DE DESIGN
// ═══════════════════════════════════════════════════════════════════

const double _borderRadiusCard = 20.0;
const double _borderRadiusSmall = 14.0;
const double _gapPadrao = 20.0;
const Color _kpiClienteCor = Color(0xFF0EA5E9);
const Color _kpiEntregadorCor = Color(0xFF6366F1);

// ═══════════════════════════════════════════════════════════════════
// DASHBOARD SCREEN
// ═══════════════════════════════════════════════════════════════════

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // ── Cores ──────────────────────────────────────────────────────
  final Color diPertinRoxo = PainelAdminTheme.roxo;
  final Color diPertinLaranja = PainelAdminTheme.laranja;

  // ── Staff KPIs ─────────────────────────────────────────────────
  int _lojasPendentes = 0;
  int _entregadoresPendentes = 0;
  int _kpiTotal = 0;
  int _kpiCliente = 0;
  int _kpiLojista = 0;
  int _kpiEntregador = 0;

  // ── Lojista Metrics ────────────────────────────────────────────
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

  // ── Animações ──────────────────────────────────────────────────
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    unawaited(_carregarDashboard());
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // MÉTODOS DE DADOS (preservados integralmente)
  // ═══════════════════════════════════════════════════════════════

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
        _erroCarregamento =
            'Tempo esgotado ao carregar o perfil. Verifique a rede.';
        _ultimaAtualizacao = DateTime.now();
        _fadeController.forward();
      });
      return;
    } catch (_) {}

    final dados = dadosUser;
    if (dados != null && mounted) {
      setState(() {
        _perfil = perfilAdministrativo(dados);
      });
    }

    final perfilPainel =
        dados != null ? perfilAdministrativoPainel(dados) : 'cliente';

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
      _fadeController.forward();
      unawaited(_carregarMetricasLojista(uLoja));
      return;
    }

    final db = FirebaseFirestore.instance;
    final erros = <String>[];

    try {
      final lojasP = await _aggregateCountSeguro(
        () => db
            .collection('users')
            .where('role', isEqualTo: 'lojista')
            .where('status_loja', isEqualTo: 'pendente')
            .count()
            .get(),
      );
      if (lojasP == null) erros.add('Lojas pendentes');
      await _yieldEntreQueriesFirestoreWeb();

      final entP = await _aggregateCountSeguro(
        () => db
            .collection('users')
            .where('role', isEqualTo: 'entregador')
            .where('entregador_status', isEqualTo: 'pendente')
            .count()
            .get(),
      );
      if (entP == null) erros.add('Entregadores pendentes');
      await _yieldEntreQueriesFirestoreWeb();

      final cli = await _aggregateCountSeguro(
          () => db.collection('users').where('role', isEqualTo: 'cliente').count().get());
      if (cli == null) erros.add('Clientes');
      await _yieldEntreQueriesFirestoreWeb();

      final loj = await _aggregateCountSeguro(
          () => db.collection('users').where('role', isEqualTo: 'lojista').count().get());
      if (loj == null) erros.add('Lojistas');
      await _yieldEntreQueriesFirestoreWeb();

      final ent = await _aggregateCountSeguro(
          () => db.collection('users').where('role', isEqualTo: 'entregador').count().get());
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
          _erroCarregamento =
              'Alguns totais podem estar incompletos: ${erros.join(", ")}.';
        }
        _ultimaAtualizacao = DateTime.now();
        _fadeController.forward();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dashboardReady = true;
        _erroCarregamento = e.toString();
        _ultimaAtualizacao = DateTime.now();
        _fadeController.forward();
      });
    }
  }

  double _extrairValorPedido(Map<String, dynamic> m) {
    final v = m['valor_total_pago_cliente'];
    if (v != null && v != '') {
      return (v as num).toDouble();
    }
    final sub = (m['subtotal'] ?? m['total_produtos'] ?? 0).toDouble();
    final frete = (m['taxa_entrega'] ?? 0).toDouble();
    return sub + frete;
  }

  Future<void> _carregarMetricasLojista(String uidLoja) async {
    if (!mounted) return;
    setState(() => _carregandoMetricasLojista = true);

    final db = FirebaseFirestore.instance;
    final hoje = DateTime.now();
    final inicioHoje =
        Timestamp.fromDate(DateTime(hoje.year, hoje.month, hoje.day));
    final fimHoje = Timestamp.fromDate(
        DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59));

    try {
      final countHoje = await db
          .collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .where('data_pedido', isGreaterThanOrEqualTo: inicioHoje)
          .where('data_pedido', isLessThanOrEqualTo: fimHoje)
          .count()
          .get();

      final statusPagos = [
        'pendente',
        'aceito',
        'em_preparo',
        'aguardando_entregador',
        'entregador_indo_loja',
        'saiu_entrega',
        'entregue',
        'pronto'
      ];

      final queryFaturamento = await db
          .collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .where('data_pedido', isGreaterThanOrEqualTo: inicioHoje)
          .where('data_pedido', isLessThanOrEqualTo: fimHoje)
          .where('status', whereIn: statusPagos)
          .get();

      double fat = 0;
      for (final doc in queryFaturamento.docs) {
        fat += _extrairValorPedido(doc.data());
      }

      final recentes = await db
          .collection('pedidos')
          .where('loja_id', isEqualTo: uidLoja)
          .orderBy('data_pedido', descending: true)
          .limit(5)
          .get();

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

  // ═══════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════

  String get _tituloPrincipal {
    switch (_perfil) {
      case 'lojista':
        return 'Sua loja no DiPertin';
      case 'master_city':
        return 'Painel regional';
      case 'master':
        return 'Painel DiPertin';
      default:
        return 'Painel DiPertin';
    }
  }

  String get _subtituloPagina {
    switch (_perfil) {
      case 'lojista':
        return 'Gerencie pedidos, produtos e carteira pelo menu ou pelos atalhos abaixo.';
      case 'master_city':
        return 'Acompanhe sua região e as aprovações do ecossistema.';
      default:
        return 'Bem-vindo ao centro de comando do DiPertin.';
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
    const dias = [
      'segunda-feira',
      'terça-feira',
      'quarta-feira',
      'quinta-feira',
      'sexta-feira',
      'sábado',
      'domingo'
    ];
    const meses = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro'
    ];
    return '${dias[d.weekday - 1]}, ${d.day} de ${meses[d.month - 1]}';
  }

  Future<List<String>> getCidadesCadastradas(String? tipo) async {
    try {
      Query query = FirebaseFirestore.instance.collection('users');
      if (tipo != null) query = query.where('role', isEqualTo: tipo);
      final QuerySnapshot snapshot =
          await query.get(const GetOptions(source: Source.server));
      final Set<String> cidades = {};
      for (final doc in snapshot.docs) {
        final Map<String, dynamic>? dados =
            doc.data() as Map<String, dynamic>?;
        if (dados != null) {
          final String? nomeCidade =
              dados['cidade']?.toString() ?? dados['Cidade']?.toString();
          if (nomeCidade != null && nomeCidade.trim().isNotEmpty) {
            String cid = nomeCidade.trim();
            cidades.add(cid[0].toUpperCase() + cid.substring(1).toLowerCase());
          }
        }
      }
      return cidades.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  Future<List<int>> _contarPedidosPorDia(List<DateTime> dias) async {
    final db = FirebaseFirestore.instance;
    final result = <int>[];
    for (final dia in dias) {
      final inicio = Timestamp.fromDate(dia);
      final fim =
          Timestamp.fromDate(DateTime(dia.year, dia.month, dia.day, 23, 59, 59));
      try {
        final count = await db
            .collection('pedidos')
            .where('data_pedido', isGreaterThanOrEqualTo: inicio)
            .where('data_pedido', isLessThanOrEqualTo: fim)
            .count()
            .get();
        result.add(count.count ?? 0);
      } catch (_) {
        result.add(0);
      }
    }
    return result;
  }

  Future<List<int>> _contarPedidosPorDiaLoja(String uidLoja) async {
    final db = FirebaseFirestore.instance;
    final results = <int>[];
    final hoje = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final dia = DateTime(hoje.year, hoje.month, hoje.day - i);
      final inicio = Timestamp.fromDate(dia);
      final fim =
          Timestamp.fromDate(DateTime(dia.year, dia.month, dia.day, 23, 59, 59));
      try {
        final snap = await db
            .collection('pedidos')
            .where('loja_id', isEqualTo: uidLoja)
            .where('data_pedido', isGreaterThanOrEqualTo: inicio)
            .where('data_pedido', isLessThanOrEqualTo: fim)
            .count()
            .get();
        results.add(snap.count ?? 0);
      } catch (e) {
        debugPrint('Erro no gráfico: $e');
        rethrow;
      }
    }
    return results;
  }

  Future<void> _dialogSelecionarCidade(String titulo, String? tipo) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    final cidades = await getCidadesCadastradas(tipo);
    if (!mounted) return;
    Navigator.pop(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: cidades.isEmpty
                  ? const Text('Nenhuma cidade encontrada.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Filtrar $titulo',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        DropdownMenu<String>(
                          width: 360,
                          enableFilter: true,
                          label: const Text('Cidade'),
                          dropdownMenuEntries: cidades
                              .map((c) =>
                                  DropdownMenuEntry<String>(value: c, label: c))
                              .toList(),
                          onSelected: (sel) {
                            if (sel != null) {
                              Navigator.pop(ctx);
                              _mostrarRanking(sel, tipo ?? 'cliente');
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                        ),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 600, maxHeight: 500),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Ranking — $cidade',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .where('role', isEqualTo: tipo)
                        .get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final users = snapshot.data!.docs
                          .where((doc) =>
                              (doc.data() as Map)['cidade']
                                  ?.toString()
                                  .toLowerCase() ==
                              cidade.toLowerCase())
                          .toList();
                      if (users.isEmpty) {
                        return const Center(
                            child: Text('Nenhum usuário nesta cidade.'));
                      }
                      users.sort(
                        (a, b) =>
                            (b.data() as Map)['totalConcluido']
                                ?.compareTo(
                                    (a.data() as Map)['totalConcluido'] ?? 0) ??
                            0,
                      );
                      return ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, i) {
                          final u = users[i].data() as Map;
                          return ListTile(
                            leading: CircleAvatar(child: Text('${i + 1}')),
                            title: Text(u['nome'] ?? 'Sem nome'),
                            subtitle: Text(
                                'Concluídos: ${u['totalConcluido'] ?? 0}'),
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

  // ═══════════════════════════════════════════════════════════════
  // BUILD PRINCIPAL
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PainelAdminTheme.fundoCanvas,
      body: LayoutBuilder(
        builder: (context, outer) {
          final mq = MediaQuery.sizeOf(context);
          final padH = mq.width < 600 ? 16.0 : 28.0;

          return FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padH, 24, padH, 100),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPremiumHero(),
                          const SizedBox(height: 24),

                          if (!_dashboardReady)
                            _buildPremiumSkeleton()
                          else if (_erroCarregamento != null &&
                              !_modoDashboardLojista) ...[
                            _buildPremiumErrorCard(),
                            const SizedBox(height: 20),
                          ],

                          if (_dashboardReady && _modoDashboardLojista)
                            _buildLojistaDashboard(maxW)
                          else if (_dashboardReady)
                            _buildStaffDashboard(maxW),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SKELETON / LOADING
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumSkeleton() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 20),
            Text('Preparando seu painel…',
                style: TextStyle(fontSize: 15, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(_borderRadiusSmall),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.red.shade600, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _erroCarregamento ?? '',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HERO PREMIUM
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumHero() {
    final pendencias = _lojasPendentes + _entregadoresPendentes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4A148C),
            Color(0xFF6A1B9A),
            Color(0xFF7B1FA2),
            Color(0xFF8E24AA),
          ],
          stops: [0.0, 0.4, 0.75, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: DiPertinTheme.primaryRoxoEscuro.withValues(alpha: 0.3),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Formas abstratas decorativas
          Positioned(
            top: -40,
            right: -20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DiPertinTheme.secondaryLaranja.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: 80,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          Positioned(
            top: 20,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DiPertinTheme.secondaryLaranja.withValues(alpha: 0.04),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: -40,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.03),
              ),
            ),
          ),

          // Conteúdo
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha superior: saudação + botão refresh
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícone do painel
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.dashboard_customize_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _saudacaoOperador(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.80),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tituloPrincipal,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _PremiumGlassButton(
                    onPressed: _refreshing ? null : _refreshDashboard,
                    loading: _refreshing,
                    label: _refreshing ? 'Atualizando…' : 'Atualizar dados',
                    icon: Icons.refresh_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Subtítulo
              Text(
                _subtituloPagina,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.85),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              // Data e última atualização
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 13, color: Colors.white.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text(
                    _dataHojePtBr(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  if (_ultimaAtualizacao != null) ...[
                    const SizedBox(width: 20),
                    Icon(Icons.access_time_rounded,
                        size: 13, color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text(
                      _horaAtualizacao(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),

              // Chips glassmorphism (apenas staff)
              if (!_modoDashboardLojista && _dashboardReady) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _buildGlassChip(
                      icon: Icons.groups_rounded,
                      label: 'Usuários',
                      value: _kpiTotal.toString(),
                    ),
                    _buildGlassChip(
                      icon: Icons.pending_actions_rounded,
                      label: 'Pendências',
                      value: pendencias.toString(),
                      accent: pendencias > 0
                          ? DiPertinTheme.secondaryLaranja
                          : const Color(0xFF86EFAC),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassChip({
    required IconData icon,
    required String label,
    required String value,
    Color? accent,
  }) {
    final cor = accent ?? Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: cor),
              const SizedBox(width: 10),
              Text(
                '$label: ',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BOTÃO GLASS
  // ═══════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════
  // STAFF DASHBOARD
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStaffDashboard(double maxW) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status (pendências ou tudo em dia)
        if (_lojasPendentes > 0 || _entregadoresPendentes > 0)
          _buildPremiumPendingSection(maxW)
        else
          _buildPremiumAllGoodCard(),

        const SizedBox(height: 36),

        // Desempenho e Rankings
        _buildPremiumSectionTitle(
          'Desempenho e Rankings',
          'Visão consolidada de usuários por perfil.',
          icon: Icons.insights_rounded,
          trailing: _buildFilterChip('Últimos 7 dias'),
        ),
        const SizedBox(height: 22),
        _buildPerformanceLayout(maxW),

        const SizedBox(height: 40),

        // Módulo Financeiro
        _buildPremiumSectionTitle(
          'Módulo Financeiro',
          'Receitas e movimentações do ecossistema.',
          icon: Icons.account_balance_wallet_rounded,
        ),
        const SizedBox(height: 22),
        _buildFinanceSection(maxW),

        const SizedBox(height: 40),

        // Atividades Recentes
        _buildPremiumSectionTitle(
          'Atividades recentes',
          'Últimas movimentações do ecossistema.',
          icon: Icons.history_rounded,
        ),
        const SizedBox(height: 22),
        _buildRecentActivities(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SEÇÃO DE STATUS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumAllGoodCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(_borderRadiusCard),
        border: Border.all(color: const Color(0xFF86EFAC).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tudo em dia!',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nenhuma aprovação pendente no momento.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Ilustração de segurança
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.verified_rounded,
                color: const Color(0xFF22C55E).withValues(alpha: 0.6), size: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumPendingSection(double maxW) {
    final gap = 16.0;
    final c1 = _buildPendenciaPremiumCard(
      title: 'Lojas pendentes',
      count: _lojasPendentes,
      icon: Icons.store_outlined,
      rota: '/lojas',
      color: DiPertinTheme.secondaryLaranja,
    );
    final c2 = _buildPendenciaPremiumCard(
      title: 'Entregadores pendentes',
      count: _entregadoresPendentes,
      icon: Icons.two_wheeler_outlined,
      rota: '/entregadores',
      color: const Color(0xFF6366F1),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Alerta
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                DiPertinTheme.secondaryLaranja.withValues(alpha: 0.08),
                Colors.transparent,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(_borderRadiusCard),
            border: Border.all(
              color: DiPertinTheme.secondaryLaranja.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DiPertinTheme.secondaryLaranja.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.notifications_active_rounded,
                    color: DiPertinTheme.secondaryLaranja, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Atenção requerida',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF9A3412),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Existem aprovações pendentes aguardando sua análise.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: const Color(0xFFC2410C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (maxW < 600)
          Column(children: [c1, SizedBox(height: gap), c2])
        else
          Row(children: [
            Expanded(child: c1),
            SizedBox(width: gap),
            Expanded(child: c2),
          ]),
      ],
    );
  }

  Widget _buildPendenciaPremiumCard({
    required String title,
    required int count,
    required IconData icon,
    required String rota,
    required Color color,
  }) {
    return MouseRegion(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.navegarPainel(rota),
          borderRadius: BorderRadius.circular(_borderRadiusSmall),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_borderRadiusSmall),
              border: Border.all(
                  color: color.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count.toString(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SEÇÃO TÍTULO
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumSectionTitle(
    String title,
    String subtitle, {
    IconData? icon,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Barra decorativa
        Container(
          width: 4,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [DiPertinTheme.primaryRoxo, DiPertinTheme.primaryRoxoClaro],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 14),
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: DiPertinTheme.primaryRoxo),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.dashboardInk,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range_rounded,
              size: 14, color: DiPertinTheme.primaryRoxo),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DiPertinTheme.primaryRoxo,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down_rounded,
              size: 18, color: DiPertinTheme.primaryRoxo),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PERFORMANCE LAYOUT (cards + gráfico)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPerformanceLayout(double maxW) {
    // 4 metric cards
    final cards = Column(
      children: [
        Row(children: [
          Expanded(
              child: _DashboardKpiCard(
            titulo: 'Total de usuários',
            cor: diPertinRoxo,
            icone: Icons.groups_rounded,
            count: _kpiTotal,
            pronto: _dashboardReady,
            onTap: () =>
                _dialogSelecionarCidade('Total de usuários', null),
          )),
          const SizedBox(width: _gapPadrao),
          Expanded(
              child: _DashboardKpiCard(
            titulo: 'Clientes',
            cor: _kpiClienteCor,
            icone: Icons.person_rounded,
            count: _kpiCliente,
            pronto: _dashboardReady,
            onTap: () =>
                _dialogSelecionarCidade('Clientes', 'cliente'),
          )),
        ]),
        const SizedBox(height: _gapPadrao),
        Row(children: [
          Expanded(
              child: _DashboardKpiCard(
            titulo: 'Lojistas',
            cor: diPertinLaranja,
            icone: Icons.storefront_rounded,
            count: _kpiLojista,
            pronto: _dashboardReady,
            onTap: () =>
                _dialogSelecionarCidade('Lojistas', 'lojista'),
          )),
          const SizedBox(width: _gapPadrao),
          Expanded(
              child: _DashboardKpiCard(
            titulo: 'Entregadores',
            cor: _kpiEntregadorCor,
            icone: Icons.delivery_dining_rounded,
            count: _kpiEntregador,
            pronto: _dashboardReady,
            onTap: () =>
                _dialogSelecionarCidade('Entregadores', 'entregador'),
          )),
        ]),
      ],
    );

    // Chart
    final chart = _buildPremiumChart();

    if (maxW >= 1000) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: cards),
          const SizedBox(width: _gapPadrao),
          Expanded(flex: 4, child: chart),
        ],
      );
    }
    return Column(
      children: [cards, const SizedBox(height: _gapPadrao), chart],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // GRÁFICO PREMIUM
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPremiumChart() {
    final hoje = DateTime.now();
    final diasLabel = List.generate(
        7, (i) => DateTime(hoje.year, hoje.month, hoje.day - (6 - i)));

    return FutureBuilder<List<int>>(
      future: _contarPedidosPorDia(diasLabel),
      builder: (context, snap) {
        final counts = snap.data ?? List.filled(7, 0);
        final maxY = counts.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
        final yMax = maxY < 5 ? 5.0 : (maxY * 1.2).ceilToDouble();
        final carregando = snap.connectionState == ConnectionState.waiting;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_borderRadiusCard),
            border: Border.all(color: PainelAdminTheme.dashboardBorder),
            boxShadow: DiPertinTheme.sombraCardSuave(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DiPertinTheme.secondaryLaranja.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.bar_chart_rounded,
                        color: DiPertinTheme.secondaryLaranja, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Volume semanal',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: PainelAdminTheme.dashboardInk,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: PainelAdminTheme.fundoCanvas,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Esta semana',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Chart body
              SizedBox(
                height: 200,
                child: carregando
                    ? const Center(child: CircularProgressIndicator())
                    : BarChart(
                        BarChartData(
                          maxY: yMax,
                          alignment: BarChartAlignment.spaceAround,
                          barGroups: List.generate(
                            7,
                            (i) => BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: counts[i].toDouble(),
                                  color: DiPertinTheme.secondaryLaranja,
                                  width: 20,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                  backDrawRodData: BackgroundBarChartRodData(
                                    show: true,
                                    toY: yMax,
                                    color: DiPertinTheme.secondaryLaranja.withValues(alpha: 0.04),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: yMax > 10 ? (yMax / 4).ceilToDouble() : 1,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: Colors.grey.shade200,
                              strokeWidth: 1,
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget: (v, _) => Text(
                                  v.toInt().toString(),
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: PainelAdminTheme.textoSecundario),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (x, _) {
                                  final d = diasLabel[x.toInt()];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      DateFormat('dd/MM').format(d),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        color: PainelAdminTheme.textoSecundario,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
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

  // ═══════════════════════════════════════════════════════════════
  // MÓDULO FINANCEIRO
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFinanceSection(double maxW) {
    if (maxW >= 1000) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: _buildPremiumFinanceCard()),
          const SizedBox(width: _gapPadrao),
          Expanded(flex: 4, child: _buildPremiumMiniCards()),
        ],
      );
    }
    return Column(
      children: [
        _buildPremiumFinanceCard(),
        const SizedBox(height: _gapPadrao),
        _buildPremiumMiniCards(),
      ],
    );
  }

  Widget _buildPremiumFinanceCard() {
    final hoje = DateTime.now();
    final diasLabel = List.generate(
        7, (i) => DateTime(hoje.year, hoje.month, hoje.day - (6 - i)));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadiusCard),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF059669),
                      Color(0xFF10B981),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF059669).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.account_balance_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receita do mês',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'R\$ 0,00',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: PainelAdminTheme.dashboardInk,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.trending_up_rounded,
                                  size: 12,
                                  color: const Color(0xFF059669)),
                              const SizedBox(width: 2),
                              Text(
                                '—',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Material(
                color: DiPertinTheme.primaryRoxo.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => context.navegarPainel('/financeiro'),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Relatório',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DiPertinTheme.primaryRoxo,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            size: 14, color: DiPertinTheme.primaryRoxo),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Mini line chart
          SizedBox(
            height: 100,
            child: FutureBuilder<List<int>>(
              future: _contarPedidosPorDia(diasLabel),
              builder: (context, snap) {
                final counts = snap.data ?? List.filled(7, 5);
                final maxV =
                    counts.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
                final yM = maxV < 5 ? 10.0 : maxV * 1.3;

                return LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: yM,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: List.generate(
                          7,
                          (i) => FlSpot(i.toDouble(), counts[i].toDouble()),
                        ),
                        isCurved: true,
                        color: const Color(0xFF059669),
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) =>
                              FlDotCirclePainter(
                            radius: 3,
                            color: const Color(0xFF059669),
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF059669).withValues(alpha: 0.2),
                              const Color(0xFF059669).withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Botão ver relatório
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.navegarPainel('/financeiro'),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Ver relatório completo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumMiniCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _buildPremiumMiniCard(
              label: 'Receitas',
              value: 'R\$ 0,00',
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF059669),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _buildPremiumMiniCard(
              label: 'Saques',
              value: 'R\$ 0,00',
              icon: Icons.download_rounded,
              color: const Color(0xFF6366F1),
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _buildPremiumMiniCard(
              label: 'Pendências',
              value: (_lojasPendentes + _entregadoresPendentes).toString(),
              icon: Icons.pending_actions_rounded,
              color: DiPertinTheme.secondaryLaranja,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _buildPremiumMiniCard(
              label: 'Disponível',
              value: 'R\$ 0,00',
              icon: Icons.account_balance_wallet_rounded,
              color: DiPertinTheme.primaryRoxo,
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildPremiumMiniCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadiusSmall),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ATIVIDADES RECENTES
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRecentActivities() {
    final items = _buildActivityItems();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadiusCard),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      child: items.isEmpty
          ? _buildEmptyActivities()
          : Column(
              children: [
                ...items.map((item) => _buildActivityTimelineItem(item)),
              ],
            ),
    );
  }

  Widget _buildEmptyActivities() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.history_rounded,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Nenhuma atividade recente',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'As movimentações aparecerão aqui em tempo real.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: PainelAdminTheme.textoSecundario.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_ActivityItem> _buildActivityItems() {
    final lista = <_ActivityItem>[];

    if (_lojasPendentes > 0) {
      lista.add(_ActivityItem(
        icon: Icons.store_outlined,
        color: DiPertinTheme.secondaryLaranja,
        name: 'Sistema',
        description: '$_lojasPendentes loja(s) pendente(s) de aprovação',
        time: 'Agora',
        type: 'pendencia',
      ));
    }
    if (_entregadoresPendentes > 0) {
      lista.add(_ActivityItem(
        icon: Icons.two_wheeler_outlined,
        color: const Color(0xFF6366F1),
        name: 'Sistema',
        description:
            '$_entregadoresPendentes entregador(es) pendente(s) de aprovação',
        time: 'Agora',
        type: 'pendencia',
      ));
    }

    if (_kpiTotal > 0) {
      lista.add(_ActivityItem(
        icon: Icons.groups_rounded,
        color: DiPertinTheme.primaryRoxo,
        name: 'Sistema',
        description: '$_kpiTotal usuários cadastrados na plataforma',
        time: _horaAtualizacao(),
        type: 'info',
      ));
    }

    if (_kpiLojista > 0) {
      lista.add(_ActivityItem(
        icon: Icons.storefront_rounded,
        color: const Color(0xFF059669),
        name: 'Sistema',
        description: '$_kpiLojista lojistas ativos na plataforma',
        time: _horaAtualizacao(),
        type: 'info',
      ));
    }

    // Limitar a 5 itens
    return lista.take(5).toList();
  }

  Widget _buildActivityTimelineItem(_ActivityItem item) {
    return IntrinsicHeight(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline: ícone + linha
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: item.color, size: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Conteúdo
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PainelAdminTheme.dashboardInk,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.type == 'pendencia'
                                ? DiPertinTheme.secondaryLaranja.withValues(alpha: 0.10)
                                : DiPertinTheme.primaryRoxo.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.type,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: item.type == 'pendencia'
                                  ? DiPertinTheme.secondaryLaranja
                                  : DiPertinTheme.primaryRoxo,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          item.time,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: PainelAdminTheme.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: PainelAdminTheme.textoSecundario,
                        height: 1.3,
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

  // ═══════════════════════════════════════════════════════════════
  // LOJISTA DASHBOARD
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLojistaDashboard(double maxW) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPremiumSectionTitle(
          'Visão geral',
          'Resumo de desempenho da sua loja hoje.',
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: 20),
        _buildLojistaKpiGrid(maxW),
        const SizedBox(height: 36),
        _buildLojistaAnalyticsLayout(maxW),
        const SizedBox(height: 36),
        _buildPremiumSectionTitle(
          'Atalhos rápidos',
          'Navegação direta para as principais funções.',
          icon: Icons.auto_awesome_motion_rounded,
        ),
        const SizedBox(height: 20),
        _buildLojistaShortcuts(maxW),
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

  Widget _buildLojistaAnalyticsLayout(double maxW) {
    final pedidosRecentes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPremiumSectionTitle(
          'Pedidos recentes',
          'Últimas movimentações da sua loja.',
          icon: Icons.history_rounded,
        ),
        const SizedBox(height: 16),
        _buildLojistaRecentOrders(),
      ],
    );

    final grafico = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPremiumSectionTitle(
          'Desempenho semanal',
          'Volume de pedidos nos últimos 7 dias.',
          icon: Icons.bar_chart_rounded,
        ),
        const SizedBox(height: 16),
        _buildLojistaChart(),
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

  Widget _buildLojistaRecentOrders() {
    if (_carregandoMetricasLojista) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_borderRadiusSmall),
          border: Border.all(color: PainelAdminTheme.dashboardBorder),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_pedidosRecentesLoja.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_borderRadiusSmall),
          border: Border.all(color: PainelAdminTheme.dashboardBorder),
        ),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Nenhum pedido encontrado',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_borderRadiusSmall),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: DiPertinTheme.sombraCardSuave(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ..._pedidosRecentesLoja.map((d) {
            final m = d.data() as Map<String, dynamic>;
            final valor = _extrairValorPedido(m);
            final data =
                (m['data_pedido'] as Timestamp?)?.toDate() ?? DateTime.now();
            final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
            final status = m['status'] ?? 'pendente';

            return ListTile(
              onTap: () => context.navegarPainel('/meus_pedidos'),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: diPertinRoxo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_outlined,
                    color: diPertinRoxo, size: 18),
              ),
              title: Row(
                children: [
                  Text(
                    m['cliente_nome'] ?? 'Cliente',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    fmt.format(valor),
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      color: diPertinRoxo,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                '${DateFormat('dd/MM HH:mm').format(data)} • ${status.toString().toUpperCase()}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: PainelAdminTheme.textoSecundario),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: PainelAdminTheme.textoSecundario),
            );
          }),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.navegarPainel('/meus_pedidos'),
                child: const Text('Ver todos os pedidos'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLojistaChart() {
    return FutureBuilder<List<int>>(
      future: _graficoFuture,
      builder: (context, snap) {
        if (_uidLoja.isEmpty) {
          return const SizedBox(
              height: 240,
              child: Center(child: Text('Carregando ID da loja…')));
        }

        final counts = snap.data ?? List.filled(7, 0);
        final maxY = counts.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
        final yMax = maxY < 5 ? 5.0 : (maxY * 1.2).ceilToDouble();
        final carregando = snap.connectionState == ConnectionState.waiting;

        if (snap.hasError) {
          return Container(
            height: 240,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_borderRadiusSmall),
              border: Border.all(color: PainelAdminTheme.dashboardBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.orange, size: 32),
                const SizedBox(height: 12),
                Text(
                  'Erro ao carregar gráfico.\nPode ser necessário criar um índice no Firebase.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: Colors.orange.shade900),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _graficoFuture = _contarPedidosPorDiaLoja(_uidLoja)),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_borderRadiusSmall),
            border: Border.all(color: PainelAdminTheme.dashboardBorder),
            boxShadow: DiPertinTheme.sombraCardSuave(),
          ),
          child: SizedBox(
            height: 240,
            child: carregando
                ? const Center(child: CircularProgressIndicator())
                : BarChart(
                    BarChartData(
                      maxY: yMax,
                      barGroups: List.generate(
                        7,
                        (i) => BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: counts[i].toDouble(),
                              color: diPertinRoxo,
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: yMax,
                                color: diPertinRoxo.withValues(alpha: 0.04),
                              ),
                            ),
                          ],
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: yMax > 10 ? (yMax / 4).ceilToDouble() : 1,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.shade200,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (x, _) {
                              final d = DateTime.now()
                                  .subtract(Duration(days: 6 - x.toInt()));
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  DateFormat('dd/MM').format(d),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: PainelAdminTheme.textoSecundario,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildLojistaShortcuts(double maxW) {
    final gap = 16.0;
    final c1 = _buildShortcutCard(
      titulo: 'Meus pedidos',
      descricao: 'Acompanhe e gerencie seus pedidos.',
      icon: Icons.receipt_long_rounded,
      cor: diPertinRoxo,
      rota: '/meus_pedidos',
    );
    final c2 = _buildShortcutCard(
      titulo: 'Meus produtos',
      descricao: 'Gerencie seu catálogo e estoque.',
      icon: Icons.inventory_2_rounded,
      cor: diPertinLaranja,
      rota: '/meu_cardapio',
    );
    final c3 = _buildShortcutCard(
      titulo: 'Minha carteira',
      descricao: 'Acompanhe seu saldo e repasses.',
      icon: Icons.account_balance_wallet_rounded,
      cor: const Color(0xFF059669),
      rota: '/carteira_loja',
    );

    if (maxW < 700) {
      return Column(
          children: [c1, SizedBox(height: gap), c2, SizedBox(height: gap), c3]);
    }
    return Row(
      children: [
        Expanded(child: c1),
        SizedBox(width: gap),
        Expanded(child: c2),
        SizedBox(width: gap),
        Expanded(child: c3),
      ],
    );
  }

  Widget _buildShortcutCard({
    required String titulo,
    required String descricao,
    required IconData icon,
    required Color cor,
    required String rota,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.navegarPainel(rota),
        borderRadius: BorderRadius.circular(_borderRadiusSmall),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_borderRadiusSmall),
            border: Border.all(color: PainelAdminTheme.dashboardBorder),
            boxShadow: DiPertinTheme.sombraCardSuave(),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      descricao,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: PainelAdminTheme.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// MODELO DE ATIVIDADE
// ═══════════════════════════════════════════════════════════════════

class _ActivityItem {
  final IconData icon;
  final Color color;
  final String name;
  final String description;
  final String time;
  final String type;

  const _ActivityItem({
    required this.icon,
    required this.color,
    required this.name,
    required this.description,
    required this.time,
    required this.type,
  });
}

// ═══════════════════════════════════════════════════════════════════
// BOTÃO GLASS PREMIUM
// ═══════════════════════════════════════════════════════════════════

class _PremiumGlassButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;
  final IconData icon;

  const _PremiumGlassButton({
    required this.onPressed,
    required this.loading,
    required this.label,
    required this.icon,
  });

  @override
  State<_PremiumGlassButton> createState() => _PremiumGlassButtonState();
}

class _PremiumGlassButtonState extends State<_PremiumGlassButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: _hover && widget.onPressed != null
            ? Matrix4.translationValues(0, -1, 0)
            : Matrix4.identity(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: _hover && widget.onPressed != null
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        AnimatedRotation(
                          turns: _hover ? 0.25 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Icon(Icons.refresh_rounded,
                              size: 18, color: Colors.white),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// KPI CARD PREMIUM
// ═══════════════════════════════════════════════════════════════════

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
    final valor =
        widget.customValor ?? (widget.pronto ? widget.count.toString() : '…');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: _hover
            ? Matrix4.translationValues(0, -4, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_borderRadiusSmall),
          boxShadow: _hover ? DiPertinTheme.sombraElevada() : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(_borderRadiusSmall),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_borderRadiusSmall),
                border: Border.all(
                  color: _hover
                      ? widget.cor.withValues(alpha: 0.2)
                      : PainelAdminTheme.dashboardBorder,
                ),
                boxShadow: DiPertinTheme.sombraCardSuave(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ícone e título
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _hover
                              ? widget.cor.withValues(alpha: 0.18)
                              : widget.cor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icone,
                            color: widget.cor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.titulo,
                          style: GoogleFonts.plusJakartaSans(
                            color: PainelAdminTheme.textoSecundario,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Valor
                  Text(
                    valor,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: widget.cor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ],
                  if (widget.onTap != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'Ver detalhes',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: DiPertinTheme.primaryRoxo,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 9,
                          color: DiPertinTheme.primaryRoxo,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
