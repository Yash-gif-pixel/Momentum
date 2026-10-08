import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/analyze_response.dart';
import '../models/bureau_record.dart';
import '../models/persona_meta.dart';
import '../state/app_state.dart';
import '../theme/credify_theme.dart';
import '../widgets/authenticity_card.dart';
import '../widgets/cashflow_chart.dart';
import '../widgets/credify_shell_widgets.dart';
import '../widgets/score_gauge.dart';
import '../widgets/score_waterfall.dart';

class LenderScreen extends StatelessWidget {
  const LenderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Consumer<AppState>(
      builder: (context, state, _) {
        final meta = PersonaMeta.forId(state.selectedProfileId);
        final step = state.lenderStep;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                pillIcon: Icons.account_balance_outlined,
                eyebrow: 'FOR LENDERS',
                title: 'A clearer\nway to look.',
                subtitle:
                    'Move from a blank bureau file to a full view of business '
                    'cash-flow — with reasons a credit team can actually discuss.',
              ),

              // Selected borrower
              GlassCard(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: t.accentGradient,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(meta.icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meta.name,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            meta.sector,
                            style: TextStyle(
                                color: t.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Step 1: traditional bureau ──────────────────────────────
              if (step == LenderStep.idle)
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Step 1 — traditional bureau'),
                      CredifyButton(
                        label: 'Run bureau check',
                        icon: Icons.search,
                        ghost: true,
                        onPressed: state.consentApproved
                            ? state.runBureauCheck
                            : null,
                      ),
                      if (!state.consentApproved) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 14, color: t.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Awaiting borrower consent — visit the Consent tab first.',
                                style: TextStyle(
                                    color: t.warning, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                )
              else
                _BureauResult(
                  record: BureauRecord.forId(state.selectedProfileId),
                ),

              // ── Step 2: Credify signal ──────────────────────────────────
              if (step == LenderStep.bureauChecked)
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Step 2 — Credify signal'),
                      CredifyButton(
                        label: 'Run Credify check',
                        icon: Icons.auto_awesome,
                        onPressed: state.runCredifyAnalysis,
                      ),
                    ],
                  ),
                ),

              if (state.analyzeLoading)
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: t.accentA),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Scoring cash-flow behaviour…',
                        style:
                            TextStyle(color: t.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),

              if (state.analyzeError != null)
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 14),
                  borderColor: t.negative.withValues(alpha: 0.4),
                  child: Text(
                    'Error: ${state.analyzeError}',
                    style: TextStyle(color: t.negative, fontSize: 13),
                  ),
                ),

              if (state.analyzeResult != null && !state.analyzeLoading)
                _ResultView(result: state.analyzeResult!),

              if (step == LenderStep.done) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: state.resetLenderFlow,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Run another check'),
                  style: TextButton.styleFrom(foregroundColor: t.textSecondary),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Step 1's outcome, in three flavours: no file at all (the credit-invisible
/// majority), a thin and stale file, or a clean file. Note that a clean file
/// is not an endorsement either — it records repayment of past borrowing, and
/// says nothing about whether the business is earning today. Step 2 is what
/// decides that, in every one of the three cases.
class _BureauResult extends StatelessWidget {
  final BureauRecord? record;
  const _BureauResult({required this.record});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = record;

