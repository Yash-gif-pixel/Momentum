import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/credify_theme.dart';
import 'climate_api_service.dart';
import 'climate_models.dart';
import 'climate_rain_chart.dart';
import 'climate_scenario_comparison.dart';

class ClimateStressCard extends StatefulWidget {
  const ClimateStressCard({
    super.key,
    required this.service,
    required this.profileId,
    this.initialScenarioId = 'heavy_rain_week',
  });

  final ClimateApiService service;
  final String profileId;
  final String initialScenarioId;

  @override
  State<ClimateStressCard> createState() => _ClimateStressCardState();
}

class _ClimateStressCardState extends State<ClimateStressCard> {
  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  ClimateOptions? _options;
  ClimateImpact? _impact;
  String? _scenarioId;
  String? _error;
  bool _loadingOptions = true;
  bool _loadingImpact = false;
  bool _detailsExpanded = false;
  bool _compareExpanded = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void didUpdateWidget(covariant ClimateStressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId &&
        _options != null &&
        _scenarioId != null) {
      _compareExpanded = false;
      _fetchImpact();
    }
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _error = null;
      _impact = null;
    });
    try {
      final options = await widget.service.fetchOptions();
      if (!mounted) return;
      final preferred = _scenarioId ?? widget.initialScenarioId;
      final selected =
          options.scenarios.any((scenario) => scenario.scenarioId == preferred)
          ? preferred
          : (options.scenarios.isEmpty
                ? null
                : options.scenarios.first.scenarioId);
      setState(() {
        _options = options;
        _scenarioId = selected;
        _loadingOptions = false;
      });
      if (selected != null) await _fetchImpact();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingOptions = false;
        _loadingImpact = false;
      });
    }
  }

  Future<void> _fetchImpact() async {
    final scenarioId = _scenarioId;
    if (scenarioId == null) return;
    final requestId = ++_requestId;
    setState(() {
      _loadingImpact = true;
      _error = null;
      _impact = null;
    });
    try {
      final impact = await widget.service.fetchImpact(
        widget.profileId,
        scenarioId,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _impact = impact;
        _loadingImpact = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error.toString();
        _loadingImpact = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scenarios = _options?.scenarios ?? const <ClimateScenario>[];
    final impact = _impact;
    return Card(
      color: tokens.cardFill,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cash-flow stress',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (scenarios.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 145),
                    child: DropdownButton<String>(
                      value: _scenarioId,
                      isExpanded: true,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final scenario in scenarios)
                          DropdownMenuItem(
                            value: scenario.scenarioId,
                            child: Text(
                              scenario.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _loadingImpact
                          ? null
                          : (value) {
                              if (value == null || value == _scenarioId) return;
                              setState(() => _scenarioId = value);
                              _fetchImpact();
                            },
                    ),
                  ),
              ],
            ),
            if (_loadingOptions || _loadingImpact)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Loading cash-flow estimate…'),
                  ],
                ),
              )
            else if (_error != null)
              _errorContent(_error!)
            else if (scenarios.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No climate scenarios are available.',
                  style: TextStyle(color: tokens.textSecondary),
                ),
              )
            else if (impact != null) ...[
              const SizedBox(height: 4),
              Text(
                impact.estimatedCashflowImpactInr == 0
                    ? 'No expected disruption'
                    : '≈ ${_currency.format(impact.estimatedCashflowImpactInr)} possible shortfall',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${impact.disruptedDays} heavy-rain days · ${impact.impactPctOfMonthlyInflow.toStringAsFixed(1)}% of a typical month\'s income',
              ),
              const SizedBox(height: 8),
              Text(
                impact.suggestedResilienceBufferInr > 0
                    ? 'Suggested: keep a ${_currency.format(impact.suggestedResilienceBufferInr)} buffer, or offer a short EMI holiday / working-capital top-up for this period.'
                    : 'No action needed for this scenario.',
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 10),
              _scoreBadge(impact, tokens),
              Wrap(
                spacing: 16,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _detailsExpanded = !_detailsExpanded),
                    icon: Icon(
                      _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: Text(_detailsExpanded ? 'Hide details' : 'Details'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _compareExpanded = !_compareExpanded),
                    icon: const Icon(Icons.stacked_bar_chart),
                    label: Text(
                      _compareExpanded
                          ? 'Hide comparison'
                          : 'Compare scenarios',
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (_detailsExpanded) ...[
                ClimateRainChart(daily: impact.daily, height: 160),
                const SizedBox(height: 12),
                const Text(
                  'Assumptions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final assumption in impact.assumptions)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $assumption'),
                  ),
              ],
            ],
            if (_compareExpanded) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: ClimateScenarioComparison(
                    service: widget.service,
                    profileId: widget.profileId,
                    scenarios: scenarios,
                    selectedScenarioId: _scenarioId ?? '',
                    onSelect: (scenarioId) {
                      if (scenarioId == _scenarioId) return;
                      setState(() => _scenarioId = scenarioId);
                      _fetchImpact();
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorContent(String message) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Could not load climate data: $message'),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _loadOptions,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _scoreBadge(ClimateImpact impact, CredifyTokens tokens) {
    final affectsCreditScore = impact.affectsCreditScore;
    final color = affectsCreditScore ? tokens.negative : tokens.positive;
    final label = affectsCreditScore
        ? 'Warning: response indicates a credit score effect'
        : 'Does not change the credit score';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            affectsCreditScore
                ? Icons.warning_amber_rounded
                : Icons.info_outline,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
