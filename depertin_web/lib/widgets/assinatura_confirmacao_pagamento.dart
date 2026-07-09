import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  AssinaturaConfirmacaoPagamento — Modal de confirmação premium
// ═══════════════════════════════════════════════════════════════════════════

class AssinaturaConfirmacaoPagamento extends StatelessWidget {
  final bool aprovado;
  final String planoNome;
  final String mensagem;
  final VoidCallback? onAcessarGestao;

  const AssinaturaConfirmacaoPagamento({
    super.key,
    required this.aprovado,
    required this.planoNome,
    required this.mensagem,
    this.onAcessarGestao,
  });

  static Future<void> mostrar(
    BuildContext context, {
    required bool aprovado,
    required String planoNome,
    required String mensagem,
    VoidCallback? onAcessarGestao,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.50),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            type: MaterialType.transparency,
            child: AssinaturaConfirmacaoPagamento(
              aprovado: aprovado,
              planoNome: planoNome,
              mensagem: mensagem,
              onAcessarGestao: onAcessarGestao,
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, secAnim, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 60, offset: const Offset(0, 20)),
            BoxShadow(color: _roxo.withValues(alpha: 0.06), blurRadius: 40),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícone de sucesso animado
            _buildIconeSucesso(),
            const SizedBox(height: 24),

            // Título
            Text(
              'Pagamento aprovado!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _roxo,
              ),
            ),
            const SizedBox(height: 12),

            // Nome do plano
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _roxo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                planoNome,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _roxo,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Mensagem
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: DiPertinTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),

            // Detalhes de liberação
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: DiPertinTheme.successGreen),
                const SizedBox(width: 6),
                Text(
                  'Gestão Comercial liberado',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: DiPertinTheme.successGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Botão
            SizedBox(
              width: double.infinity,
              height: 54,
              child: _BotaoConfirmacao(
                label: 'Acessar Gestão Comercial',
                onTap: () {
                  Navigator.of(context).pop();
                  final cb = onAcessarGestao;
                  if (cb != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => cb());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconeSucesso() {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [DiPertinTheme.successGreen, Color(0xFF4ADE80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(44),
        boxShadow: [
          BoxShadow(
            color: DiPertinTheme.successGreen.withValues(alpha: 0.3),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, size: 44, color: Colors.white),
    );
  }
}

const Color _roxo = DiPertinTheme.primaryRoxo;

// ═══════════════════════════════════════════════════════════════════════════
//  Botão de confirmação
// ═══════════════════════════════════════════════════════════════════════════
class _BotaoConfirmacao extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _BotaoConfirmacao({required this.label, required this.onTap});

  @override
  State<_BotaoConfirmacao> createState() => _BotaoConfirmacaoState();
}

class _BotaoConfirmacaoState extends State<_BotaoConfirmacao> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          transform: _hover ? (Matrix4.diagonal3Values(1.02, 1.02, 1)) : Matrix4.identity(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [DiPertinTheme.primaryRoxoEscuro, DiPertinTheme.primaryRoxo, DiPertinTheme.secondaryLaranja],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: _hover
                ? [BoxShadow(color: _roxo.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 1)]
                : [BoxShadow(color: _roxo.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
