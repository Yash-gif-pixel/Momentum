import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'demo_scenarios.dart';

enum DemoPayStage { home, pay, checking, verdict, pin, result }

class DemoPayScreens extends StatelessWidget {
  final DemoPayStage stage;
  final DemoScenario scenario;
  final bool protectedMode;
  final bool actionsEnabled;
  final Map<String, dynamic>? apiResponse;
  final bool failOpen;
  final bool cancelled;
  final bool revealScam;
  final int pinDigitCount;
  final String transactionId;
  final VoidCallback onPay;
  final VoidCallback onCancel;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final ValueChanged<int> onPinDigit;

  const DemoPayScreens({
    super.key,
    required this.stage,
    required this.scenario,
    required this.protectedMode,
    required this.actionsEnabled,
    required this.apiResponse,
    required this.failOpen,
    required this.cancelled,
    required this.revealScam,
    required this.pinDigitCount,
    required this.transactionId,
    required this.onPay,
    required this.onCancel,
    required this.onContinue,
    required this.onBack,
    required this.onDone,
    required this.onPinDigit,
  });

  static const _ink = Color(0xFF20242C);
  static const _muted = Color(0xFF747B87);
  static const _accent = Color(0xFF4657A8);
  static const _surface = Color(0xFFF5F6F8);

