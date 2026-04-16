import 'package:flutter/material.dart';

/// Exibe média (estrelas aproximadas) e total de avaliações da loja.
class LojaRatingRow extends StatelessWidget {
  const LojaRatingRow({
    super.key,
    required this.media,
    required this.total,
    this.iconSize = 14,
    this.fontSize = 12,
    this.dense = false,
  });

  final double? media;
  final int total;
  final double iconSize;
  final double fontSize;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = total;
    final m = media;
    if (t <= 0 || m == null || m <= 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...List.generate(
            5,
            (i) => Padding(
              padding: EdgeInsets.only(right: i < 4 ? 1 : 0),
              child: Icon(
                Icons.star_outline_rounded,
                size: iconSize,
                color: Colors.grey.shade400,
              ),
            ),
          ),
          SizedBox(width: dense ? 4 : 6),
          Flexible(
            child: Text(
              'Sem avaliações ainda',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: fontSize,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    final cheias = m.floor().clamp(0, 5);
    final meia = (m - cheias) >= 0.5 && cheias < 5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          if (i < cheias) {
            return Icon(Icons.star_rounded, size: iconSize, color: Colors.amber.shade700);
          }
          if (i == cheias && meia) {
            return Icon(Icons.star_half_rounded, size: iconSize, color: Colors.amber.shade700);
          }
          return Icon(Icons.star_outline_rounded, size: iconSize, color: Colors.grey.shade400);
        }),
        if (!dense) SizedBox(width: fontSize >= 13 ? 6 : 4),
        Flexible(
          child: Text(
            '${m.toStringAsFixed(1)} ($t ${t == 1 ? 'avaliação' : 'avaliações'})',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
