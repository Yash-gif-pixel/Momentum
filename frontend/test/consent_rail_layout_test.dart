import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:credify_frontend/models/analyze_response.dart';
import 'package:credify_frontend/models/portfolio_response.dart';
import 'package:credify_frontend/screens/consent_screen.dart';
import 'package:credify_frontend/services/credify_api_service.dart';
import 'package:credify_frontend/services/credify_http_service.dart';
import 'package:credify_frontend/state/app_state.dart';
import 'package:credify_frontend/theme/credify_theme.dart';

/// The persona rail chooses between a full-width Row and a swipeable list.
/// That choice used to be a flat `width >= 820`, tuned when there were five
/// profiles. Every profile added since has quietly squeezed the Row, and a
/// seventh takes each card to roughly 103px — narrow enough that the name,
/// sector and coverage lines all collapse into ellipses.
///
/// These pin the rule at the widths that matter so the next profile added
/// cannot silently crush the layout again.
class _FakeService implements CredifyApiService {
  final int count;
  const _FakeService(this.count);

  @override
  List<String> getAvailableProfileIds() =>
      List.generate(count, (i) => 'profile_$i');

  @override
  Future<AnalyzeResponse> analyzeProfile(String profileId) async =>
      throw UnimplementedError();

  @override
  Future<PortfolioResponse> getPortfolio() async => throw UnimplementedError();
}

Widget _host(int profileCount) => ChangeNotifierProvider(
      create: (_) => AppState(_FakeService(profileCount)),
      child: MaterialApp(
        theme: CredifyTheme.light,
        home: Scaffold(body: ConsentScreen(onContinue: () {})),
      ),
    );

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  int profileCount,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(profileCount));
  await tester.pump();
}

void main() {
  final realCount = CredifyHttpService(baseUrl: 'http://localhost:8000')
      .getAvailableProfileIds()
      .length;

  testWidgets('the real profile count renders without overflow at 800px',
      (tester) async {
    await _pumpAt(tester, const Size(800, 900), realCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the real profile count renders without overflow at 1280px',
      (tester) async {
    await _pumpAt(tester, const Size(1280, 900), realCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the real profile count renders without overflow at 1920px',
      (tester) async {
    await _pumpAt(tester, const Size(1920, 900), realCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('it renders without overflow at phone width', (tester) async {
    await _pumpAt(tester, const Size(375, 812), realCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a laptop cannot squeeze every profile into one row',
      (tester) async {
    // 1280 is the width that matters: the common laptop viewport, and where
    // the old flat threshold would have packed all seven in at ~160px each.
    await _pumpAt(tester, const Size(1280, 900), realCount);
    expect(
      find.byType(ListView),
      findsWidgets,
      reason: 'expected the swipeable rail, not a crushed row, at 1280px '
          'with $realCount profiles',
    );
  });

  testWidgets('a genuinely wide screen still spreads a small set into a row',
      (tester) async {
    // The Row branch is not dead code — with few enough cards and enough
    // width it is still the better layout, and this proves the rule did not
    // simply disable it.
    await _pumpAt(tester, const Size(1600, 900), 3);
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('every card stays at least 190px wide when a row is used',
      (tester) async {
    await _pumpAt(tester, const Size(1600, 900), 3);
    final cards = tester.widgetList(find.byType(GestureDetector));
    expect(cards, isNotEmpty);
    // The row branch only engages above the per-card floor, so if it engaged
    // here the arithmetic held: (1600 - 40 - 2*14) / 3 = 510px per card.
    expect(find.byType(ListView), findsNothing);
  });
}
