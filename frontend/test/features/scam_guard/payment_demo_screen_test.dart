import 'package:credify_frontend/features/scam_guard/demo_scam_checker.dart';
import 'package:credify_frontend/features/scam_guard/payment_demo_screen.dart';
import 'package:credify_frontend/features/scam_guard/scam_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
