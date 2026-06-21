import 'package:depertin_web/theme/painel_admin_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cabeçalho roxo padrão dos modais comerciais.
class ComercialModalHeader extends StatelessWidget {
  const ComercialModalHeader({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.onFechar,
    this.icone,
  });

  final String titulo;
  final String? subtitulo;
  final VoidCallback onFechar;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 8, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF7B1FA2)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icone != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icone, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (subtitulo != null && subtitulo!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitulo!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onFechar,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Campo de busca grande para modais comerciais.
class ComercialBuscaField extends StatelessWidget {
  const ComercialBuscaField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(
          color: const Color(0xFF94A3B8),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: PainelAdminTheme.roxo.withValues(alpha: 0.65),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PainelAdminTheme.roxo, width: 1.5),
        ),
      ),
    );
  }
}

/// Card branco com sombra suave.
class ComercialCardBranco extends StatelessWidget {
  const ComercialCardBranco({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: PainelAdminTheme.sombraCardSuave(),
      ),
      child: child,
    );
  }
}

/// Estado vazio elegante.
class ComercialEstadoVazio extends StatelessWidget {
  const ComercialEstadoVazio({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.icone = Icons.inbox_outlined,
  });

  final String titulo;
  final String? subtitulo;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            icone,
            size: 44,
            color: PainelAdminTheme.roxo.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitulo!,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rodapé compacto com botões secundário + primário alinhados à direita.
class ComercialModalFooterActions extends StatelessWidget {
  const ComercialModalFooterActions({
    super.key,
    required this.onSecundario,
    required this.labelSecundario,
    required this.onPrimario,
    required this.labelPrimario,
    this.iconePrimario,
    this.carregando = false,
    this.primarioHabilitado = true,
    this.mostrarPrimario = true,
  });

  final VoidCallback? onSecundario;
  final String labelSecundario;
  final VoidCallback? onPrimario;
  final String labelPrimario;
  final IconData? iconePrimario;
  final bool carregando;
  final bool primarioHabilitado;
  final bool mostrarPrimario;

  static ButtonStyle get _secundario => OutlinedButton.styleFrom(
        foregroundColor: PainelAdminTheme.roxo,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: PainelAdminTheme.roxo.withValues(alpha: 0.28)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      );

  static ButtonStyle get _primario => FilledButton.styleFrom(
        backgroundColor: PainelAdminTheme.laranja,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: carregando ? null : onSecundario,
            style: _secundario,
            child: Text(labelSecundario),
          ),
          if (mostrarPrimario) ...[
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: (carregando || !primarioHabilitado) ? null : onPrimario,
              style: _primario,
              icon: carregando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(iconePrimario ?? Icons.check_rounded, size: 16),
              label: Text(labelPrimario),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shell de modal comercial (Dialog transparente + Material).
Future<T?> mostrarComercialModalShell<T>(
  BuildContext context, {
  required Widget child,
  double minWidth = 560,
  double maxWidth = 900,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
        child: Material(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          elevation: 28,
          child: child,
        ),
      ),
    ),
  );
}
