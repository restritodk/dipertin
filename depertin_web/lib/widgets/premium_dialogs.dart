import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Cores DiPertin ──────────────────────────────────────────
const Color _roxoPrimario = Color(0xFF6A1B9A);
const Color _roxoClaro = Color(0xFF8E24AA);
const Color _textoPrimario = Color(0xFF17152A);
const Color _textoSecundario = Color(0xFF6E7894);
const Color _bordaInput = Color(0xFFE9E8F0);
const Color _verdeSucesso = Color(0xFF16A34A);
const Color _verdeClaro = Color(0xFF22C55E);
const Color _vermelhoErro = Color(0xFFDC2626);
const Color _vermelhoClaro = Color(0xFFF04438);

// ═══════════════════════════════════════════════════════════════
// PremiumConfirmDialog
// ═══════════════════════════════════════════════════════════════

/// Modal de confirmação premium, moderno e elegante.
/// Uso:
///   final confirmou = await PremiumConfirmDialog.mostrar(
///     context,
///     tituloConfiguracao: 'Cobrança automática',
///   );
class PremiumConfirmDialog {
  PremiumConfirmDialog._();

  static Future<bool> mostrar(BuildContext context, {required String tituloConfiguracao}) {
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(ctx, false);
        },
        child: Center(
          child: Container(
            width: 480,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _roxoPrimario.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 60,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Top gradient bar ────────────────────────
                  Container(
                    height: 6,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_roxoPrimario, _roxoClaro],
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Icon circle ───────────────────────
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [_roxoPrimario, _roxoClaro],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _roxoPrimario.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.help_outline_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // ── Title ─────────────────────────────
                        Text(
                          'Confirmar alteração',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: _textoPrimario,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),

                        // ── Description ───────────────────────
                        Text(
                          'Deseja realmente alterar esta configuração?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: _textoSecundario,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),

                        // ── Setting name badge ────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: _roxoPrimario.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _roxoPrimario.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 16,
                                color: _roxoPrimario.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  tituloConfiguracao,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _roxoPrimario,
                                    height: 1.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),

                        // ── Buttons ───────────────────────────
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Stack vertically if very narrow
                            if (constraints.maxWidth < 320) {
                              return Column(
                                children: [
                                  _cancelarBotao(ctx),
                                  const SizedBox(height: 10),
                                  _confirmarBotao(ctx),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: _cancelarBotao(ctx)),
                                const SizedBox(width: 12),
                                Expanded(child: _confirmarBotao(ctx)),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((v) => v ?? false);
  }

  static Widget _cancelarBotao(BuildContext ctx) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: () => Navigator.pop(ctx, false),
        style: OutlinedButton.styleFrom(
          foregroundColor: _textoSecundario,
          side: BorderSide(color: _bordaInput),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(
          'Cancelar',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textoSecundario,
          ),
        ),
      ),
    );
  }

  static Widget _confirmarBotao(BuildContext ctx) {
    return SizedBox(
      height: 46,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(ctx, true),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_roxoPrimario, _roxoClaro],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _roxoPrimario.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                'Confirmar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PremiumResultDialog
// ═══════════════════════════════════════════════════════════════

/// Modal de resultado premium (sucesso ou erro).
/// Uso:
///   PremiumResultDialog.mostrarSucesso(context, titulo: '...', mensagem: '...');
///   PremiumResultDialog.mostrarErro(context, titulo: '...', mensagem: '...');
class PremiumResultDialog {
  PremiumResultDialog._();

  static void mostrarSucesso(
    BuildContext context, {
    required String titulo,
    required String mensagem,
  }) {
    _mostrar(
      context,
      titulo: titulo,
      mensagem: mensagem,
      corInicio: _verdeSucesso,
      corFim: _verdeClaro,
      icone: Icons.check_rounded,
    );
  }

  static void mostrarErro(
    BuildContext context, {
    required String titulo,
    required String mensagem,
  }) {
    _mostrar(
      context,
      titulo: titulo,
      mensagem: mensagem,
      corInicio: _vermelhoErro,
      corFim: _vermelhoClaro,
      icone: Icons.error_outline_rounded,
    );
  }

  static void _mostrar(
    BuildContext context, {
    required String titulo,
    required String mensagem,
    required Color corInicio,
    required Color corFim,
    required IconData icone,
  }) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Center(
        child: Container(
          width: 480,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _roxoPrimario.withValues(alpha: 0.15),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 60,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Top gradient bar ────────────────────────
                Container(
                  height: 6,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [corInicio, corFim],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Icon circle ───────────────────────
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [corInicio, corFim],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: corInicio.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(icone, color: Colors.white, size: 30),
                      ),
                      const SizedBox(height: 22),

                      // ── Title ─────────────────────────────
                      Text(
                        titulo,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _textoPrimario,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

                      // ── Message ───────────────────────────
                      Text(
                        mensagem,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: _textoSecundario,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),

                      // ── OK button ─────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [corInicio, corFim],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: corInicio.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  'OK',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PremiumLoadingDialog
// ═══════════════════════════════════════════════════════════════

/// Modal de carregamento premium (não dispensável).
/// Uso:
///   PremiumLoadingDialog.mostrar(context, mensagem: 'Salvando...');
///   // depois:
///   Navigator.of(context, rootNavigator: true).pop();
class PremiumLoadingDialog {
  PremiumLoadingDialog._();

  static void mostrar(BuildContext context, {String mensagem = 'Salvando...'}) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            width: 320,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _roxoPrimario.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 60,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        valueColor: AlwaysStoppedAnimation<Color>(_roxoPrimario),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      mensagem,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _textoPrimario,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
