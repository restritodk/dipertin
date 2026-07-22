import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/cliente_assinatura_model.dart';
import '../navigation/painel_navigation_scope.dart';
import '../services/assinatura_gestao_comercial_refresh.dart';
import '../services/assinatura_gestao_comercial_service.dart';
import '../widgets/assinatura_pagamento_modal.dart';

/// Página premium: lojista com GC ativo, mas sem módulo Emissão de NF-e.
///
/// Apenas layout visual — lógica de carga/upgrade permanece inalterada.
class ComercialUpgradeFiscalScreen extends StatefulWidget {
  const ComercialUpgradeFiscalScreen({super.key});

  @override
  State<ComercialUpgradeFiscalScreen> createState() =>
      _ComercialUpgradeFiscalScreenState();
}

class _ComercialUpgradeFiscalScreenState
    extends State<ComercialUpgradeFiscalScreen> {
  // Identidade visual premium desta tela (referência de desbloqueio).
  static const _roxo = Color(0xFF6A11CB);
  static const _roxoEscuro = Color(0xFF32106D);
  static const _roxoHero1 = Color(0xFF1D0D5F);
  static const _roxoHero2 = Color(0xFF5A1DB5);
  static const _roxoHero3 = Color(0xFF7A1FFF);
  static const _laranja = Color(0xFFFF8A00);
  static const _texto = Color(0xFF1A1A2E);
  static const _muted = Color(0xFF64748B);
  static const _fundo = Color(0xFFF7F8FC);
  static const _sombraCard = Color(0x146A11CB); // rgba(106,17,203,.08)

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  bool _erro = false;
  AssinaturaGestaoComercialContexto? _ctx;
  ClienteAssinaturaModel? _assinaturaAtual;
  List<Map<String, dynamic>> _planosUpgrade = const [];
  String? _processandoPlanoId;

  @override
  void initState() {
    super.initState();
    AssinaturaGestaoComercialRefresh.instance.addListener(_onRefresh);
    _carregar();
  }

  @override
  void dispose() {
    AssinaturaGestaoComercialRefresh.instance.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (!mounted) return;
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = false;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('sem auth');

      final ctx = await AssinaturaGestaoComercialService.carregarContexto()
          .timeout(const Duration(seconds: 15));

      final subSnap = await FirebaseFirestore.instance
          .collection('assinaturas_clientes')
          .where('store_id', isEqualTo: uid)
          .get()
          .timeout(const Duration(seconds: 15));

      final assinaturas =
          subSnap.docs.map(ClienteAssinaturaModel.fromFirestore).toList();

      // Se já liberou NF-e (pagamento confirmado), remonta o gate → tela fiscal.
      if (AssinaturaGestaoComercialService.lojistaTemModuloEmissaoNfe(
        assinaturas,
        ctx,
      )) {
        AssinaturaGestaoComercialRefresh.instance.notificarPagamentoAprovado();
        if (mounted) {
          try {
            context.navegarPainel('/modulo_fiscal');
          } catch (_) {}
        }
      }

      final atual = AssinaturaGestaoComercialService.assinaturaAtivaGestao(
        assinaturas,
        ctx,
      );

      final planoAtualId = atual == null
          ? null
          : AssinaturaGestaoComercialService.resolverPlanoDocId(atual, ctx);

      final planosUpgrade = <Map<String, dynamic>>[];
      for (final entry in ctx.planosPorId.entries) {
        final data = entry.value;
        if (data['ativo'] == false) continue;
        if (planoAtualId != null && entry.key == planoAtualId) continue;
        if (!AssinaturaGestaoComercialService.planoDocTemEmissaoNfe(
          data,
          ctx: ctx,
        )) {
          continue;
        }
        planosUpgrade.add({'id': entry.key, ...data});
      }
      planosUpgrade.sort((a, b) {
        final va = (a['valor'] as num?)?.toDouble() ?? 0;
        final vb = (b['valor'] as num?)?.toDouble() ?? 0;
        return va.compareTo(vb);
      });

      if (!mounted) return;
      setState(() {
        _ctx = ctx;
        _assinaturaAtual = atual;
        _planosUpgrade = planosUpgrade;
        _carregando = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[UpgradeFiscal] erro: $e');
      if (!mounted) return;
      setState(() {
        _erro = true;
        _carregando = false;
      });
    }
  }

  Future<void> _atualizarParaPlano(Map<String, dynamic> plano) async {
    if (_processandoPlanoId != null) return;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    if (uid.isEmpty) return;

    setState(() => _processandoPlanoId = plano['id']?.toString());
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final d = doc.data() ?? {};
      final nome = (d['nome'] ?? d['nome_completo'] ?? d['displayName'] ?? '')
          .toString();
      final lojaNome =
          (d['nome_loja'] ?? d['loja_nome'] ?? nome).toString();

      if (!mounted) return;
      await AssinaturaPagamentoModal.mostrar(
        context,
        plano: plano,
        lojaId: uid,
        lojaNome: lojaNome,
        ownerName: nome,
        ownerEmail: user?.email ?? '',
        onPagamentoAprovado: () {
          AssinaturaGestaoComercialRefresh.instance.notificarPagamentoAprovado();
          _carregar();
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              context.navegarPainel('/modulo_fiscal');
            } catch (_) {}
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Não foi possível iniciar a atualização',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Verifique sua conexão e tente novamente.',
            style: GoogleFonts.plusJakartaSans(color: _muted),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: _roxo),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _processandoPlanoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: _roxo),
            )
          : _erro
              ? _estadoErro()
              : RefreshIndicator(
                  color: _roxo,
                  onRefresh: _carregar,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _heroBanner(),
                            const SizedBox(height: 24),
                            _cardPlanoAtual(),
                            const SizedBox(height: 32),
                            Text(
                              'Planos com Emissão de NF-e',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _texto,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Escolha um plano que inclui o módulo fiscal.\n'
                              'O acesso será liberado após confirmação do pagamento.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                height: 1.45,
                                color: _muted,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_planosUpgrade.isEmpty)
                              _semPlanosNfe()
                            else
                              _gradePlanosUpgrade(),
                            const SizedBox(height: 32),
                            _secaoBeneficios(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  // ─── 1. Hero Banner ───────────────────────────────────────────────────────

  Widget _heroBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(minHeight: 220, maxHeight: 260),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_roxoHero1, _roxoHero2, _roxoHero3],
            stops: [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: _roxo.withValues(alpha: 0.28),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _HeroWavesPainter()),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _HeroParticlesPainter()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 24, 28),
              child: LayoutBuilder(
                builder: (context, c) {
                  final largo = c.maxWidth >= 720;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _laranja,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: _laranja.withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.workspace_premium_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Recurso premium',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Desbloqueie o Módulo Fiscal',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: largo ? 36 : 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.15,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Seu plano atual não inclui a emissão de NF-e.\n'
                              'Atualize seu plano para emitir, consultar e gerenciar '
                              'notas fiscais diretamente pelo DiPertin.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: largo ? 16 : 14,
                                height: 1.5,
                                color: Colors.white.withValues(alpha: 0.90),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (largo) ...[
                        const SizedBox(width: 16),
                        const SizedBox(
                          width: 220,
                          height: 180,
                          child: _HeroIlustracaoFiscal(),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 2. Plano atual ───────────────────────────────────────────────────────

  Widget _cardPlanoAtual() {
    final a = _assinaturaAtual;
    final ctx = _ctx;
    if (a == null) {
      return _aviso(
        'Assinatura não encontrada',
        'Não encontramos uma assinatura ativa de Gestão Comercial para esta loja.',
      );
    }

    final planoData = ctx == null
        ? null
        : (() {
            final id =
                AssinaturaGestaoComercialService.resolverPlanoDocId(a, ctx);
            return id == null ? null : ctx.planosPorId[id];
          })();

    final recorrencia =
        (planoData?['tipo_recorrencia'] ?? 'Mensal').toString();
    final statusLower = a.status.toLowerCase();
    final ativo = statusLower.contains('ativ') ||
        statusLower == 'active' ||
        statusLower == 'pago';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: _sombraCard,
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final empilhar = c.maxWidth < 780;
          final infoPlano = Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _roxo.withValues(alpha: 0.18),
                      const Color(0xFF8A2BE2).withValues(alpha: 0.28),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: _roxo,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seu plano atual',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _roxo,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.planName.isEmpty ? 'Plano contratado' : a.planName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _texto,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_moeda.format(a.monthlyAmount)} / $recorrencia',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _roxo,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final indicadores = Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _indicadorPlano(
                Icons.event_rounded,
                'Vencimento: ${a.nextBillingDateExibir}',
              ),
              _indicadorPlano(
                Icons.timelapse_rounded,
                'Tolerância: ${a.toleranciaDias} dia(s)',
              ),
              _indicadorStatus(a.status, ativo),
            ],
          );

          final botao = _BotaoOutlinePremium(
            label: 'Gerenciar plano',
            onTap: () {
              try {
                context.navegarPainel('/comercial_dashboard');
              } catch (_) {}
            },
          );

          if (empilhar) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoPlano,
                const SizedBox(height: 16),
                indicadores,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerLeft, child: botao),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 4, child: infoPlano),
              Expanded(flex: 5, child: indicadores),
              botao,
            ],
          );
        },
      ),
    );
  }

  Widget _indicadorPlano(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _roxo.withValues(alpha: 0.75)),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
      ],
    );
  }

  Widget _indicadorStatus(String status, bool ativo) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ativo ? const Color(0xFF22C55E) : _muted,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Status: ${_capitalizar(status)}',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
      ],
    );
  }

  String _capitalizar(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }

  // ─── 3. Planos com NF-e ───────────────────────────────────────────────────

  Widget _gradePlanosUpgrade() {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 700 ? 2 : 1;
        if (cols == 1) {
          return Column(
            children: [
              for (var i = 0; i < _planosUpgrade.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _cardPlanoUpgrade(
                  _planosUpgrade[i],
                  recomendado: i == 0,
                ),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (var i = 0; i < _planosUpgrade.length; i++)
              SizedBox(
                width: (c.maxWidth - 16) / 2,
                child: _cardPlanoUpgrade(
                  _planosUpgrade[i],
                  recomendado: i == 0,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _cardPlanoUpgrade(
    Map<String, dynamic> plano, {
    required bool recomendado,
  }) {
    final id = plano['id']?.toString() ?? '';
    final nome = (plano['nome'] ?? 'Plano').toString();
    final valor = (plano['valor'] as num?)?.toDouble() ?? 0;
    final recorrencia = (plano['tipo_recorrencia'] ?? 'Mensal').toString();
    final duracao = (plano['duracao_dias'] as num?)?.toInt() ?? 30;
    final tolerancia = (plano['tolerancia_dias'] as num?)?.toInt() ?? 0;
    final vencimento = (plano['vencimento_padrao'] ?? '—').toString();
    final modulos = List<String>.from(plano['modulos'] as List? ?? []);
    final processando = _processandoPlanoId == id;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: recomendado
                ? Border.all(color: _roxo.withValues(alpha: 0.22), width: 1.5)
                : null,
            boxShadow: const [
              BoxShadow(
                color: _sombraCard,
                blurRadius: 30,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nome,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _texto,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_moeda.format(valor)} / $recorrencia',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _roxo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Inclui NF-e',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF16A34A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _metaChip(
                    Icons.calendar_month_rounded,
                    'Duração: $duracao dias',
                  ),
                  _metaChip(
                    Icons.event_available_rounded,
                    'Venc.: $vencimento',
                  ),
                  if (tolerancia > 0)
                    _metaChip(
                      Icons.timelapse_rounded,
                      'Tolerância: $tolerancia dia(s)',
                    ),
                ],
              ),
              if (modulos.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: modulos.map((m) {
                    final ehNfe = AssinaturaGestaoComercialService
                        .textoIndicaEmissaoNfe(m);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: ehNfe
                            ? const Color(0xFFFFF3E0)
                            : const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ehNfe) ...[
                            const Icon(
                              Icons.receipt_long_rounded,
                              size: 14,
                              color: Color(0xFFE65100),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            m,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ehNfe
                                  ? const Color(0xFFE65100)
                                  : _roxoEscuro,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 22),
              if (recomendado)
                _BotaoGradientPremium(
                  label: processando
                      ? 'Abrindo pagamento…'
                      : 'Atualizar para este plano',
                  loading: processando,
                  onTap: processando ? null : () => _atualizarParaPlano(plano),
                )
              else
                _BotaoOutlinePremium(
                  label: processando
                      ? 'Abrindo pagamento…'
                      : 'Atualizar para este plano',
                  loading: processando,
                  fullWidth: true,
                  icon: Icons.upgrade_rounded,
                  onTap: processando ? null : () => _atualizarParaPlano(plano),
                ),
            ],
          ),
        ),
        if (recomendado)
          Positioned(
            top: -11,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_roxo, Color(0xFF8A2BE2)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _roxo.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                'MAIS ESCOLHIDO',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── 4. Benefícios ────────────────────────────────────────────────────────

  Widget _secaoBeneficios() {
    const itens = [
      (
        Icons.verified_user_outlined,
        'Emissão simplificada',
        'Emita NF-e de forma rápida e segura.',
      ),
      (
        Icons.description_outlined,
        'Gestão completa',
        'Consulte, cancele e gerencie suas notas fiscais.',
      ),
      (
        Icons.cloud_outlined,
        '100% em nuvem',
        'Acesse de qualquer lugar, a qualquer momento.',
      ),
      (
        Icons.lock_outline_rounded,
        'Segurança garantida',
        'Seus dados fiscais protegidos com criptografia avançada.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: _sombraCard,
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 900
              ? 4
              : c.maxWidth >= 560
                  ? 2
                  : 1;
          return Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              for (final item in itens)
                SizedBox(
                  width: cols == 1
                      ? c.maxWidth
                      : (c.maxWidth - (cols - 1) * 20) / cols,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _roxo.withValues(alpha: 0.25),
                          ),
                          color: _roxo.withValues(alpha: 0.06),
                        ),
                        child: Icon(item.$1, color: _roxo, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _texto,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.$3,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                height: 1.4,
                                color: _muted,
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
        },
      ),
    );
  }

  Widget _semPlanosNfe() {
    return _aviso(
      'Nenhum plano com NF-e disponível',
      'No momento não há planos ativos que incluam Emissão de NF-e. '
          'Fale com o suporte DiPertin ou tente novamente mais tarde.',
    );
  }

  Widget _aviso(String titulo, String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _laranja.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _laranja),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    color: _texto,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  msg,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _muted),
        ),
      ],
    );
  }

  Widget _estadoErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: _muted),
            const SizedBox(height: 12),
            Text(
              'Não foi possível carregar os planos',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _texto,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _carregar,
              style: FilledButton.styleFrom(backgroundColor: _roxo),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Botões premium (só UI)
// ═══════════════════════════════════════════════════════════════════════════

class _BotaoGradientPremium extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _BotaoGradientPremium({
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  State<_BotaoGradientPremium> createState() => _BotaoGradientPremiumState();
}

class _BotaoGradientPremiumState extends State<_BotaoGradientPremium> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF8A2BE2)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A11CB).withValues(
                alpha: _hover ? 0.45 : 0.22,
              ),
              blurRadius: _hover ? 18 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons.upgrade_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BotaoOutlinePremium extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool fullWidth;
  final IconData? icon;

  const _BotaoOutlinePremium({
    required this.label,
    this.onTap,
    this.loading = false,
    this.fullWidth = false,
    this.icon,
  });

  @override
  State<_BotaoOutlinePremium> createState() => _BotaoOutlinePremiumState();
}

