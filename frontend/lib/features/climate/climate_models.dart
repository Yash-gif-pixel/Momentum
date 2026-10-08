class ClimateScenario {
  final String scenarioId;
  final String label;
  final String description;
  final double lat;
  final double lon;
  final DateTime periodStart;
  final DateTime periodEnd;

  const ClimateScenario({
    required this.scenarioId,
    required this.label,
    required this.description,
    required this.lat,
    required this.lon,
    required this.periodStart,
    required this.periodEnd,
  });

  factory ClimateScenario.fromJson(Map<String, dynamic> json) {
    final cell = json['grid_cell'] as Map<String, dynamic>;
    return ClimateScenario(
      scenarioId: json['scenario_id'] as String,
      label: json['label'] as String,
      description: json['description'] as String,
      lat: (cell['lat'] as num).toDouble(),
      lon: (cell['lon'] as num).toDouble(),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
    );
  }
}

class ClimateOptions {
  final List<ClimateScenario> scenarios;
  final List<String> profileIds;
  const ClimateOptions({required this.scenarios, required this.profileIds});

  factory ClimateOptions.fromJson(Map<String, dynamic> json) => ClimateOptions(
    scenarios: (json['scenarios'] as List<dynamic>)
        .map((e) => ClimateScenario.fromJson(e as Map<String, dynamic>))
        .toList(),
    profileIds: (json['profile_ids'] as List<dynamic>).cast<String>(),
  );
}

class DailyRain {
  final DateTime date;
  final double rainMm;
  final bool disrupted;
  const DailyRain({
    required this.date,
    required this.rainMm,
    required this.disrupted,
  });

  factory DailyRain.fromJson(Map<String, dynamic> json) => DailyRain(
    date: DateTime.parse(json['date'] as String),
    rainMm: (json['rain_mm'] as num).toDouble(),
    disrupted: json['disrupted'] as bool,
  );
}

class ClimateImpact {
  final String profileId;
  final String scenarioId;
  final double lat;
  final double lon;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<DailyRain> daily;
  final int disruptedDays;
  final double baselineDailyInflowInr;
  final double estimatedCashflowImpactInr;
  final double impactPctOfMonthlyInflow;
  final double suggestedResilienceBufferInr;
  final List<String> assumptions;
  final bool affectsCreditScore;

  const ClimateImpact({
    required this.profileId,
    required this.scenarioId,
    required this.lat,
    required this.lon,
    required this.periodStart,
    required this.periodEnd,
    required this.daily,
    required this.disruptedDays,
    required this.baselineDailyInflowInr,
    required this.estimatedCashflowImpactInr,
    required this.impactPctOfMonthlyInflow,
    required this.suggestedResilienceBufferInr,
    required this.assumptions,
    required this.affectsCreditScore,
  });

  factory ClimateImpact.fromJson(Map<String, dynamic> json) {
    final cell = json['grid_cell'] as Map<String, dynamic>;
    return ClimateImpact(
      profileId: json['profile_id'] as String,
      scenarioId: json['scenario_id'] as String,
      lat: (cell['lat'] as num).toDouble(),
      lon: (cell['lon'] as num).toDouble(),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      daily: (json['daily'] as List<dynamic>)
          .map((e) => DailyRain.fromJson(e as Map<String, dynamic>))
          .toList(),
      disruptedDays: json['disrupted_days'] as int,
      baselineDailyInflowInr: (json['baseline_daily_inflow_inr'] as num)
          .toDouble(),
      estimatedCashflowImpactInr: (json['estimated_cashflow_impact_inr'] as num)
          .toDouble(),
      impactPctOfMonthlyInflow: (json['impact_pct_of_monthly_inflow'] as num)
          .toDouble(),
      suggestedResilienceBufferInr:
          (json['suggested_resilience_buffer_inr'] as num).toDouble(),
      assumptions: (json['assumptions'] as List<dynamic>).cast<String>(),
      affectsCreditScore: json['affects_credit_score'] as bool,
    );
  }
}

class PortfolioBorrower {
  final String profileId;
  final double baselineDailyInflowInr;
  final double estimatedCashflowImpactInr;
  final double impactPctOfMonthlyInflow;
  final double suggestedResilienceBufferInr;
  final String? city;
  final bool exposed;

  const PortfolioBorrower({
    required this.profileId,
    required this.baselineDailyInflowInr,
    required this.estimatedCashflowImpactInr,
    required this.impactPctOfMonthlyInflow,
    required this.suggestedResilienceBufferInr,
    this.city,
    this.exposed = true,
  });

  factory PortfolioBorrower.fromJson(Map<String, dynamic> json) =>
      PortfolioBorrower(
        profileId: json['profile_id'] as String,
        baselineDailyInflowInr: (json['baseline_daily_inflow_inr'] as num)
            .toDouble(),
        estimatedCashflowImpactInr:
            (json['estimated_cashflow_impact_inr'] as num).toDouble(),
        impactPctOfMonthlyInflow: (json['impact_pct_of_monthly_inflow'] as num)
            .toDouble(),
        suggestedResilienceBufferInr:
            (json['suggested_resilience_buffer_inr'] as num).toDouble(),
        city: json['city'] as String?,
        exposed: json['exposed'] as bool? ?? true,
      );
}

class ClimatePortfolio {
  final String scenarioId;
  final double lat;
  final double lon;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int disruptedDays;
  final List<PortfolioBorrower> borrowers;
  final int borrowersAffected;
  final int borrowersExposed;
  final double totalEstimatedImpactInr;
  final double totalSuggestedBufferInr;
  final List<String> assumptions;
  final bool affectsCreditScore;

  const ClimatePortfolio({
    required this.scenarioId,
    required this.lat,
    required this.lon,
    required this.periodStart,
    required this.periodEnd,
    required this.disruptedDays,
    required this.borrowers,
    required this.borrowersAffected,
    required this.borrowersExposed,
    required this.totalEstimatedImpactInr,
    required this.totalSuggestedBufferInr,
    required this.assumptions,
    required this.affectsCreditScore,
  });

  factory ClimatePortfolio.fromJson(Map<String, dynamic> json) {
    final cell = json['grid_cell'] as Map<String, dynamic>;
    final borrowers = (json['borrowers'] as List<dynamic>)
        .map((item) => PortfolioBorrower.fromJson(item as Map<String, dynamic>))
        .toList();
    return ClimatePortfolio(
      scenarioId: json['scenario_id'] as String,
      lat: (cell['lat'] as num).toDouble(),
      lon: (cell['lon'] as num).toDouble(),
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      disruptedDays: json['disrupted_days'] as int,
      borrowers: borrowers,
      borrowersAffected: json['borrowers_affected'] as int,
      borrowersExposed:
          json['borrowers_exposed'] as int? ??
          borrowers.where((borrower) => borrower.exposed).length,
      totalEstimatedImpactInr: (json['total_estimated_impact_inr'] as num)
          .toDouble(),
      totalSuggestedBufferInr: (json['total_suggested_buffer_inr'] as num)
          .toDouble(),
      assumptions: (json['assumptions'] as List<dynamic>).cast<String>(),
      affectsCreditScore: json['affects_credit_score'] as bool,
    );
  }
}
