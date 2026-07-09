import 'package:depertin_web/navigation/painel_navigation_scope.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/assinaturas_dashboard_resumo.dart';
import '../models/cliente_assinatura_model.dart';
import '../services/assinaturas_dashboard_service.dart';

// Tokens locais alinhados ao design system DiPertin
const Color _fundoPagina = Color(0xFFF8F8FC);
const Color _textoPrimario = Color(0xFF17152A);
const Color _textoSecundario = Color(0xFF6E7894);
const Color _roxo = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _roxoSuave = Color(0xFFF1E9FF);
const Color _laranja = Color(0xFFFF8F00);
const Color _verde = Color(0xFF16A34A);
const Color _verdeFundo = Color(0xFFE8F5E9);
const Color _vermelho = Color(0xFFDC2626);
const Color _vermelhoFundo = Color(0xFFFEF2F2);
const Color _borda = Color(0xFFEEEAF6);

/// Dashboard premium da Gestão de Assinaturas — visão SaaS em tempo real.
class AssinaturasDashboardScreen extends StatefulWidget {
  const AssinaturasDashboardScreen({super.key});

  @override
  State<AssinaturasDashboardScreen> createState() =>
      _AssinaturasDashboardScreenState();
}

class _AssinaturasDashboardScreenState extends State<AssinaturasDashboardScreen> {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _dataHora = DateFormat('dd/MM/yyyy · HH:mm');

  late Stream<AssinaturasDashboardResumo> _streamResumo =
      AssinaturasDashboardService.streamResumo();

