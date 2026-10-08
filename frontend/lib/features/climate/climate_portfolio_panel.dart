import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/credify_theme.dart';
import 'climate_api_service.dart';
import 'climate_models.dart';

class ClimatePortfolioPanel extends StatefulWidget {
  const ClimatePortfolioPanel({
    super.key,
    required this.service,
    this.initialScenarioId = 'heavy_rain_week',
    this.onBorrowerTap,
  });

  final ClimateApiService service;
  final String initialScenarioId;
  final void Function(String profileId)? onBorrowerTap;

  @override
  State<ClimatePortfolioPanel> createState() => _ClimatePortfolioPanelState();
}

class _ClimatePortfolioPanelState extends State<ClimatePortfolioPanel> {
  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  ClimateOptions? _options;
  ClimatePortfolio? _portfolio;
  String? _scenarioId;
  String? _error;
  bool _loadingOptions = true;
  bool _loadingPortfolio = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void didUpdateWidget(covariant ClimatePortfolioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _error = null;
      _portfolio = null;
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
      if (selected != null) await _fetchPortfolio();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingOptions = false;
        _loadingPortfolio = false;
      });
    }
  }

  Future<void> _fetchPortfolio() async {
    final scenarioId = _scenarioId;
    if (scenarioId == null) return;
    final requestId = ++_requestId;
    setState(() {
      _loadingPortfolio = true;
      _error = null;
      _portfolio = null;
    });
    try {
      final portfolio = await widget.service.fetchPortfolio(scenarioId);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _portfolio = portfolio;
        _loadingPortfolio = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error.toString();
        _loadingPortfolio = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scenarios = _options?.scenarios ?? const <ClimateScenario>[];
    final portfolio = _portfolio;
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
                    'Climate portfolio',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (scenarios.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
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
                      onChanged: _loadingPortfolio
                          ? null
                          : (value) {
                              if (value == null || value == _scenarioId) return;
                              setState(() => _scenarioId = value);
                              _fetchPortfolio();
                            },
                    ),
                  ),
              ],
            ),
            if (_loadingOptions || _loadingPortfolio)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Loading climate portfolio…'),
                  ],
                ),
              )
            else if (_error != null)
              _errorView(_error!)
            else if (scenarios.isEmpty)
              _empty('No climate scenarios are available.')
            else if (portfolio != null) ...[
              const SizedBox(height: 12),
              _summary(portfolio, tokens),
              const SizedBox(height: 12),
              if (portfolio.borrowers.isEmpty)
                _empty('No borrowers are available for this scenario.')
              else
                for (final borrower in _orderedBorrowers(portfolio.borrowers))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _borrowerRow(borrower, tokens),
                  ),
              const SizedBox(height: 4),
              _creditScoreBadge(portfolio.affectsCreditScore, tokens),
            ],
          ],
        ),
      ),
    );
  }

  List<PortfolioBorrower> _orderedBorrowers(
    List<PortfolioBorrower> borrowers,
  ) => [...borrowers]
    ..sort((a, b) {
      final exposureOrder = (b.exposed ? 1 : 0).compareTo(a.exposed ? 1 : 0);
      if (exposureOrder != 0) return exposureOrder;
      final impactOrder = b.estimatedCashflowImpactInr.compareTo(
        a.estimatedCashflowImpactInr,
      );
      return impactOrder != 0
          ? impactOrder
          : a.profileId.compareTo(b.profileId);
    });

  Widget _summary(ClimatePortfolio portfolio, CredifyTokens tokens) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: _summaryTile(
          'Borrowers exposed',
          '${portfolio.borrowersExposed} of ${portfolio.borrowers.length}',
          tokens,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _summaryTile(
          'Estimated cash at risk',
          _currency.format(portfolio.totalEstimatedImpactInr),
          tokens,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _summaryTile(
          'Suggested buffers',
          _currency.format(portfolio.totalSuggestedBufferInr),
          tokens,
        ),
      ),
    ],
  );

  Widget _summaryTile(String label, String value, CredifyTokens tokens) =>
      Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tokens.pillFill,
          border: Border.all(color: tokens.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );

  Widget _borrowerRow(
    PortfolioBorrower borrower,
    CredifyTokens tokens,
  ) => InkWell(
    onTap: widget.onBorrowerTap == null
        ? null
        : () => widget.onBorrowerTap!(borrower.profileId),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.cardFill,
        border: Border.all(color: tokens.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      borrower.profileId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (borrower.city != null &&
                        borrower.city!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          borrower.city!,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _exposureChip(borrower.exposed, tokens),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                'Impact: ${_currency.format(borrower.estimatedCashflowImpactInr)}',
              ),
              Text(
                'Buffer: ${_currency.format(borrower.suggestedResilienceBufferInr)}',
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _exposureChip(bool exposed, CredifyTokens tokens) {
    final color = exposed ? tokens.positive : tokens.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            exposed ? Icons.location_on_outlined : Icons.location_off_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            exposed ? 'Exposed' : 'Not exposed',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _creditScoreBadge(bool affectsCreditScore, CredifyTokens tokens) {
    final color = affectsCreditScore ? tokens.negative : tokens.positive;
    final text = affectsCreditScore
        ? 'Warning: response indicates a credit score effect'
        : 'Does not change credit scores';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(String message) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Could not load climate portfolio: $message'),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _loadOptions,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Center(child: Text(message, textAlign: TextAlign.center)),
  );
}
