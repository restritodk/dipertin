import 'dart:async';
import 'dart:math' as math;

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
import '../widgets/botao_suporte_flutuante.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Color diPertinRoxo = PainelAdminTheme.roxo;
  final Color diPertinLaranja = PainelAdminTheme.laranja;

  /// KPIs: marca (roxo/laranja) + neutros — evita “arco-íris”.
  static const Color _kpiNeutro = Color(0xFF64748B);
  static const Color _kpiNeutroEscuro = Color(0xFF475569);

  int _lojasPendentes = 0;
  int _entregadoresPendentes = 0;
  int _kpiTotal = 0;
  int _kpiCliente = 0;
  int _kpiLojista = 0;
  int _kpiEntregador = 0;
  /// Evita tela em branco: layout aparece já; KPIs mostram "…" até o count.
  bool _dashboardReady = false;
  String? _erroCarregamento;
  bool _refreshing = false;

  /// Dashboard “chefe” (KPIs globais + gráfico) — lojista usa visão resumida sem agregações pesadas.
  bool _modoDashboardLojista = false;

  String _perfil = 'master';
  DateTime? _ultimaAtualizacao;

  static const Duration _timeoutDashboard = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    unawaited(_carregarDashboard());
  }

  /// Firestore Web: várias agregações em paralelo + listeners ativos pode disparar
  /// `INTERNAL ASSERTION FAILED` no SDK — consultas em série + retry leve.
  /// Retorna `null` se as duas tentativas falharem.
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

  /// Uma rodada só: pendências + KPIs via [AggregateQuery] (sem baixar `users`).
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
      setState(() {
        _modoDashboardLojista = true;
        _lojasPendentes = 0;
        _entregadoresPendentes = 0;
        _kpiTotal = 0;
        _kpiCliente = 0;
        _kpiLojista = 0;
        _kpiEntregador = 0;
        _dashboardReady = true;
        _erroCarregamento = null;
        _ultimaAtualizacao = DateTime.now();
      });
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

      final total = await _aggregateCountSeguro(
        () => db.collection('users').count().get(),
      );
      if (total == null) erros.add('Total de usuários');
      await _yieldEntreQueriesFirestoreWeb();

      final cli = await _aggregateCountSeguro(
        () => db
            .collection('users')
            .where('role', isEqualTo: 'cliente')
            .count()
            .get(),
      );
      if (cli == null) erros.add('Clientes');
      await _yieldEntreQueriesFirestoreWeb();

      final loj = await _aggregateCountSeguro(
        () => db
            .collection('users')
            .where('role', isEqualTo: 'lojista')
            .count()
            .get(),
      );
      if (loj == null) erros.add('Lojistas');
      await _yieldEntreQueriesFirestoreWeb();

      final ent = await _aggregateCountSeguro(
        () => db
            .collection('users')
            .where('role', isEqualTo: 'entregador')
            .count()
            .get(),
      );
      if (ent == null) erros.add('Entregadores');

      if (!mounted) return;
      setState(() {
        _lojasPendentes = lojasP ?? 0;
        _entregadoresPendentes = entP ?? 0;
        _kpiTotal = total ?? 0;
        _kpiCliente = cli ?? 0;
        _kpiLojista = loj ?? 0;
        _kpiEntregador = ent ?? 0;
        _dashboardReady = true;
        if (erros.isEmpty) {
          _erroCarregamento = null;
        } else if (erros.length >= 4) {
          _erroCarregamento =
              'Várias consultas falharam (${erros.join(", ")}). '
              'Tente o botão Atualizar ou recarregar a página (F5). '
              'No Web, muitos listeners ao mesmo tempo podem gerar erro no Firestore.';
        } else {
          _erroCarregamento =
              'Alguns totais podem estar incompletos: ${erros.join(", ")}.';
        }
        _ultimaAtualizacao = DateTime.now();
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _dashboardReady = true;
        _erroCarregamento =
            'Tempo esgotado ao consultar o Firestore. Verifique a rede ou os índices.';
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

  Future<void> _refreshDashboard() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _carregarDashboard();
    if (mounted) setState(() => _refreshing = false);
  }

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
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return 'Dados atualizados às $h:$m';
  }

  Future<List<String>> getCidadesCadastradas(String? tipo) async {
    try {
      Query query = FirebaseFirestore.instance.collection('users');
      if (tipo != null) query = query.where('role', isEqualTo: tipo);

      final QuerySnapshot snapshot = await query.get(
        const GetOptions(source: Source.server),
      );
      final Set<String> cidades = {};

      for (final doc in snapshot.docs) {
        try {
          final Map<String, dynamic>? dados = doc.data() as Map<String, dynamic>?;
          if (dados != null) {
            final String? nomeCidade =
                dados['cidade']?.toString() ?? dados['Cidade']?.toString();
            if (nomeCidade != null && nomeCidade.trim().isNotEmpty) {
              String cidFormatada = nomeCidade.trim();
              cidFormatada =
                  cidFormatada[0].toUpperCase() +
                  cidFormatada.substring(1).toLowerCase();
              cidades.add(cidFormatada);
            }
          }
        } catch (_) {}
      }
      return cidades.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  static const Color _pendenciaCor = Color(0xFFD97706);

  Widget _buildPendenciaCard(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required String rota,
  }) {
    final color = _pendenciaCor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.navegarPainel(rota),
        borderRadius: BorderRadius.circular(16),
        hoverColor: _pendenciaCor.withOpacity(0.06),
        splashColor: _pendenciaCor.withOpacity(0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(22),
          decoration: PainelAdminTheme.dashboardCard().copyWith(
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        color: PainelAdminTheme.textoSecundario,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count.toString(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: color.withOpacity(0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [tipo] para o diálogo de ranking: null = todos os perfis (filtra por cidade nos docs).
  Widget _cardContadorRanking(
    String titulo,
    String? tipo,
    Color cor,
    int count,
  ) {
    final total = _dashboardReady ? count.toString() : '…';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _dashboardReady ? () => _dialogSelecionarCidade(titulo, tipo) : null,
        borderRadius: BorderRadius.circular(16),
        hoverColor: PainelAdminTheme.roxo.withOpacity(0.04),
        splashColor: PainelAdminTheme.roxo.withOpacity(0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          decoration: PainelAdminTheme.dashboardCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 3,
                    width: 40,
                    decoration: BoxDecoration(
                      color: cor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    titulo,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: PainelAdminTheme.textoSecundario,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    total,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      color: cor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Ver ranking',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PainelAdminTheme.roxo.withOpacity(
                        _dashboardReady ? 1 : 0.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 14,
                    color: PainelAdminTheme.roxo.withOpacity(
                      _dashboardReady ? 0.8 : 0.25,
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

  /// Evita GridView dentro de Column+Scroll (problemas no web). Usa Row/Column.
  Widget _buildKpiGrid(double maxW) {
    const gap = 18.0;
    final w = maxW.isFinite && maxW > 120 ? maxW : 800.0;

    final c1 = _cardContadorRanking(
      'Total usuários',
      null,
      diPertinRoxo,
      _kpiTotal,
    );
    final c2 = _cardContadorRanking(
      'Clientes',
      'cliente',
      _kpiNeutro,
      _kpiCliente,
    );
    final c3 = _cardContadorRanking(
      'Lojistas',
      'lojista',
      diPertinLaranja,
      _kpiLojista,
    );
    final c4 = _cardContadorRanking(
      'Entregadores',
      'entregador',
      _kpiNeutroEscuro,
      _kpiEntregador,
    );

    if (w >= 1000) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: c1),
          SizedBox(width: gap),
          Expanded(child: c2),
          SizedBox(width: gap),
          Expanded(child: c3),
          SizedBox(width: gap),
          Expanded(child: c4),
        ],
      );
    }
    if (w >= 520) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: c1),
              SizedBox(width: gap),
              Expanded(child: c2),
            ],
          ),
          SizedBox(height: gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: c3),
              SizedBox(width: gap),
              Expanded(child: c4),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        c1,
        SizedBox(height: gap),
        c2,
        SizedBox(height: gap),
        c3,
        SizedBox(height: gap),
        c4,
      ],
    );
  }

  Widget _buildPendenciasRow(double maxW) {
    final lojas = _lojasPendentes > 0;
    final ent = _entregadoresPendentes > 0;
    if (!lojas && !ent) return const SizedBox.shrink();

    if (maxW >= 520 && lojas && ent) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildPendenciaCard(
              context,
              title: 'Lojas pendentes',
              count: _lojasPendentes,
              icon: Icons.store_outlined,
              rota: '/lojas',
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildPendenciaCard(
              context,
              title: 'Entregadores pendentes',
              count: _entregadoresPendentes,
              icon: Icons.two_wheeler_outlined,
              rota: '/entregadores',
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lojas) ...[
          _buildPendenciaCard(
            context,
            title: 'Lojas pendentes',
            count: _lojasPendentes,
            icon: Icons.store_outlined,
            rota: '/lojas',
          ),
          if (ent) const SizedBox(height: 16),
        ],
        if (ent)
          _buildPendenciaCard(
            context,
            title: 'Entregadores pendentes',
            count: _entregadoresPendentes,
            icon: Icons.two_wheeler_outlined,
            rota: '/entregadores',
          ),
      ],
    );
  }

  String _labelTipoRanking(String tipo) {
    switch (tipo) {
      case 'cliente':
        return 'Clientes';
      case 'lojista':
        return 'Lojistas';
      case 'entregador':
        return 'Entregadores';
      default:
        return tipo;
    }
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

    final tipoBusca = tipo ?? 'cliente';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: cidades.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dialogTitle(ctx, 'Filtrar $titulo'),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma cidade encontrada para este recorte.',
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Fechar'),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dialogTitle(ctx, 'Filtrar $titulo'),
                        const SizedBox(height: 8),
                        Text(
                          'Selecione a cidade para ver o ranking.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: PainelAdminTheme.textoSecundario,
                          ),
                        ),
                        const SizedBox(height: 20),
                        DropdownMenu<String>(
                          width: math.min(360, MediaQuery.sizeOf(ctx).width - 80),
                          menuHeight: 280,
                          enableFilter: true,
                          requestFocusOnTap: true,
                          label: const Text('Cidade'),
                          leadingIcon: const Icon(Icons.search_rounded),
                          inputDecorationTheme: InputDecorationTheme(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          dropdownMenuEntries: cidades
                              .map(
                                (c) =>
                                    DropdownMenuEntry<String>(value: c, label: c),
                              )
                              .toList(),
                          onSelected: (selecionada) {
                            if (selecionada != null) {
                              Navigator.pop(ctx);
                              _mostrarRanking(selecionada, tipoBusca);
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

  Widget _dialogTitle(BuildContext ctx, String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1E1B4B),
      ),
    );
  }

  void _mostrarRanking(String cidade, String tipo) {
    final label = _labelTipoRanking(tipo);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final screenH = MediaQuery.sizeOf(ctx).height;
        final maxH = math.min(560.0, screenH * 0.88);

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: maxH,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ranking — $label',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E1B4B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              cidade,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Fechar',
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
                        .get(const GetOptions(source: Source.server)),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(48),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Nenhum usuário cadastrado.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        );
                      }

                      final usuarios = snapshot.data!.docs.where((doc) {
                        try {
                          final dados = doc.data() as Map<String, dynamic>;
                          final nomeCid = dados['cidade'] ?? dados['Cidade'];
                          if (nomeCid != null) {
                            return nomeCid.toString().trim().toLowerCase() ==
                                cidade.toLowerCase();
                          }
                        } catch (_) {}
                        return false;
                      }).toList();

                      if (usuarios.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Nenhum usuário encontrado nesta cidade.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        );
                      }

                      usuarios.sort((a, b) {
                        var sA = 0;
                        var sB = 0;
                        try {
                          sA = a.get('totalConcluido');
                        } catch (_) {}
                        try {
                          sB = b.get('totalConcluido');
                        } catch (_) {}
                        return sB.compareTo(sA);
                      });

                      final top10 = usuarios.take(10).toList();
                      final piores = usuarios
                          .where((doc) {
                            var s = 0;
                            try {
                              s = doc.get('totalConcluido');
                            } catch (_) {}
                            return s == 0;
                          })
                          .take(5)
                          .toList();

                      return LayoutBuilder(
                        builder: (context, c) {
                          final narrow = c.maxWidth < 560;
                          final content = narrow
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _rankingPanel(
                                        icon: Icons.emoji_events_outlined,
                                        iconColor: const Color(0xFF059669),
                                        title: 'Maior engajamento',
                                        subtitle: 'Top 10 por atividades concluídas',
                                        child: _listaTop(top10, true),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Expanded(
                                      child: _rankingPanel(
                                        icon: Icons.hourglass_empty_rounded,
                                        iconColor: const Color(0xFFB45309),
                                        title: 'Sem atividade',
                                        subtitle: 'Até 5 contas com zero concluídas',
                                        child: _listaInativos(piores),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _rankingPanel(
                                        icon: Icons.emoji_events_outlined,
                                        iconColor: const Color(0xFF059669),
                                        title: 'Maior engajamento',
                                        subtitle: 'Top 10 por atividades concluídas',
                                        child: _listaTop(top10, true),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _rankingPanel(
                                        icon: Icons.hourglass_empty_rounded,
                                        iconColor: const Color(0xFFB45309),
                                        title: 'Sem atividade',
                                        subtitle: 'Até 5 contas com zero concluídas',
                                        child: _listaInativos(piores),
                                      ),
                                    ),
                                  ],
                                );

                          return Padding(
                            padding: const EdgeInsets.all(20),
                            child: content,
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Fechar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rankingPanel({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withOpacity(0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E1B4B),
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
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _listaTop(List<QueryDocumentSnapshot> top10, bool showRank) {
    return ListView.separated(
      itemCount: top10.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        var nome = 'Sem nome';
        var atv = 0;
        try {
          nome = top10[index].get('nome').toString();
        } catch (_) {}
        try {
          atv = top10[index].get('totalConcluido');
        } catch (_) {}
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: PainelAdminTheme.roxo.withOpacity(0.12),
            child: Text(
              showRank ? '${index + 1}' : '?',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: PainelAdminTheme.roxo,
              ),
            ),
          ),
          title: Text(
            nome,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            'Atividades concluídas: $atv',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        );
      },
    );
  }

  Widget _listaInativos(List<QueryDocumentSnapshot> piores) {
    if (piores.isEmpty) {
      return Center(
        child: Text(
          'Nenhum perfil inativo neste filtro.',
          style: GoogleFonts.plusJakartaSans(
            color: PainelAdminTheme.textoSecundario,
            fontSize: 13,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: piores.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        var nome = 'Sem nome';
        try {
          nome = piores[index].get('nome').toString();
        } catch (_) {}
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            Icons.person_off_outlined,
            color: const Color(0xFFB45309).withOpacity(0.9),
            size: 22,
          ),
          title: Text(
            nome,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            'Zero atividades concluídas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTudoEmDiaCard() {
    return IntrinsicHeight(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: const Color(0xFF22C55E)),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: PainelAdminTheme.dashboardCard(),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF15803D),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nenhuma aprovação pendente',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: const Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Lojas e entregadores estão em dia com as aprovações.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              height: 1.45,
                              color: const Color(0xFF15803D),
                            ),
                          ),
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

  Widget _buildHeroHeader(TextTheme textTheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PainelAdminTheme.dashboardBorder),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visão geral',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _tituloPrincipal,
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.08,
                    color: PainelAdminTheme.dashboardInk,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtituloPagina,
                  style: textTheme.bodyLarge?.copyWith(
                    color: PainelAdminTheme.textoSecundario,
                    height: 1.45,
                  ),
                ),
                if (_ultimaAtualizacao != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _horaAtualizacao(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: PainelAdminTheme.textoSecundario.withOpacity(0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_dashboardReady && !_refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: diPertinRoxo.withValues(alpha: 0.85),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Atualizar dados',
            onPressed: _refreshing ? null : _refreshDashboard,
            icon: _refreshing
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: diPertinRoxo,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: diPertinRoxo, size: 26),
          ),
        ],
      ),
    );
  }

  Widget _atalhoLojistaCard({
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
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: PainelAdminTheme.dashboardCard(),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: cor, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        descricao,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          height: 1.45,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: cor.withValues(alpha: 0.65)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardLojistaAtalhos(double maxW) {
    final narrow = maxW < 520;
    final gap = 16.0;
    final c1 = _atalhoLojistaCard(
      titulo: 'Meus pedidos',
      descricao: 'Acompanhe e atualize o status dos pedidos da sua loja.',
      icon: Icons.receipt_long_rounded,
      cor: diPertinRoxo,
      rota: '/meus_pedidos',
    );
    final c2 = _atalhoLojistaCard(
      titulo: 'Meus produtos',
      descricao: 'Produtos, preços e disponibilidade na vitrine.',
      icon: Icons.inventory_2_rounded,
      cor: diPertinLaranja,
      rota: '/meu_cardapio',
    );
    final c3 = _atalhoLojistaCard(
      titulo: 'Minha carteira',
      descricao: 'Saldo, repasses e configurações de recebimento.',
      icon: Icons.account_balance_wallet_rounded,
      cor: const Color(0xFF059669),
      rota: '/carteira_loja',
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          c1,
          SizedBox(height: gap),
          c2,
          SizedBox(height: gap),
          c3,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: c1),
            SizedBox(width: gap),
            Expanded(child: c2),
          ],
        ),
        SizedBox(height: gap),
        c3,
      ],
    );
  }

  Widget _buildSectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: diPertinRoxo,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: PainelAdminTheme.dashboardInk,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 15),
          child: Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.4,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
        ),
      ],
    );
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
                    final raw = constraints.maxWidth;
                    final maxW = (!raw.isFinite || raw < 120)
                        ? (mq.width - 2 * padH).clamp(280.0, 1280.0)
                        : raw;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_erroCarregamento != null &&
                            !_modoDashboardLojista) ...[
                          Material(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.red.shade700,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Não foi possível carregar todos os números do dashboard. '
                                      'Confira o console (F12) ou os índices do Firestore. '
                                      'Detalhe: ${_erroCarregamento!}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: const Color(0xFF9F1239),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        _buildHeroHeader(textTheme),
                        const SizedBox(height: 28),

                        if (_modoDashboardLojista && _dashboardReady) ...[
                          _buildSectionHeading(
                            'Atalhos',
                            'Acesso rápido às áreas da sua loja.',
                          ),
                          const SizedBox(height: 20),
                          _buildDashboardLojistaAtalhos(maxW),
                          const SizedBox(height: 48),
                        ] else if (!_modoDashboardLojista) ...[
                        if (_lojasPendentes > 0 ||
                            _entregadoresPendentes > 0) ...[
                          IntrinsicHeight(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 4,
                                    color: diPertinLaranja,
                                  ),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.all(22),
                                      decoration:
                                          PainelAdminTheme.dashboardCard(),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: diPertinLaranja
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Icon(
                                              Icons
                                                  .notifications_active_rounded,
                                              color: diPertinLaranja,
                                              size: 28,
                                            ),
                                          ),
                                          const SizedBox(width: 18),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Atenção requerida',
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    color: const Color(
                                                      0xFFC2410C,
                                                    ),
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Existem aprovações pendentes aguardando sua análise para entrarem no aplicativo.',
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    color: const Color(
                                                      0xFF9A3412,
                                                    ),
                                                    fontSize: 14,
                                                    height: 1.45,
                                                  ),
                                                ),
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
                          ),
                          const SizedBox(height: 16),
                          _buildPendenciasRow(maxW),
                          const SizedBox(height: 36),
                        ] else ...[
                          _buildTudoEmDiaCard(),
                          const SizedBox(height: 36),
                        ],

                        _buildSectionHeading(
                          'Desempenho e rankings',
                          'Visão consolidada de usuários por perfil.',
                        ),
                        const SizedBox(height: 20),
                        _buildKpiGrid(maxW),
                        const SizedBox(height: 40),

                        _buildSectionHeading(
                          'Módulo financeiro',
                          'Receitas e movimentações do ecossistema.',
                        ),
                        const SizedBox(height: 18),
                        IntrinsicHeight(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: 4,
                                  color: const Color(0xFF059669),
                                ),
                                Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => context
                                          .navegarPainel('/financeiro'),
                                      hoverColor: const Color(0xFF059669)
                                          .withValues(alpha: 0.05),
                                      splashColor: const Color(0xFF059669)
                                          .withValues(alpha: 0.1),
                                      child: Ink(
                                        decoration:
                                            PainelAdminTheme.dashboardCard(),
                                        child: Padding(
                                          padding: const EdgeInsets.all(22),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(14),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFECFDF5,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: const Icon(
                                                  Icons
                                                      .account_balance_rounded,
                                                  color: Color(0xFF059669),
                                                  size: 30,
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Visão financeira',
                                                      style: GoogleFonts
                                                          .plusJakartaSans(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 17,
                                                        color: const Color(
                                                          0xFF047857,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      'Gerencie receitas de destaques, vitrine, telefones premium e assinaturas.',
                                                      style: GoogleFonts
                                                          .plusJakartaSans(
                                                        color: const Color(
                                                          0xFF065F46,
                                                        ),
                                                        fontSize: 14,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                Icons.arrow_forward_rounded,
                                                color: Color(0xFF059669),
                                                size: 22,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildGraficoPedidos(),
                        const SizedBox(height: 48),
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
      floatingActionButton: const BotaoSuporteFlutuante(),
    );
  }

  // ─── Gráfico de pedidos últimos 7 dias ─────────────────────────────────────

  Widget _buildGraficoPedidos() {
    final hoje = DateTime.now();
    final diasLabel = List.generate(
        7,
        (i) => DateTime(
            hoje.year, hoje.month, hoje.day - (6 - i)));

    return FutureBuilder<List<int>>(
      future: _contarPedidosPorDia(diasLabel),
      builder: (context, snap) {
        final counts = snap.data ?? List.filled(7, 0);
        final maxY =
            counts.fold<int>(0, (a, b) => a > b ? a : b).toDouble();
        final yMax = maxY < 5 ? 5.0 : (maxY * 1.2).ceilToDouble();

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: diPertinRoxo.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.bar_chart_rounded,
                        color: diPertinRoxo, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedidos — últimos 7 dias',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: diPertinRoxo,
                        ),
                      ),
                      Text(
                        'Total de pedidos criados por dia',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 200,
                child: snap.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : BarChart(
                        BarChartData(
                          maxY: yMax,
                          minY: 0,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: yMax / 4,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: const Color(0xFFE2E8F0),
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
                                reservedSize: 32,
                                getTitlesWidget: (v, _) => Text(
                                  v.toInt().toString(),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8)),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                getTitlesWidget: (x, _) {
                                  final idx = x.toInt();
                                  if (idx < 0 || idx >= diasLabel.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final d = diasLabel[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      DateFormat('dd/MM').format(d),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF94A3B8)),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: List.generate(
                            7,
                            (i) => BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: counts[i].toDouble(),
                                  width: 28,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6)),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      diPertinLaranja.withValues(alpha: 0.7),
                                      diPertinLaranja,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => diPertinRoxo,
                              getTooltipItem: (group, _, rod, __) =>
                                  BarTooltipItem(
                                '${rod.toY.toInt()} pedidos',
                                const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
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

  Future<List<int>> _contarPedidosPorDia(List<DateTime> dias) async {
    final db = FirebaseFirestore.instance;
    final result = <int>[];
    for (final dia in dias) {
      final inicio = Timestamp.fromDate(dia);
      final fim = Timestamp.fromDate(
          DateTime(dia.year, dia.month, dia.day, 23, 59, 59));
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
}
