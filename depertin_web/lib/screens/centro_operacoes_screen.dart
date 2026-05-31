// Centro de operações — hub de gestão (CRM, agenda, simulador de frete).

import 'dart:math' show max, min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:depertin_web/screens/centro_operacoes_agenda_panel.dart';
import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Paleta própria do hub (diferente do restante do painel, discreta e legível).
abstract final class _CofTheme {
  static const Color sidebar = Color(0xFF0F172A);
  static const Color sidebarBorder = Color(0xFF1E293B);
  static const Color sidebarMuted = Color(0xFF94A3B8);
  static const Color accent = Color(0xFFF59E0B);
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color cardBorder = Color(0xFFE2E8F0);
}

class CentroOperacoesScreen extends StatefulWidget {
  const CentroOperacoesScreen({super.key});

  @override
  State<CentroOperacoesScreen> createState() => _CentroOperacoesScreenState();
}

class _CentroOperacoesScreenState extends State<CentroOperacoesScreen> {
  int _ix = 0;

  static final _fmtData = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final useDrawer = w < 920;

    final modulos = _listaModulos(context);
    final ix =
        modulos.isEmpty ? 0 : _ix.clamp(0, modulos.length - 1);
    if (ix != _ix) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _ix = ix);
      });
    }

    Widget corpo = Container(
      color: _CofTheme.canvas,
      child: modulos[ix].builder(context),
    );

    if (useDrawer) {
      return Scaffold(
        backgroundColor: _CofTheme.canvas,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: _CofTheme.sidebar,
          foregroundColor: Colors.white,
          title: Text(modulos[ix].titulo),
          actions: [
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Módulos',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
            ),
          ],
        ),
        endDrawer: Drawer(
          width: min(320.0, w * 0.88),
          child: _SidebarCof(
            modulos: modulos,
            selecionado: ix,
            onSelect: (i) {
              setState(() => _ix = i);
              Navigator.pop(context);
            },
          ),
        ),
        body: corpo,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 268,
          child: _SidebarCof(
            modulos: modulos,
            selecionado: ix,
            onSelect: (i) => setState(() => _ix = i),
          ),
        ),
        Expanded(child: corpo),
      ],
    );
  }

  List<_CofModulo> _listaModulos(BuildContext context) {
    return [
      _CofModulo(
        titulo: 'CRM & campanhas',
        subtitulo: 'Funil, KPIs e canais',
        icon: Icons.auto_graph_rounded,
        builder: (ctx) => _PainelCrmHub(fmtData: _fmtData),
      ),
      _CofModulo(
        titulo: 'Agenda',
        subtitulo: 'Reuniões e compromissos',
        icon: Icons.calendar_month_rounded,
        builder: (ctx) => const PainelCentroOpsAgenda(),
      ),
      _CofModulo(
        titulo: 'Simulador de frete',
        subtitulo: 'Tabela publicada',
        icon: Icons.calculate_outlined,
        builder: (ctx) => _PainelSimuladorFrete(),
      ),
    ];
  }
}

class _CofModulo {
  _CofModulo({
    required this.titulo,
    required this.subtitulo,
    required this.icon,
    required this.builder,
  });
  final String titulo;
  final String subtitulo;
  final IconData icon;
  final Widget Function(BuildContext) builder;
}

class _SidebarCof extends StatelessWidget {
  const _SidebarCof({
    required this.modulos,
    required this.selecionado,
    required this.onSelect,
  });

