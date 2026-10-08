import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:credify_frontend/models/analyze_response.dart';
import 'package:credify_frontend/models/portfolio_response.dart';
import 'package:credify_frontend/screens/consent_screen.dart';
import 'package:credify_frontend/services/credify_api_service.dart';
import 'package:credify_frontend/state/app_state.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:credify_frontend/widgets/credify_shell_widgets.dart';

class _FakeService implements CredifyApiService {
  @override
  List<String> getAvailableProfileIds() => const [
        'lakshmi_vendor_001',
        'meera_tailor_005',
        'arjun_kirana_006',
      ];

  @override
  Future<AnalyzeResponse> analyzeProfile(String profileId) async =>
      throw UnimplementedError();

  @override
  Future<PortfolioResponse> getPortfolio() async => throw UnimplementedError();
}

void main() {
  late AppState state;

  Future<void> pumpConsent(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    state = AppState(_FakeService());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: CredifyTheme.dark,
          home: Scaffold(body: ConsentScreen(onContinue: () {})),
        ),
      ),
    );
    await tester.pump();
  }

  /// Two pumps: the first rebuilds with the new target and starts the
  /// implicit animation, the second advances the clock through it.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder cardFor(String name) => find
      .ancestor(of: find.text(name), matching: find.byType(GlassCard))
      .first;

  Color? borderOf(WidgetTester tester, String name) =>
      tester.widget<GlassCard>(cardFor(name)).borderColor;

  // ── No pre-selection ─────────────────────────────────────────────────────

  testWidgets('no borrower is pre-selected on arrival', (tester) async {
    // A pre-lit card reads as "we have already chosen for you". The user has
    // not picked yet, so nothing is highlighted.
    await pumpConsent(tester);

    expect(state.hasPickedProfile, isFalse);
    for (final name in ['Lakshmi', 'Meera', 'Arjun']) {
      expect(borderOf(tester, name), isNull, reason: '$name is pre-lit');
    }
  });

  testWidgets('selectedProfileId still resolves before any pick',
      (tester) async {
    // The id stays non-null so every screen reading it keeps working; only
    // the HIGHLIGHT is withheld. This pins that distinction.
    await pumpConsent(tester);
    expect(state.selectedProfileId, isNotEmpty);
    expect(state.hasPickedProfile, isFalse);
  });

  testWidgets('picking a borrower lights that card and only that card',
      (tester) async {
    await pumpConsent(tester);

    state.selectProfile('meera_tailor_005');
    await settle(tester);

    expect(state.hasPickedProfile, isTrue);
    expect(borderOf(tester, 'Meera'), isNotNull);
    expect(borderOf(tester, 'Lakshmi'), isNull);
    expect(borderOf(tester, 'Arjun'), isNull);
  });

  // ── Hover ────────────────────────────────────────────────────────────────

  Future<TestGesture> hoverOver(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await settle(tester);
    return gesture;
  }

  testWidgets('hovering a persona card lights its border', (tester) async {
    await pumpConsent(tester);
    expect(borderOf(tester, 'Lakshmi'), isNull);

    await hoverOver(tester, find.text('Lakshmi'));
    expect(borderOf(tester, 'Lakshmi'), isNotNull);
  });

  testWidgets('the hover lift raises the card and settles back',
      (tester) async {
    await pumpConsent(tester);
    final restTop = tester.getRect(cardFor('Lakshmi')).top;

    final gesture = await hoverOver(tester, find.text('Lakshmi'));
    expect(tester.getRect(cardFor('Lakshmi')).top, lessThan(restTop));

    await gesture.moveTo(Offset.zero);
    await settle(tester);
    expect(
      tester.getRect(cardFor('Lakshmi')).top,
      moreOrLessEquals(restTop, epsilon: 0.5),
    );
  });

  testWidgets('hover is per-card', (tester) async {
    await pumpConsent(tester);
    await hoverOver(tester, find.text('Lakshmi'));

    expect(borderOf(tester, 'Lakshmi'), isNotNull);
    expect(borderOf(tester, 'Arjun'), isNull);
  });

  testWidgets('a selected card stays lit when the pointer leaves it',
      (tester) async {
    // Selection outranks hover: moving away from the chosen borrower must not
    // dim it back down, or the user loses track of what they picked.
    await pumpConsent(tester);
    state.selectProfile('lakshmi_vendor_001');
    await settle(tester);

    final selectedBorder = borderOf(tester, 'Lakshmi');
    final gesture = await hoverOver(tester, find.text('Arjun'));
    await gesture.moveTo(Offset.zero);
    await settle(tester);

    expect(borderOf(tester, 'Lakshmi'), selectedBorder);
  });

  testWidgets('selection is stronger than hover', (tester) async {
    await pumpConsent(tester);
    await hoverOver(tester, find.text('Lakshmi'));
    final hoverBorder = borderOf(tester, 'Lakshmi')!;

    state.selectProfile('lakshmi_vendor_001');
    await settle(tester);
    final selectedBorder = borderOf(tester, 'Lakshmi')!;

    expect(selectedBorder.a, greaterThan(hoverBorder.a),
        reason: 'a picked card should read stronger than a hovered one');
  });
}
