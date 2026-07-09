import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card com gráfico donut de distribuição das pendências.
class DebtChartCard extends StatelessWidget {
  const DebtChartCard({
    super.key,
    required this.vencidas,
    required this.venceHoje,
    required this.vence7Dias,
    required this.totalEmAberto,
  });

  final double vencidas;
  final double venceHoje;
  final double vence7Dias;
  final double totalEmAberto;

  /// Valor com vencimento além de 7 dias.
  double get _outros =>
      (totalEmAberto - vencidas - venceHoje - vence7Dias).clamp(0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final total = totalEmAberto; // base real para o percentual
    final pctVencidas = total > 0 ? vencidas / total : 0.0;
    final pctHoje = total > 0 ? venceHoje / total : 0.0;
    final pct7Dias = total > 0 ? vence7Dias / total : 0.0;
    final pctOutros = total > 0 ? _outros / total : 0.0;

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
            'Resumo por Status',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 20),
          // Gráfico donut
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(
                painter: _DonutPainter(
                  segments: [
                    if (pctVencidas > 0)
                      _DonutSegment(pctVencidas, const Color(0xFFDC2626)),
                    if (pctHoje > 0)
                      _DonutSegment(pctHoje, const Color(0xFFFF8F00)),
                    if (pct7Dias > 0)
                      _DonutSegment(pct7Dias, const Color(0xFFCA8A04)),
                    if (pctOutros > 0)
                      _DonutSegment(pctOutros, const Color(0xFF94A3B8)),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'R\$ ${totalEmAberto.toStringAsFixed(0)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        'total',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legenda
          _legendaItem(const Color(0xFFDC2626), 'Vencidas', vencidas),
          const SizedBox(height: 8),
          _legendaItem(const Color(0xFFFF8F00), 'Vence Hoje', venceHoje),
          const SizedBox(height: 8),
          _legendaItem(const Color(0xFFCA8A04), 'Vencendo em 7 dias', vence7Dias),
          if (_outros > 0) ...[
            const SizedBox(height: 8),
            _legendaItem(const Color(0xFF94A3B8), 'Outros vencimentos', _outros),
          ],
        ],
      ),
    );
  }

  Widget _legendaItem(Color cor, String label, double valor) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Text(
          'R\$ ${valor.toStringAsFixed(2)}',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}

class _DonutSegment {
  const _DonutSegment(this.proporcao, this.cor);
  final double proporcao;
  final Color cor;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments});

  final List<_DonutSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round;

    var startAngle = -pi / 2;
    for (final seg in segments) {
      final sweep = seg.proporcao * 2 * pi;
      paint.color = seg.cor;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}
