import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cores e estilos compartilhados do painel administrativo DiPertin.
abstract final class PainelAdminTheme {
  static const Color roxo = Color(0xFF6A1B9A);
  static const Color roxoEscuro = Color(0xFF4A148C);
  static const Color roxoSidebarFim = Color(0xFF5E1788);
  static const Color laranja = Color(0xFFFF8F00);
  static const Color laranjaSuave = Color(0xFFFFB74D);
  static const Color fundoCanvas = Color(0xFFF3F1F8);
  static const Color textoSecundario = Color(0xFF64748B);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: roxo,
        brightness: Brightness.light,
        primary: roxo,
        secondary: laranja,
        surface: Colors.white,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1E1B4B),
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1E1B4B),
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF334155),
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        height: 1.5,
        color: const Color(0xFF475569),
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        height: 1.45,
        color: textoSecundario,
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: fundoCanvas,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.08),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.12),
        thickness: 1,
      ),
    );
  }

  static List<BoxShadow> sombraCardSuave() => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 24,
          offset: const Offset(0, 10),
          spreadRadius: -4,
        ),
        BoxShadow(
          color: roxo.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// Cartão padrão do dashboard (fundo branco, borda leve, sombra única).
  static BoxDecoration dashboardCard({Color borderColor = const Color(0xFFE2E8F0)}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor),
      boxShadow: sombraCardSuave(),
    );
  }

  static const Color dashboardBorder = Color(0xFFE2E8F0);
  static const Color dashboardInk = Color(0xFF1E1B4B);
}
