import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Badge de status premium em formato pill (border-radius: 999).
///
/// Largura 100% dinâmica baseada no conteúdo. Sem largura fixa.
/// Altura entre 26~30px. Padding horizontal 12px.
///
/// Use em tabelas, cards, listas — qualquer lugar que exiba status.
///
/// Exemplo:
/// ```dart
/// StatusBadge('Em dia')
/// StatusBadge('Em atraso')
/// StatusBadge(cliente.statusExibicaoRotulo)
/// ```
class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.status, {
    super.key,
    this.fontSize = 11.5,
  });

  /// Texto do status (ex.: "Em dia", "Cancelado", "Em atraso").
  final String status;

  /// Tamanho da fonte. Padrão: 11.5.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final config = _config(status);
    final cor = config.$1;
    final fundo = config.$2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      constraints: const BoxConstraints(minHeight: 26),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Text(
        status,
        style: GoogleFonts.plusJakartaSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: cor,
          height: 1.2,
        ),
      ),
    );
  }

  /// Retorna (cor do texto/ícone, cor de fundo) para cada status.
  static (Color, Color) _config(String status) {
    switch (status) {
      // ── Positivos / Em dia ──
      case 'Em dia':
      case 'Ativo':
      case 'Ativa':
      case 'Aprovado':
      case 'Aprovada':
      case 'Pago':
      case 'Paga':
      case 'Concluído':
      case 'Concluida':
      case 'Confirmado':
        return (
          const Color(0xFF16A34A),
          const Color(0xFFE8F5E9),
        );

      // ── Atenção / Vence hoje / Pendente ──
      case 'Vence hoje':
      case 'Vencer hoje':
      case 'Pendente':
      case 'Aguardando':
        return (
          const Color(0xFFFF8F00),
          const Color(0xFFFFF3E6),
        );

      // ── Neutro / A vencer / Em análise ──
      case 'A vencer':
      case 'Vence em breve':
      case 'Em análise':
      case 'Em processamento':
        return (
          const Color(0xFF0EA5E9),
          const Color(0xFFE6F6FE),
        );

      // ── Negativos / Em atraso / Bloqueado ──
      case 'Em atraso':
      case 'Vencido':
      case 'Vencida':
      case 'Bloqueado':
      case 'Suspenso':
      case 'Recusado':
      case 'Recusada':
      case 'Cancelado':
      case 'Cancelada':
        return (
          const Color(0xFFF04438),
          const Color(0xFFFEF2F2),
        );

      // ── Inativo / Cancelado (tom cinza) ──
      case 'Inativo':
      case 'Inativa':
      case 'Expirado':
      case 'Expirada':
        return (
          const Color(0xFF94A3B8),
          const Color(0xFFF1F5F9),
        );

      // ── Fallback ──
      default:
        return (
          const Color(0xFF64748B),
          const Color(0xFFF1F5F9),
        );
    }
  }
}
