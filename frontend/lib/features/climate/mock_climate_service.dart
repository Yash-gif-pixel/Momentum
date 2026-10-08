import 'climate_api_service.dart';
import 'climate_models.dart';

class MockClimateService implements ClimateApiService {
  static const _ids = [
    'lakshmi_vendor_001',
    'meera_tailor_005',
    'arjun_kirana_006',
  ];
  static const _scenarioIds = [
    'normal_monsoon',
    'heavy_rain_week',
    'flash_flood',
  ];
  @override
  Future<ClimateOptions> fetchOptions() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final scenarios = <ClimateScenario>[];
    for (var i = 0; i < _scenarioIds.length; i++) {
      final id = _scenarioIds[i];
      scenarios.add(
        ClimateScenario(
          scenarioId: id,
          label: ['Typical monsoon', 'Heavy rain week', 'Flash flood'][i],
          description: [
            'Seasonal rainfall with occasional disruption',
            'A concentrated week of intense rainfall',
            'Severe rainfall causing multiple disrupted days',
          ][i],
          lat: 19.076 + i * 0.02,
          lon: 72.8777 + i * 0.02,
          periodStart: DateTime(2025, 7, 1),
          periodEnd: DateTime(2025, 7, 30),
        ),
      );
    }
    return ClimateOptions(scenarios: scenarios, profileIds: _ids);
  }

  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final scenarioIndex = _scenarioIds.indexOf(scenarioId).clamp(0, 2).toInt();
    final disruptionCount = [3, 8, 13][scenarioIndex];
    final daily = List<DailyRain>.generate(30, (i) {
      final disrupted = (i * 7 + scenarioIndex * 3) % 30 < disruptionCount;
      final rain = disrupted
          ? 30.0 + ((i * 13 + scenarioIndex * 17) % 110)
          : ((i * 11) % 18).toDouble();
      return DailyRain(
        date: DateTime(2025, 7, i + 1),
        rainMm: rain,
        disrupted: disrupted,
      );
    });
    const inflow = 1800.0;
    final impact = disruptionCount * inflow * 0.7;
    return ClimateImpact(
      profileId: profileId,
      scenarioId: scenarioId,
      lat: 19.076 + scenarioIndex * 0.02,
      lon: 72.8777 + scenarioIndex * 0.02,
      periodStart: DateTime(2025, 7, 1),
      periodEnd: DateTime(2025, 7, 30),
      daily: daily,
      disruptedDays: disruptionCount,
      baselineDailyInflowInr: inflow,
      estimatedCashflowImpactInr: impact,
      impactPctOfMonthlyInflow: impact / (inflow * 30) * 100,
      suggestedResilienceBufferInr: impact * 0.75,
      assumptions: const [
        'Daily inflow is estimated from the selected borrower profile.',
        'Rainfall disruption is a proxy for short-term business interruption.',
        'This estimate describes cash flow only.',
      ],
      affectsCreditScore: false,
    );
  }

  @override
  Future<ClimatePortfolio> fetchPortfolio(String scenarioId) async {
    final options = await fetchOptions();
    ClimateScenario? scenario;
    for (final candidate in options.scenarios) {
      if (candidate.scenarioId == scenarioId) {
        scenario = candidate;
        break;
      }
    }
    if (scenario == null) {
      throw ClimateApiException(
        statusCode: 404,
        message: "Unknown scenario_id '$scenarioId'.",
      );
    }

    const cities = ['Mumbai', 'Pune', 'Nashik'];
    const dailyInflows = [1800.0, 1450.0, 2200.0];
    const exposureByScenario = [
      [true, true, false],
      [true, false, true],
      [false, true, true],
    ];
    final scenarioIndex = _scenarioIds.indexOf(scenarioId);
    final borrowers = <PortfolioBorrower>[];
    final assumptions = <String>[];
    var disruptedDays = 0;
    for (var index = 0; index < options.profileIds.length; index++) {
      final impact = await fetchImpact(options.profileIds[index], scenarioId);
      final exposed = exposureByScenario[scenarioIndex][index];
      final baselineInflow = dailyInflows[index];
      final scale = baselineInflow / impact.baselineDailyInflowInr;
      final cashflowImpact = exposed
          ? (impact.estimatedCashflowImpactInr * scale).roundToDouble()
          : 0.0;
      borrowers.add(
        PortfolioBorrower(
          profileId: impact.profileId,
          baselineDailyInflowInr: baselineInflow,
          estimatedCashflowImpactInr: cashflowImpact,
          impactPctOfMonthlyInflow: exposed
              ? impact.impactPctOfMonthlyInflow
              : 0,
          suggestedResilienceBufferInr: exposed
              ? (cashflowImpact * 0.75).roundToDouble()
              : 0,
          city: cities[index],
          exposed: exposed,
        ),
      );
      disruptedDays = impact.disruptedDays;
      for (final assumption in impact.assumptions) {
        if (!assumptions.contains(assumption)) assumptions.add(assumption);
      }
    }
    assumptions.add(
      'Borrowers marked not exposed are outside this scenario grid cell.',
    );

    return ClimatePortfolio(
      scenarioId: scenarioId,
      lat: scenario.lat,
      lon: scenario.lon,
      periodStart: scenario.periodStart,
      periodEnd: scenario.periodEnd,
      disruptedDays: disruptedDays,
      borrowers: borrowers,
      borrowersAffected: borrowers
          .where((borrower) => borrower.estimatedCashflowImpactInr > 0)
          .length,
      borrowersExposed: borrowers.where((borrower) => borrower.exposed).length,
      totalEstimatedImpactInr: borrowers.fold(
        0,
        (total, borrower) => total + borrower.estimatedCashflowImpactInr,
      ),
      totalSuggestedBufferInr: borrowers.fold(
        0,
        (total, borrower) => total + borrower.suggestedResilienceBufferInr,
      ),
      assumptions: assumptions,
      affectsCreditScore: false,
    );
  }
}
