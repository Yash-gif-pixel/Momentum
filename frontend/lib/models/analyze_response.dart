class ReasonItem {
  final String feature;
  final String statement;
  final double contribution;

  const ReasonItem({
    required this.feature,
    required this.statement,
    required this.contribution,
  });

  factory ReasonItem.fromJson(Map<String, dynamic> json) {
    return ReasonItem(
      feature: json['feature'] as String? ?? '',
      statement: json['statement'] as String? ?? '',
      contribution: (json['contribution'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'feature': feature,
        'statement': statement,
        'contribution': contribution,
      };
}

class ReasonCodes {
  final List<ReasonItem> strengths;
  final List<ReasonItem> concerns;

  const ReasonCodes({
    required this.strengths,
    required this.concerns,
  });

  factory ReasonCodes.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ReasonCodes(strengths: [], concerns: []);
    }
    final rawStrengths = json['strengths'] as List<dynamic>? ?? [];
    final rawConcerns = json['concerns'] as List<dynamic>? ?? [];
    return ReasonCodes(
      strengths: rawStrengths
          .map((e) => ReasonItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      concerns: rawConcerns
          .map((e) => ReasonItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'strengths': strengths.map((e) => e.toJson()).toList(),
        'concerns': concerns.map((e) => e.toJson()).toList(),
      };
}

/// The exact additive decomposition behind a SCORED result.
///
/// `intercept + sum(contributions.values)` equals `logit` exactly, because the
/// model is linear. That additivity is in LOG-ODDS space only — vitalityScore
/// is a percentile rank of [pDefault], which is monotonic but not linear, so
/// these values must never be shown as "points added to the score".
class ScoreBreakdown {
  final double intercept;
  final Map<String, double> contributions;
  final double logit;
  final double pDefault;

  const ScoreBreakdown({
    required this.intercept,
    required this.contributions,
    required this.logit,
    required this.pDefault,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic> json) {
    final raw = json['contributions'] as Map<String, dynamic>? ?? {};
    return ScoreBreakdown(
      intercept: (json['intercept'] as num?)?.toDouble() ?? 0.0,
      contributions: raw.map(
        (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0.0),
      ),
      logit: (json['logit'] as num?)?.toDouble() ?? 0.0,
      pDefault: (json['p_default'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'intercept': intercept,
        'contributions': contributions,
        'logit': logit,
        'p_default': pDefault,
      };
}

/// Whether an income trail looks *too* smooth to be a real business's.
///
/// The mirror image of the sufficiency gate: that one catches too little
/// data, this catches data that is too clean. Backend-side it is computed
/// after scoring is already finished and feeds neither the gate nor the
/// model, so it never moves [AnalyzeResponse.vitalityScore], `band`,
/// `outcome` or `confidence` — and nothing in this app should present it as
/// if it did.
///
/// [status] is a prompt to look, not a verdict. A genuinely well-run
/// business on a fixed monthly contract could sit below the floor with
/// nothing wrong.
///
/// Absent (null on [AnalyzeResponse]) when the backend could not answer:
/// either the variation is not computable at all, or there are too few
/// monthly observations for it to mean anything. That is "cannot tell", not
/// "passed" — never render a missing check as a clean bill of health.
class AuthenticityCheck {
  /// "natural" | "unusually_uniform"
  final String status;

  /// The feature this was read from, e.g. income_coefficient_of_variation.
  final String signal;

  /// The profile's actual value for [signal].
  final double observed;

  /// The calibrated floor [observed] was compared against.
  final double floor;
  final String note;

  const AuthenticityCheck({
    required this.status,
    required this.signal,
    required this.observed,
    required this.floor,
    required this.note,
  });

  bool get isUnusuallyUniform => status == 'unusually_uniform';

  factory AuthenticityCheck.fromJson(Map<String, dynamic> json) {
    return AuthenticityCheck(
      status: json['status'] as String? ?? 'natural',
      signal: json['signal'] as String? ?? '',
      observed: (json['observed'] as num?)?.toDouble() ?? 0.0,
      floor: (json['floor'] as num?)?.toDouble() ?? 0.0,
      note: json['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'signal': signal,
        'observed': observed,
        'floor': floor,
        'note': note,
      };
}

class Affordability {
  final double indicativeEmiLow;
  final double indicativeEmiHigh;
  final int monthsWouldCoverEmiOfLast24;

  const Affordability({
    required this.indicativeEmiLow,
    required this.indicativeEmiHigh,
    required this.monthsWouldCoverEmiOfLast24,
  });

  factory Affordability.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const Affordability(
        indicativeEmiLow: 0.0,
        indicativeEmiHigh: 0.0,
        monthsWouldCoverEmiOfLast24: 0,
      );
    }
    return Affordability(
      indicativeEmiLow: (json['indicative_emi_low'] as num?)?.toDouble() ?? 0.0,
      indicativeEmiHigh: (json['indicative_emi_high'] as num?)?.toDouble() ?? 0.0,
      monthsWouldCoverEmiOfLast24:
          (json['months_would_cover_emi_of_last_24'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'indicative_emi_low': indicativeEmiLow,
        'indicative_emi_high': indicativeEmiHigh,
        'months_would_cover_emi_of_last_24': monthsWouldCoverEmiOfLast24,
      };
}

class MonthlyCashflow {
  final String month;
  final double inflow;
  final double outflow;
  final double net;

  const MonthlyCashflow({
    required this.month,
    required this.inflow,
    required this.outflow,
    required this.net,
  });

  factory MonthlyCashflow.fromJson(Map<String, dynamic> json) {
    return MonthlyCashflow(
      month: json['month'] as String? ?? '',
      inflow: (json['inflow'] as num?)?.toDouble() ?? 0.0,
      outflow: (json['outflow'] as num?)?.toDouble() ?? 0.0,
      net: (json['net'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'month': month,
        'inflow': inflow,
        'outflow': outflow,
        'net': net,
      };
}

class AnalyzeResponse {
  final String profileId;
  final String outcome; // "SCORED" | "LOW_CONFIDENCE" | "NOT_ASSESSABLE"
  final double? vitalityScore; // 0-100 or null
  final String? band; // "strong_candidate" | "manual_review" | "high_risk_referral" | null
  final String? confidence; // "high" | "low" | null
  final ReasonCodes reasonCodes;
  final ScoreBreakdown? scoreBreakdown;
  final Affordability affordability;
  final List<MonthlyCashflow> monthlyCashflow;

  /// Null means the backend could not assess the pattern, NOT that it passed.
  final AuthenticityCheck? authenticityCheck;
  final String? coverageReason;
  final String disclaimer;

  const AnalyzeResponse({
    required this.profileId,
    required this.outcome,
    this.vitalityScore,
    this.band,
    this.confidence,
    required this.reasonCodes,
    this.scoreBreakdown,
    required this.affordability,
    required this.monthlyCashflow,
    this.authenticityCheck,
    this.coverageReason,
    required this.disclaimer,
  });

  bool get isScored => outcome == 'SCORED';
  bool get isNotAssessable => outcome == 'NOT_ASSESSABLE';
  bool get isLowConfidence => outcome == 'LOW_CONFIDENCE';

  factory AnalyzeResponse.fromJson(Map<String, dynamic> json) {
    final rawCashflow = json['monthly_cashflow'] as List<dynamic>? ?? [];
    return AnalyzeResponse(
      profileId: json['profile_id'] as String? ?? '',
      outcome: json['outcome'] as String? ?? 'NOT_ASSESSABLE',
      vitalityScore: (json['vitality_score'] as num?)?.toDouble(),
      band: json['band'] as String?,
      confidence: json['confidence'] as String?,
      reasonCodes: ReasonCodes.fromJson(
        json['reason_codes'] as Map<String, dynamic>?,
      ),
      scoreBreakdown: json['score_breakdown'] == null
          ? null
          : ScoreBreakdown.fromJson(
              json['score_breakdown'] as Map<String, dynamic>,
            ),
      affordability: Affordability.fromJson(
        json['affordability'] as Map<String, dynamic>?,
      ),
      monthlyCashflow: rawCashflow
          .map((e) => MonthlyCashflow.fromJson(e as Map<String, dynamic>))
          .toList(),
      authenticityCheck: json['authenticity_check'] == null
          ? null
          : AuthenticityCheck.fromJson(
              json['authenticity_check'] as Map<String, dynamic>,
            ),
      coverageReason: json['coverage_reason'] as String?,
      disclaimer: json['disclaimer'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'outcome': outcome,
        'vitality_score': vitalityScore,
        'band': band,
        'confidence': confidence,
        'reason_codes': reasonCodes.toJson(),
        'score_breakdown': scoreBreakdown?.toJson(),
        'affordability': affordability.toJson(),
        'monthly_cashflow': monthlyCashflow.map((e) => e.toJson()).toList(),
        'authenticity_check': authenticityCheck?.toJson(),
        'coverage_reason': coverageReason,
        'disclaimer': disclaimer,
      };
}
