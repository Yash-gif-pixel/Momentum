import 'package:credify_frontend/features/climate/climate_api_service.dart';
import 'package:credify_frontend/features/climate/climate_models.dart';
import 'package:credify_frontend/features/climate/climate_scenario_comparison.dart';
import 'package:credify_frontend/features/climate/mock_climate_service.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ComparisonService implements ClimateApiService {
  final MockClimateService _mock = MockClimateService();
  final List<(String, String)> requests = [];
  final Set<String> failOnce = {};

  @override
  Future<ClimateOptions> fetchOptions() => _mock.fetchOptions();

  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) async {
    requests.add((profileId, scenarioId));
    if (failOnce.remove(scenarioId)) {
      throw const ClimateApiException(
        statusCode: 503,
        message: 'Scenario unavailable',
      );
    }
    return _mock.fetchImpact(profileId, scenarioId);
  }

  @override
  Future<ClimatePortfolio> fetchPortfolio(String scenarioId) =>
      _mock.fetchPortfolio(scenarioId);
}

final _scenarios = [
  ClimateScenario(
    scenarioId: 'normal_monsoon',
    label: 'Typical monsoon',
    description: 'Seasonal rainfall',
    lat: 19.076,
    lon: 72.8777,
    periodStart: DateTime(2025, 7, 1),
    periodEnd: DateTime(2025, 7, 30),
  ),
  ClimateScenario(
    scenarioId: 'heavy_rain_week',
    label: 'Heavy rain week',
    description: 'A week of intense rainfall',
    lat: 19.096,
    lon: 72.8977,
    periodStart: DateTime(2025, 7, 1),
    periodEnd: DateTime(2025, 7, 30),
  ),
  ClimateScenario(
    scenarioId: 'flash_flood',
    label: 'Flash flood',
    description: 'Severe rainfall',
    lat: 19.116,
    lon: 72.9177,
    periodStart: DateTime(2025, 7, 1),
    periodEnd: DateTime(2025, 7, 30),
  ),
];

Widget _app(
  ClimateApiService service, {
  String profileId = 'lakshmi_vendor_001',
  String selectedScenarioId = 'heavy_rain_week',
  ValueChanged<String>? onSelect,
  Key? comparisonKey,
}) => MaterialApp(
  theme: CredifyTheme.dark,
  home: Scaffold(
    body: SingleChildScrollView(
      child: ClimateScenarioComparison(
        key: comparisonKey,
        service: service,
        profileId: profileId,
        scenarios: _scenarios,
        selectedScenarioId: selectedScenarioId,
        onSelect: onSelect ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows impacts and disruption days for all scenarios', (
    tester,
  ) async {
    await tester.pumpWidget(_app(MockClimateService()));
    await tester.pumpAndSettle();

    expect(find.text('3 disrupted days'), findsOneWidget);
    expect(find.text('8 disrupted days'), findsOneWidget);
    expect(find.text('13 disrupted days'), findsOneWidget);
    expect(find.text('₹3,780'), findsOneWidget);
    expect(find.text('₹10,080'), findsOneWidget);
    expect(find.text('₹16,380'), findsWidgets);
    expect(
      find.text(
        'Cash-flow estimates only — none of these change the credit score.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('takeaway compares the worst case to the mildest', (
    tester,
  ) async {
    await tester.pumpWidget(_app(MockClimateService()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Worst case: Flash flood — about ₹16,380 at risk'),
      findsOneWidget,
    );
    expect(find.textContaining('4.3× the mildest scenario.'), findsOneWidget);
  });

  testWidgets('tapping a scenario calls onSelect with its id', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _app(
        MockClimateService(),
        onSelect: (scenarioId) => selected = scenarioId,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InkWell).last);
    expect(selected, 'flash_flood');
  });

  testWidgets('partial failure shows Unavailable and retry fetches only it', (
    tester,
  ) async {
    final service = _ComparisonService()..failOnce.add('flash_flood');
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('₹3,780'), findsOneWidget);
    expect(find.text('₹10,080'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(service.requests, hasLength(3));

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(service.requests, hasLength(4));
    expect(service.requests.last, ('lakshmi_vendor_001', 'flash_flood'));
    expect(find.text('Unavailable'), findsNothing);
    expect(find.text('₹16,380'), findsWidgets);
  });

  testWidgets('changing profile fetches all scenarios for the new borrower', (
    tester,
  ) async {
    final service = _ComparisonService();
    const key = ValueKey('scenario-comparison');
    await tester.pumpWidget(_app(service, comparisonKey: key));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(service, profileId: 'meera_tailor_005', comparisonKey: key),
    );
    await tester.pumpAndSettle();

    expect(service.requests, hasLength(6));
    expect(
      service.requests.skip(3).map((request) => request.$1),
      everyElement('meera_tailor_005'),
    );
  });

  testWidgets('all failures show an error and one retry action', (
    tester,
  ) async {
    final service = _ComparisonService()
      ..failOnce.addAll(_scenarios.map((scenario) => scenario.scenarioId));
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.text('Could not compare climate scenarios.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });
}
