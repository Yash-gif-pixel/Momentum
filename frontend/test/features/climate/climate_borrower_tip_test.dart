import 'package:credify_frontend/features/climate/climate_api_service.dart';
import 'package:credify_frontend/features/climate/climate_borrower_tip.dart';
import 'package:credify_frontend/features/climate/climate_models.dart';
import 'package:credify_frontend/features/climate/mock_climate_service.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingService implements ClimateApiService {
  final MockClimateService _mock = MockClimateService();
  final List<(String, String)> impactRequests = [];
  int optionsRequests = 0;
  bool zeroImpact = false;
  bool affectsCreditScore = false;
  bool failNextImpact = false;

  @override
  Future<ClimateOptions> fetchOptions() {
    optionsRequests++;
    return _mock.fetchOptions();
  }

  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) async {
    impactRequests.add((profileId, scenarioId));
    if (failNextImpact) {
      failNextImpact = false;
      throw const ClimateApiException(
        statusCode: 503,
        message: 'Climate data unavailable',
      );
    }
    final impact = await _mock.fetchImpact(profileId, scenarioId);
    return ClimateImpact(
      profileId: impact.profileId,
      scenarioId: impact.scenarioId,
      lat: impact.lat,
      lon: impact.lon,
      periodStart: impact.periodStart,
      periodEnd: impact.periodEnd,
      daily: impact.daily,
      disruptedDays: zeroImpact ? 0 : impact.disruptedDays,
      baselineDailyInflowInr: impact.baselineDailyInflowInr,
      estimatedCashflowImpactInr: zeroImpact
          ? 0
          : impact.estimatedCashflowImpactInr,
      impactPctOfMonthlyInflow: zeroImpact
          ? 0
          : impact.impactPctOfMonthlyInflow,
      suggestedResilienceBufferInr: zeroImpact
          ? 0
          : impact.suggestedResilienceBufferInr,
      assumptions: impact.assumptions,
      affectsCreditScore: affectsCreditScore,
    );
  }

  @override
  Future<ClimatePortfolio> fetchPortfolio(String scenarioId) =>
      _mock.fetchPortfolio(scenarioId);
}

Widget _app(
  ClimateApiService service, {
  String profileId = 'lakshmi_vendor_001',
  String scenarioId = 'heavy_rain_week',
  bool initialHindi = false,
  Key? tipKey,
}) => MaterialApp(
  theme: CredifyTheme.dark,
  home: Scaffold(
    body: SingleChildScrollView(
      child: ClimateBorrowerTip(
        key: tipKey,
        service: service,
        profileId: profileId,
        scenarioId: scenarioId,
        initialHindi: initialHindi,
      ),
    ),
  ),
);

void main() {
  testWidgets('English default shows rounded borrower advice', (tester) async {
    final service = _RecordingService();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.text('Rain can slow your business'), findsOneWidget);
    expect(find.textContaining('about 8 days'), findsOneWidget);
    expect(find.textContaining('about ₹10,100'), findsOneWidget);
    expect(find.textContaining('₹7,600 aside'), findsOneWidget);
    expect(
      find.text('This is an estimate. It does not change your credit score.'),
      findsOneWidget,
    );
    expect(service.optionsRequests, 1);
  });

  testWidgets('language toggle switches Hindi and English copy', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_RecordingService()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('हिंदी'));
    await tester.pumpAndSettle();
    expect(find.text('बारिश से आपका कारोबार धीमा हो सकता है'), findsOneWidget);
    expect(find.textContaining('₹10,100'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Rain can slow your business'), findsOneWidget);
  });

  testWidgets('initialHindi starts with Hindi copy', (tester) async {
    await tester.pumpWidget(_app(_RecordingService(), initialHindi: true));
    await tester.pumpAndSettle();

    expect(find.text('बारिश से आपका कारोबार धीमा हो सकता है'), findsOneWidget);
    expect(find.textContaining('लगभग ₹10,100'), findsOneWidget);
  });

  testWidgets('zero impact shows good news without a buffer line', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_RecordingService()..zeroImpact = true));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Good news: this kind of rain is not expected to affect your work.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('aside before the rainy season'), findsNothing);
  });

  testWidgets('service failure shows retry and retry fetches impact again', (
    tester,
  ) async {
    final service = _RecordingService()..failNextImpact = true;
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't load rain information right now."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(service.impactRequests, hasLength(1));

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(service.impactRequests, hasLength(2));
    expect(find.text('Rain can slow your business'), findsOneWidget);
  });

  testWidgets('changing profile fetches impact for the new borrower', (
    tester,
  ) async {
    final service = _RecordingService();
    const key = ValueKey('borrower-tip');
    await tester.pumpWidget(_app(service, tipKey: key));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(service, profileId: 'meera_tailor_005', tipKey: key),
    );
    await tester.pumpAndSettle();

    expect(service.impactRequests, hasLength(2));
    expect(service.impactRequests.last, (
      'meera_tailor_005',
      'heavy_rain_week',
    ));
    expect(service.optionsRequests, 1);
  });

  testWidgets('scenario change fetches new impact and keeps cached options', (
    tester,
  ) async {
    final service = _RecordingService();
    const key = ValueKey('borrower-tip');
    await tester.pumpWidget(_app(service, tipKey: key));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(service, scenarioId: 'flash_flood', tipKey: key),
    );
    await tester.pumpAndSettle();

    expect(service.impactRequests, hasLength(2));
    expect(service.impactRequests.last, ('lakshmi_vendor_001', 'flash_flood'));
    expect(service.optionsRequests, 1);
    expect(find.textContaining('Flash flood'), findsOneWidget);
  });

  testWidgets('credit score effect replaces the footer with a warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_RecordingService()..affectsCreditScore = true),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Warning: response indicates a credit score effect'),
      findsOneWidget,
    );
    expect(
      find.text('This is an estimate. It does not change your credit score.'),
      findsNothing,
    );
  });
}
