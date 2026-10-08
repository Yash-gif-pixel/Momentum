import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/analyze_response.dart';
import '../models/persona_meta.dart';
import '../state/app_state.dart';
import '../theme/credify_theme.dart';
import '../widgets/credify_shell_widgets.dart';
import '../widgets/score_gauge.dart';

class BorrowerScreen extends StatelessWidget {
  const BorrowerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Consumer<AppState>(
      builder: (context, state, _) {
        final result = state.analyzeResult;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                pillIcon: Icons.person_outline,
                eyebrow: 'YOUR SIGNAL',
                title: 'Make the\nsignal visible.',
                subtitle:
                    "Here's what your transaction history tells a lender — "
                    'in plain language.',
              ),

              if (!state.consentApproved)
                _Notice(
                  icon: Icons.lock_outline,
                  color: t.warning,
                  title: 'Consent not yet given',
                  body: 'Go to the Consent tab and approve data sharing, then ask '
                      'the lender to run the Credify check. Your results will '
                      'appear here.',
                )
              else if (result == null)
                _Notice(
                  icon: Icons.hourglass_empty_outlined,
                  color: t.accentA,
                  title: 'Awaiting assessment',
                  body: 'Your data has been shared. The lender needs to run the '
                      'Credify check — results will appear here once it is done.',
                )
              else
                _BorrowerResult(
                  result: result,
                  profileId: state.selectedProfileId,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BorrowerResult extends StatelessWidget {
  final AnalyzeResponse result;
  final String profileId;

  const _BorrowerResult({required this.result, required this.profileId});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final meta = PersonaMeta.forId(profileId);

    if (result.isNotAssessable) {
      return Column(
        children: [
          _Notice(
            icon: Icons.info_outline,
            color: t.accentA,
            title: "We couldn't assess your signal yet",
            body: result.coverageReason ??
                'There was not enough transaction history to produce a reliable '
                    'signal. This is not a rejection — Credify refuses to guess.',
          ),
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('What you can do'),
                Text(
                  'Keep using a bank account or UPI for your business '
                  'transactions. The more months of digital history you build, '
                  'the stronger the signal Credify can generate.',
                  style: TextStyle(
                      color: t.textSecondary, fontSize: 13, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: t.accentGradient,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(meta.icon, color: Colors.white, size: 15),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    meta.name,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ScoreGauge(
                score: result.vitalityScore ?? 0,
                band: result.band,
                confidence: result.confidence,
              ),
              const SizedBox(height: 8),
              Text(
                'Higher is better  ·  Scale 0 to 100',
                style: TextStyle(color: t.textTertiary, fontSize: 11),
              ),
            ],
          ),
        ),

        if (result.reasonCodes.strengths.isNotEmpty)
          GlassCard(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel("What's helping you"),
                ...result.reasonCodes.strengths.map(
                  (s) => _PlainPoint(text: s.statement, positive: true),
                ),
              ],
            ),
          ),

        if (result.reasonCodes.concerns.isNotEmpty)
          GlassCard(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Areas to watch'),
                ...result.reasonCodes.concerns.map(
                  (c) => _PlainPoint(text: c.statement, positive: false),
                ),
              ],
            ),
          ),

        GlassCard(
          margin: const EdgeInsets.only(bottom: 14),
          borderColor: t.positive.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.rocket_launch_outlined,
                      color: t.positive, size: 17),
                  const SizedBox(width: 8),
                  Text(
                    'One thing you can do to improve',
                    style: TextStyle(
                      color: t.positive,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _tip(result),
                style: TextStyle(
                    color: t.textSecondary, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),

        if (result.isScored)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('About your loan affordability'),
                Text(
                  'Based on your income pattern, a monthly instalment of roughly '
                  '₹${_fmt(result.affordability.indicativeEmiLow)} to '
                  '₹${_fmt(result.affordability.indicativeEmiHigh)} looks '
                  'manageable. In ${result.affordability.monthsWouldCoverEmiOfLast24} '
                  'of the last 24 months your income would have comfortably '
                  'covered an EMI in that range.',
                  style: TextStyle(
                      color: t.textSecondary, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 10),
                Text(
                  'Indicative estimates only. A lender makes the final assessment.',
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _fmt(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)},000';
    return v.toStringAsFixed(0);
  }

  static String _tip(AnalyzeResponse result) {
    final features = result.reasonCodes.concerns.map((c) => c.feature).toList();
    if (features.contains('buffer_days')) {
      return 'Try to keep a cash buffer of at least 15 days of business expenses '
          'in your account. It shows lenders you can handle a slow month.';
    }
    if (features.contains('income_volatility')) {
      return 'Smoothing out your income — for example by taking smaller orders '
          'during off-peak months — can noticeably improve your signal over the '
          'next six months.';
    }
    if (features.contains('cash_share')) {
      return 'Routing more sales through UPI or bank transfer rather than cash '
          'gives Credify a clearer picture of your income.';
    }
    return 'Keep your business account active and consistent. Regular digital '
        'transactions over the next 6–12 months build a stronger record.';
  }
}

class _PlainPoint extends StatelessWidget {
  final String text;
  final bool positive;

  const _PlainPoint({required this.text, required this.positive});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = positive ? t.positive : t.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              positive ? Icons.check : Icons.priority_high,
              size: 13,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: t.textSecondary, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlassCard(
      borderColor: color.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style:
                TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}