class _BotaoOutlinePremiumState extends State<_BotaoOutlinePremium> {
  static const _roxo = Color(0xFF6A11CB);
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: widget.fullWidth ? double.infinity : null,
        height: 48,
        decoration: BoxDecoration(
          color: _hover ? _roxo.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _roxo, width: 1.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.fullWidth ? 12 : 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize:
                    widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (widget.loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _roxo,
                      ),
                    )
                  else if (widget.icon != null)
                    Icon(widget.icon, size: 18, color: _roxo)
                  else
                    const Icon(Icons.arrow_forward_rounded,
                        size: 16, color: _roxo),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: GoogleFonts.plusJakartaSans(
                      color: _roxo,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ilustração + painters do hero (sem assets externos)
// ═══════════════════════════════════════════════════════════════════════════

class _HeroIlustracaoFiscal extends StatelessWidget {
  const _HeroIlustracaoFiscal();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Reflexo / plataforma
        Positioned(
          bottom: 8,
          child: Container(
            width: 140,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFB388FF).withValues(alpha: 0.55),
                  Colors.transparent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7A1FFF).withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
        // Escudo
        Container(
          width: 110,
          height: 128,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
              bottomLeft: Radius.circular(48),
              bottomRight: Radius.circular(48),
            ),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9C4DFF), Color(0xFF5A1DB5), Color(0xFF32106D)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7A1FFF).withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.lock_rounded,
              color: Color(0xFFFFB300),
              size: 42,
            ),
          ),
        ),
        // Documento NF-e flutuante
        Positioned(
          right: 8,
          top: 28,
          child: Transform.rotate(
            angle: 0.12,
            child: Container(
              width: 64,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'NF-e',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF6A11CB),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9D5FF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    height: 4,
                    width: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Brilho neon
        Positioned(
          left: 18,
          top: 22,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.35),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.5),
                  blurRadius: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.10);

    for (var i = 0; i < 4; i++) {
      final path = Path();
      final yBase = size.height * (0.35 + i * 0.14);
      path.moveTo(0, yBase);
      for (double x = 0; x <= size.width; x += 8) {
        final y = yBase +
            math.sin((x / size.width) * math.pi * 2 + i) * (10.0 + i * 3);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }

    // Glow suave no canto direito
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.85, size.height * 0.45),
        size.width * 0.35,
        [
          const Color(0xFFB388FF).withValues(alpha: 0.22),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.45),
      size.width * 0.35,
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeroParticlesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 28; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.8 + rnd.nextDouble() * 2.2;
      paint.color = Colors.white.withValues(alpha: 0.12 + rnd.nextDouble() * 0.25);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
