import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens visuais da tela Financeiro (partilhados com [lojista_carteira_financeiro_widgets.dart]).
abstract final class CarteiraFinTokens {
  static const Color bg = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF3F4F6);
  static const Color segmentBg = Color(0xFFF3F4F6);
  static const Color green = Color(0xFF16A34A);
  static const Color red = Color(0xFFDC2626);
  static const Color chartBar = Color(0xFF94A3B8);
  static const Color chartGrid = Color(0xFFF3F4F6);

  static const double rCard = 14;
  static const double rButton = 10;
  static const double rSegment = 10;
  static const double rBadge = 6;

  static TextStyle inter(double size, FontWeight w, Color c) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: 1.35);

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
      blurRadius: 16,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.02),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> pillActiveShadow = [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
      blurRadius: 8,
      offset: const Offset(0, 1),
    ),
  ];
}
