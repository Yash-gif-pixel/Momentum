import 'package:credify_frontend/features/scam_guard/demo_scam_checker.dart';
import 'package:credify_frontend/features/scam_guard/payment_demo_screen.dart';
import 'package:credify_frontend/features/scam_guard/scam_guard_adapter.dart';
import 'package:credify_frontend/features/scam_guard/scam_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scam_guard/scam_guard.dart';

Widget _app({ScamChecker? checker}) => MaterialApp(
      home: PaymentDemoScreen(checker: checker ?? demoScamChecker),
    );

Future<void> _tapProceed(WidgetTester tester) async {
  final button = find.text('Proceed to pay');
  await tester.drag(find.byType(ListView).first, const Offset(0, -240));
  await tester.pumpAndSettle();
  await tester.tap(button);
}

void main() {
  group('scamWarningFromResult', () {
    test('maps low, medium, and high risk levels', () {
      ScamWarning warningFor(ScamRiskLevel level) => scamWarningFromResult(
            ScamCheckResult(
              level: level,
              score: 0,
              signals: const [],
              elapsed: Duration.zero,
            ),
          );

      expect(warningFor(ScamRiskLevel.low).level, WarningLevel.none);
      expect(warningFor(ScamRiskLevel.medium).level, WarningLevel.caution);
      expect(warningFor(ScamRiskLevel.high).level, WarningLevel.danger);
    });

    test('preserves signal message order and converts elapsed microseconds', () {
      final warning = scamWarningFromResult(
        const ScamCheckResult(
          level: ScamRiskLevel.medium,
          score: 30,
          signals: [
            ScamSignal(code: 'FIRST', message: 'First reason', weight: 15),
            ScamSignal(code: 'SECOND', message: 'Second reason', weight: 15),
          ],
          elapsed: Duration(microseconds: 2500),
        ),
      );

      expect(warning.reasons, ['First reason', 'Second reason']);
      expect(warning.elapsedMs, 2.5);
    });
  });

  test('the three payment presets produce the expected SDK warning levels', () {
    const localShop = (
      vpa: 'corner.shop@example',
      name: 'Corner Shop',
      amount: 240.0,
      note: 'Groceries',
    );
    const kycScam = (
      vpa: 'demo.kyc@example',
      name: 'Demo KYC Desk',
      amount: 1.0,
      note: 'Urgent KYC update',
    );
    const refundScam = (
      vpa: 'demo.refund@example',
      name: 'Demo Refund Desk',
      amount: 99.0,
      note: 'You have won a cashback refund, pay abhi to claim',
    );

    ScamWarning checkPreset({
      required String vpa,
      required String name,
      required double amount,
      required String note,
    }) =>
        scamGuardChecker(
          payeeVpa: vpa,
          amountInr: amount,
          payeeName: name,
          note: note,
        );

    expect(
      checkPreset(
        vpa: localShop.vpa,
        name: localShop.name,
        amount: localShop.amount,
        note: localShop.note,
      ).level,
      WarningLevel.none,
    );
    expect(
      checkPreset(
        vpa: kycScam.vpa,
        name: kycScam.name,
        amount: kycScam.amount,
        note: kycScam.note,
      ).level,
      WarningLevel.caution,
    );
    expect(
      checkPreset(
        vpa: refundScam.vpa,
        name: refundScam.name,
        amount: refundScam.amount,
        note: refundScam.note,
      ).level,
      WarningLevel.caution,
    );
  });

  testWidgets('Local shop proceeds to PIN without a warning sheet', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Local shop'));
    await _tapProceed(tester);
    await tester.pumpAndSettle();
    expect(find.text('Enter your UPI PIN'), findsOneWidget);
    expect(find.text('Be careful'), findsNothing);
  });

  testWidgets('KYC scam shows reasons and check duration', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('KYC scam'));
    await _tapProceed(tester);
    await tester.pumpAndSettle();
    expect(find.text('This looks like a scam'), findsOneWidget);
    expect(find.textContaining('often used').evaluate().isNotEmpty ||
        find.textContaining('high-risk').evaluate().isNotEmpty, isTrue);
    expect(find.textContaining('ms'), findsOneWidget);
  });

  testWidgets('Pay anyway continues to PIN', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('KYC scam'));
    await _tapProceed(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your UPI PIN'), findsOneWidget);
  });

  testWidgets('Cancel payment returns to form and keeps values', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('KYC scam'));
    await _tapProceed(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel payment'));
    await tester.pumpAndSettle();
    expect(find.text('Proceed to pay'), findsOneWidget);
    expect(find.text('demo.kyc@example'), findsOneWidget);
  });

  testWidgets('zero amount validation does not call checker', (tester) async {
    var calls = 0;
    ScamWarning checker({
      required String payeeVpa,
      required double amountInr,
      String? payeeName,
      String? note,
    }) {
      calls++;
      return const ScamWarning(level: WarningLevel.none, reasons: [], elapsedMs: 1);
    }

    await tester.pumpWidget(_app(checker: checker));
    await tester.tap(find.text('Local shop'));
    await tester.enterText(find.byKey(const Key('amount')), '0');
    await _tapProceed(tester);
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount above ₹0'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('entering four PIN digits shows success', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Local shop'));
    await _tapProceed(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin')), '1234');
    await tester.pumpAndSettle();
    expect(find.text('Demo payment complete'), findsOneWidget);
    expect(find.text('New payment'), findsOneWidget);
  });
}
