import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/analyze_response.dart';
import '../theme/credify_theme.dart';

class CashflowChart extends StatelessWidget {
  final List<MonthlyCashflow> data;
  const CashflowChart({super.key, required this.data});

  static const _inflow = Color(0xFF4ADE80);
  static const _outflow = Color(0xFFF87171);
  static const _net = Color(0xFF60A5FA);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (data.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No cashflow data available',
            style: TextStyle(color: t.textTertiary, fontSize: 13),
          ),
        ),
      );
    }

    final spots = <String, List<FlSpot>>{
      'inflow': [],
      'outflow': [],
      'net': [],
    };

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      spots['inflow']!.add(FlSpot(i.toDouble(), d.inflow / 1000));
      spots['outflow']!.add(FlSpot(i.toDouble(), d.outflow / 1000));
      spots['net']!.add(FlSpot(i.toDouble(), d.net / 1000));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly cashflow (₹ thousands)',
          style: TextStyle(color: t.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _legend(_inflow, 'Inflow', t),
            const SizedBox(width: 16),
            _legend(_outflow, 'Outflow', t),
            const SizedBox(width: 16),
            _legend(_net, 'Net', t),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
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
                    reservedSize: 36,
                    getTitlesWidget: (val, meta) => Text(
                      '${val.toInt()}k',
                      style: TextStyle(color: t.textTertiary, fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: data.length > 6 ? 2 : 1,
                    getTitlesWidget: (val, meta) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= data.length) return const SizedBox();
                      final parts = data[idx].month.split('-');
                      final label = parts.length == 2
                          ? '${parts[1]}/${parts[0].substring(2)}'
                          : data[idx].month;
                      return Text(
                        label,
                        style: TextStyle(color: t.textTertiary, fontSize: 9),
                      );
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                _line(spots['inflow']!, _inflow),
                _line(spots['outflow']!, _outflow),
                _line(spots['net']!, _net, isDashed: true),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => t.textPrimary,
                  getTooltipItems: (touched) => touched.map((s) {
                    const labels = ['Inflow', 'Outflow', 'Net'];
                    const colors = [_inflow, _outflow, _net];
                    return LineTooltipItem(
                      '${labels[s.barIndex]}: ₹${(s.y * 1000).toStringAsFixed(0)}',
                      TextStyle(color: colors[s.barIndex], fontSize: 11),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color,
      {bool isDashed = false}) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dashArray: isDashed ? [6, 4] : null,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  Widget _legend(Color color, String label, CredifyTokens t) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: t.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