    if (r == null) {
      return GlassCard(
        margin: const EdgeInsets.only(bottom: 14),
        borderColor: t.negative.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: t.negative, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Text(
                  'NO BUREAU FILE FOUND',
                  style: TextStyle(
                    color: t.negative,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'This borrower is credit invisible — no bureau record exists, so '
              'traditional scoring cannot proceed. This is exactly the gap '
              'Credify closes.',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final healthy = r.quality == BureauFileQuality.healthy;
    final accent = healthy ? t.positive : t.warning;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      borderColor: accent.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  healthy
                      ? 'CLEAN BUREAU FILE FOUND'
                      : 'THIN BUREAU FILE FOUND',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const StatusBadge(label: 'SIMULATED', color: Color(0xFF9CA3AF)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${r.score}',
                style: TextStyle(
                  color: accent,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  r.scale,
                  style: TextStyle(color: t.textTertiary, fontSize: 12),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  r.vintage,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: t.textTertiary, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            r.summary,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Illustrative bureau record on synthetic data — no bureau was '
            'queried, and nothing here reaches the Credify score.',
            style: TextStyle(
              color: t.textTertiary,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final AnalyzeResponse result;
  const _ResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (result.isNotAssessable) {
      return GlassCard(
        borderColor: t.negative.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge(label: 'NOT ASSESSABLE', color: t.negative),
            const SizedBox(height: 12),
            Text(
              'Not enough transaction history for a responsible assessment.',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              result.coverageReason ??
                  'Credify refuses to guess when data coverage is too thin — a '
                      'deliberate sufficiency gate, not a risk judgment.',
              style: TextStyle(
                  color: t.textSecondary, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      );
    }

    final scored = result.isScored;
    final badgeColor = scored ? t.positive : t.warning;
    final badgeLabel = scored ? 'SCORED' : 'LOW CONFIDENCE';

    final reasons = <_Reason>[
      ...result.reasonCodes.strengths
          .map((r) => _Reason(item: r, positive: true)),
      ...result.reasonCodes.concerns
          .map((r) => _Reason(item: r, positive: false)),
    ];
    final maxAbs = reasons.isEmpty
        ? 1.0
        : reasons
            .map((r) => r.item.contribution.abs())
            .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionLabel('Credify score'),
                  StatusBadge(label: badgeLabel, color: badgeColor),
                ],
              ),
              Center(
                child: ScoreGauge(
                  score: result.vitalityScore ?? 0,
                  band: result.band,
                  confidence: result.confidence,
                ),
              ),
              if (result.coverageReason != null) ...[
                const SizedBox(height: 14),
                Text(
                  result.coverageReason!,
                  style: TextStyle(
                      color: t.textSecondary, fontSize: 12.5, height: 1.5),
                ),
              ],
            ],
          ),
        ),

        // Data-pattern check. Sits directly under the score because it is a
        // statement about the input the score was built from, but is sized to
        // how much it actually matters: a quiet line when the pattern is
        // normal, a full card only when something is worth looking at.
        if (result.authenticityCheck != null)
          AuthenticityCard(check: result.authenticityCheck!),

        // Affordability
        GlassCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Indicative EMI affordability'),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      value:
                          '₹${_fmt(result.affordability.indicativeEmiLow)} – ₹${_fmt(result.affordability.indicativeEmiHigh)}',
                      label: 'EMI RANGE',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Metric(
                      value:
                          '${result.affordability.monthsWouldCoverEmiOfLast24} / 24',
                      label: 'MONTHS COVERED',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Reason codes
        if (reasons.isNotEmpty)
          GlassCard(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Why this signal'),
                for (var i = 0; i < reasons.length; i++)
                  _ReasonRow(
                    reason: reasons[i],
                    maxAbs: maxAbs,
                    showDivider: i > 0,
                  ),
              ],
            ),
          ),

        // Exact additive decomposition — only present for SCORED results.
        if (result.scoreBreakdown != null)
          GlassCard(
            margin: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('How the score was built'),
                ScoreWaterfall(
                  breakdown: result.scoreBreakdown!,
                  vitalityScore: result.vitalityScore,
                ),
              ],
            ),
          ),

        // Cashflow
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('24-month cashflow trend'),
              CashflowChart(data: result.monthlyCashflow),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmt(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }
}

class _Reason {
  final ReasonItem item;
  final bool positive;
  const _Reason({required this.item, required this.positive});
}

class _ReasonRow extends StatelessWidget {
  final _Reason reason;
  final double maxAbs;
  final bool showDivider;

  const _ReasonRow({
    required this.reason,
    required this.maxAbs,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = reason.positive ? t.positive : t.warning;
    final contribution = reason.item.contribution;
    // Bar length is relative to the strongest driver in this result — the raw
    // log-odds contribution is printed separately so it is never read as a %.
    final fraction = maxAbs == 0 ? 0.0 : (contribution.abs() / maxAbs).clamp(0.0, 1.0);

    return Padding(
      padding: EdgeInsets.only(top: showDivider ? 12 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDivider) ...[
            Divider(color: t.hairline, height: 1),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  reason.item.statement,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${contribution >= 0 ? '+' : ''}${contribution.toStringAsFixed(2)}',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Feature: ${reason.item.feature}  ·  log-odds contribution',
            style: TextStyle(color: t.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: t.hairline,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.hairline,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: t.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
