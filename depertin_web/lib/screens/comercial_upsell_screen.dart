import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../navigation/painel_navigation_scope.dart';
import '../theme/painel_admin_theme.dart';
import '../services/assinatura_gestao_comercial_refresh.dart';
import '../widgets/assinatura_pagamento_modal.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  PALETA — alinhada ao dashboard principal (DiPertinTheme)
// ═══════════════════════════════════════════════════════════════════════════
abstract final class _P {
  static const bg = DiPertinTheme.backgroundFundo;
  static const card = DiPertinTheme.surfaceCard;
  static const cardInner = Color(0xFFF8F7FC);
  static const borda = DiPertinTheme.borderDefault;
  static const bordaSuave = DiPertinTheme.borderSoft;
  static const texto = DiPertinTheme.textPrimary;
  static const textoMuted = DiPertinTheme.textSecondary;
  static const roxo = DiPertinTheme.primaryRoxo;
  static const roxoClaro = DiPertinTheme.primaryRoxoClaro;
  static const laranja = DiPertinTheme.secondaryLaranja;
  static const sucesso = Color(0xFF22C55E);
  static const erro = DiPertinTheme.errorRedAlt;

  static const glowRoxo = Color(0x266A1B9A);

  static const dashBg = DiPertinTheme.surfaceCard;
  static const dashBorda = DiPertinTheme.borderDefault;

  static const List<Color> gradBtn = [
    DiPertinTheme.primaryRoxoEscuro,
    DiPertinTheme.primaryRoxo,
    DiPertinTheme.secondaryLaranja,
  ];
  static const List<Color> gradTtl = [
    DiPertinTheme.primaryRoxo,
    DiPertinTheme.secondaryLaranja,
  ];
  static const List<Color> gradChart = [
    DiPertinTheme.primaryRoxo,
    DiPertinTheme.secondaryLaranja,
  ];