  void _recarregar() {
    setState(() {
      _streamResumo = AssinaturasDashboardService.streamResumo();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload pode manter instância antiga de AssinaturasDashboardResumo no snapshot.
    _recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundoPagina,
      body: StreamBuilder<AssinaturasDashboardResumo>(
        stream: _streamResumo,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErroState(onRetry: _recarregar);
          }

          final resumo =
              AssinaturasDashboardResumo.tentarNormalizar(snapshot.data);

          if (resumo == null) {
            return const _DashboardLoadingSkeleton();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroBanner(
                  resumo: resumo,
                  moeda: _moeda,
                  onVerClientes: () =>
                      context.navegarPainel('/assinaturas_clientes'),
                  onAtualizar: _recarregar,
                ),
                const SizedBox(height: 20),
                _KpiGrid(
                  resumo: resumo,
                  moeda: _moeda,
                ),
                const SizedBox(height: 20),
                _PainelSecundario(
                  resumo: resumo,
                  moeda: _moeda,
                  onVerInadimplencia: () =>
                      context.navegarPainel('/assinaturas_inadimplencia'),
                ),
                const SizedBox(height: 20),
                _TabelaRecentes(
                  assinaturas: resumo.ultimasAssinaturas,
                  moeda: _moeda,
                  onVerTodas: () =>
                      context.navegarPainel('/assinaturas_clientes'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Atualizado em ${_dataHora.format(DateTime.now())}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Hero MRR ───────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.resumo,
    required this.moeda,
    required this.onVerClientes,
    required this.onAtualizar,
  });

  final AssinaturasDashboardResumo resumo;
  final NumberFormat moeda;
  final VoidCallback onVerClientes;
  final VoidCallback onAtualizar;

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_roxo, _roxoClaro, Color(0xFFAB47BC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _roxo.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            left: largura > 700 ? 120 : 60,
            bottom: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _laranja.withValues(alpha: 0.12),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, largura > 700 ? 28 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.insights_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gestão de Assinaturas',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0.3,
                            ),
                          ),
                          Text(
                            'Receita recorrente mensal',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar',
                      onPressed: onAtualizar,
                      icon: Icon(Icons.refresh_rounded,
                          color: Colors.white.withValues(alpha: 0.9)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  moeda.format(resumo.receitaMensal),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: largura > 700 ? 42 : 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HeroChip(
                      icone: Icons.storefront_rounded,
                      texto:
                          '${resumo.lojasContratantes} loja${resumo.lojasContratantes == 1 ? '' : 's'} ativas',
                    ),
                    _HeroChip(
                      icone: Icons.layers_rounded,
                      texto:
                          '${resumo.planosAtivos} plano${resumo.planosAtivos == 1 ? '' : 's'} no catálogo',
                    ),
                    _HeroChip(
                      icone: Icons.verified_rounded,
                      texto: '${resumo.taxaAdimplencia}% adimplência',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onVerClientes,
                      icon: const Icon(Icons.people_alt_rounded, size: 18),
                      label: const Text('Ver assinaturas'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _roxo,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.navegarPainel('/assinaturas_planos'),
                      icon: Icon(Icons.widgets_outlined,
                          size: 18, color: Colors.white.withValues(alpha: 0.95)),
                      label: Text(
                        'Gerenciar planos',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
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
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            texto,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── KPIs ───────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.resumo,
    required this.moeda,
  });

  final AssinaturasDashboardResumo resumo;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width - 48;
    final cols = largura > 1100 ? 4 : (largura > 640 ? 2 : 1);
    const gap = 14.0;
    final cardWidth = cols == 1 ? largura : (largura - gap * (cols - 1)) / cols;

    final cards = [
      _KpiPremiumCard(
        titulo: 'Planos ativos',
        valor: '${resumo.planosAtivos}',
        subtitulo: 'Disponíveis para contratação',
        icone: Icons.widgets_outlined,
        cor: _roxo,
      ),
      _KpiPremiumCard(
        titulo: 'Assinaturas',
        valor: '${resumo.totalAssinaturas}',
        subtitulo:
            '${resumo.assinaturasAtivas} ativas · ${resumo.inadimplentes} em atraso',
        icone: Icons.autorenew_rounded,
        cor: const Color(0xFF0288D1),
      ),
      _KpiPremiumCard(
        titulo: 'MRR confirmado',
        valor: moeda.format(resumo.receitaMensal),
        subtitulo: 'Ativos + em atraso',
        icone: Icons.payments_outlined,
        cor: _laranja,
      ),
      _KpiPremiumCard(
        titulo: 'Inadimplência',
        valor: resumo.inadimplentes == 0 ? '0' : '${resumo.inadimplentes}',
        subtitulo: resumo.valorInadimplencia > 0
            ? '${moeda.format(resumo.valorInadimplencia)} em aberto'
            : 'Carteira saudável',
        icone: Icons.warning_amber_rounded,
        cor: resumo.inadimplentes > 0 ? _vermelho : _verde,
        destaqueAlerta: resumo.inadimplentes > 0,
      ),
    ];

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
    );
  }
}

class _KpiPremiumCard extends StatelessWidget {
  const _KpiPremiumCard({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
    this.subtitulo,
    this.destaqueAlerta = false,
  });

  final String titulo;
  final String valor;
  final String? subtitulo;
  final IconData icone;
  final Color cor;
  final bool destaqueAlerta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: destaqueAlerta ? _vermelho.withValues(alpha: 0.25) : _borda,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icone, color: cor, size: 20),
              ),
              const Spacer(),
              if (destaqueAlerta)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _vermelhoFundo,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Atenção',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _vermelho,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textoSecundario,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _textoPrimario,
              letterSpacing: -0.5,
            ),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitulo!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: _textoSecundario,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Painel secundário: distribuição + saúde ────────────────────────────────

class _PainelSecundario extends StatelessWidget {
  const _PainelSecundario({
    required this.resumo,
    required this.moeda,
    required this.onVerInadimplencia,
  });

  final AssinaturasDashboardResumo resumo;
  final NumberFormat moeda;
  final VoidCallback onVerInadimplencia;

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final empilhado = largura < 960;

    final distribuicao = _DistribuicaoStatus(resumo: resumo);
    final saude = _PainelSaude(
      resumo: resumo,
      moeda: moeda,
      onVerInadimplencia: onVerInadimplencia,
    );

    if (empilhado) {
      return Column(
        children: [
          distribuicao,
          const SizedBox(height: 14),
          saude,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: distribuicao),
          const SizedBox(width: 14),
          Expanded(flex: 2, child: saude),
        ],
      ),
    );
  }
}

class _DistribuicaoStatus extends StatelessWidget {
  const _DistribuicaoStatus({required this.resumo});

  final AssinaturasDashboardResumo resumo;

