import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Badge de status compacto (chip) para a tabela de pendências financeiras.
///
/// Largura automática (conteúdo), padding horizontal 10px, vertical 5px,
/// border radius 999px, fonte 12px semibold. Alinhada à esquerda.
class FinancialStatusBadge extends StatelessWidget {
  const FinancialStatusBadge({super.key, required this.status});

  /// Status do cliente agrupado: vencido | vence_hoje | vence_em_breve | em_dia
  final String status;

  @override
  Widget build(BuildContext context) {
    final (cor, fundo, rotulo) = _config(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      constraints: const BoxConstraints(minWidth: 0),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rotulo,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cor,
          height: 1.2,
        ),
      ),
    );
  }

  /// Mapa de status → (cor do texto, fundo, rótulo)
  static (Color, Color, String) _config(String status) {
    switch (status) {
      case 'vencido':
        return (
          const Color(0xFFDC2626), // texto vermelho
          const Color(0xFFFEE2E2), // fundo vermelho claro
          'Vencido',
        );
      case 'vence_hoje':
        return (
          const Color(0xFFF97316), // texto laranja
          const Color(0xFFFFF0E2), // fundo laranja claro
          'Vence hoje',
        );
      case 'vence_em_breve':
        return (
          const Color(0xFFCA8A04), // texto amarelo
          const Color(0xFFFFF7D6), // fundo amarelo claro
          'Vence em breve',
        );
      case 'em_dia':
      default:
        return (
          const Color(0xFF16A34A), // texto verde
          const Color(0xFFE7F8EE), // fundo verde claro
          'Em dia',
        );
    }
  }
}
