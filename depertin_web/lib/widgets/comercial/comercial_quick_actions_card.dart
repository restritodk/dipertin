import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card de ações rápidas na sidebar da tela de pendências.
class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({
    super.key,
    this.onEnviarLembretes,
    this.onGerarCobrancas,
    this.onExportarRelatorio,
  });

  final VoidCallback? onEnviarLembretes;
  final VoidCallback? onGerarCobrancas;
  final VoidCallback? onExportarRelatorio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ações Rápidas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 16),
          _botaoAcao(
            Icons.send_rounded,
            'Enviar lembretes',
            const Color(0xFF6A1B9A),
            onEnviarLembretes,
          ),
          const SizedBox(height: 10),
          _botaoAcao(
            Icons.receipt_long_rounded,
            'Gerar cobranças',
            const Color(0xFFFF8F00),
            onGerarCobrancas,
          ),
          const SizedBox(height: 10),
          _botaoAcao(
            Icons.download_rounded,
            'Exportar relatório',
            const Color(0xFF16A34A),
            onExportarRelatorio,
          ),
        ],
      ),
    );
  }

  Widget _botaoAcao(
    IconData icone,
    String label,
    Color cor,
    VoidCallback? onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: cor,
          backgroundColor: cor.withValues(alpha: 0.05),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cor.withValues(alpha: 0.2)),
          ),
        ),
        icon: Icon(icone, size: 18),
        label: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