  @override
  Widget build(BuildContext context) {
    final total = resumo.totalAssinaturas;

    return _PainelSurface(
      titulo: 'Distribuição por status',
      subtitulo: 'Panorama da base de assinantes',
      icone: Icons.donut_large_rounded,
      child: total == 0
          ? _EmptyInline(
              icone: Icons.pie_chart_outline_rounded,
              titulo: 'Sem assinaturas ainda',
              descricao:
                  'A distribuição aparecerá quando lojistas contratarem planos.',
            )
          : Column(
              children: [
                _BarraStatus(
                  rotulo: 'Ativo',
                  quantidade: resumo.assinaturasAtivas,
                  total: total,
                  cor: _verde,
                ),
                const SizedBox(height: 12),
                _BarraStatus(
                  rotulo: 'Em atraso',
                  quantidade: resumo.inadimplentes,
                  total: total,
                  cor: _laranja,
                ),
                const SizedBox(height: 12),
                _BarraStatus(
                  rotulo: 'Suspenso',
                  quantidade: resumo.assinaturasSuspensas,
                  total: total,
                  cor: _vermelho,
                ),
                const SizedBox(height: 12),
                _BarraStatus(
                  rotulo: 'Cancelado',
                  quantidade: resumo.assinaturasCanceladas,
                  total: total,
                  cor: _textoSecundario,
                ),
              ],
            ),
    );
  }
}

class _BarraStatus extends StatelessWidget {
  const _BarraStatus({
    required this.rotulo,
    required this.quantidade,
    required this.total,
    required this.cor,
  });

  final String rotulo;
  final int quantidade;
  final int total;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? quantidade / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              rotulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
            const Spacer(),
            Text(
              '$quantidade · ${(pct * 100).round()}%',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: cor.withValues(alpha: 0.12),
            color: cor,
          ),
        ),
      ],
    );
  }
}

class _PainelSaude extends StatelessWidget {
  const _PainelSaude({
    required this.resumo,
    required this.moeda,
    required this.onVerInadimplencia,
  });

  final AssinaturasDashboardResumo resumo;
  final NumberFormat moeda;
  final VoidCallback onVerInadimplencia;

  @override
  Widget build(BuildContext context) {
    final saudeOk = resumo.inadimplentes == 0 && resumo.totalAssinaturas > 0;
    final corScore = resumo.taxaAdimplencia >= 80
        ? _verde
        : resumo.taxaAdimplencia >= 50
            ? _laranja
            : _vermelho;

    return _PainelSurface(
      titulo: 'Saúde da carteira',
      subtitulo: 'Indicadores operacionais',
      icone: Icons.monitor_heart_outlined,
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        corScore.withValues(alpha: 0.08),
                        corScore.withValues(alpha: 0.03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: corScore.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: resumo.totalAssinaturas == 0
                                  ? 0
                                  : resumo.taxaAdimplencia / 100,
                              strokeWidth: 5,
                              backgroundColor: corScore.withValues(alpha: 0.15),
                              color: corScore,
                            ),
                            Text(
                              resumo.totalAssinaturas == 0
                                  ? '—'
                                  : '${resumo.taxaAdimplencia}%',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _textoPrimario,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resumo.totalAssinaturas == 0
                                  ? 'Aguardando contratações'
                                  : saudeOk
                                      ? 'Carteira saudável'
                                      : 'Requer acompanhamento',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _textoPrimario,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              resumo.totalAssinaturas == 0
                                  ? 'Publique planos e aguarde lojistas.'
                                  : '${resumo.assinaturasAtivas} de ${resumo.totalAssinaturas} assinaturas em dia',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: _textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (resumo.pendenciasInadimplencia.isEmpty)
                  _InsightTile(
                    icone: Icons.check_circle_outline_rounded,
                    cor: _verde,
                    fundo: _verdeFundo,
                    titulo: 'Nenhuma pendência crítica',
                    descricao: 'Não há lojas em atraso no momento.',
                  )
                else ...[
                  for (final c in resumo.pendenciasInadimplencia)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PendenciaTile(
                        assinatura: c,
                        moeda: moeda,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: onVerInadimplencia,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('Ver inadimplência'),
                    style: TextButton.styleFrom(foregroundColor: _roxo),
                  ),
                ],
              ],
            ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.icone,
    required this.cor,
    required this.fundo,
    required this.titulo,
    required this.descricao,
  });

