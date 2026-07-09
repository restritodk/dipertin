import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Menu de ações (três pontos) para cada linha da tabela de pendências.
class FinancialActionMenu extends StatelessWidget {
  const FinancialActionMenu({
    super.key,
    this.onReceber,
    this.onEnviarCobranca,
    this.onNegociar,
    this.onBloquearCredito,
    this.onExcluir,
  });

  final VoidCallback? onReceber;
  final VoidCallback? onEnviarCobranca;
  final VoidCallback? onNegociar;
  final VoidCallback? onBloquearCredito;
  final VoidCallback? onExcluir;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(-160, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shadowColor: const Color(0xFF1A1A2E).withValues(alpha: 0.1),
      onSelected: (acao) {
        switch (acao) {
          case 'receber':
            onReceber?.call();
            break;
          case 'enviar_cobranca':
            onEnviarCobranca?.call();
            break;
          case 'negociar':
            onNegociar?.call();
            break;
          case 'bloquear':
            onBloquearCredito?.call();
            break;
          case 'excluir':
            onExcluir?.call();
            break;
        }
      },
      itemBuilder: (_) => [
        _item(
          'receber',
          Icons.payments_outlined,
          'Receber pagamento',
          'laranja',
          onReceber != null,
        ),
        _item(
          'enviar_cobranca',
          Icons.send_rounded,
          'Enviar cobrança',
          'roxo',
          onEnviarCobranca != null,
        ),
        _item(
          'negociar',
          Icons.handshake_outlined,
          'Negociar dívida',
          'neutro',
          onNegociar != null,
        ),
        _item(
          'bloquear',
          Icons.block_rounded,
          'Bloquear crédito',
          'neutro',
          onBloquearCredito != null,
        ),
        const PopupMenuDivider(height: 1),
        _item(
          'excluir',
          Icons.delete_outline_rounded,
          'Excluir lançamento',
          'vermelho',
          onExcluir != null,
        ),
      ],
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.more_horiz_rounded, size: 18, color: Color(0xFF64748B)),
      ),
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label,
    String corTema,
    bool habilitado,
  ) {
    Color cor;
    switch (corTema) {
      case 'laranja':
        cor = const Color(0xFFFF8F00);
        break;
      case 'roxo':
        cor = const Color(0xFF6A1B9A);
        break;
      case 'vermelho':
        cor = const Color(0xFFDC2626);
        break;
      default:
        cor = const Color(0xFF1A1A2E);
    }

    return PopupMenuItem<String>(
      value: value,
      enabled: habilitado,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: habilitado ? cor : const Color(0xFFCBD5E1)),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: habilitado
                  ? (corTema == 'vermelho' ? cor : const Color(0xFF1A1A2E))
                  : const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }
}
