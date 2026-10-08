import 'package:flutter/material.dart';

import '../models/analyze_response.dart';
import '../theme/credify_theme.dart';
import 'credify_shell_widgets.dart';

/// The data-pattern check, rendered at two very different weights.
///
/// A flag is rare and worth interrupting for, so it gets a full bordered
/// card with the backend's own note. "Natural" is the case for every demo
/// profile, and a prominent green card on every single result would train a
/// viewer to ignore this area entirely — so it collapses to one quiet line
/// that still proves the check ran and shows the margin.
///
/// Neither state may be phrased as a verdict on the borrower: this reads the
/// *shape of the data*, not the business, and it never moved the score.
class AuthenticityCard extends StatelessWidget {
  final AuthenticityCheck check;
  const AuthenticityCard({super.key, required this.check});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (!check.isUnusuallyUniform) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14, left: 4, right: 4),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, size: 14, color: t.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Data pattern check passed — month-to-month income varies by '
                '${_pct(check.observed)}, within the range real businesses show '
                '(floor ${_pct(check.floor)}).',
                style: TextStyle(
                  color: t.textTertiary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      borderColor: t.warning.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pattern_outlined, size: 16, color: t.warning),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'UNUSUALLY UNIFORM INCOME PATTERN',
                  style: TextStyle(
                    color: t.warning,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              StatusBadge(label: 'NOT A SCORE FACTOR', color: t.textTertiary),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _pct(check.observed),
                style: TextStyle(
                  color: t.warning,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  height: 1,
                ),
              ),
              const SizedBox(width: 7),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'variation · floor ${_pct(check.floor)}',
                  style: TextStyle(color: t.textTertiary, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            check.note,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This reads the shape of the data, not the business. It did not '
            'change the score above, and a steady business on a fixed monthly '
            'contract can legitimately land here.',
            style: TextStyle(color: t.textTertiary, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }

  /// The coefficient of variation is a ratio of a value to its own mean, so a
  /// percentage is the honest reading of it — 0.41 really is "varies by 41%
  /// of its own average", which is how reason_codes.py words it too.
  static String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';
}
