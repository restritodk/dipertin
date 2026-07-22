import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de design unificado DiPertin - Paleta de cores extraída do app mobile.
///
/// Cores primárias:
/// - Roxo: #6A1B9A (principal)
/// - Roxo Escuro: #4A148C (gradientes)
/// - Roxo Médio: #7B1FA2, #8E24AA
///
/// Cores secundárias:
/// - Laranja: #FF8F00 (principal)
/// - Laranja Suave: #FFB74D
///
/// Neutros:
/// - Fundo: #F5F4F8
/// - Texto Primário: #1A1A2E
/// - Texto Secundário: #64748B
/// - Borda: #E0DEE8
abstract final class DiPertinTheme {
  // ================================================================
  // CORES PRIMÁRIAS (Extraídas do app mobile)
  // ================================================================

  /// Roxo principal - Cor primária do app (#6A1B9A)
  static const Color primaryRoxo = Color(0xFF6A1B9A);

  /// Roxo escuro - Usado em gradientes (#4A148C)
  static const Color primaryRoxoEscuro = Color(0xFF4A148C);

  /// Roxo médio - Variante para gradientes (#7B1FA2)
  static const Color primaryRoxoMedio = Color(0xFF7B1FA2);

  /// Roxo claro - Variante para gradientes (#8E24AA)
  static const Color primaryRoxoClaro = Color(0xFF8E24AA);

  // ================================================================
  // CORES SECUNDÁRIAS
  // ================================================================

  /// Laranja principal - Cor secundária/CTA (#FF8F00)
  static const Color secondaryLaranja = Color(0xFFFF8F00);

  /// Laranja suave - Variante para backgrounds (#FFB74D)
  static const Color secondaryLaranjaSuave = Color(0xFFFFB74D);

  // ================================================================
  // CORES DE FUNDO E SUPERFÍCIE
  // ================================================================

  /// Fundo principal da tela (#F5F4F8)
  static const Color backgroundFundo = Color(0xFFF5F4F8);

  /// Fundo modal (#F5F4F8)
  static const Color backgroundModal = Color(0xFFF5F4F8);

  /// Fundo de cards (#FFFFFF)
  static const Color surfaceCard = Color(0xFFFFFFFF);

  /// Background elevado (sidebar) - Gradiente roxo
  static const Color sidebarBackground = Color(0xFF2D1B4E);
  static const Color sidebarBackgroundEnd = Color(0xFF1A0F2E);

  /// Background hover na sidebar
  static const Color sidebarHover = Color(0x1A6A1B9A);

  /// Background item ativo na sidebar
  static const Color sidebarAtivoBackground = Color(0x336A1B9A);

  // ================================================================
  // CORES DE TEXTO
  // ================================================================

  /// Texto primário (#1A1A2E)
  static const Color textPrimary = Color(0xFF1A1A2E);

  /// Texto secundário/muted (#64748B)
  static const Color textSecondary = Color(0xFF64748B);

  /// Texto no fundo escuro (sidebar)
  static const Color textOnDark = Color(0xFFF1F0F6);

  /// Texto muted no fundo escuro (sidebar)
  static const Color textMutedOnDark = Color(0xFFB8A8D0);

  // ================================================================
  // CORES DE BORDA
  // ================================================================

  /// Borda padrão (#E0DEE8)
  static const Color borderDefault = Color(0xFFE0DEE8);

  /// Borda suave (#EDEAF5)
  static const Color borderSoft = Color(0xFFEDEAF5);

  /// Borda na sidebar
  static const Color sidebarBorder = Color(0xFF4A3068);

  // ================================================================
  // CORES SEMÂNTICAS (Status)
  // ================================================================

  /// Verde para status de sucesso (#2E7D32)
  static const Color successGreen = Color(0xFF2E7D32);

  /// Verde alternativo (#059669)
  static const Color successGreenAlt = Color(0xFF059669);

  /// Vermelho para status de erro (#C62828)
  static const Color errorRed = Color(0xFFC62828);

  /// Vermelho alternativo (#DC2626)
  static const Color errorRedAlt = Color(0xFFDC2626);

  /// Amarelo/Warning (#D97706)
  static const Color warningAmber = Color(0xFFD97706);

  /// Azul informativo (#0EA5E9)
  static const Color infoBlue = Color(0xFF0EA5E9);

  // ================================================================
  // GRADIENTES
  // ================================================================

