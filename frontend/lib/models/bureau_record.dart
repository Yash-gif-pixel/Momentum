/// How a bureau file reads on its own terms, before any cashflow is looked at.
enum BureauFileQuality {
  /// A real file, but old and sparse — a bureau-only policy would decline.
  thinAndStale,

  /// A current file a bureau-only policy would happily approve.
  healthy,
}

/// A SIMULATED traditional bureau file, for the demo's "step 1" lookup.
///
/// Entirely fictitious and entirely frontend-side: no bureau is queried, and
/// none of this reaches the scoring path. It is kept out of `AnalyzeResponse`
/// deliberately so a bureau record can never influence a Credify score —
/// the whole point of the product is that the two are independent.
///
/// Three outcomes are represented, because all three are real:
///
/// * No record at all — the credit-invisible majority of this segment, and
///   the case Credify exists for.
/// * A thin, stale record — the bureau is not only absent for these
///   borrowers, it is sometimes years out of date about the ones it holds.
/// * A healthy record attached to a business whose cashflow is deteriorating
///   — the bureau reports past *borrowing*, with a lag, and cannot see that
///   turnover has halved since the last account was reported.
class BureauRecord {
  final int score;
  final String scale;
  final String vintage;
  final String summary;
  final BureauFileQuality quality;

  const BureauRecord({
    required this.score,
    required this.scale,
    required this.vintage,
    required this.summary,
    required this.quality,
  });

  static const _known = <String, BureauRecord>{
    'meera_tailor_005': BureauRecord(
      score: 611,
      scale: '300–900',
      vintage: 'Last updated 41 months ago',
      quality: BureauFileQuality.thinAndStale,
      summary:
          'One closed personal loan from 2021 with two late payments, and no '
          'activity since. Nothing about the tailoring business appears in '
          'this file at all.',
    ),
    'arjun_kirana_006': BureauRecord(
      score: 784,
      scale: '300–900',
      vintage: 'Last updated 7 months ago',
      quality: BureauFileQuality.healthy,
      summary:
          'Two serviced loans and a credit card, 48 months of on-time '
          'repayment, no defaults. A clean file — but it records what was '
          'borrowed and repaid, not what the shop is earning now.',
    ),
  };

  /// Null means no bureau file exists — the credit-invisible case.
  static BureauRecord? forId(String profileId) => _known[profileId];
}
