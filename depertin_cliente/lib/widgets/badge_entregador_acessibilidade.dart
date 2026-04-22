// Arquivo: lib/widgets/badge_entregador_acessibilidade.dart

import 'package:flutter/material.dart';

/// Badge visual exibido no card do pedido quando o entregador atribuído tem
/// limitação auditiva. Orienta cliente e lojista a usarem o chat.
///
/// Lê o campo denormalizado `pedidos.entregador_acessibilidade_audicao` com
/// valores esperados: "surdo" | "deficiencia" | "normal" | "" (ausente).
class BadgeEntregadorAcessibilidade extends StatelessWidget {
  final String? audicao;
  final EdgeInsetsGeometry padding;

  const BadgeEntregadorAcessibilidade({
    super.key,
    required this.audicao,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  bool get _temLimitacao {
    final v = (audicao ?? '').toLowerCase().trim();
    return v == 'surdo' || v == 'deficiencia' || v == 'deficiência';
  }

  @override
  Widget build(BuildContext context) {
    if (!_temLimitacao) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFFF8F00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF8F00).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hearing_disabled_rounded,
            color: Color(0xFFFF8F00),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Entregador com limitação auditiva',
                  style: TextStyle(
                    color: Color(0xFFFF8F00),
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Prefira usar o chat; evite chamadas de voz.',
                  style: TextStyle(
                    color: const Color(0xFFFF8F00).withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
