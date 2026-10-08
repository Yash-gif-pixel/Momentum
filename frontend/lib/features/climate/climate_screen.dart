import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/credify_theme.dart';
import 'climate_api_service.dart';
import 'climate_models.dart';
import 'climate_rain_chart.dart';

class ClimateScreen extends StatefulWidget {
  final ClimateApiService service;
  const ClimateScreen({super.key, required this.service});
  @override
  State<ClimateScreen> createState() => _ClimateScreenState();
}

class _ClimateScreenState extends State<ClimateScreen> {
  ClimateOptions? _options;
  ClimateImpact? _impact;
  String? _profile;
  String? _scenario;
  String? _optionsError;
  String? _impactError;
  bool _loadingOptions = true;
  bool _loadingImpact = false;
  final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() { super.initState(); _loadOptions(); }
  Future<void> _loadOptions() async {
    setState(() { _loadingOptions = true; _optionsError = null; });
    try {
      final value = await widget.service.fetchOptions();
      if (!mounted) return;
      setState(() { _options = value; _profile = value.profileIds.isEmpty ? null : value.profileIds.first; _scenario = value.scenarios.isEmpty ? null : value.scenarios.first.scenarioId; _loadingOptions = false; });
    } catch (e) { if (mounted) setState(() { _optionsError = e.toString(); _loadingOptions = false; }); }
  }
  Future<void> _estimate() async {
    if (_profile == null || _scenario == null) return;
    setState(() { _loadingImpact = true; _impactError = null; _impact = null; });
    try { final value = await widget.service.fetchImpact(_profile!, _scenario!); if (mounted) setState(() { _impact = value; _loadingImpact = false; }); }
    catch (e) { if (mounted) setState(() { _impactError = e.toString(); _loadingImpact = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: _loadingOptions
        ? const Center(child: CircularProgressIndicator())
        : _optionsError != null ? _error(_optionsError!, _loadOptions)
        : _options == null || _options!.scenarios.isEmpty || _options!.profileIds.isEmpty ? _empty('No climate scenarios or borrower profiles are available.')
        : ListView(padding: const EdgeInsets.all(24), children: [
          Text('Climate impact', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6), Text('Weather can affect short-term cash flow.', style: TextStyle(color: t.textSecondary)),
          const SizedBox(height: 6), Text('This estimate does not determine creditworthiness.', style: TextStyle(color: t.textTertiary, fontSize: 12)),
          const SizedBox(height: 24), _section('Borrower profile', DropdownButtonFormField<String>(initialValue: _profile, decoration: const InputDecoration(border: OutlineInputBorder()), items: _options!.profileIds.map((id) => DropdownMenuItem(value: id, child: Text(id))).toList(), onChanged: (value) => setState(() { _profile = value; _impact = null; }))),
          const SizedBox(height: 20), _section('Weather scenario', RadioGroup<String>(groupValue: _scenario, onChanged: (value) => setState(() { _scenario = value; _impact = null; }), child: Column(children: [for (final scenario in _options!.scenarios) Card(color: t.cardFill, child: RadioListTile<String>(value: scenario.scenarioId, title: Text(scenario.label), subtitle: Text(scenario.description))) ]))),
          FilledButton.icon(onPressed: _loadingImpact ? null : _estimate, icon: const Icon(Icons.insights), label: const Text('Estimate impact')),
          if (_loadingImpact) const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator())),
          if (_impactError != null) _error(_impactError!, _estimate),
          if (_options!.scenarios.isEmpty) _empty('No scenarios found.'),
          if (_impact != null) _result(_impact!),
        ])))));
  }

  Widget _section(String title, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 8), child]);
  Widget _empty(String text) => Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(text, textAlign: TextAlign.center)));
  Widget _error(String message, VoidCallback retry) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Could not load climate data: $message'), const SizedBox(height: 8), OutlinedButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Retry'))])));

  Widget _result(ClimateImpact impact) {
    final t = context.tokens;
    final disrupted = impact.daily.where((day) => day.disrupted).length;
    return Card(color: t.cardFill, margin: const EdgeInsets.only(top: 24, bottom: 50), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Estimated cash-flow impact', style: TextStyle(color: t.textSecondary)),
      const SizedBox(height: 4), Text(_currency.format(impact.estimatedCashflowImpactInr), style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
      Text('${impact.impactPctOfMonthlyInflow.toStringAsFixed(1)}% of a typical month\'s inflow'),
      const SizedBox(height: 14), Wrap(spacing: 12, runSpacing: 8, children: [Chip(label: Text('$disrupted disrupted days')), Chip(label: Text('Resilience buffer ${_currency.format(impact.suggestedResilienceBufferInr)}'))]),
      const SizedBox(height: 16),
      ClimateRainChart(daily: impact.daily),
      const SizedBox(height: 18), if (!impact.affectsCreditScore) _badge('Does not change the credit score', t.positive) else _badge('Warning: response indicates a credit score effect', t.negative),
      const SizedBox(height: 16), const Text('Assumptions', style: TextStyle(fontWeight: FontWeight.bold)),
      for (final item in impact.assumptions) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $item')),
    ])));
  }
  Widget _badge(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: color.withValues(alpha: .12), border: Border.all(color: color), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.info_outline, color: color, size: 17), const SizedBox(width: 8), Flexible(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)))]));
}
