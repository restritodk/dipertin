import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../constants/conta_bloqueio_lojista.dart';
import '../services/marketing_leads_service.dart';
import '../theme/painel_admin_theme.dart';

/// Painel de Marketing (dentro do Centro de operações): status unificado das
/// contas de parceiros + captação de leads por mês. Leituras de contagem usam
/// agregação (`count()`), evitando baixar documentos.
class PainelMarketingDashboard extends StatefulWidget {
  const PainelMarketingDashboard({super.key});

  @override
  State<PainelMarketingDashboard> createState() =>
      _PainelMarketingDashboardState();
}

class _PainelMarketingDashboardState extends State<PainelMarketingDashboard> {
  static const Color _cardBorder = Color(0xFFE2E8F0);
  static const Duration _timeout = Duration(seconds: 30);

  bool _carregando = true;
  bool _erro = false;

  // Lojistas
  int? _lojTotal, _lojAprov, _lojPend, _lojBloq;
  // Entregadores
  int? _entTotal, _entAprov, _entPend, _entBloq, _entExcl;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<int?> _count(Query<Map<String, dynamic>> q) async {
    for (var i = 0; i < 2; i++) {
      try {
        final s = await q.count().get().timeout(_timeout);
        return s.count ?? 0;
      } on TimeoutException {
        return null;
      } catch (_) {
        if (i == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }
    return null;
  }

  Future<void> _yield() =>
      Future<void>.delayed(const Duration(milliseconds: 32));

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = false;
      _lojTotal = _lojAprov = _lojPend = _lojBloq = null;
      _entTotal = _entAprov = _entPend = _entBloq = _entExcl = null;
    });
    final db = FirebaseFirestore.instance;
    final users = db.collection('users');
    var falhou = false;

    // Executa a contagem e atualiza a UI assim que o valor chega (progressivo),
    // para o painel nunca ficar "vazio" enquanto as 9 queries rodam.
    Future<void> run(
      Query<Map<String, dynamic>> q,
      void Function(int? v) set,
    ) async {
      final v = await _count(q);
      if (v == null) falhou = true;
      if (!mounted) return;
      setState(() => set(v));
      await _yield();
    }

    await run(users.where('role', isEqualTo: 'lojista'),
        (v) => _lojTotal = v);
    await run(
        users
            .where('role', isEqualTo: 'lojista')
            .where('status_loja', isEqualTo: 'aprovada'),
        (v) => _lojAprov = v);
    await run(
        users
            .where('role', isEqualTo: 'lojista')
            .where('status_loja', isEqualTo: 'pendente'),
        (v) => _lojPend = v);
    await run(
        users
            .where('role', isEqualTo: 'lojista')
            .where('status_loja', isEqualTo: 'bloqueada'),
        (v) => _lojBloq = v);

    await run(users.where('role', isEqualTo: 'entregador'),
        (v) => _entTotal = v);
    await run(
        users
            .where('role', isEqualTo: 'entregador')
            .where('entregador_status', isEqualTo: 'aprovado'),
        (v) => _entAprov = v);
    await run(
        users
            .where('role', isEqualTo: 'entregador')
            .where('entregador_status', isEqualTo: 'pendente'),
        (v) => _entPend = v);
    await run(
        users.where('role', isEqualTo: 'entregador').where(
          'entregador_status',
          whereIn: [
            ContaBloqueioLojista.statusLojaBloqueado,
            ContaBloqueioLojista.statusLojaBloqueioTemporario,
          ],
        ),
        (v) => _entBloq = v);
    await run(
        users.where(
          'entregador_perfil_operacional',
          isEqualTo: 'perfil_removido',
        ),
        (v) => _entExcl = v);

