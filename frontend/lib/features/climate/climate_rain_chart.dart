import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/credify_theme.dart';
import 'climate_models.dart';

/// The shared rainfall visualization used on the climate screen and compact card.
class ClimateRainChart extends StatelessWidget {
  const ClimateRainChart({super.key, required this.daily, this.height = 230});

  final List<DailyRain> daily;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Daily rainfall',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY:
                  daily.fold<double>(
                    0,
                    (max, day) => day.rainMm > max ? day.rainMm : max,
                  ) +
                  15,
              barGroups: [
                for (var i = 0; i < daily.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: daily[i].rainMm,
                        color: daily[i].disrupted
                            ? tokens.warning
                            : tokens.accentA,
                        width: 7,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                    showingTooltipIndicators: daily[i].disrupted ? [0] : [],
                  ),
              ],
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 36),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                        '${daily[group.x].date.day}: ${rod.toY.toStringAsFixed(0)} mm${daily[group.x].disrupted ? '\nDisrupted' : ''}',
                        const TextStyle(color: Colors.white),
                      ),
                ),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 18,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.square, size: 14, color: tokens.accentA),
                const SizedBox(width: 5),
                const Text('Regular day'),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.square, size: 14, color: tokens.warning),
                const SizedBox(width: 5),
                const Text('Disrupted (tooltip marked)'),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
