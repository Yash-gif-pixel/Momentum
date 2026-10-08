import 'package:credify_frontend/features/climate/climate_api_service.dart';
import 'package:credify_frontend/features/climate/climate_models.dart';
import 'package:credify_frontend/features/climate/climate_screen.dart';
import 'package:credify_frontend/features/climate/mock_climate_service.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sampleImpact({bool affects = false}) => {
  'profile_id': 'lakshmi_vendor_001', 'scenario_id': 'normal_monsoon',
  'grid_cell': {'lat': 19, 'lon': 72.5}, 'period_start': '2025-07-01', 'period_end': '2025-07-30',
  'daily': [{'date': '2025-07-01', 'rain_mm': 8, 'disrupted': true}, {'date': '2025-07-02', 'rain_mm': 0.5, 'disrupted': false}],
  'disrupted_days': 1, 'baseline_daily_inflow_inr': 1800, 'estimated_cashflow_impact_inr': 1260,
  'impact_pct_of_monthly_inflow': 2.33, 'suggested_resilience_buffer_inr': 945,
  'assumptions': ['Synthetic daily inflow estimate'], 'affects_credit_score': affects,
};

class _FailingService implements ClimateApiService {
  int attempts = 0;
  @override
  Future<ClimateOptions> fetchOptions() async => MockClimateService().fetchOptions();
  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) async { attempts++; throw const ClimateApiException(statusCode: 503, message: 'Climate backend unavailable'); }
}

class _WarningService implements ClimateApiService {
  @override
  Future<ClimateOptions> fetchOptions() async => MockClimateService().fetchOptions();
  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) async => ClimateImpact.fromJson(_sampleImpact(affects: true));
}

void main() {
  test('fromJson parses complete impact with integer-valued numbers', () {
    final model = ClimateImpact.fromJson(_sampleImpact());
    expect(model.lat, 19.0); expect(model.daily.first.rainMm, 8.0); expect(model.baselineDailyInflowInr, 1800.0);
    expect(model.suggestedResilienceBufferInr, 945.0); expect(model.daily, hasLength(2));
  });

  testWidgets('mock flow selects profile and scenario and shows cash flow result', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: CredifyTheme.dark, home: ClimateScreen(service: MockClimateService())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('meera_tailor_005').last); await tester.pumpAndSettle();
    await tester.tap(find.text('Heavy rain week')); await tester.pumpAndSettle();
    await tester.tap(find.text('Estimate impact')); await tester.pumpAndSettle();
    expect(find.textContaining('₹'), findsWidgets);
    expect(find.textContaining('Resilience buffer'), findsOneWidget);
    expect(find.text('Does not change the credit score'), findsOneWidget);
  });

  testWidgets('impact errors show message and Retry calls service again', (tester) async {
    final service = _FailingService();
    await tester.pumpWidget(MaterialApp(theme: CredifyTheme.dark, home: ClimateScreen(service: service))); await tester.pumpAndSettle();
    await tester.tap(find.text('Estimate impact')); await tester.pumpAndSettle();
    expect(find.textContaining('Climate backend unavailable'), findsOneWidget); expect(find.text('Retry'), findsOneWidget); expect(service.attempts, 1);
    await tester.ensureVisible(find.text('Retry')); await tester.pumpAndSettle();
    await tester.tap(find.text('Retry')); await tester.pumpAndSettle(); expect(service.attempts, 2);
  });

  testWidgets('credit score effect displays warning instead of badge', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: CredifyTheme.dark, home: ClimateScreen(service: _WarningService()))); await tester.pumpAndSettle();
    await tester.tap(find.text('Estimate impact')); await tester.pumpAndSettle();
    expect(find.textContaining('Warning: response indicates a credit score effect'), findsOneWidget);
    expect(find.text('Does not change the credit score'), findsNothing);
  });
}
