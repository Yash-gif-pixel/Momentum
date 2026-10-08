import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:credify_frontend/widgets/credify_shell_widgets.dart';

/// The slide is the only way from Consent into the rest of the app, so its
/// gesture handling is covered directly rather than only through the UI.
void main() {
  Future<void> pumpSlider(
    WidgetTester tester, {
    required VoidCallback onAuthorized,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CredifyTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SlideToAuthorize(
                label: 'Slide to authorise',
                doneLabel: 'Consent granted',
                onAuthorized: onAuthorized,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a full drag authorises and swaps to the done state',
      (tester) async {
    var authorised = 0;
    await pumpSlider(tester, onAuthorized: () => authorised++);

    expect(find.text('Slide to authorise'), findsOneWidget);

    // Track is 400 wide; drag well past the three-quarter threshold.
    await tester.drag(
      find.byIcon(Icons.arrow_forward_rounded),
      const Offset(340, 0),
    );
    await tester.pumpAndSettle();

    expect(authorised, 1);
    expect(find.text('Consent granted'), findsOneWidget);
    expect(find.text('Slide to authorise'), findsNothing);
  });

  testWidgets('a short drag springs back without authorising', (tester) async {
    var authorised = 0;
    await pumpSlider(tester, onAuthorized: () => authorised++);

    // Well under the 75% threshold.
    await tester.drag(
      find.byIcon(Icons.arrow_forward_rounded),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    expect(authorised, 0);
    expect(find.text('Slide to authorise'), findsOneWidget);
  });

  testWidgets('authorises exactly once even if dragged again', (tester) async {
    var authorised = 0;
    await pumpSlider(tester, onAuthorized: () => authorised++);

    await tester.drag(
      find.byIcon(Icons.arrow_forward_rounded),
      const Offset(340, 0),
    );
    await tester.pumpAndSettle();
    expect(authorised, 1);

    // The thumb is gone in the done state, so there is nothing left to drag.
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(authorised, 1);
  });

  // The thumb used to be exactly as tall as the track, which does not fit
  // inside the track's 1px border -- it overhung the rounded edge at rest and
  // pushed past the right end at full travel, because the drag limit was
  // measured against the outer width. These assert the geometry rather than
  // the behaviour, since the bug was purely visual and the drag still worked.
  Rect thumbRect(WidgetTester tester) =>
      tester.getRect(find.byIcon(Icons.arrow_forward_rounded).hitTestable());

  Rect trackRect(WidgetTester tester) =>
      tester.getRect(find.byType(SlideToAuthorize));

  testWidgets('the thumb sits inside the track at rest', (tester) async {
    await pumpSlider(tester, onAuthorized: () {});
    await tester.pumpAndSettle();

    final thumb = thumbRect(tester);
    final track = trackRect(tester);

    // Strictly inside, not merely non-overlapping. The original bug sized the
    // thumb to the track's OUTER box, which satisfies >= / <= exactly while
    // still covering the border and breaching the rounded corner visually.
    expect(thumb.left, greaterThan(track.left));
    expect(thumb.right, lessThan(track.right));
    expect(thumb.top, greaterThan(track.top));
    expect(thumb.bottom, lessThan(track.bottom));
  });

  testWidgets('the thumb is vertically centred in the track', (tester) async {
    await pumpSlider(tester, onAuthorized: () {});
    await tester.pumpAndSettle();

    expect(
      thumbRect(tester).center.dy,
      moreOrLessEquals(trackRect(tester).center.dy, epsilon: 0.5),
    );
  });

  testWidgets('the thumb stays inside the track at full travel',
      (tester) async {
    await pumpSlider(tester, onAuthorized: () {});

    // Drag hard, but stop short of the authorise threshold so the thumb is
    // still on screen to measure. 250 of ~346 is under 75%.
    await tester.drag(
      find.byIcon(Icons.arrow_forward_rounded),
      const Offset(250, 0),
    );
    await tester.pump();

    final thumb = thumbRect(tester);
    final track = trackRect(tester);
    expect(thumb.right, lessThan(track.right));
    expect(thumb.top, greaterThan(track.top));
    expect(thumb.bottom, lessThan(track.bottom));
  });

  testWidgets('the left and right insets match at the end of travel',
      (tester) async {
    await pumpSlider(tester, onAuthorized: () {});
    await tester.pumpAndSettle();

    final restLeftGap = thumbRect(tester).left - trackRect(tester).left;
    expect(restLeftGap, greaterThan(0), reason: 'thumb should be inset');

    // Held mid-gesture rather than via tester.drag: a completed drag this
    // long authorises, and the done state removes the thumb before it can be
    // measured. _done only flips on drag END, so the thumb is still present
    // and clamped to maxDrag here.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.arrow_forward_rounded)),
    );
    await gesture.moveBy(const Offset(1000, 0));
    await tester.pump();

    final endRightGap = trackRect(tester).right - thumbRect(tester).right;
    expect(endRightGap, moreOrLessEquals(restLeftGap, epsilon: 0.5));

    await gesture.cancel();
  });
}
