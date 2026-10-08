import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/portfolio_response.dart';
import '../theme/credify_theme.dart';

class ScoreHistogramChart extends StatelessWidget {
  final List<ScoreBucket> buckets;

  /// When set, buckets at or above this score render as "would approve" and
  /// the rest are dimmed. Null leaves every bar at full strength.
  final int? cutoff;

  const ScoreHistogramChart({
    super.key,
    required this.buckets,
    this.cutoff,
  });

  /// Lower bound of a "60-70" style bucket label.
  static int lowerBound(String bucket) =>
      int.tryParse(bucket.split('-').first.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (buckets.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'No histogram data',
            style: TextStyle(color: t.textTertiary),
          ),
        ),
      );
    }

    final maxCount = buckets.map((b) => b.count).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: t.hairline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (val, meta) => Text(
                  val.toInt().toString(),
                  style: TextStyle(color: t.textTertiary, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= buckets.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      buckets[idx].bucket,
                      style: TextStyle(color: t.textSecondary, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          maxY: (maxCount * 1.25).ceilToDouble(),
          barGroups: buckets.asMap().entries.map((entry) {
            final idx = entry.key;
            final b = entry.value;
            // Color gradient: low scores red → high scores green
            final fraction = idx / (buckets.length - 1);
            var color = Color.lerp(
              const Color(0xFFF87171),
              const Color(0xFF4ADE80),
              fraction,
            )!;
            // Below the lender's cutoff, dim the bar rather than recolour it —
            // the band it belongs to has not changed, only the policy.
            if (cutoff != null && lowerBound(b.bucket) < cutoff!) {
              color = color.withValues(alpha: 0.22);
            }
            return BarChartGroupData(
              x: idx,
              barRods: [
                BarChartRodData(
                  toY: b.count.toDouble(),
                  color: color,
                  width: 36,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => t.textPrimary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${buckets[group.x].bucket}\n${rod.toY.toInt()} profiles',
                  TextStyle(color: t.bg, fontSize: 12),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
