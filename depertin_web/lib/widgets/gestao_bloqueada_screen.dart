import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/cliente_assinatura_model.dart';
import '../navigation/painel_navigation_scope.dart';
import '../services/assinaturas_clientes_service.dart';
import '../services/assinatura_gestao_comercial_refresh.dart';
import 'assinatura_pagamento_modal.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  GestaoBloqueadaScreen — Tela premium de bloqueio por inadimplência
//  Exibida quando o lojista tenta acessar o Gestão Comercial e sua
//  assinatura está vencida + período de suspensão atingido.
// ═══════════════════════════════════════════════════════════════════════════

class GestaoBloqueadaScreen extends StatefulWidget {
  final ClienteAssinaturaModel assinatura;
  final String lojaId;
  final String lojaNome;
  final String ownerName;
  final String ownerEmail;

  const GestaoBloqueadaScreen({
    super.key,
    required this.assinatura,
    required this.lojaId,
    required this.lojaNome,
    required this.ownerName,
    required this.ownerEmail,
  });

  @override
  State<GestaoBloqueadaScreen> createState() => _GestaoBloqueadaScreenState();
}

class _GestaoBloqueadaScreenState extends State<GestaoBloqueadaScreen> {
  ClienteAssinaturaModel? _assinaturaAtual;

  @override
  void initState() {
    super.initState();
    _assinaturaAtual = widget.assinatura;
    _escutarAssinatura();
  }

  void _escutarAssinatura() {
    FirebaseFirestore.instance
        .collection(AssinaturasClientesService.colecao)
        .doc(widget.assinatura.id)
        .snapshots()
        .listen((snap) {
      if (!mounted || snap.data() == null) return;
      final atualizada = ClienteAssinaturaModel.fromFirestore(snap);
      setState(() => _assinaturaAtual = atualizada);
    });
  }

  void _abrirPagamento() {
    if (_assinaturaAtual == null) return;
    final a = _assinaturaAtual!;
    AssinaturaPagamentoModal.mostrar(
      context,
      plano: {
        'id': a.planId,
        'nome': a.planName,
        'descricao': 'Renovação de assinatura',
        'valor': a.totalAtualizado,
        'modulos': a.modulosExtras,
      },
      lojaId: widget.lojaId,
      lojaNome: widget.lojaNome,
      ownerName: widget.ownerName,
      ownerEmail: widget.ownerEmail,
      ehRenovacao: true,
      assinaturaId: a.id,
      onPagamentoAprovado: () {
        AssinaturaGestaoComercialRefresh.instance.notificarPagamentoAprovado();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            context.navegarPainel('/comercial_clientes');
          } catch (_) {
            // Fallback
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _assinaturaAtual;
    if (a == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final vs = NumberFormat('#,##0.00', 'pt_BR');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Card principal ──
              Container(
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFEEEAF6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    children: [
                      // ── Header com gradiente ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF6E22D9),
                              Color(0xFF8E3EE6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Ícone grande
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Seu plano está bloqueado',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sua assinatura encontra-se vencida. Para continuar utilizando o Gestão Comercial, realize o pagamento.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Detalhes financeiros ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
                        child: Column(
                          children: [
                            _linhaDetalhe('Plano', a.planName, const Color(0xFF6E22D9)),
                            const Divider(height: 24, color: Color(0xFFF0EFF5)),
                            _linhaDetalhe(
                              'Valor original',
                              'R\$ ${vs.format(a.monthlyAmount)}',
                              const Color(0xFF17152A),
                            ),
                            const SizedBox(height: 10),
                            _linhaDetalhe(
                              'Dias em atraso',
                              '${a.diasEmAtrasoReal} dia(s)',
                              const Color(0xFFF04438),
                            ),
                            const SizedBox(height: 10),
                            _linhaDetalhe(
                              'Multa (${a.multaPercentual.toStringAsFixed(1).replaceAll('.', ',')}%)',
                              a.multaCalculada > 0
                                  ? 'R\$ ${vs.format(a.multaCalculada)}'
                                  : '—',
                              a.multaCalculada > 0
                                  ? const Color(0xFFF04438)
                                  : const Color(0xFF6E7894),
                            ),
                            const SizedBox(height: 10),
                            _linhaDetalhe(
                              'Juros (${a.jurosPercentual.toStringAsFixed(3).replaceAll('.', ',')}% a.d.)',
                              a.jurosCalculados > 0
                                  ? 'R\$ ${vs.format(a.jurosCalculados)}'
                                  : '—',
                              a.jurosCalculados > 0
                                  ? const Color(0xFFF04438)
                                  : const Color(0xFF6E7894),
                            ),
                            const Divider(height: 24, color: Color(0xFFF0EFF5)),
                            _linhaDetalhe(
                              'Total atualizado',
                              'R\$ ${vs.format(a.totalAtualizado)}',
                              const Color(0xFF17152A),
                              bold: true,
                              grande: true,
                            ),
                            const SizedBox(height: 10),
                            _linhaDetalhe(
                              'Próximo vencimento',
                              a.nextBillingDateExibir,
                              const Color(0xFF6E7894),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  'Status',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: const Color(0xFF6E7894),
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: a.statusExibicaoFundo,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    a.statusExibicaoRotulo,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: a.statusExibicaoCor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // ── Botão de pagamento ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: _abrirPagamento,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7D20E8),
                                      Color(0xFF6E22D9),
                                      Color(0xFFFF8F00),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6E22D9)
                                          .withValues(alpha: 0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.payment_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Efetuar pagamento — '
                                        'R\$ ${vs.format(a.totalAtualizado)}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _linhaDetalhe(
    String label,
    String valor,
    Color corValor, {
    bool bold = false,
    bool grande = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF6E7894),
            ),
          ),
        ),
        Text(
          valor,
          style: GoogleFonts.plusJakartaSans(
            fontSize: grande ? 18 : 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: corValor,
          ),
        ),
      ],
    );
  }
}
