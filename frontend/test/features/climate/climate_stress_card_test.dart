import 'package:credify_frontend/features/climate/climate_api_service.dart';
import 'package:credify_frontend/features/climate/climate_models.dart';
import 'package:credify_frontend/features/climate/climate_rain_chart.dart';
import 'package:credify_frontend/features/climate/climate_stress_card.dart';
import 'package:credify_frontend/features/climate/mock_climate_service.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingService implements ClimateApiService {
  final MockClimateService _mock = MockClimateService();
  final List<(String, String)> requests = [];
  bool fail = false;
  bool zeroImpact = false;

  @override
  Future<ClimateOptions> fetchOptions() => _mock.fetchOptions();

  @override
  Future<ClimatePortfolio> fetchPortfolio(String scenarioId) =>
      _mock.fetchPortfolio(scenarioId);

  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) async {
    requests.add((profileId, scenarioId));
    if (fail) {
      throw const ClimateApiException(
        statusCode: 404,
        message: 'No climate data found for this borrower.',
      );
    }
    final impact = await _mock.fetchImpact(profileId, scenarioId);
    if (!zeroImpact) return impact;
    return ClimateImpact(
      profileId: impact.profileId,
      scenarioId: impact.scenarioId,
      lat: impact.lat,
      lon: impact.lon,
      periodStart: impact.periodStart,
      periodEnd: impact.periodEnd,
      daily: impact.daily,
      disruptedDays: impact.disruptedDays,
      baselineDailyInflowInr: impact.baselineDailyInflowInr,
      estimatedCashflowImpactInr: 0,
      impactPctOfMonthlyInflow: 0,
      suggestedResilienceBufferInr: 0,
      assumptions: impact.assumptions,
      affectsCreditScore: false,
    );
  }
}

Widget _app(
  ClimateApiService service, {
  String profileId = 'lakshmi_vendor_001',
  Key? cardKey,
}) => MaterialApp(
  theme: CredifyTheme.dark,
  home: Scaffold(
    body: ClimateStressCard(
      key: cardKey,
      service: service,
      profileId: profileId,
    ),
  ),
);

void main() {
  testWidgets(
    'mock card shows cash-flow headline, heavy-rain days, buffer, and score badge',
    (tester) async {
      await tester.pumpWidget(_app(MockClimateService()));
      await tester.pumpAndSettle();

      expect(find.text('≈ ₹10,080 possible shortfall'), findsOneWidget);
      expect(find.textContaining('8 heavy-rain days'), findsOneWidget);
      expect(
        find.textContaining('Suggested: keep a ₹7,560 buffer'),
        findsOneWidget,
      );
      expect(find.text('Does not change the credit score'), findsOneWidget);
    },
  );

  testWidgets('zero-impact scenario shows no disruption and no action', (
    tester,
  ) async {
    final service = _RecordingService()..zeroImpact = true;
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.text('No expected disruption'), findsOneWidget);
    expect(find.text('No action needed for this scenario.'), findsOneWidget);
  });

  testWidgets('changing scenario fetches again and updates the headline', (
    tester,
  ) async {
    final service = _RecordingService();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(find.text('≈ ₹10,080 possible shortfall'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flash flood').last);
    await tester.pumpAndSettle();

    expect(service.requests, hasLength(2));
    expect(service.requests.last.$2, 'flash_flood');
    expect(find.text('≈ ₹16,380 possible shortfall'), findsOneWidget);
  });

  testWidgets('changing profile re-fetches the impact for the new borrower', (
    tester,
  ) async {
    final service = _RecordingService();
    await tester.pumpWidget(
      _app(service, cardKey: const ValueKey('stress-card')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(
        service,
        profileId: 'meera_tailor_005',
        cardKey: const ValueKey('stress-card'),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.requests, hasLength(2));
    expect(service.requests.last.$1, 'meera_tailor_005');
  });

  testWidgets(
    'service error shows the API detail and Retry calls the service again',
    (tester) async {
      final service = _RecordingService()..fail = true;
      await tester.pumpWidget(_app(service));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No climate data found for this borrower.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(service.requests, hasLength(1));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(service.requests, hasLength(2));
    },
  );

  testWidgets('Details expands to the rainfall chart and assumptions', (
    tester,
  ) async {
    await tester.pumpWidget(_app(MockClimateService()));
    await tester.pumpAndSettle();
    expect(find.byType(ClimateRainChart), findsNothing);
    expect(
      find.textContaining(
        'Daily inflow is estimated from the selected borrower profile.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(ClimateRainChart), findsOneWidget);
    expect(
      find.textContaining(
        'Daily inflow is estimated from the selected borrower profile.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Compare scenarios is available and starts collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(_app(MockClimateService()));
    await tester.pumpAndSettle();

    expect(find.text('Compare scenarios'), findsOneWidget);
    expect(find.text('Comparing scenarios…'), findsNothing);
  });

  testWidgets('comparison selection updates the card scenario and impact', (
    tester,
  ) async {
    await tester.pumpWidget(_app(MockClimateService()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compare scenarios'));
    await tester.pumpAndSettle();
    expect(find.text('13 disrupted days'), findsOneWidget);

    await tester.ensureVisible(find.byType(InkWell).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InkWell).last);
    await tester.pumpAndSettle();

    expect(find.text('≈ ₹16,380 possible shortfall'), findsOneWidget);
  });
}