    if (!mounted) return;
    setState(() {
      _carregando = false;
      _erro = falhou;
    });
  }

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
              _cabecalho(),
              const SizedBox(height: 22),
              _blocoContas(),
              const SizedBox(height: 26),
              _MkSectionTitle(
                titulo: 'Captação de leads por mês',
                subtitulo:
                    'Leads de lojistas e entregadores criados nos últimos 6 meses.',
              ),
              const SizedBox(height: 14),
              const _MkCaptacaoLeads(),
              const SizedBox(height: 26),
              _MkSectionTitle(
                titulo: 'Leads recentes',
                subtitulo: 'Últimos parceiros captados no CRM de marketing.',
              ),
              const SizedBox(height: 14),
              const _MkLeadsRecentes(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), PainelAdminTheme.roxo, Color(0xFF7C3AED)],
          stops: [0, 0.45, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: PainelAdminTheme.roxo.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 16),
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(Icons.insights_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Painel de Marketing',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saúde das contas de parceiros e captação de novos lojistas e '
                  'entregadores — base para campanhas, reativação e metas de crescimento.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _blocoContas() {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900
            ? 4
            : c.maxWidth >= 560
                ? 2
                : 1;
        final lojaCards = <Widget>[
          _MkKpiCard(
            titulo: 'Lojistas (total)',
            valor: _lojTotal,
            carregando: _carregando,
            icon: Icons.storefront_rounded,
            cor: PainelAdminTheme.roxo,
          ),
          _MkKpiCard(
            titulo: 'Lojistas ativos',
            valor: _lojAprov,
            carregando: _carregando,
            icon: Icons.check_circle_outline_rounded,
            cor: const Color(0xFF059669),
          ),
          _MkKpiCard(
            titulo: 'Lojistas pendentes',
            valor: _lojPend,
            carregando: _carregando,
            icon: Icons.hourglass_empty_rounded,
            cor: const Color(0xFFD97706),
          ),
          _MkKpiCard(
            titulo: 'Lojistas bloqueados',
            valor: _lojBloq,
            carregando: _carregando,
            icon: Icons.block_rounded,
            cor: const Color(0xFFDC2626),
          ),
        ];
        final entCards = <Widget>[
          _MkKpiCard(
            titulo: 'Entregadores (total)',
            valor: _entTotal,
            carregando: _carregando,
            icon: Icons.delivery_dining_rounded,
            cor: PainelAdminTheme.roxo,
          ),
          _MkKpiCard(
            titulo: 'Entregadores ativos',
            valor: _entAprov,
            carregando: _carregando,
            icon: Icons.check_circle_outline_rounded,
            cor: const Color(0xFF059669),
          ),
          _MkKpiCard(
            titulo: 'Entregadores pendentes',
            valor: _entPend,
            carregando: _carregando,
            icon: Icons.hourglass_empty_rounded,
            cor: const Color(0xFFD97706),
          ),
          _MkKpiCard(
            titulo: 'Entregadores bloqueados',
            valor: _entBloq,
            carregando: _carregando,
            icon: Icons.block_rounded,
            cor: const Color(0xFFDC2626),
          ),
          _MkKpiCard(
            titulo: 'Entregadores excluídos',
            valor: _entExcl,
            carregando: _carregando,
            icon: Icons.person_off_rounded,
            cor: const Color(0xFF64748B),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_erro) ...[
              _avisoParcial(),
              const SizedBox(height: 14),
            ],
            _MkSectionTitle(
              titulo: 'Status das contas',
              subtitulo: 'Contagem ao vivo das contas de parceiros.',
            ),
            const SizedBox(height: 12),
            _grade(lojaCards, cols),
            const SizedBox(height: 12),
            _grade(entCards, cols),
          ],
        );
      },
    );
  }

  Widget _grade(List<Widget> cards, int cols) {
    final linhas = <Widget>[];
    for (var i = 0; i < cards.length; i += cols) {
      final fim = (i + cols) > cards.length ? cards.length : i + cols;
      final grupo = cards.sublist(i, fim);
      // IntrinsicHeight dá altura limitada à Row (que está num Column de altura
      // ilimitada, dentro do scroll vertical), permitindo cards de mesma altura
      // sem cair em constraints infinitas (CrossAxisAlignment.stretch).
      linhas.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) const SizedBox(width: 12),
              Expanded(
                child: j < grupo.length ? grupo[j] : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
      if (fim < cards.length) linhas.add(const SizedBox(height: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: linhas,
    );
  }

  Widget _avisoParcial() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Algumas contagens não puderam ser carregadas. Toque em atualizar para tentar novamente.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ——— Captação de leads por mês ———

class _MkCaptacaoLeads extends StatelessWidget {
  const _MkCaptacaoLeads();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: MarketingLeadsService.stream(MarketingLeadsService.colecaoLojistas),
      builder: (context, snapLoj) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: MarketingLeadsService.stream(
              MarketingLeadsService.colecaoEntregadores),
          builder: (context, snapEnt) {
            final carregando = snapLoj.connectionState == ConnectionState.waiting ||
                snapEnt.connectionState == ConnectionState.waiting;
            final loj = snapLoj.data?.docs ?? const [];
            final ent = snapEnt.data?.docs ?? const [];

            final agora = DateTime.now();
            final meses = List.generate(6, (i) {
              final d = DateTime(agora.year, agora.month - (5 - i), 1);
              return d;
            });
            int contar(
              List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
              DateTime mes,
            ) {
              final inicio = DateTime(mes.year, mes.month, 1);
              final fim = DateTime(mes.year, mes.month + 1, 1);
              var n = 0;
              for (final d in docs) {
                final ts = d.data()['criado_em'];
                if (ts is Timestamp) {
                  final dt = ts.toDate();
                  if (!dt.isBefore(inicio) && dt.isBefore(fim)) n++;
                }
              }
              return n;
            }

            final dadosLoj = [for (final m in meses) contar(loj, m)];
            final dadosEnt = [for (final m in meses) contar(ent, m)];
            final temDados =
                dadosLoj.any((e) => e > 0) || dadosEnt.any((e) => e > 0);

            return _MkCard(
              child: carregando
                  ? const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : !temDados
                      ? const SizedBox(
                          height: 160,
                          child: Center(
                            child: Text(
                              'Sem leads captados ainda.\n'
                              'Cadastre leads em "Leads de lojistas/entregadores".',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: PainelAdminTheme.textoSecundario,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : _MkBarChart(
                          meses: meses,
                          serieA: dadosLoj,
                          serieB: dadosEnt,
                          labelA: 'Lojistas',
                          labelB: 'Entregadores',
                          corA: PainelAdminTheme.roxo,
                          corB: PainelAdminTheme.laranja,
                        ),
            );
          },
        );
      },
    );
  }
}

class _MkBarChart extends StatelessWidget {
  const _MkBarChart({
    required this.meses,
    required this.serieA,
    required this.serieB,
    required this.labelA,
    required this.labelB,
    required this.corA,
    required this.corB,
  });

  final List<DateTime> meses;
  final List<int> serieA;
  final List<int> serieB;
  final String labelA;
  final String labelB;
  final Color corA;
  final Color corB;

  @override
  Widget build(BuildContext context) {
    final maxVal = [
      ...serieA,
      ...serieB,
      1,
    ].reduce((a, b) => a > b ? a : b);
    const mesesAbrev = [
      'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
      'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legenda(labelA, corA),
            const SizedBox(width: 16),
            _legenda(labelB, corB),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 180,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < meses.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _barra(serieA[i], maxVal, corA),
                            const SizedBox(width: 5),
                            _barra(serieB[i], maxVal, corB),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mesesAbrev[meses[i].month - 1],
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: PainelAdminTheme.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _barra(int valor, int maxVal, Color cor) {
    final h = (valor / maxVal) * 140.0;
    return Tooltip(
      message: '$valor',
      child: Container(
        width: 16,
        height: h.clamp(valor > 0 ? 6.0 : 2.0, 140.0),
        decoration: BoxDecoration(
          color: valor > 0 ? cor : cor.withValues(alpha: 0.18),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        ),
      ),
    );
  }

  Widget _legenda(String label, Color cor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration:
              BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: PainelAdminTheme.dashboardInk,
          ),
        ),
      ],
    );
  }
}