  String get _amount => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      ).format(scenario.amountInr);

  @override
  Widget build(BuildContext context) {
    final screen = _screen();
    final responseState = apiResponse?['decision'] ?? apiResponse?['error'];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (transitionChild, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(animation),
          child: transitionChild,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('${stage.name}-$responseState-$cancelled-$revealScam'),
        child: screen,
      ),
    );
  }

  Widget _screen() {
    return switch (stage) {
      DemoPayStage.home => _home(),
      DemoPayStage.pay => _pay(),
      DemoPayStage.checking => _checking(),
      DemoPayStage.verdict => _verdict(),
      DemoPayStage.pin => _pin(),
      DemoPayStage.result => _result(),
    };
  }

  Widget _scrollPage(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('phone-scroll'),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _home() {
    return _scrollPage([
      Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'DemoPay',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink),
            ),
          ),
          const CircleAvatar(
            radius: 19,
            backgroundColor: Color(0xFFE8EAF4),
            child: Text('AM', style: TextStyle(color: _accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      if (protectedMode) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6EF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded, size: 15, color: Color(0xFF288253)),
              SizedBox(width: 5),
              Text(
                'Protected by Momentum Scam Guard',
                style: TextStyle(fontSize: 10, color: Color(0xFF246E48), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4657A8), Color(0xFF6375C1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TOTAL BALANCE', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.1)),
            SizedBox(height: 7),
            Text('₹24,500.00', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('DemoPay Bank  •• 4821  ·  fictional', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
      const SizedBox(height: 19),
      Row(
        children: [
          _quickAction(Icons.qr_code_scanner_rounded, 'Scan QR'),
          _quickAction(Icons.person_add_alt_1_rounded, 'Pay contact'),
          _quickAction(Icons.account_balance_rounded, 'Transfer'),
          _quickAction(Icons.receipt_long_rounded, 'Bills'),
        ],
      ),
      const SizedBox(height: 21),
      const Text('Payment requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _avatar(scenario.payeeName, 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scenario.payeeName, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(scenario.payeeVpa, style: const TextStyle(color: _muted, fontSize: 10)),
                    ],
                  ),
                ),
                Text(_amount, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 9),
            Text(scenario.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(height: 11),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('home-pay-button'),
                onPressed: actionsEnabled ? onPay : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                child: const Text('Pay'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 19),
      const Text('People', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final person in [
            scenario.payeeName,
            'Aarav Shah',
            'Mira Das',
            'Kabir Rao',
          ])
            Column(
              children: [
                _avatar(person, 23),
                const SizedBox(height: 5),
                SizedBox(
                  width: 58,
                  child: Text(
                    person.split(' ').first,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 9),
                  ),
                ),
              ],
            ),
        ],
      ),
    ]);
  }

  Widget _quickAction(IconData icon, String label) => Expanded(
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xFFEFF1F7), borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, color: _accent, size: 19),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: _muted)),
          ],
        ),
      );

  Widget _pay() {
    return _scrollPage([
      _backHeader('Review payment'),
      const SizedBox(height: 24),
      Center(child: _avatar(scenario.payeeName, 32)),
      const SizedBox(height: 10),
      Center(child: Text(scenario.payeeName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink))),
      const SizedBox(height: 4),
      Center(child: Text(scenario.payeeVpa, style: const TextStyle(color: _muted, fontSize: 12))),
      const SizedBox(height: 23),
      Center(child: Text(_amount, style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w800, color: _ink))),
      const SizedBox(height: 10),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(18)),
          child: Text(scenario.note, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: _muted)),
        ),
      ),
      if (scenario.isFirstTimePayee) ...[
        const SizedBox(height: 13),
        const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF777E8B), size: 15),
              SizedBox(width: 5),
              Text('First time paying this person', style: TextStyle(fontSize: 11, color: _muted)),
            ],
          ),
        ),
      ],
      const SizedBox(height: 23),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16)),
        child: const Row(
          children: [
            Icon(Icons.account_balance_rounded, color: _accent),
            SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DemoPay Bank  •• 4821', style: TextStyle(fontWeight: FontWeight.w700, color: _ink, fontSize: 12)),
              Text('UPI account · fictional', style: TextStyle(color: _muted, fontSize: 10)),
            ])),
            Icon(Icons.keyboard_arrow_down_rounded, color: _muted),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey('review-pay-button'),
          onPressed: actionsEnabled ? onPay : null,
          style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
          child: Text('Pay $_amount', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }

  Widget _checking() {
    return _scrollPage([
      const SizedBox(height: 24),
      Center(
        child: const _PulseShield(),
      ),
      const SizedBox(height: 22),
      const Center(child: Text('Scam Guard is checking this payment…', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink))),
      const SizedBox(height: 9),
      const Center(child: Text('POST /v1/scam-guard/check', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: _muted))),
      const SizedBox(height: 24),
    ]);
  }

  Widget _verdict() {
    final decision = apiResponse?['decision'];
    if (decision == 'block') return _blockVerdict();
    if (decision == 'warn') return _warnVerdict();
    if (decision == 'allow') {
      return _scrollPage([
        const SizedBox(height: 24),
        const Center(child: Icon(Icons.verified_rounded, size: 68, color: Color(0xFF2D8B58))),
        const SizedBox(height: 14),
        const Center(child: Text('Looks safe ✓', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink))),
        const Center(child: Text('Taking you to your UPI PIN…', style: TextStyle(fontSize: 12, color: _muted))),
        const SizedBox(height: 24),
      ]);
    }
    return _scrollPage([
      const SizedBox(height: 24),
      const Center(child: Icon(Icons.shield_outlined, size: 58, color: _muted)),
      const SizedBox(height: 12),
      const Center(child: Text('Checking payment…', style: TextStyle(color: _muted))),
      const SizedBox(height: 24),
    ]);
  }

  Widget _blockVerdict() {
    final score = apiResponse?['score'] ?? 0;
    return ColoredBox(
      color: const Color(0xFFFFF7F7),
      child: _scrollPage([
      const SizedBox(height: 24),
      const Center(child: Icon(Icons.warning_amber_rounded, size: 66, color: Color(0xFFBC3945))),
      const SizedBox(height: 12),
      const Center(child: Text('Stop! This looks like a scam', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF9C2735)))),
      const SizedBox(height: 6),
      Center(child: Text('Score $score/100', style: const TextStyle(color: _muted, fontWeight: FontWeight.w600))),
      const SizedBox(height: 8),
      const Text(
        'Signals are warning indicators, not proof. Verify the recipient through a separate trusted channel before deciding.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: _muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      _reasons(),
      const SizedBox(height: 17),
      _filledAction('Cancel payment', onCancel, key: const ValueKey('cancel-payment-button'), color: const Color(0xFFB62F3B)),
      TextButton(
        onPressed: actionsEnabled ? onContinue : null,
        child: const Text('I verified the recipient; continue to pay', style: TextStyle(color: _muted, fontSize: 11)),
      ),
      const SizedBox(height: 24),
      ]),
    );
  }

  Widget _warnVerdict() {
    return _scrollPage([
      const SizedBox(height: 24),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: const Color(0xFFFFF5DF), borderRadius: BorderRadius.circular(21), border: Border.all(color: const Color(0xFFF3D28B))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_rounded, color: Color(0xFFB87913), size: 32),
            const SizedBox(height: 7),
            const Text('Check before you pay', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF75500E))),
            const SizedBox(height: 6),
            const Text(
              'Signals are clues, not proof. Verify the recipient before continuing.',
              style: TextStyle(fontSize: 11, color: _muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            _reasons(),
            const SizedBox(height: 17),
            _filledAction('Cancel', onCancel, key: const ValueKey('cancel-warning-button'), color: const Color(0xFF4657A8)),
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: actionsEnabled ? onContinue : null,
                child: const Text('Continue to pay'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _reasons() {
    final signals = apiResponse?['signals'];
    final reasons = signals is List
        ? signals
            .whereType<Map>()
            .map((signal) => (
                  signal['source'] == 'simulated_payment_context'
                      ? 'PAYMENT CONTEXT'
                      : 'SCAM GUARD RULE',
                  signal['message']?.toString() ?? '',
                ))
            .where((reason) => reason.$2.isNotEmpty)
            .toList()
        : <(String, String)>[];
    if (reasons.isEmpty) {
      return const Text(
        'Take a moment to check the payment details.',
        style: TextStyle(fontSize: 12, color: _muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (source, message) in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 6, color: Color(0xFF9C2735))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(message, style: const TextStyle(fontSize: 11, color: _ink, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pin() {
    final digits = List.generate(6, (index) {
      final filled = index < pinDigitCount;
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: filled ? _accent : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: filled ? _accent : const Color(0xFFCDD1D9), width: 1.5),
        ),
      );
    });
    return _scrollPage([
      _backHeader('Secure payment'),
      if (failOpen) ...[
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('fail-open-banner'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF0F1F3), borderRadius: BorderRadius.circular(12)),
          child: const Text(
            "Couldn't reach Scam Guard — continuing with normal checks",
            style: TextStyle(fontSize: 10, color: Color(0xFF5E6470)),
          ),
        ),
      ],
      const SizedBox(height: 22),
      Center(child: _avatar(scenario.payeeName, 27)),
      const SizedBox(height: 9),
      Center(child: Text('Paying ${scenario.payeeName}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink, fontSize: 15))),
      const SizedBox(height: 3),
      Center(child: Text(scenario.payeeVpa, style: const TextStyle(color: _muted, fontSize: 11))),
      const SizedBox(height: 8),
      Center(child: Text(_amount, style: const TextStyle(color: _ink, fontSize: 25, fontWeight: FontWeight.w800))),
      const SizedBox(height: 14),
      const Center(child: Text('Enter UPI PIN', style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w700))),
      const SizedBox(height: 13),
      Center(child: Row(mainAxisSize: MainAxisSize.min, children: [for (final dot in digits) Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: dot)])),
      const SizedBox(height: 18),
      _numberPad(),
      const SizedBox(height: 24),
      const Center(child: Text('Your PIN stays on this device in a real UPI app.', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: _muted))),
    ]);
  }

  Widget _numberPad() {
    final keys = <int?>[1, 2, 3, 4, 5, 6, 7, 8, 9, null, 0, -1];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 5,
      crossAxisSpacing: 20,
      childAspectRatio: 1.55,
      children: [
        for (final key in keys)
          if (key == null)
            const SizedBox.shrink()
          else
            TextButton(
              key: ValueKey('pin-key-$key'),
              onPressed: actionsEnabled ? () => onPinDigit(key == -1 ? -1 : key) : null,
              style: TextButton.styleFrom(shape: const CircleBorder(), foregroundColor: _ink),
              child: key == -1
                  ? const Icon(Icons.backspace_outlined, size: 18)
                  : Text('$key', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            ),
      ],
    );
  }

  Widget _result() {
    if (cancelled) {
      return _scrollPage([
        const SizedBox(height: 24),
        const Center(child: Icon(Icons.verified_user_rounded, size: 72, color: Color(0xFF2D8B58))),
        const SizedBox(height: 12),
        Center(child: Text('Payment cancelled — $_amount saved', textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink))),
        const SizedBox(height: 8),
        const Center(child: Text('Blocked by Momentum Scam Guard', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF288253), fontSize: 12, fontWeight: FontWeight.w600))),
        const SizedBox(height: 24),
        _filledAction('Back to home', onDone, key: const ValueKey('result-done-button')),
      ]);
    }

    return _scrollPage([
      const SizedBox(height: 24),
      const Center(child: Icon(Icons.check_circle_rounded, size: 72, color: Color(0xFF2D8B58))),
      const SizedBox(height: 14),
      Center(child: Text('$_amount paid to ${scenario.payeeName}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink))),
      const SizedBox(height: 7),
      Center(child: Text(transactionId, style: const TextStyle(color: _muted, fontFamily: 'monospace', fontSize: 11))),
      if (revealScam && scenario.isScam) ...[
        const SizedBox(height: 20),
        Container(
          key: const ValueKey('scam-reveal-banner'),
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: const Color(0xFFFFE9EB), borderRadius: BorderRadius.circular(14)),
          child: Text('This was a scam. $_amount is gone.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFA12635), fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ],
      const SizedBox(height: 24),
      _filledAction('Done', onDone, key: const ValueKey('result-done-button')),
    ]);
  }

  Widget _backHeader(String title) => Row(
        children: [
          IconButton(
            key: const ValueKey('phone-back-button'),
            onPressed: actionsEnabled ? onBack : null,
            icon: const Icon(Icons.arrow_back_rounded),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 38),
          ),
          const SizedBox(width: 5),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
        ],
      );

  Widget _filledAction(
    String label,
    VoidCallback action, {
    Key? key,
    Color color = _accent,
  }) =>
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: key,
          onPressed: actionsEnabled ? action : null,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _avatar(String name, double radius) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE8EAF4),
      child: Text(initials, style: TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: radius * 0.58)),
    );
  }
}

class _PulseShield extends StatefulWidget {
  const _PulseShield();

  @override
  State<_PulseShield> createState() => _PulseShieldState();
}

class _PulseShieldState extends State<_PulseShield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Transform.scale(
          scale: 0.92 + _controller.value * 0.1,
          child: Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6EF),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D8B58).withValues(alpha: 0.05 + _controller.value * 0.12),
                  blurRadius: 14 + _controller.value * 10,
                  spreadRadius: _controller.value * 2,
                ),
              ],
            ),
            child: const Icon(Icons.shield_rounded, size: 42, color: Color(0xFF2D8B58)),
          ),
        ),
      );
}
