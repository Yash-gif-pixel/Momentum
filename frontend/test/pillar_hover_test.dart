import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credify_frontend/screens/landing_screen.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:credify_frontend/widgets/credify_shell_widgets.dart';

/// The pillar cards light up on hover. Driven here rather than eyeballed:
/// hover state is invisible to a screenshot taken without a pointer, and the
/// preview pane cannot reliably hold a cursor over a canvas-rendered card.
void main() {
  /// The landing runs looping ambient animations, so pumpAndSettle never
  /// returns here. Pump past the 200ms hover transition explicitly instead.
  ///
  /// TWO pumps, not one. The first rebuilds with the new target and starts
  /// the implicit animation; only the second advances the clock through it.
  /// With a single pump the AnimatedSlide's own widget already reports the
  /// new offset while the FractionalTranslation under it is still at zero --
  /// which made an earlier version of the lift assertion fail against
  /// perfectly working code.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpLanding(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: CredifyTheme.dark,
        home: LandingScreen(
          onEnter: () {},
          isDark: true,
          onToggleTheme: () {},
        ),
      ),
    );
    await settle(tester);
  }

  /// The GlassCard belonging to the first pillar.
  Finder firstPillarCard() => find
      .ancestor(
        of: find.text('Ten predictive features'),
        matching: find.byType(GlassCard),
      )
      .first;

  Color? borderColourOf(WidgetTester tester) =>
      tester.widget<GlassCard>(firstPillarCard()).borderColor;

  Future<TestGesture> hoverOver(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await settle(tester);
    return gesture;
  }

  testWidgets('a pillar card is unlit until hovered', (tester) async {
    await pumpLanding(tester, size: const Size(1400, 2600));
    await tester.ensureVisible(find.text('Ten predictive features'));
    await settle(tester);

    expect(borderColourOf(tester), isNull);
  });

  testWidgets('hovering a pillar lights its border', (tester) async {
    await pumpLanding(tester, size: const Size(1400, 2600));
    await tester.ensureVisible(find.text('Ten predictive features'));
    await settle(tester);

    await hoverOver(tester, find.text('Ten predictive features'));

    expect(borderColourOf(tester), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving the pointer away puts it back', (tester) async {
    await pumpLanding(tester, size: const Size(1400, 2600));
    await tester.ensureVisible(find.text('Ten predictive features'));
    await settle(tester);

    final gesture = await hoverOver(
      tester,
      find.text('Ten predictive features'),
    );
    expect(borderColourOf(tester), isNotNull);

    await gesture.moveTo(Offset.zero);
    await settle(tester);
    expect(borderColourOf(tester), isNull);
  });

  testWidgets('hover is per-card, not shared across the row', (tester) async {
    // Each card owns its state. If it were lifted to _Pillars, hovering one
    // would light all three.
    await pumpLanding(tester, size: const Size(1400, 2600));
    await tester.ensureVisible(find.text('Ten predictive features'));
    await settle(tester);

    await hoverOver(tester, find.text('Ten predictive features'));

    final others = find
        .ancestor(
          of: find.text('A gate on data, not on risk'),
          matching: find.byType(GlassCard),
        )
        .first;
    expect(tester.widget<GlassCard>(others).borderColor, isNull);
  });

  testWidgets('the card lifts on hover and settles back', (tester) async {
    await pumpLanding(tester, size: const Size(1400, 2600));
    final title = find.text('Ten predictive features');
    await tester.ensureVisible(title);
    await settle(tester);

    final restTop = tester.getRect(firstPillarCard()).top;

    final gesture = await hoverOver(tester, title);
    final hoveredTop = tester.getRect(firstPillarCard()).top;
    expect(
      hoveredTop,
      lessThan(restTop),
      reason: 'the card should rise, not sink or stay put',
    );

    await gesture.moveTo(Offset.zero);
    await settle(tester);
    expect(
      tester.getRect(firstPillarCard()).top,
      moreOrLessEquals(restTop, epsilon: 0.5),
    );
  });

  testWidgets('the lift is suppressed when the OS asks for reduced motion',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CredifyTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LandingScreen(
            onEnter: () {},
            isDark: true,
            onToggleTheme: () {},
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.ensureVisible(find.text('Ten predictive features'));
    await settle(tester);

    final restTop = tester.getRect(firstPillarCard()).top;
    await hoverOver(tester, find.text('Ten predictive features'));

    // The colour still responds; only the movement is withheld.
    expect(borderColourOf(tester), isNotNull);
    expect(
      tester.getRect(firstPillarCard()).top,
      moreOrLessEquals(restTop, epsilon: 0.5),
    );
  });

  testWidgets('hover works on the narrow stacked layout too', (tester) async {
    await pumpLanding(tester, size: const Size(600, 3200));
    await tester.ensureVisible(find.text('Ten predictive features'));
    await settle(tester);

    await hoverOver(tester, find.text('Ten predictive features'));
    expect(borderColourOf(tester), isNotNull);
    expect(tester.takeException(), isNull);
  });
}