  final IconData icone;
  final Color cor;
  final Color fundo;
  final String titulo;
  final String descricao;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textoPrimario,
                  ),
                ),
                Text(
                  descricao,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
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

class _PendenciaTile extends StatelessWidget {
  const _PendenciaTile({required this.assinatura, required this.moeda});

  final ClienteAssinaturaModel assinatura;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _vermelhoFundo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _vermelho.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _vermelho.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.storefront_rounded,
                size: 18, color: _vermelho),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assinatura.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textoPrimario,
                  ),
                ),
                Text(
                  '${assinatura.planName} · ${moeda.format(assinatura.monthlyAmount)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: _textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Em atraso',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _vermelho,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tabela recentes ──────────────────────────────────────────────────────────

class _TabelaRecentes extends StatelessWidget {
  const _TabelaRecentes({
    required this.assinaturas,
    required this.moeda,
    required this.onVerTodas,
  });

  final List<ClienteAssinaturaModel> assinaturas;
  final NumberFormat moeda;
  final VoidCallback onVerTodas;

  @override
  Widget build(BuildContext context) {
    return _PainelSurface(
      titulo: 'Assinaturas recentes',
      subtitulo: 'Últimas lojas na base',
      icone: Icons.receipt_long_outlined,
      trailing: TextButton.icon(
        onPressed: onVerTodas,
        icon: const Icon(Icons.north_east_rounded, size: 14),
        label: const Text('Ver todas'),
        style: TextButton.styleFrom(foregroundColor: _roxo),
      ),
      child: assinaturas.isEmpty
          ? _EmptyInline(
              icone: Icons.inbox_outlined,
              titulo: 'Nenhuma assinatura registrada',
              descricao:
                  'Os lojistas aparecerão aqui ao contratarem planos ou módulos.',
            )
          : Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFCFE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _ColHeader('Loja / Lojista', flex: 3),
                      _ColHeader('Plano', flex: 2),
                      _ColHeader('Valor', flex: 1),
                      _ColHeader('Vencimento', flex: 1),
                      SizedBox(
                        width: 90,
                        child: Text(
                          'Status',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _textoSecundario,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                for (var i = 0; i < assinaturas.length; i++)
                  _LinhaAssinatura(
                    assinatura: assinaturas[i],
                    moeda: moeda,
                    isUltima: i == assinaturas.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.texto, {this.flex = 1});

  final String texto;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _textoSecundario,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _LinhaAssinatura extends StatelessWidget {
  const _LinhaAssinatura({
    required this.assinatura,
    required this.moeda,
    required this.isUltima,
  });

  final ClienteAssinaturaModel assinatura;
  final NumberFormat moeda;
  final bool isUltima;

  Color _corStatus(String status) {
    switch (status) {
      case 'ativo':
        return _verde;
      case 'em_atraso':
        return _laranja;
      case 'suspenso':
        return _vermelho;
      default:
        return _textoSecundario;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicial = assinatura.storeName.isNotEmpty
        ? assinatura.storeName[0].toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isUltima
            ? null
            : Border(bottom: BorderSide(color: _borda.withValues(alpha: 0.7))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_roxo.withValues(alpha: 0.85), _roxoClaro],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    inicial,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assinatura.storeName.isNotEmpty
                            ? assinatura.storeName
                            : 'Loja sem nome',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textoPrimario,
                        ),
                      ),
                      Text(
                        assinatura.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: _textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              assinatura.planName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoPrimario,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              moeda.format(assinatura.monthlyAmount),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textoPrimario,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              assinatura.nextBillingDateExibir,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: _textoSecundario,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _corStatus(assinatura.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  assinatura.statusRotulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _corStatus(assinatura.status),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Componentes base ───────────────────────────────────────────────────────

class _PainelSurface extends StatelessWidget {
  const _PainelSurface({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.child,
    this.trailing,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _roxoSuave,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, size: 18, color: _roxo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textoPrimario,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({
    required this.icone,
    required this.titulo,
    required this.descricao,
  });

  final IconData icone;
  final String titulo;
  final String descricao;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icone, size: 36, color: _roxo.withValues(alpha: 0.35)),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textoPrimario,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            descricao,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _textoSecundario,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading ──────────────────────────────────────────────────────────────────

class _DashboardLoadingSkeleton extends StatelessWidget {
  const _DashboardLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _roxoSuave,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(strokeWidth: 2.5, color: _roxo),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Carregando dashboard…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sincronizando planos e assinaturas',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: _textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroState extends StatelessWidget {
  const _ErroState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _vermelhoFundo,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off_rounded,
                  size: 36, color: _vermelho),
            ),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar o dashboard',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textoPrimario,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Não foi possível ler os dados de assinaturas. Tente novamente.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: _textoSecundario,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                backgroundColor: _roxo,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
