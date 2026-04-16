import 'package:depertin_web/screens/lojista_carteira_financeiro_theme.dart';
import 'package:depertin_web/services/carteira_lojista_extrato.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Widgets extraídos para biblioteca própria — evita erros de hot reload ao mudar
/// `const`/campos em classes que já estavam carregadas na mesma unidade de compilação.
class CarteiraFinKpiCard extends StatelessWidget {
  const CarteiraFinKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.valueColor,
    required this.width,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          color: CarteiraFinTokens.surface,
          borderRadius: BorderRadius.circular(CarteiraFinTokens.rCard),
          border: Border.all(color: CarteiraFinTokens.border),
          boxShadow: CarteiraFinTokens.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: CarteiraFinTokens.textSecondary.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: CarteiraFinTokens.inter(
                      12,
                      FontWeight.w500,
                      CarteiraFinTokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: CarteiraFinTokens.inter(22, FontWeight.w600, valueColor)
                  .copyWith(letterSpacing: -0.3, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class CarteiraFinChartPanel extends StatelessWidget {
  const CarteiraFinChartPanel({
    super.key,
    required this.chartPts,
    required this.maxY,
    required this.wide,
    required this.moeda,
  });

  final List<CarteiraVendaDia> chartPts;
  final double maxY;
  final bool wide;
  final NumberFormat moeda;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
      decoration: BoxDecoration(
        color: CarteiraFinTokens.surface,
        borderRadius: BorderRadius.circular(CarteiraFinTokens.rCard),
        border: Border.all(color: CarteiraFinTokens.border),
        boxShadow: CarteiraFinTokens.cardShadow,
      ),
      child: chartPts.isEmpty
          ? Center(
              child: Text(
                'Sem vendas creditadas neste período.',
                style: CarteiraFinTokens.inter(
                  14,
                  FontWeight.w400,
                  CarteiraFinTokens.textSecondary,
                ),
              ),
            )
          : BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: CarteiraFinTokens.chartGrid,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => CarteiraFinTokens.surface,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    tooltipMargin: 8,
                    tooltipRoundedRadius: 8,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final i = group.x.toInt();
                      if (i < 0 || i >= chartPts.length) {
                        return null;
                      }
                      final v = chartPts[i];
                      final line1 = _formatChartDateLabel(v.data);
                      final line2 = moeda.format(v.valor);
                      return BarTooltipItem(
                        '$line1\n$line2',
                        CarteiraFinTokens.inter(
                          12,
                          FontWeight.w600,
                          CarteiraFinTokens.textPrimary,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      getTitlesWidget: (v, m) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          v >= 1000
                              ? '${(v / 1000).toStringAsFixed(1)}k'
                              : v.toStringAsFixed(0),
                          style: CarteiraFinTokens.inter(
                            10,
                            FontWeight.w500,
                            CarteiraFinTokens.textSecondary,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= chartPts.length) {
                          return const SizedBox.shrink();
                        }
                        final parts = chartPts[i].data.split('-');
                        if (parts.length != 3) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${parts[2]}/${parts[1]}',
                            style: CarteiraFinTokens.inter(
                              9,
                              FontWeight.w500,
                              CarteiraFinTokens.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < chartPts.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: chartPts[i].valor,
                          width: wide ? 12 : 8,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          color: CarteiraFinTokens.chartBar.withValues(alpha: 0.92),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  static String _formatChartDateLabel(String yyyyMmDd) {
    final p = yyyyMmDd.split('-');
    if (p.length != 3) return yyyyMmDd;
    return '${p[2]}/${p[1]}/${p[0]}';
  }
}
