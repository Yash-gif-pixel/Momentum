import 'package:flutter/material.dart';
import '../models/analyze_response.dart';
import '../theme/credify_theme.dart';

/// Walks from the model's base log-odds to this borrower's, one feature at a
/// time. Because the scorecard is linear the bars sum to the final logit
/// exactly — there is no approximation step here, unlike SHAP over a tree
/// ensemble.
///
/// Deliberately drawn in LOG-ODDS, not score points: vitality_score is a
/// percentile rank against a frozen reference cohort, which is monotonic but
/// not linear, so "this feature added N points" would simply be false.
class ScoreWaterfall extends StatelessWidget {
  final ScoreBreakdown breakdown;
  final double? vitalityScore;

  const ScoreWaterfall({
    super.key,
    required this.breakdown,
    this.vitalityScore,
  });

  static String prettify(String feature) => feature
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Biggest movers first — the order a credit officer would read them in.
    final steps = breakdown.contributions.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    // Domain across the whole walk, so every bar shares one scale.
    var running = breakdown.intercept;
    var lo = running;
    var hi = running;
    for (final s in steps) {
      running += s.value;
      lo = running < lo ? running : lo;
      hi = running > hi ? running : hi;
    }
    lo = lo < 0 ? lo : 0;
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    double frac(double v) => ((v - lo) / span).clamp(0.0, 1.0);

    running = breakdown.intercept;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: 'Model baseline',
          detail: 'intercept',
          value: breakdown.intercept,
          start: 0,
          end: frac(breakdown.intercept),
          color: t.textTertiary,
          emphasise: true,
        ),
        for (final s in steps) ...[
          Builder(
            builder: (_) {
              final from = running;
              running += s.value;
              final positive = s.value >= 0;
              return _Row(
                label: prettify(s.key),
                detail: positive ? 'pushes toward repaying' : 'pushes toward risk',
                value: s.value,
                start: frac(positive ? from : running),
                end: frac(positive ? running : from),
                color: positive ? t.positive : t.warning,
                signed: true,
              );
            },
          ),
        ],
        Divider(color: t.hairline, height: 20),
        _Row(
          label: 'Final log-odds',
          detail: 'baseline + every feature',
          value: breakdown.logit,
          start: 0,
          end: frac(breakdown.logit),
          color: t.accentA,
          emphasise: true,
        ),
        const SizedBox(height: 16),
        _Conversion(breakdown: breakdown, vitalityScore: vitalityScore),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String detail;
  final double value;
  final double start;
  final double end;
  final Color color;
  final bool emphasise;
  final bool signed;

  const _Row({
    required this.label,
    required this.detail,
    required this.value,
    required this.start,
    required this.end,
    required this.color,
    this.emphasise = false,
    this.signed = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = signed
        ? '${value >= 0 ? '+' : '−'}${value.abs().toStringAsFixed(2)}'
        : value.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 11.5,
                    fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textTertiary, fontSize: 9.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final left = c.maxWidth * start;
                final width = (c.maxWidth * (end - start)).clamp(2.0, c.maxWidth);
                return SizedBox(
                  height: 16,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: t.hairline,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Positioned(
                        left: left,
                        top: 2,
                        bottom: 2,
                        width: width,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The non-linear tail of the pipeline, kept visually separate from the
/// additive bars so the two are never confused.
class _Conversion extends StatelessWidget {
  final ScoreBreakdown breakdown;
  final double? vitalityScore;

  const _Conversion({required this.breakdown, this.vitalityScore});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pct = (breakdown.pDefault * 100);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.hairline,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FROM LOG-ODDS TO SCORE',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(t, breakdown.logit.toStringAsFixed(2), 'log-odds'),
              _arrow(t),
              _chip(
                t,
                pct < 0.01 ? '<0.01%' : '${pct.toStringAsFixed(2)}%',
                'default risk',
              ),
              _arrow(t),
              _chip(
                t,
                vitalityScore == null
                    ? '—'
                    : vitalityScore!.toStringAsFixed(1),
                'rank vs cohort',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'The bars above add up exactly, because the scorecard is linear. '
            'The score itself is a percentile rank against the training '
            'cohort — monotonic but not linear — so a feature moves the '
            'log-odds by a fixed amount, not the score by a fixed number of '
            'points.',
            style: TextStyle(
              color: t.textTertiary,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(CredifyTokens t, String value, String caption) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(caption, style: TextStyle(color: t.textTertiary, fontSize: 9.5)),
      ],
    );
  }

  Widget _arrow(CredifyTokens t) =>
      Icon(Icons.arrow_forward_rounded, size: 13, color: t.textTertiary);
}
