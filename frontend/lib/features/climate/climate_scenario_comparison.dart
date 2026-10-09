import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/credify_theme.dart';
import 'climate_api_service.dart';
import 'climate_models.dart';

class ClimateScenarioComparison extends StatefulWidget {
  const ClimateScenarioComparison({
    super.key,
    required this.service,
    required this.profileId,
    required this.scenarios,
    required this.selectedScenarioId,
    required this.onSelect,
  });

  final ClimateApiService service;
  final String profileId;
  final List<ClimateScenario> scenarios;
  final String selectedScenarioId;
  final ValueChanged<String> onSelect;

  @override
  State<ClimateScenarioComparison> createState() =>
      _ClimateScenarioComparisonState();
}

class _ClimateScenarioComparisonState extends State<ClimateScenarioComparison> {
  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  final Map<String, Map<String, ClimateImpact>> _impactCache = {};
  final Map<String, Set<String>> _failedCache = {};
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadImpacts();
  }

  @override
  void didUpdateWidget(covariant ClimateScenarioComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        !_sameScenarios(oldWidget.scenarios, widget.scenarios)) {
      _loadImpacts();
    }
  }

  bool _sameScenarios(
    List<ClimateScenario> first,
    List<ClimateScenario> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];
      if (a.scenarioId != b.scenarioId ||
          a.label != b.label ||
          a.description != b.description) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadImpacts({bool retryFailed = false}) async {
    final requestId = ++_requestId;
    final profileId = widget.profileId;
    final cache = _impactCache.putIfAbsent(profileId, () => {});
    final failures = _failedCache.putIfAbsent(profileId, () => {});
    final scenarios = List<ClimateScenario>.of(widget.scenarios);
    final toFetch = scenarios
        .where(
          (scenario) => retryFailed
              ? failures.contains(scenario.scenarioId)
              : !cache.containsKey(scenario.scenarioId) &&
                    !failures.contains(scenario.scenarioId),
        )
        .toList();

    setState(() => _loading = true);
    final results = await Future.wait(
      toFetch.map((scenario) async {
        try {
          final impact = await widget.service.fetchImpact(
            profileId,
            scenario.scenarioId,
          );
          return (scenario.scenarioId, impact, false);
        } catch (_) {
          return (scenario.scenarioId, null, true);
        }
      }),
    );

    for (final result in results) {
      if (result.$3) {
        failures.add(result.$1);
      } else {
        cache[result.$1] = result.$2!;
        failures.remove(result.$1);
      }
    }
    if (!mounted || requestId != _requestId) return;
    setState(() => _loading = false);
  }

  ClimateImpact? _impactFor(ClimateScenario scenario) =>
      _impactCache[widget.profileId]?[scenario.scenarioId];

  List<ClimateImpact> get _availableImpacts =>
      widget.scenarios.map(_impactFor).whereType<ClimateImpact>().toList();

  List<ClimateScenario> get _failedScenarios => widget.scenarios
      .where(
        (scenario) =>
            _failedCache[widget.profileId]?.contains(scenario.scenarioId) ??
            false,
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final available = _availableImpacts;
    final failures = _failedScenarios;
    final allFailed =
        widget.scenarios.isNotEmpty && available.isEmpty && failures.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading && available.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 9),
                Text('Comparing scenarios…'),
              ],
            ),
          )
        else if (widget.scenarios.isEmpty)
          const Text('No climate scenarios are available.')
        else if (allFailed)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Could not compare climate scenarios.'),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => _loadImpacts(retryFailed: true),
                child: const Text('Retry'),
              ),
            ],
          )
        else ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Comparing scenarios…'),
            ),
          SizedBox(height: 160, child: _chart(tokens)),
          const SizedBox(height: 8),
          for (final scenario in widget.scenarios)
            _scenarioRow(scenario, tokens),
          if (failures.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () => _loadImpacts(retryFailed: true),
                child: const Text('Retry'),
              ),
            ),
          if (_takeaway(available) case final takeaway?) ...[
            const SizedBox(height: 8),
            Text(
              takeaway,
              style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Cash-flow estimates only — none of these change the credit score.',
            style: TextStyle(color: tokens.textTertiary, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _chart(CredifyTokens tokens) {
    final maximum = widget.scenarios
        .map(
          (scenario) => _impactFor(scenario)?.estimatedCashflowImpactInr ?? 0,
        )
        .fold<double>(0, (current, value) => value > current ? value : current);
    return BarChart(
      BarChartData(
        maxY: maximum > 0 ? maximum * 1.18 : 1,
        minY: 0,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        barGroups: [
          for (var index = 0; index < widget.scenarios.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY:
                      _impactFor(widget.scenarios[index])
                          ?.estimatedCashflowImpactInr ??
                      0,
                  color:
                      widget.scenarios[index].scenarioId ==
                          widget.selectedScenarioId
                      ? tokens.accentA
                      : tokens.textTertiary,
                  width: 22,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= widget.scenarios.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _shortLabel(widget.scenarios[index].label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 220),
    );
  }

  String _shortLabel(String label) =>
      label.length <= 12 ? label : '${label.substring(0, 11)}…';

  Widget _scenarioRow(ClimateScenario scenario, CredifyTokens tokens) {
    final impact = _impactFor(scenario);
    final selected = scenario.scenarioId == widget.selectedScenarioId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSelect(scenario.scenarioId),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? tokens.accentA.withValues(alpha: .10)
                  : tokens.pillFill,
              border: Border.all(
                color: selected ? tokens.accentA : tokens.hairline,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scenario.label,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (impact == null)
                  Text(
                    'Unavailable',
                    style: TextStyle(color: tokens.textSecondary),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text('${impact.disruptedDays} disrupted days'),
                      Text(_currency.format(impact.estimatedCashflowImpactInr)),
                      Text(
                        '${impact.impactPctOfMonthlyInflow.toStringAsFixed(1)}% of monthly inflow',
                      ),
                      Text(
                        'Buffer ${_currency.format(impact.suggestedResilienceBufferInr)}',
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _takeaway(List<ClimateImpact> impacts) {
    if (impacts.isEmpty) return null;
    final nonZero = impacts
        .where((impact) => impact.estimatedCashflowImpactInr > 0)
        .toList();
    final worst = impacts.reduce(
      (a, b) =>
          a.estimatedCashflowImpactInr >= b.estimatedCashflowImpactInr ? a : b,
    );
    final scenario = widget.scenarios.firstWhere(
      (item) => item.scenarioId == worst.scenarioId,
    );
    final prefix =
        'Worst case: ${scenario.label} — about ${_currency.format(worst.estimatedCashflowImpactInr)} at risk';
    if (nonZero.length < 2) return '$prefix.';
    final mildest = nonZero.reduce(
      (a, b) =>
          a.estimatedCashflowImpactInr <= b.estimatedCashflowImpactInr ? a : b,
    );
    final multiple =
        (worst.estimatedCashflowImpactInr / mildest.estimatedCashflowImpactInr)
            .toStringAsFixed(1);
    return '$prefix, $multiple× the mildest scenario.';
  }
}
