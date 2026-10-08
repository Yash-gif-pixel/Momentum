import 'package:flutter_test/flutter_test.dart';
import 'package:credify_frontend/main.dart';
import 'package:credify_frontend/mock_backend.dart';

void main() {
  testWidgets('App boots to the landing, then enters the shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(CredifyApp(service: MockBackend()));
    // The landing runs a looping waveform animation, so settle explicitly
    // rather than with pumpAndSettle (which would never return).
    await tester.pump(const Duration(milliseconds: 1600));

    // Landing shows the wordmark, the tagline and how the signal is built.
    expect(find.text('Credify'), findsOneWidget);
    expect(find.textContaining('credit invisible'), findsWidgets);
    expect(find.textContaining('A gate on data, not on risk'), findsOneWidget);
    // Claims on the landing must stay verifiable — the data source is stated
    // up front rather than implied.
    expect(find.textContaining('SYNTHETIC DATA'), findsOneWidget);

    // The CTA sits below the fold, so scroll it in before tapping.
    final cta = find.text('Open the demo');
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The persistent disclaimer carries the regulatory guard on every screen.
    expect(find.textContaining('not a regulated entity'), findsOneWidget);

    // All four tabs are present.
    expect(find.text('Consent'), findsWidgets);
    expect(find.text('Lender'), findsWidgets);
    expect(find.text('Borrower'), findsWidgets);
    expect(find.text('Portfolio'), findsWidgets);
  });
}