  /// Gradiente roxo padrão (app mobile)
  static const LinearGradient gradienteRoxo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryRoxoEscuro, primaryRoxo, primaryRoxoClaro],
  );

  /// Gradiente roxo suave
  static const LinearGradient gradienteRoxoSuave = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryRoxo, primaryRoxoMedio],
  );

  /// Gradiente sidebar (fundo escuro roxo)
  static const LinearGradient gradienteSidebar = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [sidebarBackground, sidebarBackgroundEnd],
  );

  /// Gradiente para o card header do dashboard
  static const LinearGradient gradienteCardHeader = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryRoxoEscuro, primaryRoxo],
  );

  // ================================================================
  // SHADOWS
  // ================================================================

  /// Sombra suave para cards
  static List<BoxShadow> sombraCardSuave() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 10),
          spreadRadius: -4,
        ),
        BoxShadow(
          color: primaryRoxo.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// Sombra para elementos elevados
  static List<BoxShadow> sombraElevada() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 6),
          spreadRadius: -2,
        ),
      ];

  // ================================================================
  // DECORAÇÕES
  // ================================================================

  /// Card padrão do dashboard (fundo branco, borda leve, sombra)
  static BoxDecoration dashboardCard({Color? borderColor}) {
    return BoxDecoration(
      color: surfaceCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: borderColor ?? borderDefault,
      ),
      boxShadow: sombraCardSuave(),
    );
  }

  /// Card com fundo gradiente roxo (para cards de destaque)
  static BoxDecoration dashboardCardGradiente() {
    return BoxDecoration(
      gradient: gradienteRoxo,
      borderRadius: BorderRadius.circular(16),
      boxShadow: sombraElevada(),
    );
  }

  /// Container do header da sidebar
  static BoxDecoration sidebarHeaderDecoration({bool collapsed = false}) {
    return BoxDecoration(
      gradient: gradienteRoxoSuave,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: primaryRoxo.withValues(alpha: 0.3)),
    );
  }

  /// Badge de pendência (laranja)
  static BoxDecoration badgePendencia() {
    return BoxDecoration(
      color: secondaryLaranja,
      borderRadius: BorderRadius.circular(10),
    );
  }

  /// Badge de status ativo
  static BoxDecoration badgeAtivo() {
    return BoxDecoration(
      color: successGreenAlt.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: successGreenAlt.withValues(alpha: 0.3)),
    );
  }

  // ================================================================
  // THEMEDATA
  // ================================================================

  /// Tema principal do painel administrativo
  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryRoxo,
        brightness: Brightness.light,
        primary: primaryRoxo,
        secondary: secondaryLaranja,
        surface: surfaceCard,
        error: errorRedAlt,
      ),
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.3,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF334155),
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        height: 1.5,
        color: const Color(0xFF475569),
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        height: 1.45,
        color: textSecondary,
      ),
      bodySmall: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        color: textSecondary,
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: backgroundFundo,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: surfaceCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
      dividerTheme: DividerThemeData(
        color: borderDefault,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryRoxo,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryRoxo,
          side: const BorderSide(color: primaryRoxo, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryRoxo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRoxo,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryRoxo, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorRedAlt),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: textSecondary.withValues(alpha: 0.7),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: backgroundFundo,
        selectedColor: primaryRoxo.withValues(alpha: 0.15),
        side: BorderSide(color: borderDefault),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: surfaceCard,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Alias para compatibilidade com código existente
abstract final class PainelAdminTheme {
  static const Color roxo = DiPertinTheme.primaryRoxo;
  static const Color roxoEscuro = DiPertinTheme.primaryRoxoEscuro;
  static const Color roxoSidebarFim = DiPertinTheme.sidebarBackgroundEnd;
  static const Color laranja = DiPertinTheme.secondaryLaranja;
  static const Color laranjaSuave = DiPertinTheme.secondaryLaranjaSuave;
  static const Color fundoCanvas = DiPertinTheme.backgroundFundo;
  static const Color surfaceCard = DiPertinTheme.surfaceCard;
  static const Color textPrimary = DiPertinTheme.textPrimary;
  static const Color textoSecundario = DiPertinTheme.textSecondary;
  static const Color dashboardBorder = DiPertinTheme.borderDefault;
  static const Color dashboardInk = DiPertinTheme.textPrimary;
  static const Color errorRed = DiPertinTheme.errorRed;
  static const Color errorRedAlt = DiPertinTheme.errorRedAlt;
  static const Color warningAmber = DiPertinTheme.warningAmber;
  static const Color infoBlue = DiPertinTheme.infoBlue;
  static const Color successGreen = DiPertinTheme.successGreen;
  static const Color successGreenAlt = DiPertinTheme.successGreenAlt;

  static ThemeData theme() => DiPertinTheme.theme();

  static List<BoxShadow> sombraCardSuave() => DiPertinTheme.sombraCardSuave();

  static BoxDecoration dashboardCard({Color borderColor = const Color(0xFFE2E8F0)}) {
    return DiPertinTheme.dashboardCard(borderColor: borderColor);
  }
}