  final List<_CofModulo> modulos;
  final int selecionado;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _CofTheme.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _CofTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _CofTheme.accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.hub_rounded,
                        color: _CofTheme.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Centro de operações',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Gestão avançadas.',
                  style: TextStyle(
                    color: _CofTheme.sidebarMuted.withValues(alpha: 0.95),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: _CofTheme.sidebarBorder),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
              itemCount: modulos.length,
              itemBuilder: (context, i) {
                final m = modulos[i];
                final sel = i == selecionado;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: sel
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelect(i),
                      hoverColor: Colors.white.withValues(alpha: 0.05),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              m.icon,
                              size: 20,
                              color: sel
                                  ? _CofTheme.accent
                                  : _CofTheme.sidebarMuted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.titulo,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight:
                                          sel ? FontWeight.w700 : FontWeight.w600,
                                      fontSize: 13,
                                      color: sel
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.82),
                                    ),
                                  ),
                                  Text(
                                    m.subtitulo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _CofTheme.sidebarMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (sel)
                              Container(
                                width: 4,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: _CofTheme.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ——— Painéis ———

class _PainelShell extends StatelessWidget {
  const _PainelShell({
    required this.titulo,
    required this.descricao,
    required this.child,
  });

  final String titulo;
  final String descricao;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titulo,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PainelAdminTheme.dashboardInk,
                      letterSpacing: -0.35,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                descricao,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: PainelAdminTheme.textoSecundario,
                ),
              ),
              const SizedBox(height: 22),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _CofCard extends StatelessWidget {
  const _CofCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _CofTheme.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}

bool _crmComunicadoNoAr(Map<String, dynamic> d) {
  if (d['ativo'] != true) return false;
  final exp = d['data_expiracao'];
  if (exp is Timestamp) {
    if (exp.toDate().isBefore(DateTime.now())) return false;
  }
  return true;
}

bool _crmCupomValido(Map<String, dynamic> d) {
  if (d['ativo'] != true) return false;
  final v = d['validade'];
  if (v is Timestamp) {
    if (v.toDate().isBefore(DateTime.now())) return false;
  }
  return true;
}

bool _crmBannerNoAr(Map<String, dynamic> d) {
  if (d['ativo'] != true) return false;
  final ini = d['data_inicio'];
  final fim = d['data_fim'];
  final now = DateTime.now();
  if (ini is Timestamp && ini.toDate().isAfter(now)) return false;
  if (fim is Timestamp && fim.toDate().isBefore(now)) return false;
  return true;
}

String _crmLabelPublico(dynamic p) {
  switch ('${p ?? 'todos'}') {
    case 'cliente':
      return 'Clientes';
    case 'lojista':
      return 'Lojistas';
    case 'entregador':
      return 'Entregadores';
    default:
      return 'Todos';
  }
}

Color _crmCorStatusPush(String status) {
  switch (status) {
    case 'enviado':
      return const Color(0xFF15803D);
    case 'erro':
      return const Color(0xFFB91C1C);
    default:
      return PainelAdminTheme.laranja;
  }
}

class _PainelCrmHub extends StatelessWidget {
  const _PainelCrmHub({required this.fmtData});

  final DateFormat fmtData;

  @override
  Widget build(BuildContext context) {
    return _PainelShell(
      titulo: 'CRM & campanhas',
      descricao:
          'Visão operacional dos canais de relacionamento do DiPertin — métricas '
          'em tempo real sobre comunicados institucionais, cupons, vitrine e push. '
          'O funil abaixo é um roteiro sugerido; a edição detalhada continua em cada módulo do painel.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CrmHeroBand(),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, c) {
              final estreito = c.maxWidth < 720;
              final kpis = <Widget>[
                _CrmKpiTile(
                  stream: FirebaseFirestore.instance
                      .collection('comunicados')
                      .orderBy('data_criacao', descending: true)
                      .snapshots(),
                  icone: Icons.campaign_outlined,
                  titulo: 'Comunicados',
                  valorBuilder: (docs) =>
                      '${docs.where((e) => _crmComunicadoNoAr(e.data())).length}',
                  legenda: 'ao ar (ativo + dentro da validade)',
                  corDestaque: const Color(0xFF4338CA),
                ),
                _CrmKpiTile(
                  stream: FirebaseFirestore.instance
                      .collection('cupons')
                      .orderBy('data_criacao', descending: true)
                      .snapshots(),
                  icone: Icons.local_offer_outlined,
                  titulo: 'Cupons',
                  valorBuilder: (docs) =>
                      '${docs.where((e) => _crmCupomValido(e.data())).length}',
                  legenda: 'ativos dentro da validade',
                  corDestaque: const Color(0xFF0369A1),
                ),
                _CrmKpiTile(
                  stream: FirebaseFirestore.instance
                      .collection('banners')
                      .orderBy('data_criacao', descending: true)
                      .snapshots(),
                  icone: Icons.photo_library_outlined,
                  titulo: 'Vitrine',
                  valorBuilder: (docs) =>
                      '${docs.where((e) => _crmBannerNoAr(e.data())).length}',
                  legenda: 'banners no período vigente',
                  corDestaque: const Color(0xFF047857),
                ),
                _CrmKpiTile(
                  stream: FirebaseFirestore.instance
                      .collection('notificacoes_campanhas')
                      .orderBy('data_criacao', descending: true)
                      .snapshots(),
                  icone: Icons.notifications_active_outlined,
                  titulo: 'Push',
                  valorBuilder: (docs) {
                    var fila = 0;
                    for (final e in docs) {
                      final s = e.data()['status']?.toString() ?? 'pendente';
                      if (s != 'enviado' && s != 'erro') fila++;
                    }
                    return '$fila';
                  },
                  legendaBuilder: (docs) {
                    var ok = 0;
                    var falha = 0;
                    for (final e in docs) {
                      final s = e.data()['status']?.toString() ?? 'pendente';
                      if (s == 'enviado') ok++;
                      if (s == 'erro') falha++;
                    }
                    return 'na fila · $ok enviadas · $falha com erro';
                  },
                  corDestaque: PainelAdminTheme.laranja,
                ),
              ];
              if (estreito) {
                return Column(
                  children: [
                    for (var i = 0; i < kpis.length; i++) ...[
                      if (i > 0) const SizedBox(height: 11),
                      kpis[i],
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < kpis.length; i++) ...[
                    if (i > 0) const SizedBox(width: 11),
                    Expanded(child: kpis[i]),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          const _CrmFunnelBoard(),
          const SizedBox(height: 10),
          Text(
            'Canais — abrir no painel',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.dashboardInk,
                  letterSpacing: -0.2,
                ),
          ),
          const SizedBox(height: 12),
          const _CrmCanalDeck(),
          const SizedBox(height: 26),
          Text(
            'Atividade recente',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PainelAdminTheme.dashboardInk,
                  letterSpacing: -0.2,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Amostras ao vivo das coleções Firestore utilizadas pelo painel.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final duasCols = c.maxWidth >= 960;
              Widget par(Widget a, Widget b) {
                if (!duasCols) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      a,
                      const SizedBox(height: 14),
                      b,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 14),
                    Expanded(child: b),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  par(
                    _CrmListaComunicados(fmtData: fmtData),
                    _CrmListaPush(fmtData: fmtData),
                  ),
                  SizedBox(height: duasCols ? 14 : 0),
                  par(
                    const _CrmListaCupons(),
                    _CrmListaBanners(fmtData: fmtData),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CrmHeroBand extends StatelessWidget {
  const _CrmHeroBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E1B4B),
            PainelAdminTheme.roxo,
            const Color(0xFF7C3AED),
          ],
          stops: const [0, 0.45, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: PainelAdminTheme.roxo.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Relacionamento em um só lugar',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            fontSize: 19,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Alinhe mensagem institucional, incentivo de compra, mídia na vitrine '
                      'e reforço por push — com indicadores ao vivo e acesso rápido a cada canal.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CrmBadgePill(
                texto: 'Comunicados',
                cor: const Color(0xFFA5B4FC),
              ),
              _CrmBadgePill(
                texto: 'Cupons',
                cor: const Color(0xFF7DD3FC),
              ),
              _CrmBadgePill(
                texto: 'Banners',
                cor: const Color(0xFF6EE7B7),
              ),
              _CrmBadgePill(
                texto: 'Push',
                cor: PainelAdminTheme.laranja,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CrmBadgePill extends StatelessWidget {
  const _CrmBadgePill({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _CrmKpiTile extends StatelessWidget {
  const _CrmKpiTile({
    required this.stream,
    required this.icone,
    required this.titulo,
    required this.valorBuilder,
    required this.corDestaque,
    this.legenda,
    this.legendaBuilder,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final IconData icone;
  final String titulo;
  final String Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) valorBuilder;
  final String? legenda;
  final String Function(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  )? legendaBuilder;
  final Color corDestaque;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: corDestaque.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          final carregando =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          final docs =
              snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final valor = snap.hasError ? '—' : valorBuilder(docs);
          final legendaTexto = legendaBuilder != null
              ? (snap.hasError ? '' : legendaBuilder!(docs))
              : (legenda ?? '');

          return Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: corDestaque.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icone, size: 21, color: corDestaque),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        titulo.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: carregando ? 18 : 10),
                if (snap.hasError)
                  Text(
                    'Erro ao ler dados',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (carregando)
                  SizedBox(
                    height: 28,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: corDestaque,
                        ),
                      ),
                    ),
                  )
                else ...[
                  Text(
                    valor,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -1,
                      color: corDestaque,
                    ),
                  ),
                  if (legendaTexto.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      legendaTexto,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: PainelAdminTheme.textoSecundario,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CrmFunnelBoard extends StatelessWidget {
  const _CrmFunnelBoard();

  @override
  Widget build(BuildContext context) {
    return _CofCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_alt_rounded,
                color: PainelAdminTheme.roxo.withValues(alpha: 0.9),
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Funil sugerido de campanha',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.dashboardInk,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Toque em uma etapa para abrir o módulo correspondente e publicar ou ajustar conteúdo.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: PainelAdminTheme.textoSecundario,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, c) {
              final col = c.maxWidth < 640;
              final etapas = <({String t, String s, IconData i, String r, Color k})>[
                (
                  t: 'Mensagem',
                  s: 'Comunicados',
                  i: Icons.forum_outlined,
                  r: '/comunicados',
                  k: const Color(0xFF4F46E5),
                ),
                (
                  t: 'Oferta',
                  s: 'Cupons',
                  i: Icons.savings_outlined,
                  r: '/cupons',
                  k: const Color(0xFF0284C7),
                ),
                (
                  t: 'Escopo',
                  s: 'Push segmentado',
                  i: Icons.podcasts_outlined,
                  r: '/notificacoes',
                  k: PainelAdminTheme.laranja,
                ),
                (
                  t: 'Vitrine',
                  s: 'Banners por cidade',
                  i: Icons.view_carousel_outlined,
                  r: '/banners',
                  k: const Color(0xFF059669),
                ),
              ];
              if (col) {
                return Column(
                  children: [
                    for (var i = 0; i < etapas.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _CrmFunnelStep(
                        indice: i + 1,
                        titulo: etapas[i].t,
                        subtitulo: etapas[i].s,
                        icon: etapas[i].i,
                        rota: etapas[i].r,
                        cor: etapas[i].k,
                      ),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < etapas.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 26),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: Colors.blueGrey.shade300,
                        ),
                      ),
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _CrmFunnelStep(
                        indice: i + 1,
                        titulo: etapas[i].t,
                        subtitulo: etapas[i].s,
                        icon: etapas[i].i,
                        rota: etapas[i].r,
                        cor: etapas[i].k,
                      ),
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
}

class _CrmFunnelStep extends StatelessWidget {
  const _CrmFunnelStep({
    required this.indice,
    required this.titulo,
    required this.subtitulo,
    required this.icon,
    required this.rota,
    required this.cor,
  });

  final int indice;
  final String titulo;
  final String subtitulo;
  final IconData icon;
  final String rota;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cor.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.navegarPainel(rota),
        hoverColor: cor.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: cor.withValues(alpha: 0.22),
                    child: Text(
                      '$indice',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: cor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(icon, size: 22, color: cor),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                titulo,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.dashboardInk,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: PainelAdminTheme.textoSecundario,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Abrir',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_outward_rounded, size: 15, color: cor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrmCanalDeck extends StatelessWidget {
  const _CrmCanalDeck();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final tileW =
            maxW >= 560 ? ((maxW - 12) / 2).clamp(200.0, 560.0) : maxW;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CrmCanalCard(
              largura: tileW,
              titulo: 'Comunicados',
              subtitulo: 'Mensagens institucionais por público',
              icone: Icons.mark_chat_read_outlined,
              rota: '/comunicados',
              cor: const Color(0xFF4F46E5),
            ),
            _CrmCanalCard(
              largura: tileW,
              titulo: 'Cupons',
              subtitulo: 'Desconto e urgência na conversão',
              icone: Icons.card_giftcard_rounded,
              rota: '/cupons',
              cor: const Color(0xFF0284C7),
            ),
            _CrmCanalCard(
              largura: tileW,
              titulo: 'Notificações',
              subtitulo: 'Campanhas push em massa',
              icone: Icons.send_rounded,
              rota: '/notificacoes',
              cor: PainelAdminTheme.laranja,
            ),
            _CrmCanalCard(
              largura: tileW,
              titulo: 'Banners',
              subtitulo: 'Arte na vitrine por cidade',
              icone: Icons.image_aspect_ratio_rounded,
              rota: '/banners',
              cor: const Color(0xFF059669),
            ),
          ],
        );
      },
    );
  }
}

class _CrmCanalCard extends StatelessWidget {
  const _CrmCanalCard({
    required this.largura,
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.rota,
    required this.cor,
  });

  final double largura;
  final String titulo;
  final String subtitulo;
  final IconData icone;
  final String rota;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largura,
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _CofTheme.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.navegarPainel(rota),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icone, color: cor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: PainelAdminTheme.dashboardInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cor.withValues(alpha: 0.75),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CrmListaComunicados extends StatelessWidget {
  const _CrmListaComunicados({required this.fmtData});

  final DateFormat fmtData;

  @override
  Widget build(BuildContext context) {
    return _CofCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CrmPainelTituloLista(
            titulo: 'Comunicados prioritários',
            acaoRotulo: 'Gerir',
            rota: '/comunicados',
          ),
          SizedBox(
            height: 220,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('comunicados')
                  .orderBy('data_criacao', descending: true)
                  .limit(24)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text('${snap.error}',
                      style: TextStyle(color: Colors.red.shade700));
                }
                final noAr = snap.data!.docs
                    .where((e) => _crmComunicadoNoAr(e.data()))
                    .take(6)
                    .toList();
                if (noAr.isEmpty) {
                  return const _CrmListaVazia(
                    mensagem: 'Nenhum comunicado ativo na amostra.',
                  );
                }
                return ListView.separated(
                  itemCount: noAr.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = noAr[i].data();
                    final ts = d['data_criacao'] as Timestamp?;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.campaign_outlined,
                        color: PainelAdminTheme.roxo.withValues(alpha: 0.85),
                      ),
                      title: Text(
                        (d['titulo'] ?? '—').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${_crmLabelPublico(d['publico_alvo'])} · '
                        '${ts != null ? fmtData.format(ts.toDate()) : '—'}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CrmListaPush extends StatelessWidget {
  const _CrmListaPush({required this.fmtData});

  final DateFormat fmtData;

  @override
  Widget build(BuildContext context) {
    return _CofCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CrmPainelTituloLista(
            titulo: 'Campanhas push',
            acaoRotulo: 'Histórico',
            rota: '/notificacoes',
          ),
          SizedBox(
            height: 220,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notificacoes_campanhas')
                  .orderBy('data_criacao', descending: true)
                  .limit(12)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text('${snap.error}',
                      style: TextStyle(color: Colors.red.shade700));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const _CrmListaVazia(
                    mensagem: 'Nenhuma campanha registrada.',
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final st = d['status']?.toString() ?? 'pendente';
                    final ts = d['data_criacao'] as Timestamp?;
                    final cor = _crmCorStatusPush(st);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.notifications_none_rounded,
                            size: 20, color: cor),
                      ),
                      title: Text(
                        (d['titulo'] ?? '—').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${_crmLabelPublico(d['publico_alvo'])} · '
                        '${ts != null ? fmtData.format(ts.toDate()) : '—'} · '
                        '${st.toUpperCase()}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CrmListaCupons extends StatelessWidget {
  const _CrmListaCupons();

  @override
  Widget build(BuildContext context) {
    return _CofCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CrmPainelTituloLista(
            titulo: 'Cupons em destaque',
            acaoRotulo: 'Cupons',
            rota: '/cupons',
          ),
          SizedBox(
            height: 220,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('cupons')
                  .orderBy('data_criacao', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text('${snap.error}',
                      style: TextStyle(color: Colors.red.shade700));
                }
                final validos = snap.data!.docs
                    .where((e) => _crmCupomValido(e.data()))
                    .take(6)
                    .toList();
                if (validos.isEmpty) {
                  return const _CrmListaVazia(
                    mensagem: 'Nenhum cupom ativo na amostra.',
                  );
                }
                return ListView.separated(
                  itemCount: validos.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = validos[i].data();
                    final codigo = (d['codigo'] ?? '—').toString();
                    final tipo = (d['tipo'] ?? '').toString();
                    final valor = (d['valor'] as num?)?.toDouble();
                    final usos = d['usos_atual'] ?? 0;
                    final lim = d['limite_usos'] ?? 0;
                    final valStr = valor != null
                        ? (tipo == 'porcentagem'
                            ? '${valor.toStringAsFixed(0)}%'
                            : 'R\$ ${valor.toStringAsFixed(2)}')
                        : '—';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.local_offer_rounded,
                        color: const Color(0xFF0284C7).withValues(alpha: 0.9),
                      ),
                      title: Text(
                        codigo,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '$valStr · usos $usos'
                        '${(lim is num && lim > 0) ? ' / $lim' : ''}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CrmListaBanners extends StatelessWidget {
  const _CrmListaBanners({required this.fmtData});

  final DateFormat fmtData;

  @override
  Widget build(BuildContext context) {
    return _CofCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CrmPainelTituloLista(
            titulo: 'Banners na vitrine',
            acaoRotulo: 'Banners',
            rota: '/banners',
          ),
          SizedBox(
            height: 220,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('banners')
                  .orderBy('data_criacao', descending: true)
                  .limit(24)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text('${snap.error}',
                      style: TextStyle(color: Colors.red.shade700));
                }
                final noAr = snap.data!.docs
                    .where((e) => _crmBannerNoAr(e.data()))
                    .take(6)
                    .toList();
                if (noAr.isEmpty) {
                  return const _CrmListaVazia(
                    mensagem: 'Nenhum banner vigente na amostra.',
                  );
                }
                return ListView.separated(
                  itemCount: noAr.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = noAr[i].data();
                    final cidade = (d['cidade'] ?? 'todas').toString();
                    final ini = d['data_inicio'] as Timestamp?;
                    final fim = d['data_fim'] as Timestamp?;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.view_day_outlined,
                        color: const Color(0xFF059669).withValues(alpha: 0.9),
                      ),
                      title: Text(
                        cidade == 'todas'
                            ? 'Todas as cidades'
                            : cidade.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${ini != null ? fmtData.format(ini.toDate()) : '—'} → '
                        '${fim != null ? fmtData.format(fim.toDate()) : '—'}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CrmPainelTituloLista extends StatelessWidget {
  const _CrmPainelTituloLista({
    required this.titulo,
    required this.acaoRotulo,
    required this.rota,
  });

  final String titulo;
  final String acaoRotulo;
  final String rota;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: PainelAdminTheme.dashboardInk,
                  ),
            ),
          ),
          TextButton.icon(
            onPressed: () => context.navegarPainel(rota),
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: Text(acaoRotulo),
            style: TextButton.styleFrom(
              foregroundColor: PainelAdminTheme.roxo,
            ),
          ),
        ],
      ),
    );
  }
}

class _CrmListaVazia extends StatelessWidget {
  const _CrmListaVazia({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        mensagem,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: Colors.blueGrey.shade600,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}


class _SimFreteDetalhe {
  const _SimFreteDetalhe({
    required this.regra,
    required this.combinacaoExataCidadeVeiculo,
    required this.kmInformado,
    required this.valorBase,
    required this.distanciaBaseKm,
    required this.valorKmAdicional,
    required this.kmExtra,
    required this.total,
  });

  final Map<String, dynamic> regra;
  final bool combinacaoExataCidadeVeiculo;
  final double kmInformado;
  final double valorBase;
  final double distanciaBaseKm;
  final double valorKmAdicional;
  final double kmExtra;
  final double total;
}

/// Mesma coleção que [Configurações → Tabela de fretes].
_SimFreteDetalhe? _simFreteCalcular({
  required List<Map<String, dynamic>> regras,
  required String cidadeBruta,
  required double km,
  required String tipoVeiculoRaw,
}) {
  final cidade = cidadeBruta.trim().toLowerCase();
  final tipoVeiculo = tipoVeiculoRaw.trim().toLowerCase();
  if (cidade.isEmpty || regras.isEmpty) return null;

  Map<String, dynamic>? escolhida;
  var exata = false;
  for (final r in regras) {
    final c = (r['cidade'] ?? '').toString().trim().toLowerCase();
    final v = (r['veiculo'] ?? '').toString().trim().toLowerCase();
    if (c == cidade && v == tipoVeiculo) {
      escolhida = r;
      exata = true;
      break;
    }
  }
  if (escolhida == null) {
    for (final r in regras) {
      final c = (r['cidade'] ?? '').toString().trim().toLowerCase();
      if (c == cidade) {
        escolhida = r;
        break;
      }
    }
  }
  if (escolhida == null) return null;

  final valorBase = (escolhida['valor_base'] as num?)?.toDouble() ?? 0;
  final dist = (escolhida['distancia_base_km'] as num?)?.toDouble() ?? 0;
  final extra = (escolhida['valor_km_adicional'] as num?)?.toDouble() ?? 0;
  final kmExtra = max(0.0, km - dist);
  final cobrarExtra = kmExtra * extra;
  return _SimFreteDetalhe(
    regra: escolhida,
    combinacaoExataCidadeVeiculo: exata,
    kmInformado: km,
    valorBase: valorBase,
    distanciaBaseKm: dist,
    valorKmAdicional: extra,
    kmExtra: kmExtra,
    total: valorBase + cobrarExtra,
  );
}

class _PainelSimuladorFrete extends StatefulWidget {
  @override
  State<_PainelSimuladorFrete> createState() => _PainelSimuladorFreteState();
}

class _PainelSimuladorFreteState extends State<_PainelSimuladorFrete> {
  final _cidadeC = TextEditingController();
  final _kmC = TextEditingController(text: '3');
  String _tipoVeiculo = 'padrão';

  static final _fmtBrl = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
    decimalDigits: 2,
  );

  @override
  void dispose() {
    _cidadeC.dispose();
    _kmC.dispose();
    super.dispose();
  }

  List<String> _cidadesOrdenadas(List<Map<String, dynamic>> regras) {
    final s = <String>{};
    for (final r in regras) {
      final c = (r['cidade'] ?? '').toString().trim();
      if (c.isNotEmpty) s.add(c);
    }
    final l = s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return l;
  }

  List<String> _tiposVeiculoOrdenados(List<Map<String, dynamic>> regras) {
    final s = <String>{};
    for (final r in regras) {
      final v = (r['veiculo'] ?? '').toString().trim();
      if (v.isNotEmpty) s.add(v);
    }
    if (s.isEmpty) {
      return ['padrão', 'carro'];
    }
    final l = s.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return l;
  }

  String _tipoResolvido(List<String> tiposLista) {
    for (final t in tiposLista) {
      if (t.toLowerCase() == _tipoVeiculo.trim().toLowerCase()) return t;
    }
    return tiposLista.isNotEmpty ? tiposLista.first : 'padrão';
  }

  Widget _cabecalhoSimulador() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PainelAdminTheme.dashboardInk.withValues(alpha: 0.97),
            PainelAdminTheme.roxo,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: PainelAdminTheme.roxo.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(
              Icons.calculate_rounded,
              color: PainelAdminTheme.laranja.withValues(alpha: 0.95),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estimativa de frete',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Lê ao vivo a coleção tabela_fretes (idem Configurações). '
                  'Escolha cidade e km para ver como a taxa será cobrada pelo app.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decCampo({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22, color: PainelAdminTheme.roxo),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _CofTheme.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PainelAdminTheme.roxo, width: 1.5),
      ),
      filled: true,
      fillColor: const Color(0xFFFAFAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  List<Widget> _linhasBreakdown(_SimFreteDetalhe det) {
    final fd = det.distanciaBaseKm == det.distanciaBaseKm.roundToDouble()
        ? det.distanciaBaseKm.toStringAsFixed(0)
        : det.distanciaBaseKm.toStringAsFixed(1);
    final linhas = <(String rotulo, String valor)>[
      ('Base até $fd km', _fmtBrl.format(det.valorBase)),
      ('Km acima da franquia', '${det.kmExtra.toStringAsFixed(2)} km'),
      ('Taxa por km extra',
          '${_fmtBrl.format(det.valorKmAdicional)} / km'),
      ('Km informado para simulação',
          '${det.kmInformado.toStringAsFixed(2)} km'),
    ];
    return [
      for (final e in linhas)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  e.$1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: e.$1.startsWith('Base')
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: PainelAdminTheme.textoSecundario,
                  ),
                ),
              ),
              Text(
                e.$2,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PainelAdminTheme.dashboardInk,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _painelResultado(_SimFreteDetalhe? det, {required bool semRegras}) {
    if (semRegras) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDBA74)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_outlined, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                Text(
                  'Nenhuma regra na tabela',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.orange.shade900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre cidades e valores em Configurações → Tabela de fretes. '
              'Os mesmos dados aparecerão aqui automaticamente.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Colors.orange.shade900.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.navegarPainel('/configuracoes'),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Abrir Configurações'),
              style: FilledButton.styleFrom(
                foregroundColor: PainelAdminTheme.roxo,
              ),
            ),
          ],
        ),
      );
    }

    if (det == null) {
      final temCidade = _cidadeC.text.trim().isNotEmpty;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _CofTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.blueGrey.shade600),
                const SizedBox(width: 8),
                Text(
                  'Aguardando parâmetros',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Colors.blueGrey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              temCidade
                  ? 'Não há regra para esta cidade (ou o nome não bate com o '
                      'cadastro — use o mesmo texto da Configurações, em minúsculas).'
                  : 'Informe a cidade cadastrada e a distância em km. A estimativa '
                      'atualiza enquanto você digita.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: PainelAdminTheme.textoSecundario,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PainelAdminTheme.roxo.withValues(alpha: 0.08),
            PainelAdminTheme.laranja.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(
          color: PainelAdminTheme.roxo.withValues(alpha: 0.22),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_rounded,
                  color: PainelAdminTheme.roxo, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Valor estimado',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: PainelAdminTheme.dashboardInk,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (!det.combinacaoExataCidadeVeiculo)
                Tooltip(
                  message:
                      'Usada a primeira regra encontrada só por cidade — '
                      'não há par cidade + tipo exato na tabela.',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: PainelAdminTheme.laranja.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Cidade apenas',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _fmtBrl.format(det.total),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: PainelAdminTheme.dashboardInk,
            ),
          ),
          const SizedBox(height: 14),
          ..._linhasBreakdown(det),
        ],
      ),
    );
  }

  Widget _listaRegrasCadastradas(List<Map<String, dynamic>> regras) {
    final ordenadas = [...regras];
    ordenadas.sort((a, b) {
      final ca = '${a['cidade']}|${a['veiculo']}';
      final cb = '${b['cidade']}|${b['veiculo']}';
      return ca.toLowerCase().compareTo(cb.toLowerCase());
    });

    return _CofCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_rows_rounded,
                  size: 20, color: PainelAdminTheme.roxo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Taxas cadastradas (${regras.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: PainelAdminTheme.dashboardInk,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.navegarPainel('/configuracoes'),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Editar'),
                style: TextButton.styleFrom(
                  foregroundColor: PainelAdminTheme.roxo,
                ),
              ),
            ],
          ),
          Text(
            'Mesmos registros salvos em Configurações.',
            style: TextStyle(
              fontSize: 12.5,
              color: PainelAdminTheme.textoSecundario,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: ordenadas.length,
              separatorBuilder: (context, i) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = ordenadas[i];
                final base = (d['valor_base'] as num?)?.toDouble() ?? 0;
                final dist =
                    (d['distancia_base_km'] as num?)?.toDouble() ?? 0;
                final extra =
                    (d['valor_km_adicional'] as num?)?.toDouble() ?? 0;
                final veiculo = (d['veiculo'] ?? '—').toString();
                final cidade = (d['cidade'] ?? '—').toString();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _CofTheme.cardBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: PainelAdminTheme.laranja.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.local_shipping_outlined,
                          size: 18,
                          color: PainelAdminTheme.laranja,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$veiculo · ${cidade.toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _chipFreteInfo(
                                  'Base ${_fmtBrl.format(base)} até '
                                  '${dist == dist.roundToDouble() ? dist.toStringAsFixed(0) : dist.toStringAsFixed(1)} km',
                                ),
                                _chipFreteInfo(
                                  '+ ${_fmtBrl.format(extra)} / km extra',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipFreteInfo(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _CofTheme.cardBorder),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.blueGrey.shade700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PainelShell(
      titulo: 'Simulador de frete',
      descricao:
          'Simula o cálculo do app com base na tabela publicada em Configurações. '
          'As taxas exibidas ao lado são as regras atuais no Firestore.',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('tabela_fretes').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _CofCard(
              child: SelectableText(
                'Erro ao carregar tabela_fretes: ${snap.error}',
                style: const TextStyle(color: Color(0xFFB45309)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final regras = snap.data!.docs.map((e) => e.data()).toList();
          final cidadesLista = _cidadesOrdenadas(regras);
          final tiposLista = _tiposVeiculoOrdenados(regras);
          final tipoUsado = _tipoResolvido(tiposLista);

          final kmTxt = double.tryParse(_kmC.text.replaceAll(',', '.')) ?? 0.0;
          final det = _simFreteCalcular(
            regras: regras,
            cidadeBruta: _cidadeC.text,
            km: kmTxt,
            tipoVeiculoRaw: tipoUsado,
          );

          return LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final formCol = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cabecalhoSimulador(),
                  const SizedBox(height: 20),
                  _CofCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Parâmetros',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: PainelAdminTheme.dashboardInk,
                                  ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _cidadeC,
                          spellCheckConfiguration:
                              const SpellCheckConfiguration.disabled(),
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          decoration: _decCampo(
                            label: 'Cidade (como cadastrado)',
                            icon: Icons.location_city_rounded,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (cidadesLista.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Atalhos — mesmas chaves da Configurações',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.blueGrey.shade600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final city in cidadesLista)
                                ActionChip(
                                  label: Text(city),
                                  elevation: 0,
                                  backgroundColor: Colors.white,
                                  side: BorderSide(color: _CofTheme.cardBorder),
                                  onPressed: () {
                                    _cidadeC.text = city;
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: _kmC,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          spellCheckConfiguration:
                              const SpellCheckConfiguration.disabled(),
                          decoration: _decCampo(
                            label: 'Distância total (km)',
                            icon: Icons.straighten_rounded,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: _decCampo(
                            label: 'Tipo de veículo (regra)',
                            icon: Icons.two_wheeler_rounded,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: tipoUsado,
                              items: [
                                for (final t in tiposLista)
                                  DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                              ],
                              onChanged: regras.isEmpty
                                  ? null
                                  : (v) => setState(
                                        () => _tipoVeiculo =
                                            v ?? tiposLista.first,
                                      ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: KeyedSubtree(
                            key: ValueKey<String>(
                              det == null
                                  ? '${_cidadeC.text}|$kmTxt|$tipoUsado|${regras.length}'
                                  : '${det.total}_${det.combinacaoExataCidadeVeiculo}',
                            ),
                            child: _painelResultado(det, semRegras: regras.isEmpty),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final painelTaxas =
                  _listaRegrasCadastradas(regras);

              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    formCol,
                    const SizedBox(height: 20),
                    painelTaxas,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 52, child: formCol),
                  const SizedBox(width: 22),
                  Expanded(flex: 48, child: painelTaxas),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

