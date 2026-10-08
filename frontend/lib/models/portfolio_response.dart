class BandDistribution {
  final int strongCandidate;
  final int manualReview;
  final int highRiskReferral;

  const BandDistribution({
    required this.strongCandidate,
    required this.manualReview,
    required this.highRiskReferral,
  });

  factory BandDistribution.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const BandDistribution(
        strongCandidate: 0,
        manualReview: 0,
        highRiskReferral: 0,
      );
    }
    return BandDistribution(
      strongCandidate: (json['strong_candidate'] as num?)?.toInt() ?? 0,
      manualReview: (json['manual_review'] as num?)?.toInt() ?? 0,
      highRiskReferral: (json['high_risk_referral'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'strong_candidate': strongCandidate,
        'manual_review': manualReview,
        'high_risk_referral': highRiskReferral,
      };
}

class ScoreBucket {
  final String bucket;
  final int count;

  const ScoreBucket({
    required this.bucket,
    required this.count,
  });

  factory ScoreBucket.fromJson(Map<String, dynamic> json) {
    return ScoreBucket(
      bucket: json['bucket'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'bucket': bucket,
        'count': count,
      };
}

class PortfolioResponse {
  final int nProfiles;
  final double coveragePct;
  final double? auc;
  final BandDistribution bandDistribution;
  final List<ScoreBucket> scoreHistogram;

  const PortfolioResponse({
    required this.nProfiles,
    required this.coveragePct,
    this.auc,
    required this.bandDistribution,
    required this.scoreHistogram,
  });

  factory PortfolioResponse.fromJson(Map<String, dynamic> json) {
    final rawHistogram = json['score_histogram'] as List<dynamic>? ?? [];
    return PortfolioResponse(
      nProfiles: (json['n_profiles'] as num?)?.toInt() ?? 0,
      coveragePct: (json['coverage_pct'] as num?)?.toDouble() ?? 0.0,
      auc: (json['auc'] as num?)?.toDouble(),
      bandDistribution: BandDistribution.fromJson(
        json['band_distribution'] as Map<String, dynamic>?,
      ),
      scoreHistogram: rawHistogram
          .map((e) => ScoreBucket.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'n_profiles': nProfiles,
        'coverage_pct': coveragePct,
        'auc': auc,
        'band_distribution': bandDistribution.toJson(),
        'score_histogram': scoreHistogram.map((e) => e.toJson()).toList(),
      };
}
