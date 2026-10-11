import 'package:credify_frontend/features/scam_guard_partner/scam_guard_simulation_screen.dart';
import 'package:credify_frontend/features/scam_guard_partner/simulated_scam_guard_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    Duration checkingDuration = Duration.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScamGuardSimulationScreen(
          api: SimulatedScamGuardApi(simulatedLatency: Duration.zero),
          checkingDisplayDuration: checkingDuration,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openPayment(WidgetTester tester) async {
    await tapVisible(tester, find.byKey(const ValueKey('home-pay-button')));
    final reviewButton = find.byKey(const ValueKey('review-pay-button'));
    await tester.ensureVisible(reviewButton);
    await tester.pumpAndSettle();
    await tester.tap(reviewButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester) async {
    for (var digit = 1; digit <= 6; digit++) {
      await tapVisible(tester, find.byKey(ValueKey('pin-key-$digit')));
    }
  }

  testWidgets('guard blocks KYC scam and cancellation updates impact', (tester) async {
    await pumpScreen(tester);
    await openPayment(tester);
    expect(find.text('Stop! This looks like a scam'), findsOneWidget);

    await tapVisible(tester, find.byKey(const ValueKey('cancel-payment-button')));
    expect(find.textContaining('₹9,999 saved'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('impact-value-1'))).data, '1');
  });

  testWidgets('without guard proceeds to PIN and reveals the scam after payment', (tester) async {
    await pumpScreen(tester);
    await tapVisible(tester, find.text('Without Scam Guard'));
    await openPayment(tester);
    expect(find.text('Enter UPI PIN'), findsOneWidget);
    await enterPin(tester);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    expect(find.textContaining('This was a scam.'), findsOneWidget);
  });

  testWidgets('normal payment gets an allow verdict and proceeds to PIN', (tester) async {
    await pumpScreen(tester);
    final normalScenario = find.byKey(const ValueKey('scenario-normal'));
    await tapVisible(tester, normalScenario);
    await openPayment(tester);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Enter UPI PIN'), findsOneWidget);
    await enterPin(tester);
    expect(find.textContaining('paid to Ravi Kumar'), findsOneWidget);
  });

  testWidgets('wrong key shows API 401 and phone fail-open message', (tester) async {
    await pumpScreen(tester);
    final normalScenario = find.byKey(const ValueKey('scenario-normal'));
    await tapVisible(tester, normalScenario);
    final wrongKeySwitch = find.byKey(const ValueKey('wrong-api-key-switch'));
    await tester.ensureVisible(wrongKeySwitch);
    await tester.pumpAndSettle();
    await tester.tap(wrongKeySwitch);
    await tester.pumpAndSettle();

    await openPayment(tester);
    expect(find.textContaining("Couldn't reach Scam Guard"), findsOneWidget);
    expect(find.text('401'), findsOneWidget);
  });

  for (final size in const [
    Size(375, 812),
    Size(768, 1024),
    Size(1440, 900),
  ]) {
    testWidgets('responsive layout has no exceptions at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpScreen(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }
}