// ——— Leads recentes ———

class _MkLeadsRecentes extends StatelessWidget {
  const _MkLeadsRecentes();

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: MarketingLeadsService.stream(MarketingLeadsService.colecaoLojistas),
      builder: (context, snapLoj) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: MarketingLeadsService.stream(
              MarketingLeadsService.colecaoEntregadores),
          builder: (context, snapEnt) {
            final itens = <({String nome, String tipo, DateTime? data})>[];
            for (final d in (snapLoj.data?.docs ?? const [])) {
              final m = d.data();
              itens.add((
                nome: (m['nome_fantasia'] ?? m['nome'] ?? m['razao_social'] ?? '—')
                    .toString(),
                tipo: 'Lojista',
                data: (m['criado_em'] is Timestamp)
                    ? (m['criado_em'] as Timestamp).toDate()
                    : null,
              ));
            }
            for (final d in (snapEnt.data?.docs ?? const [])) {
              final m = d.data();
              itens.add((
                nome: (m['nome'] ?? '—').toString(),
                tipo: 'Entregador',
                data: (m['criado_em'] is Timestamp)
                    ? (m['criado_em'] as Timestamp).toDate()
                    : null,
              ));
            }
            itens.sort((a, b) =>
                (b.data ?? DateTime(0)).compareTo(a.data ?? DateTime(0)));
            final top = itens.take(8).toList();

            return _MkCard(
              child: top.isEmpty
                  ? const SizedBox(
                      height: 120,
                      child: Center(
                        child: Text(
                          'Nenhum lead cadastrado ainda.',
                          style:
                              TextStyle(color: PainelAdminTheme.textoSecundario),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < top.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: (top[i].tipo == 'Lojista'
                                      ? PainelAdminTheme.roxo
                                      : PainelAdminTheme.laranja)
                                  .withValues(alpha: 0.12),
                              child: Icon(
                                top[i].tipo == 'Lojista'
                                    ? Icons.storefront_rounded
                                    : Icons.delivery_dining_rounded,
                                size: 18,
                                color: top[i].tipo == 'Lojista'
                                    ? PainelAdminTheme.roxo
                                    : PainelAdminTheme.laranja,
                              ),
                            ),
                            title: Text(
                              top[i].nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${top[i].tipo}'
                              '${top[i].data != null ? ' · ${fmt.format(top[i].data!)}' : ''}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

// ——— Componentes compartilhados ———

class _MkSectionTitle extends StatelessWidget {
  const _MkSectionTitle({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: PainelAdminTheme.dashboardInk,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.4,
            color: PainelAdminTheme.textoSecundario,
          ),
        ),
      ],
    );
  }
}

class _MkCard extends StatelessWidget {
  const _MkCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _PainelMarketingDashboardState._cardBorder),
      ),
      child: child,
    );
  }
}

class _MkKpiCard extends StatelessWidget {
  const _MkKpiCard({
    required this.titulo,
    required this.valor,
    required this.carregando,
    required this.icon,
    required this.cor,
  });

  final String titulo;
  final int? valor;
  final bool carregando;
  final IconData icon;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _PainelMarketingDashboardState._cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: cor),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (carregando && valor == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                else
                  Text(
                    valor == null ? '—' : '$valor',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: PainelAdminTheme.dashboardInk,
                      height: 1.05,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PainelAdminTheme.textoSecundario,
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
