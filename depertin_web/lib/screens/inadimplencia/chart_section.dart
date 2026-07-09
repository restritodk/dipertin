part of '../assinaturas_inadimplencia_screen.dart';

// ─── Gráfico de Evolução ────────────────────────────────────────────────────
// Altura determinada pelo pai (IntrinsicHeight no Row). O BarChart preenche
// o espaço disponível via Expanded.

class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.evolucao});

  final List<di.InadimplenciaMes> evolucao;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _cardWrapper(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1E9FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bar_chart_rounded,
                      color: Color(0xFF6A1B9A), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Evolução da Inadimplência',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Últimos 12 meses',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                // Legenda
                _legendaItem('Cobrado', const Color(0xFF6A1B9A)),
                const SizedBox(width: 12),
                _legendaItem('Pago', const Color(0xFF16A34A)),
                const SizedBox(width: 12),
                _legendaItem('Em atraso', const Color(0xFFF04438)),
              ],
            ),
            const SizedBox(height: 16),
            // Gráfico — preenche o espaço restante
            Expanded(
              child: evolucao.isEmpty
                  ? Center(
                      child: Text(
                        'Sem dados para exibir',
                        style: TextStyle(
                          color: const Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _maxY,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final mes = evolucao[groupIndex];
                              final label = switch (rodIndex) {
                                0 => 'Cobrado: ${fmtMoeda(mes.cobrado)}',
                                1 => 'Pago: ${fmtMoeda(mes.pago)}',
                                _ => 'Atraso: ${fmtMoeda(mes.emAtraso)}',
                              };
                              return BarTooltipItem(
                                '${mes.rotulo}\n$label',
                                const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, meta) {
                                final i = v.toInt();
                                if (i < 0 || i >= evolucao.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(top: 6),
                                  child: Text(
                                    evolucao[i].rotulo,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              },
                              reservedSize: 22,
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              getTitlesWidget: (v, meta) {
                                if (v == 0) return const SizedBox.shrink();
                                return Text(
                                  fmtMoeda(v),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF94A3B8),
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _maxY / 4,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: _buildBars(),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double get _maxY {
    double max = 0;
    for (final m in evolucao) {
      max = math.max(max, m.cobrado);
      max = math.max(max, m.pago);
      max = math.max(max, m.emAtraso);
    }
    return max == 0 ? 100 : max * 1.2;
  }

  List<BarChartGroupData> _buildBars() {
    return evolucao.asMap().entries.map((e) {
      final i = e.key;
      final m = e.value;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: m.cobrado,
            color: const Color(0xFF6A1B9A),
            width: 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
          BarChartRodData(
            toY: m.pago,
            color: const Color(0xFF16A34A),
            width: 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
          BarChartRodData(
            toY: m.emAtraso,
            color: const Color(0xFFF04438),
            width: 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    }).toList();
  }

  Widget _legendaItem(String label, Color cor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
