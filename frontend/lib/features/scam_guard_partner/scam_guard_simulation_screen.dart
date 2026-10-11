import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_console_panel.dart';
import 'demo_scenarios.dart';
import 'demopay_screens.dart';
import 'phone_frame.dart';
import 'simulated_scam_guard_api.dart';

class ScamGuardSimulationScreen extends StatefulWidget {
  final SimulatedScamGuardApi? api;
  final Duration checkingDisplayDuration;

  const ScamGuardSimulationScreen({
    super.key,
    this.api,
    this.checkingDisplayDuration = const Duration(milliseconds: 1200),
  });

  @override
  State<ScamGuardSimulationScreen> createState() =>
      _ScamGuardSimulationScreenState();
}

class _ScamGuardSimulationScreenState extends State<ScamGuardSimulationScreen> {
  static const _accent = Color(0xFF4657A8);
  static const _ink = Color(0xFF20242C);
  static const _muted = Color(0xFF747B87);
  static const _soft = Color(0xFFF5F6F8);

  late final SimulatedScamGuardApi _api;
  DemoScenario _scenario = kDemoScenarios.first;
  DemoPayStage _stage = DemoPayStage.home;
  bool _protectedMode = true;
  bool _wrongApiKey = false;
  bool _actionsEnabled = true;
  bool _failOpen = false;
  bool _cancelled = false;
  bool _revealScam = false;
  int _pinDigitCount = 0;
  int _checksRun = 0;
  int _scamsBlocked = 0;
  double _amountProtected = 0;
  int _paymentSequence = 0;
  SimulatedApiResponse? _lastResponse;
  Map<String, dynamic>? _lastRequestBody;
  String? _lastUsedApiKey;
  Timer? _transitionTimer;
  Timer? _scamRevealTimer;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? SimulatedScamGuardApi();
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    _scamRevealTimer?.cancel();
    super.dispose();
  }

  void _goTo(DemoPayStage next) {
    _transitionTimer?.cancel();
    setState(() {
      _stage = next;
      _actionsEnabled = false;
    });
    _transitionTimer = Timer(const Duration(milliseconds: 270), () {
      if (mounted) setState(() => _actionsEnabled = true);
    });
  }

  void _selectScenario(DemoScenario scenario) {
    _transitionTimer?.cancel();
    _scamRevealTimer?.cancel();
    setState(() {
      _scenario = scenario;
      _stage = DemoPayStage.home;
      _actionsEnabled = true;
      _failOpen = false;
      _cancelled = false;
      _revealScam = false;
      _pinDigitCount = 0;
      _lastResponse = null;
      _lastRequestBody = null;
      _lastUsedApiKey = null;
    });
  }

  Future<void> _openPayment() async {
    _pinDigitCount = 0;
    _failOpen = false;
    if (!_protectedMode) {
      _goTo(DemoPayStage.pin);
      return;
    }

    final requestBody = _scenario.toRequestBody();
    final apiKey = _wrongApiKey ? kWrongApiKey : kDemoApiKey;
    final minimumDisplay = Future<void>.delayed(widget.checkingDisplayDuration);
    setState(() {
      _checksRun++;
      _stage = DemoPayStage.checking;
      _actionsEnabled = false;
      _lastResponse = null;
      _lastRequestBody = null;
      _lastUsedApiKey = null;
    });

    final responseFuture = _api.check(apiKey: apiKey, requestBody: requestBody);
    SimulatedApiResponse? response;
    try {
      response = await responseFuture;
    } finally {
      await minimumDisplay;
    }
    if (!mounted) return;

    setState(() {
      _lastRequestBody = requestBody;
      _lastUsedApiKey = apiKey;
      _lastResponse = response;
    });

    if (response == null || response.statusCode != 200) {
      setState(() => _failOpen = true);
      _goTo(DemoPayStage.pin);
      return;
    }

    _goTo(DemoPayStage.verdict);
    switch (response.body['decision']) {
      case 'allow':
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted && _stage == DemoPayStage.verdict) {
          _goTo(DemoPayStage.pin);
        }
        break;
      case 'warn':
      case 'block':
        break;
      default:
        setState(() => _failOpen = true);
        _goTo(DemoPayStage.pin);
        break;
    }
  }

  void _cancelPayment() {
    if (_scenario.isScam) {
      setState(() {
        _scamsBlocked++;
        _amountProtected += _scenario.amountInr;
        _cancelled = true;
      });
    } else {
      setState(() => _cancelled = true);
    }
    _goTo(DemoPayStage.result);
  }

  void _enterPinDigit(int digit) {
    if (digit == -1) {
      setState(() => _pinDigitCount = (_pinDigitCount - 1).clamp(0, 6).toInt());
      return;
    }
    if (_pinDigitCount >= 5) {
      _paymentSequence++;
      setState(() {
        _pinDigitCount = 0;
        _cancelled = false;
        _revealScam = false;
      });
      _goTo(DemoPayStage.result);
      if (_scenario.isScam) {
        _scamRevealTimer?.cancel();
        _scamRevealTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted && _stage == DemoPayStage.result && !_cancelled) {
            setState(() => _revealScam = true);
          }
        });
      }
      return;
    }
    setState(() => _pinDigitCount++);
  }

  void _returnHome() {
    _scamRevealTimer?.cancel();
    setState(() {
      _stage = DemoPayStage.home;
      _actionsEnabled = true;
      _failOpen = false;
      _cancelled = false;
      _revealScam = false;
      _pinDigitCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _accent,
        brightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: viewport.maxWidth < 700 ? 16 : 32,
                    vertical: 22,
                  ),
                  child: Column(
                    children: [
                      _header(viewport.maxWidth),
                      const SizedBox(height: 20),
                      _impactStrip(),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, content) => _responsiveContent(
                          width: content.maxWidth,
                          screenWidth: MediaQuery.sizeOf(context).width,
                          viewportHeight: viewport.maxHeight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(double width) => Column(
        children: [
          Text(
            'Scam Guard — inside any UPI app',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: width < 500 ? 25 : 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'See how an in-app check can combine the payment details with '
            'synthetic transaction context before the PIN screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _soft,
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text(
              'Simulation · real 10-rule SDK + illustrative context signals',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );

  Widget _impactStrip() {
    final protected = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(_amountProtected);
    final stats = [
      ('Checks run', '$_checksRun', Icons.bolt_rounded),
      ('Scams blocked', '$_scamsBlocked', Icons.shield_rounded),
      ('₹ protected', protected, Icons.savings_rounded),
    ];
    return Container(
      constraints: const BoxConstraints(maxWidth: 820),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(19)),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) Container(width: 1, height: 35, color: const Color(0xFFE1E4E9)),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(stats[i].$3, color: _accent, size: 17),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stats[i].$2, key: ValueKey('impact-value-$i'), overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(stats[i].$1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _responsiveContent(
    {
    required double width,
    required double screenWidth,
    required double viewportHeight,
  }) {
    if (screenWidth >= 1100) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _controlsAndSteps()),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: _phone(width * 4 / 11, viewportHeight)),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: _console()),
        ],
      );
    }

    return Column(
      children: [
        _controlsAndSteps(),
        const SizedBox(height: 20),
        _phone(width, viewportHeight),
        const SizedBox(height: 22),
        _console(),
      ],
    );
  }

  Widget _phone(double width, double viewportHeight) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final availableHeight = compact
        ? (viewportHeight - 235).clamp(480.0, viewportHeight).toDouble()
        : viewportHeight;
    return Center(
      child: PhoneFrame(
        compact: compact,
        availableWidth: width,
        availableHeight: availableHeight,
        child: DemoPayScreens(
          stage: _stage,
          scenario: _scenario,
          protectedMode: _protectedMode,
          actionsEnabled: _actionsEnabled,
          apiResponse: _lastResponse?.body,
          failOpen: _failOpen,
          cancelled: _cancelled,
          revealScam: _revealScam,
          pinDigitCount: _pinDigitCount,
          transactionId: 'DPAY${_paymentSequence.toString().padLeft(6, '0')}',
          onPay: _stage == DemoPayStage.home ? () => _goTo(DemoPayStage.pay) : _openPayment,
          onCancel: _cancelPayment,
          onContinue: () => _goTo(DemoPayStage.pin),
          onBack: _returnHome,
          onDone: _returnHome,
          onPinDigit: _enterPinDigit,
        ),
      ),
    );
  }

  Widget _controlsAndSteps() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _controls(),
          const SizedBox(height: 18),
          _howItWorks(),
        ],
      );

  Widget _controls() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE9EBEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose a mode', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              key: const ValueKey('guard-mode-toggle'),
              segments: const [
                ButtonSegment(value: false, label: Text('Without Scam Guard')),
                ButtonSegment(value: true, label: Text('With Scam Guard')),
              ],
              selected: {_protectedMode},
              onSelectionChanged: _actionsEnabled
                  ? (selection) => setState(() => _protectedMode = selection.first)
                  : null,
              showSelectedIcon: false,
              style: ButtonStyle(
                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 11)),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Choose a scenario', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = ((constraints.maxWidth - 8) / 2)
                  .clamp(112.0, constraints.maxWidth)
                  .toDouble();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scenario in kAllDemoScenarios)
                    SizedBox(
                      width: itemWidth,
                      child: _scenarioChoice(scenario),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _paymentContextSummary(),
        ],
      ),
    );
  }

  Widget _paymentContextSummary() {
    final context = _scenario.paymentContext;
    final parameters = <(String, String)>[
      ('Payments to payee / 10 min', '${context.recentPaymentsToPayee10m}'),
      ('Similar transfers / hour', '${context.similarPaymentsLastHour}'),
      (
        'Recipient details recently changed',
        context.beneficiaryDetailsChangedRecently ? 'Yes' : 'No',
      ),
      ('Synthetic recipient reports', '${context.recipientRiskReports}'),
      ('Unexpected payment request', context.unexpectedCollectRequest ? 'Yes' : 'No'),
      ('External-link origin', context.paymentStartedFromExternalLink ? 'Yes' : 'No'),
      ('New device/session', context.newDeviceSession ? 'Yes' : 'No'),
      ('Recent SIM change', context.recentSimChange ? 'Yes' : 'No'),
      ('Screen sharing active', context.activeScreenSharing ? 'Yes' : 'No'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FB),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE9EBEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Synthetic payment-context parameters',
            style: TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, value) in parameters)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFE5E7ED)),
                  ),
                  child: Text(
                    '$label: $value',
                    style: const TextStyle(color: _muted, fontSize: 9, height: 1.25),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Demo values only. No real contacts, messages, SIM status, device state, or risk reports are accessed.',
            style: TextStyle(color: _muted, fontSize: 9, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _scenarioChoice(DemoScenario scenario) {
    final selected = _scenario.id == scenario.id;
    return InkWell(
      key: ValueKey('scenario-${scenario.id}'),
      onTap: _actionsEnabled ? () => _selectScenario(scenario) : null,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF0FA) : _soft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _accent : Colors.transparent, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(scenario.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? _accent : _ink)),
            const SizedBox(height: 4),
            Text(scenario.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, height: 1.25, color: _muted)),
          ],
        ),
      ),
    );
  }

  Widget _howItWorks() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How it works', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            _step(1, 'DemoPay sends payee, amount, note, and available context.'),
            _step(2, 'The published SDK rules and the separate demo context layer return explainable signals.'),
            _step(3, 'DemoPay shows the recommendation; the user or host app controls what happens next.'),
          ],
        ),
      );

  Widget _step(int number, String copy) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Text('$number', style: const TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(copy, style: const TextStyle(color: _muted, fontSize: 11, height: 1.45))),
          ],
        ),
      );

  Widget _console() => ApiConsolePanel(
        guardEnabled: _protectedMode,
        wrongApiKey: _wrongApiKey,
        onWrongApiKeyChanged: (value) => setState(() => _wrongApiKey = value),
        requestBody: _lastRequestBody,
        usedApiKey: _lastUsedApiKey,
        response: _lastResponse,
      );
}
