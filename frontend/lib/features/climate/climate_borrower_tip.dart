import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/credify_theme.dart';
import '../../widgets/credify_shell_widgets.dart';
import 'climate_api_service.dart';
import 'climate_models.dart';

class ClimateBorrowerTip extends StatefulWidget {
  const ClimateBorrowerTip({
    super.key,
    required this.service,
    required this.profileId,
    this.scenarioId = 'heavy_rain_week',
    this.initialHindi = false,
  });

  final ClimateApiService service;
  final String profileId;
  final String scenarioId;
  final bool initialHindi;

  @override
  State<ClimateBorrowerTip> createState() => _ClimateBorrowerTipState();
}

class _TipLanguage {
  final String languageName;
  final String title;
  final String line1;
  final String line2;
  final String line3;
  final String noDisruption;
  final String footer;
  final String warning;
  final String loading;
  final String error;
  final String retry;

  const _TipLanguage({
    required this.languageName,
    required this.title,
    required this.line1,
    required this.line2,
    required this.line3,
    required this.noDisruption,
    required this.footer,
    required this.warning,
    required this.loading,
    required this.error,
    required this.retry,
  });
}

const _english = _TipLanguage(
  languageName: 'English',
  title: 'Rain can slow your business',
  line1:
      'If a {scenarioLabel} happens, rain could stop about {n} days of work.',
  line2: 'Your sales could drop by about {impact}.',
  line3: 'Try to keep {buffer} aside before the rainy season.',
  noDisruption:
      'Good news: this kind of rain is not expected to affect your work.',
  footer: 'This is an estimate. It does not change your credit score.',
  warning: 'Warning: response indicates a credit score effect',
  loading: 'Checking rain risk…',
  error: "Couldn't load rain information right now.",
  retry: 'Try again',
);

const _hindi = _TipLanguage(
  languageName: 'हिंदी',
  title: 'बारिश से आपका कारोबार धीमा हो सकता है',
  line1: 'अगर {scenarioLabel} जैसी स्थिति बनती है, तो बारिश से लगभग {n} दिन काम रुक सकता है।',
  line2: 'आपकी बिक्री लगभग {impact} तक कम हो सकती है।',
  line3: 'बारिश के मौसम से पहले {buffer} अलग बचाकर रखने की कोशिश करें।',
  noDisruption:
      'अच्छी खबर: इस तरह की बारिश से आपके काम पर असर पड़ने की उम्मीद नहीं है।',
  footer: 'यह केवल एक अनुमान है। इससे आपका क्रेडिट स्कोर नहीं बदलता।',
  warning: 'चेतावनी: जवाब में क्रेडिट स्कोर पर असर बताया गया है',
  loading: 'बारिश का जोखिम देखा जा रहा है…',
  error: 'अभी बारिश की जानकारी नहीं मिल सकी।',
  retry: 'फिर कोशिश करें',
);

class _ClimateBorrowerTipState extends State<ClimateBorrowerTip> {
  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  Future<ClimateOptions>? _optionsFuture;
  ClimateOptions? _options;
  ClimateImpact? _impact;
  String? _error;
  bool _loading = true;
  late bool _isHindi;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _isHindi = widget.initialHindi;
    _load();
  }

  @override
  void didUpdateWidget(covariant ClimateBorrowerTip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _options = null;
      _optionsFuture = null;
      _load();
    } else if (oldWidget.profileId != widget.profileId ||
        oldWidget.scenarioId != widget.scenarioId) {
      _load();
    }
    if (oldWidget.initialHindi != widget.initialHindi) {
      _isHindi = widget.initialHindi;
    }
  }

  Future<ClimateOptions> _loadOptions() =>
      _optionsFuture ??= widget.service.fetchOptions();

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _impact = null;
    });
    try {
      final options = await _loadOptions();
      if (!mounted || requestId != _requestId) return;
      _options = options;
      final impact = await widget.service.fetchImpact(
        widget.profileId,
        widget.scenarioId,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _impact = impact;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      if (_options == null) _optionsFuture = null;
      setState(() {
        _error = _copy.error;
        _loading = false;
      });
    }
  }

  _TipLanguage get _copy => _isHindi ? _hindi : _english;

  String get _scenarioLabel {
    for (final scenario in _options?.scenarios ?? const <ClimateScenario>[]) {
      if (scenario.scenarioId == widget.scenarioId) return scenario.label;
    }
    return widget.scenarioId;
  }

  String _money(double amount) =>
      _currency.format((amount / 100).round() * 100);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = _copy;
    final impact = _impact;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.umbrella_outlined, color: tokens.accentA, size: 25),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  copy.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _languageToggle(tokens),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            Row(
              children: [
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accentA,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  copy.loading,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 15),
                ),
              ],
            )
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.error,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 15),
                ),
                const SizedBox(height: 4),
                TextButton(onPressed: _load, child: Text(copy.retry)),
              ],
            )
          else if (impact != null)
            _impactText(impact, copy, tokens),
          const SizedBox(height: 12),
          Text(
            impact?.affectsCreditScore == true ? copy.warning : copy.footer,
            style: TextStyle(
              color: impact?.affectsCreditScore == true
                  ? tokens.negative
                  : tokens.textTertiary,
              fontSize: 12,
              fontWeight: impact?.affectsCreditScore == true
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _languageToggle(CredifyTokens tokens) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: tokens.pillFill,
      border: Border.all(color: tokens.hairline),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _languageButton(_english, false, tokens),
        _languageButton(_hindi, true, tokens),
      ],
    ),
  );

  Widget _languageButton(
    _TipLanguage language,
    bool hindi,
    CredifyTokens tokens,
  ) {
    final selected = _isHindi == hindi;
    return InkWell(
      onTap: () => setState(() => _isHindi = hindi),
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? tokens.accentA.withValues(alpha: .16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          language.languageName,
          style: TextStyle(
            color: selected ? tokens.textPrimary : tokens.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _impactText(
    ClimateImpact impact,
    _TipLanguage copy,
    CredifyTokens tokens,
  ) {
    final style = TextStyle(
      color: tokens.textPrimary,
      fontSize: 15.5,
      height: 1.4,
    );
    final noDisruption =
        impact.disruptedDays <= 0 || impact.estimatedCashflowImpactInr <= 0;
    if (noDisruption) {
      return Text(copy.noDisruption, style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.line1
              .replaceAll('{scenarioLabel}', _scenarioLabel)
              .replaceAll('{n}', '${impact.disruptedDays}'),
          style: style,
        ),
        const SizedBox(height: 6),
        Text(
          copy.line2.replaceAll(
            '{impact}',
            _money(impact.estimatedCashflowImpactInr),
          ),
          style: style,
        ),
        const SizedBox(height: 6),
        Text(
          copy.line3.replaceAll(
            '{buffer}',
            _money(impact.suggestedResilienceBufferInr),
          ),
          style: style,
        ),
      ],
    );
  }
}
