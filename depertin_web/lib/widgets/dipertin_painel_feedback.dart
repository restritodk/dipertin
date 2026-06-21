import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/painel_admin_theme.dart';

enum DiPertinFeedbackTipo { sucesso, erro, aviso, info }

/// Feedback flutuante no topo + diálogos de confirmação premium (painel web).
abstract final class DiPertinPainelFeedback {
  static OverlayEntry? _overlay;
  static Timer? _timer;

  static void fechar() {
    _timer?.cancel();
    _timer = null;
    _overlay?.remove();
    _overlay = null;
  }

  static void mostrar(
    BuildContext context, {
    required String mensagem,
    DiPertinFeedbackTipo tipo = DiPertinFeedbackTipo.sucesso,
    Duration duracao = const Duration(seconds: 3),
  }) {
    fechar();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _DiPertinFeedbackToast(
        mensagem: mensagem,
        tipo: tipo,
        onFechar: () {
          if (entry.mounted) entry.remove();
          if (_overlay == entry) {
            _overlay = null;
            _timer?.cancel();
            _timer = null;
          }
        },
      ),
    );
    _overlay = entry;
    overlay.insert(entry);
    _timer = Timer(duracao, () {
      if (entry.mounted) entry.remove();
      if (_overlay == entry) _overlay = null;
    });
  }

  static void sucesso(BuildContext context, String mensagem) =>
      mostrar(context, mensagem: mensagem, tipo: DiPertinFeedbackTipo.sucesso);

  static void erro(BuildContext context, String mensagem) =>
      mostrar(context, mensagem: mensagem, tipo: DiPertinFeedbackTipo.erro);

  static void aviso(BuildContext context, String mensagem) =>
      mostrar(context, mensagem: mensagem, tipo: DiPertinFeedbackTipo.aviso);

  static void info(BuildContext context, String mensagem) =>
      mostrar(context, mensagem: mensagem, tipo: DiPertinFeedbackTipo.info);

  /// Diálogo de confirmação premium. Retorna `true` se confirmou.
  static Future<bool> confirmar(
    BuildContext context, {
    required String titulo,
    required String mensagem,
    String botaoConfirmar = 'Confirmar',
    String botaoCancelar = 'Cancelar',
    bool destrutivo = false,
    IconData icone = Icons.help_outline_rounded,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (destrutivo
                                  ? const Color(0xFFEF4444)
                                  : PainelAdminTheme.roxo)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          icone,
                          color: destrutivo
                              ? const Color(0xFFEF4444)
                              : PainelAdminTheme.roxo,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titulo,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E1B4B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              mensagem,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                height: 1.45,
                                color: PainelAdminTheme.textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          botaoCancelar,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: destrutivo
                              ? const Color(0xFFEF4444)
                              : PainelAdminTheme.roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          botaoConfirmar,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
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
    return r == true;
  }
}

class _DiPertinFeedbackToast extends StatefulWidget {
  const _DiPertinFeedbackToast({
    required this.mensagem,
    required this.tipo,
    required this.onFechar,
  });

  final String mensagem;
  final DiPertinFeedbackTipo tipo;
  final VoidCallback onFechar;

  @override
  State<_DiPertinFeedbackToast> createState() => _DiPertinFeedbackToastState();
}

class _DiPertinFeedbackToastState extends State<_DiPertinFeedbackToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fecharAnimado() async {
    await _ctrl.reverse();
    widget.onFechar();
  }

  ({Color cor, Color fundo, IconData icone}) get _estilo {
    switch (widget.tipo) {
      case DiPertinFeedbackTipo.sucesso:
        return (
          cor: const Color(0xFF10B981),
          fundo: const Color(0xFFD1FAE5),
          icone: Icons.check_circle_rounded,
        );
      case DiPertinFeedbackTipo.erro:
        return (
          cor: const Color(0xFFEF4444),
          fundo: const Color(0xFFFEE2E2),
          icone: Icons.error_outline_rounded,
        );
      case DiPertinFeedbackTipo.aviso:
        return (
          cor: PainelAdminTheme.laranja,
          fundo: const Color(0xFFFFF3E0),
          icone: Icons.info_outline_rounded,
        );
      case DiPertinFeedbackTipo.info:
        return (
          cor: PainelAdminTheme.roxo,
          fundo: const Color(0xFFEDE9FE),
          icone: Icons.notifications_none_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final est = _estilo;
    final top = MediaQuery.paddingOf(context).top + 16;
    final largura = MediaQuery.sizeOf(context).width;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: largura > 520 ? 480 : largura - 32,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: est.cor.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: est.cor.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: est.fundo,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(est.icone, color: est.cor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.mensagem,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E1B4B),
                          height: 1.35,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _fecharAnimado,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.grey.shade500,
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Fechar',
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