  /// Gradiente premium (login/dashboard hero): roxo → laranja
  static const LinearGradient gradPremium = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      DiPertinTheme.primaryRoxoEscuro,
      DiPertinTheme.primaryRoxo,
      DiPertinTheme.primaryRoxoClaro,
      DiPertinTheme.secondaryLaranja,
    ],
    stops: [0.0, 0.35, 0.72, 1.0],
  );

  static List<BoxShadow> sombraGradPremium() => [
        BoxShadow(
          color: DiPertinTheme.primaryRoxoEscuro.withValues(alpha: 0.28),
          blurRadius: 32,
          offset: const Offset(0, 12),
          spreadRadius: -4,
        ),
      ];

  static BoxDecoration decoGradIcon({double radius = 12}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  WIDGET PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════
class ComercialUpsellScreen extends StatefulWidget {
  const ComercialUpsellScreen({super.key});

  @override
  State<ComercialUpsellScreen> createState() => _ComercialUpsellScreenState();
}

class _ComercialUpsellScreenState extends State<ComercialUpsellScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _planos = [];
  bool _carregandoPlanos = true;
  bool _erroPlanos = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeIn;

  // Hover states
  bool _benefHover0 = false, _benefHover1 = false, _benefHover2 = false;
  bool _benefHover3 = false, _benefHover4 = false, _benefHover5 = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
    _iniciar();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    await _carregarPlanos();
  }

  Future<void> _carregarPlanos() async {
    try {
      setState(() {
        _carregandoPlanos = true;
        _erroPlanos = false;
      });
      final snap = await FirebaseFirestore.instance
          .collection('modulos_planos')
          .where('ativo', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 10));
      final planos = snap.docs
          .map((d) => <String, dynamic>{
            'id': d.id,
            ...d.data(),
          })
          .toList();
      if (mounted) {
        setState(() {
          _planos = planos;
          _carregandoPlanos = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Upsell] erro planos: $e');
      if (mounted) {
        setState(() {
          _erroPlanos = true;
          _carregandoPlanos = false;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CONTRATAR PLANO DIRETO (pula modal de planos)
  // ═══════════════════════════════════════════════════════════════════════
  void _contratarPlano(Map<String, dynamic> plano) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final email = user?.email ?? '';

    _carregarDadosLojista().then((dados) {
      if (!mounted) return;
      AssinaturaPagamentoModal.mostrar(
        context,
        plano: plano,
        lojaId: uid,
        lojaNome: dados['lojaNome'] ?? _lojaNome ?? '',
        ownerName: dados['ownerName'] ?? '',
        ownerEmail: email,
        onPagamentoAprovado: _recarregarAposPagamento,
      );
    });
  }

  void _recarregarAposPagamento() {
    AssinaturaGestaoComercialRefresh.instance.notificarPagamentoAprovado();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.navegarPainel('/comercial_dashboard');
      } catch (_) {
        // Gate e sidebar recarregam via notifier.
      }
    });
  }

  String? _lojaNome;

  Future<Map<String, String>> _carregarDadosLojista() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return {};
      final d = doc.data() ?? {};
      final nome = d['nome']?.toString() ?? d['nome_completo']?.toString() ?? d['displayName']?.toString() ?? '';
      _lojaNome = d['nome_loja']?.toString() ?? d['loja_nome']?.toString() ?? nome;
      return {
        'lojaNome': _lojaNome ?? '',
        'ownerName': nome,
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.bg,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_carregandoPlanos && _planos.isEmpty) return _buildSkeletonCarregando();
    return _buildUpsellLayout();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UPSELL LAYOUT COMPLETO
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildUpsellLayout() {
    return FadeTransition(
      opacity: _fadeIn,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HERO: duas colunas
              _buildHero(),
              const SizedBox(height: 56),

              // CARDS BENEFÍCIOS
              _buildSecaoBeneficios(),
              const SizedBox(height: 56),

              // SEÇÃO PLANOS OU ESTADOS
              _buildSecaoPlanosOuEstado(),
              const SizedBox(height: 56),

              // RODAPÉ PREMIUM
              _buildRodapePremium(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecaoPlanosOuEstado() {
    if (_carregandoPlanos) return _buildSkeletonPlanos();
    if (_erroPlanos) return _buildEstadoErroPlanos();
    if (_planos.isEmpty) return _buildNenhumPlanoDisponivel();
    return _buildSecaoPlanos(_planos);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HERO — DUAS COLUNAS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildHero() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final larga = constraints.maxWidth >= 1100;
        return larga ? _heroLinha() : _heroColuna();
      },
    );
  }

  Widget _heroLinha() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: _heroConteudo()),
        const SizedBox(width: 48),
        Expanded(flex: 6, child: _buildDashboardMockup()),
      ],
    );
  }

  Widget _heroColuna() {
    return Column(
      children: [
        _heroConteudo(),
        const SizedBox(height: 40),
        _buildDashboardMockup(),
      ],
    );
  }

  // ─── LADO ESQUERDO: CONTEÚDO ───
  Widget _heroConteudo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Badge premium
        _buildBadge(),
        const SizedBox(height: 24),

        // Título
        _buildTitulo(),
        const SizedBox(height: 18),

        // Subtexto
        Text(
          'Venda mais, controle melhor e tenha uma visão completa do '
          'desempenho financeiro da sua empresa utilizando ferramentas '
          'profissionais.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            color: _P.textoMuted,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 28),

        // Checklist
        _buildCheckList(),
        const SizedBox(height: 20),

        // Texto seguro
        Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: _P.textoMuted),
            const SizedBox(width: 8),
            Text(
              'Módulo exclusivo para lojistas Premium',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _P.textoMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _P.roxo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _P.roxo.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 13, color: _P.laranja),
          const SizedBox(width: 7),
          Text(
            'MÓDULO PREMIUM',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _P.laranja,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitulo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gestão Comercial\npara ',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 44,
            fontWeight: FontWeight.w800,
            color: _P.texto,
            height: 1.12,
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: _P.gradTtl,
          ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
          blendMode: BlendMode.srcIn,
          child: Text(
            'sua loja',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              decoration: TextDecoration.none,
              height: 1.12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckList() {
    final itens = [
      'PDV completo com emissão de NFC-e',
      'Controle de crédito e pendências',
      'Histórico completo de vendas',
      'Gestão de recebimentos e pagamentos',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: itens
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _P.sucesso.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: _P.sucesso.withValues(alpha: 0.15),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child:
                          const Icon(Icons.check_rounded, size: 15, color: _P.sucesso),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      t,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        color: _P.texto,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LADO DIREITO — DASHBOARD MOCKUP
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDashboardMockup() {
    return Container(
      decoration: BoxDecoration(
        color: _P.dashBg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _P.dashBorda),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // System bar
            _dashSystemBar(),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  _dashTitleRow(),
                  const SizedBox(height: 18),
                  // KPI cards
                  _dashKpiRow(),
                  const SizedBox(height: 18),
                  // Main area chart + activities
                  _dashMainArea(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashSystemBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _P.dashBg,
        border: Border(bottom: BorderSide(color: _P.dashBorda)),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _P.roxo,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.grid_view_rounded, size: 13, color: _P.texto),
              ),
              const SizedBox(width: 8),
              Text(
                'DiPertin',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _P.texto,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.notifications_outlined, size: 18, color: _P.textoMuted),
          const SizedBox(width: 16),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _P.roxo.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _P.roxo.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.person_outline, size: 16, color: _P.roxoClaro),
          ),
        ],
      ),
    );
  }

  Widget _dashTitleRow() {
    return Row(
      children: [
        Text(
          'Resumo Comercial',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _P.texto,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _P.cardInner,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _P.borda),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Últimos 7 dias',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: _P.textoMuted,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: _P.textoMuted),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dashKpiRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final small = constraints.maxWidth < 500;
        final cards = [
              ('Vendas hoje', 'R\$ 8.420,50', '+12,5%', true),
              ('Recebimentos', 'R\$ 6.180,30', '+8,3%', true),
              ('Pendências', 'R\$ 2.240,20', '-5,7%', false),
              ('Clientes ativos', '1.236', '+9,2%', true),
            ];
        if (small) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cards.map((c) {
              return SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _dashKpiCard(c.$1, c.$2, c.$3, c.$4),
              );
            }).toList(),
          );
        }
        return Row(
          children: cards
              .map((c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _dashKpiCard(c.$1, c.$2, c.$3, c.$4),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _dashKpiCard(String label, String valor, String variacao, bool positivo) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _P.cardInner,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _P.bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: _P.textoMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _P.texto,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                positivo ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 12,
                color: positivo ? _P.sucesso : _P.erro,
              ),
              const SizedBox(width: 3),
              Text(
                variacao,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: positivo ? _P.sucesso : _P.erro,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── ÁREA PRINCIPAL: GRÁFICO + ATIVIDADES ───
  Widget _dashMainArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final empilhado = constraints.maxWidth < 400;
        if (empilhado) {
          return Column(
            children: [
              _dashGraficoMock(),
              const SizedBox(height: 16),
              _dashAtividades(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _dashGraficoMock()),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: _dashAtividades()),
          ],
        );
      },
    );
  }

  Widget _dashGraficoMock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _P.cardInner,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _P.bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Evolução de vendas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _P.texto,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 100,
            child: CustomPaint(
              size: const Size(double.infinity, 100),
              painter: _ChartLinePainter(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']
                .map((d) => Text(
                      d,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        color: _P.textoMuted.withValues(alpha: 0.5),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _dashAtividades() {
    final atividades = [
      ('Pagamento recebido', 'R\$ 1.240,00', 'Há 12 min', _P.sucesso, Icons.arrow_downward_rounded),
      ('Venda realizada', 'R\$ 89,90', 'Há 38 min', _P.roxoClaro, Icons.shopping_bag_rounded),
      ('Nova pendência', 'R\$ 320,00', 'Há 1 h', _P.laranja, Icons.warning_amber_rounded),
      ('Crédito concedido', 'R\$ 500,00', 'Há 2 h', _P.roxo, Icons.credit_card_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _P.cardInner,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _P.bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Atividades recentes',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _P.texto,
            ),
          ),
          const SizedBox(height: 16),
          ...atividades.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: a.$4.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(a.$5, size: 15, color: a.$4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.$1,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _P.texto)),
                          Text(a.$3,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9.5, color: _P.textoMuted)),
                        ],
                      ),
                    ),
                    Text(a.$2,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _P.texto)),
                  ],
                ),
              )),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.arrow_forward_rounded, size: 13, color: _P.roxoClaro),
            label: Text(
              'Ver todas atividades',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: _P.roxoClaro, fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SEÇÃO BENEFÍCIOS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildSecaoBeneficios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tudo que sua loja precisa em um só lugar',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _P.texto,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final large = constraints.maxWidth >= 900;
            final colunas = large ? 3 : (constraints.maxWidth >= 600 ? 2 : 1);
            return _buildGridBeneficios(colunas, large);
          },
        ),
      ],
    );
  }

  Widget _buildGridBeneficios(int colunas, bool large) {
    final beneficios = <_Beneficio>[
      _Beneficio(Icons.point_of_sale_rounded, 'PDV Completo',
          'Sistema de vendas rápido e intuitivo com emissão de NFC-e.'),
      _Beneficio(Icons.credit_score_rounded, 'Controle de Crédito',
          'Gerencie limites, acompanhe pendências e evite inadimplência.'),
      _Beneficio(Icons.bar_chart_rounded, 'Relatórios Avançados',
          'Gráficos e indicadores de desempenho para decisões estratégicas.'),
      _Beneficio(Icons.receipt_long_rounded, 'Histórico Completo',
          'Consulte todas as vendas, recebimentos e extratos detalhados.'),
      _Beneficio(Icons.notifications_active_rounded, 'Alertas Inteligentes',
          'Receba notificações sobre pendências, vencimentos e mais.'),
    ];

    final linhas = <Widget>[];
    // 5 cards normais
    for (var row = 0; row < beneficios.length; row += colunas) {
      final fim = (row + colunas).clamp(0, beneficios.length);
      final fatia = beneficios.sublist(row, fim);
      linhas.add(Padding(
        padding: EdgeInsets.only(bottom: row + colunas < beneficios.length ? 16 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: fatia.asMap().entries.map((e) {
            final idx = row + e.key;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: e.key > 0 ? 10 : 0,
                  right: e.key < fatia.length - 1 ? 10 : 0,
                ),
                child: _CardBeneficio(
                  beneficio: e.value,
                  isHovered: idx == 0
                      ? _benefHover0
                      : idx == 1
                          ? _benefHover1
                          : idx == 2
                              ? _benefHover2
                              : idx == 3
                                  ? _benefHover3
                                  : _benefHover4,
                  onEnter: () => _setBenefHover(idx, true),
                  onExit: () => _setBenefHover(idx, false),
                ),
              ),
            );
          }).toList(),
        ),
      ));
    }

    // Card especial (ocupa largura total)
    linhas.add(const SizedBox(height: 16));
    linhas.add(
      MouseRegion(
        onEnter: (_) => setState(() => _benefHover5 = true),
        onExit: (_) => setState(() => _benefHover5 = false),
        child: _CardEspecial(isHovered: _benefHover5),
      ),
    );

    return Column(children: linhas);
  }

  void _setBenefHover(int idx, bool val) {
    setState(() {
      if (idx == 0) _benefHover0 = val;
      if (idx == 1) _benefHover1 = val;
      if (idx == 2) _benefHover2 = val;
      if (idx == 3) _benefHover3 = val;
      if (idx == 4) _benefHover4 = val;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  RODAPÉ PREMIUM
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildRodapePremium() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: _P.gradPremium,
        boxShadow: _P.sombraGradPremium(),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final empilhado = constraints.maxWidth < 500;
          if (empilhado) {
            return Column(
              children: [_footerItem(Icons.shield_rounded, 'Segurança e confiabilidade', 'Seus dados protegidos com criptografia e backup automático.'), const SizedBox(height: 20), _footerItem(Icons.computer_rounded, 'Acesso em todos os dispositivos', 'Use no computador, tablet ou celular quando e onde quiser.')],
            );
          }
          return Row(
            children: [
              Expanded(
                child: _footerItem(Icons.shield_rounded, 'Segurança e confiabilidade',
                    'Seus dados protegidos com criptografia e backup automático.'),
              ),
              const SizedBox(width: 40),
              Expanded(
                child: _footerItem(Icons.computer_rounded, 'Acesso em todos os dispositivos',
                    'Use no computador, tablet ou celular quando e onde quiser.'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _footerItem(IconData icone, String titulo, String desc) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: _P.decoGradIcon(radius: 12),
          child: Icon(icone, size: 22, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text(desc,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.82))),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SEÇÃO PLANOS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildSecaoPlanos(List<Map<String, dynamic>> planos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Cabeçalho premium ──
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_P.roxo, _P.roxoClaro],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _P.roxo.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  size: 22, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Escolha o plano ideal para seu negócio',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _P.texto,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ative o Gestão Comercial e tenha recursos premium para sua loja',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _P.textoMuted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 28),
        LayoutBuilder(builder: (_, constraints) {
          final larguraDisponivel = constraints.maxWidth;
          double cardWidth;
          if (larguraDisponivel >= 900) {
            cardWidth = 380;
          } else if (larguraDisponivel >= 600) {
            cardWidth = (larguraDisponivel - 16) / 2;
          } else {
            cardWidth = larguraDisponivel;
          }
          cardWidth = cardWidth.clamp(340.0, 420.0);

          return Center(
            child: Wrap(
              spacing: 16,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              children: planos.asMap().entries.map((entry) {
                final idx = entry.key;
                final p = entry.value;
                return SizedBox(
                  width: cardWidth,
                  child: _CardPlano(
                    dados: p,
                    recomendado: planos.length > 1 && idx == 1,
                    onContratar: () => _contratarPlano(p),
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _CardBeneficio
// ═══════════════════════════════════════════════════════════════════════════
class _Beneficio {
  final IconData icone;
  final String titulo;
  final String descricao;
  const _Beneficio(this.icone, this.titulo, this.descricao);
}

class _CardBeneficio extends StatelessWidget {
  final _Beneficio beneficio;
  final bool isHovered;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  const _CardBeneficio({
    required this.beneficio,
    required this.isHovered,
    required this.onEnter,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        transform: isHovered ? Matrix4.translationValues(0, -6, 0) : Matrix4.identity(),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _P.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isHovered ? _P.roxo.withValues(alpha: 0.25) : _P.borda,
          ),
          boxShadow: isHovered
              ? [
                  BoxShadow(
                    color: _P.glowRoxo,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : PainelAdminTheme.sombraCardSuave(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _P.roxo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(beneficio.icone, size: 22, color: _P.roxoClaro),
                ),
                Icon(Icons.arrow_forward_rounded,
                    size: 16,
                    color: isHovered ? _P.roxoClaro : _P.textoMuted.withValues(alpha: 0.3)),
              ],
            ),
            const SizedBox(height: 16),
            Text(beneficio.titulo,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _P.texto)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Text(beneficio.descricao,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: _P.textoMuted, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _CardEspecial
// ═══════════════════════════════════════════════════════════════════════════
class _CardEspecial extends StatelessWidget {
  final bool isHovered;
  const _CardEspecial({required this.isHovered});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      transform: isHovered ? Matrix4.translationValues(0, -6, 0) : Matrix4.identity(),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: _P.gradPremium,
        boxShadow: _P.sombraGradPremium(),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: _P.decoGradIcon(radius: 14),
            child: const Icon(Icons.workspace_premium_rounded,
                size: 30, color: Colors.white),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transforme a gestão da sua loja em resultados.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mais controle. Mais segurança. Mais crescimento para o seu negócio.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
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

// ═══════════════════════════════════════════════════════════════════════════
//  _CardPlano — Card premium estilo SaaS (altura padronizada)
// ═══════════════════════════════════════════════════════════════════════════

/// Altura fixa para todos os cards de plano (compacta e elegante)
const double _cardPlanoAltura = 560.0;

/// Espaçamento interno padrão entre elementos do card
const double _cardPlanoPadding = 24.0;

/// Espaço entre badge "Mais popular" e nome do plano
const double _cardPlanoBadgeMarginBottom = 12.0;

/// Espaço entre elementos internos
const double _cardPlanoSpacer = 6.0;

/// Espaço maior entre seções
const double _cardPlanoSpacerLarge = 16.0;

/// Espaço entre lista de módulos e botão
const double _cardPlanoModulosBotao = 20.0;
class _CardPlano extends StatefulWidget {
  final Map<String, dynamic> dados;
  final bool recomendado;
  final VoidCallback? onContratar;

  const _CardPlano({
    required this.dados,
    this.recomendado = false,
    this.onContratar,
  });

  @override
  State<_CardPlano> createState() => _CardPlanoState();
}

class _CardPlanoState extends State<_CardPlano> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dados = widget.dados;
    final nome = dados['nome']?.toString() ?? 'Plano';
    final descricao = dados['descricao']?.toString() ?? '';
    final valor = (dados['valor'] as num?)?.toDouble() ?? 0;
    final vs = NumberFormat('#,##0.00', 'pt_BR').format(valor);
    final modulos = List<String>.from(dados['modulos'] as List? ?? []);
    final tipoRec = dados['tipo_recorrencia']?.toString() ?? 'Mensal';
    final duracaoDias = (dados['duracao_dias'] as num?)?.toInt() ?? 30;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        transform: _hover
            ? Matrix4.translationValues(0, -6, 0)
            : Matrix4.identity(),
        child: Container(
          height: _cardPlanoAltura,
          padding: const EdgeInsets.all(_cardPlanoPadding),
          decoration: BoxDecoration(
            color: _P.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.recomendado
                  ? _P.roxo.withValues(alpha: 0.4)
                  : _P.bordaSuave,
              width: widget.recomendado ? 1.5 : 1,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: _P.glowRoxo,
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                      spreadRadius: -2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              // ── Badge "Mais popular" ──
              if (widget.recomendado)
                Container(
                  margin: const EdgeInsets.only(bottom: _cardPlanoBadgeMarginBottom),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [_P.roxo, _P.roxoClaro, _P.laranja],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _P.roxo.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'MAIS POPULAR',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Nome do plano ──
              Text(
                nome,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _P.texto,
                ),
              ),

              // ── Descrição ──
              if (descricao.isNotEmpty) ...[
                const SizedBox(height: _cardPlanoSpacer),
                Text(
                  descricao,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: _P.textoMuted,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: _cardPlanoSpacerLarge),

              // ── Preço ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'R\$ ',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _P.textoMuted,
                    ),
                  ),
                  Text(
                    vs,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: _P.texto,
                      height: 1.0,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Text(
                      '/mês',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: _P.textoMuted,
                      ),
                    ),
                  ),
                ],
              ),

              // ── Informação de cobrança ──
              const SizedBox(height: _cardPlanoSpacer),
              Text(
                duracaoDias > 0
                    ? (tipoRec == 'Mensal'
                        ? 'Cobrança mensal · Cancele quando quiser'
                        : 'A cada $duracaoDias dias')
                    : 'Cobrança única',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: _P.textoMuted.withValues(alpha: 0.7),
                ),
              ),

              // ── Divisor ──
              const Padding(
                padding: EdgeInsets.symmetric(vertical: _cardPlanoSpacerLarge),
                child: Divider(height: 1, color: _P.bordaSuave),
              ),

              // ── Módulos inclusos ──
              if (modulos.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _P.roxoClaro,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Módulos inclusos:',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _P.texto,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Layout inteligente: 1 ou 2 colunas conforme quantidade
                _buildModulosLayout(modulos),
              ],

              // ── Spacer: empurra o botão para a parte inferior do card ──
              const Spacer(),

              // ── Botão (ancorado na parte inferior) ──
              SizedBox(
                width: double.infinity,
                height: 48,
                child: _BotaoGradiente(
                  label: 'Contratar este plano',
                  onTap: widget.onContratar ?? () {},
                  largura: double.infinity,
                ),
              ),

              // ── Margem inferior após o botão ──
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Constrói o layout de módulos: 1 ou 2 colunas conforme quantidade.
  Widget _buildModulosLayout(List<String> modulos) {
    if (modulos.length <= 4) {
      // Uma coluna simples
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: modulos.asMap().entries.map((entry) {
          return _buildModuloItem(entry.value, entry.key, modulos.length);
        }).toList(),
      );
    } else {
      // Duas colunas: divide automaticamente (primeira coluna = ceil(n/2))
      final metade = (modulos.length / 2).ceil();
      final colunaEsquerda = modulos.sublist(0, metade);
      final colunaDireita = modulos.sublist(metade);

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coluna esquerda
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: colunaEsquerda.asMap().entries.map((entry) {
                return _buildModuloItem(entry.value, entry.key, colunaEsquerda.length);
              }).toList(),
            ),
          ),
          const SizedBox(width: 16),
          // Coluna direita
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: colunaDireita.asMap().entries.map((entry) {
                return _buildModuloItem(entry.value, entry.key, colunaDireita.length);
              }).toList(),
            ),
          ),
        ],
      );
    }
  }

  /// Constrói um item individual de módulo.
  Widget _buildModuloItem(String modulo, int index, int totalNaColuna) {
    return Padding(
      padding: EdgeInsets.only(bottom: index < totalNaColuna - 1 ? 8 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _P.sucesso.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.check_rounded, size: 11, color: _P.sucesso),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              modulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _P.texto,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _BotaoGradiente
// ═══════════════════════════════════════════════════════════════════════════
class _BotaoGradiente extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final double largura;

  const _BotaoGradiente({
    required this.label,
    required this.onTap,
    this.largura = double.infinity,
  });

  @override
  State<_BotaoGradiente> createState() => _BotaoGradienteState();
}

class _BotaoGradienteState extends State<_BotaoGradiente> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        transform: _hover ? (Matrix4.diagonal3Values(1.03, 1.03, 1)) : Matrix4.identity(),
        width: widget.largura,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: _P.gradBtn,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                      color: _P.glowRoxo.withValues(alpha: 0.35),
                      blurRadius: 20,
                      spreadRadius: 2),
                ]
              : [],
        ),
        child: ElevatedButton(
          onPressed: widget.onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// (restante das classes do modal removido)

// ═══════════════════════════════════════════════════════════════════════════
//  ChartLinePainter
// ═══════════════════════════════════════════════════════════════════════════
class _ChartLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      Offset(size.width * 0.05, size.height * 0.65),
      Offset(size.width * 0.2, size.height * 0.5),
      Offset(size.width * 0.35, size.height * 0.7),
      Offset(size.width * 0.5, size.height * 0.35),
      Offset(size.width * 0.65, size.height * 0.55),
      Offset(size.width * 0.8, size.height * 0.25),
      Offset(size.width * 0.95, size.height * 0.4),
    ];

    // Grid
    final gridPaint = Paint()
      ..color = _P.bordaSuave
      ..strokeWidth = 0.5;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Fill gradient abaixo da linha
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          _P.roxo.withValues(alpha: 0.25),
          _P.laranja.withValues(alpha: 0.12),
          const Color(0x00000000),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Linha
    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: _P.gradChart,
      ).createShader(Rect.fromLTWH(0, 0, size.width, 4))
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      if (i == 0) {
        linePath.moveTo(points[i].dx, points[i].dy);
      } else {
        final prev = points[i - 1];
        final ctrl1 = Offset((prev.dx + points[i].dx) / 2, prev.dy);
        final ctrl2 = Offset((prev.dx + points[i].dx) / 2, points[i].dy);
        linePath.cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(linePath, linePaint);

    // Pontos
    for (final p in points) {
      canvas.drawCircle(p, 3, Paint()..color = _P.roxoClaro);
      canvas.drawCircle(p, 1.5, Paint()..color = _P.texto);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  ESTADOS SECUNDÁRIOS
// ═══════════════════════════════════════════════════════════════════════════
Widget _buildNenhumPlanoDisponivel() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
    decoration: BoxDecoration(
      color: _P.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _P.bordaSuave),
      boxShadow: PainelAdminTheme.sombraCardSuave(),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _P.roxo.withValues(alpha: 0.1),
                _P.roxo.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _P.roxo.withValues(alpha: 0.12)),
          ),
          child: Icon(Icons.widgets_outlined,
              size: 34, color: _P.roxo.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 24),
        Text('Nenhum plano disponível no momento',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _P.texto)),
        const SizedBox(height: 12),
        Text(
          'Ainda não há planos cadastrados para o Gestão Comercial.\n'
          'Entre em contato com o suporte para mais informações.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _P.textoMuted, height: 1.6),
        ),
      ],
    ),
  );
}

Widget _buildEstadoErroPlanos() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: _P.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _P.erro.withValues(alpha: 0.2)),
      boxShadow: PainelAdminTheme.sombraCardSuave(),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _P.erro.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.cloud_off_rounded,
              size: 28, color: _P.erro),
        ),
        const SizedBox(height: 18),
        Text('Erro ao carregar planos',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _P.texto)),
        const SizedBox(height: 10),
        Text(
          'Não foi possível carregar a lista de planos. '
          'Verifique sua conexão e tente novamente.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: _P.textoMuted, height: 1.6),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  SKELETON
// ═══════════════════════════════════════════════════════════════════════════
Widget _buildSkeletonCarregando() {
  return const Center(
    child: CircularProgressIndicator(color: _P.roxo),
  );
}

Widget _buildSkeletonPlanos() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _skeletonBox(width: 360, height: 28),
      const SizedBox(height: 12),
      _skeletonBox(width: 280, height: 16),
      const SizedBox(height: 32),
      Row(
        children: List.generate(
          3,
          (_) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _skeletonBox(height: 340),
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _skeletonBox({double? width, required double height}) {
  return Container(
    width: width ?? double.infinity,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: _P.bordaSuave,
      border: Border.all(color: _P.borda),
    ),
  );
}
