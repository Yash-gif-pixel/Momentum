import 'package:flutter/material.dart';
import '../mock_backend.dart';
import '../models/portfolio_response.dart';
import '../services/credify_api_service.dart';
import '../theme/credify_theme.dart';
import '../widgets/credify_shell_widgets.dart';
import '../widgets/score_histogram_chart.dart';

class PortfolioScreen extends StatefulWidget {
  final CredifyApiService service;
  const PortfolioScreen({super.key, required this.service});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  PortfolioResponse? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.getPortfolio();
      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isMock = widget.service is MockBackend;

    return RefreshIndicator(
      onRefresh: _load,
      color: t.accentA,
      backgroundColor: t.bg,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              pillIcon: Icons.bar_chart_outlined,
              eyebrow: 'LENDER PORTFOLIO',
              title: 'Portfolio,\nin focus.',
              subtitle: isMock
                  ? 'Aggregate signal metrics — illustrative placeholder data '
                      '(mock backend).'
                  : 'Aggregate signal metrics across the credit-invisible book, '
                      'live from the Credify backend.',
            ),

            if (_loading)
              GlassCard(
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
                      'Loading portfolio metrics…',
                      style: TextStyle(color: t.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              )
            else if (_error != null)
              GlassCard(
                borderColor: t.negative.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Could not load the portfolio',
                      style: TextStyle(
                        color: t.negative,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: t.textSecondary, fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    CredifyButton(
                      label: 'Retry',
                      icon: Icons.refresh,
                      ghost: true,
                      onPressed: _load,
                    ),
                  ],
                ),
              )
            else if (_data != null)
              _PortfolioBody(data: _data!),
          ],
        ),
      ),
    );
  }
}

class _PortfolioBody extends StatelessWidget {
  final PortfolioResponse data;
  const _PortfolioBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bands = data.bandDistribution;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                value: data.nProfiles.toString(),
                label: 'ASSESSED',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                value: '${data.coveragePct.toStringAsFixed(0)}%',
                label: 'COVERAGE',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                value: data.auc == null
                    ? '—'
                    : data.auc!.toStringAsFixed(2),
                label: 'MODEL AUC',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        const SectionLabel('Band distribution'),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 22),
          child: Column(
            children: [
              _BandRow(
                label: 'Strong candidate',
                count: bands.strongCandidate,
                total: data.nProfiles,
                color: t.positive,
              ),
              const SizedBox(height: 14),
              _BandRow(
                label: 'Manual review',
                count: bands.manualReview,
                total: data.nProfiles,
                color: t.warning,
              ),
              const SizedBox(height: 14),
              _BandRow(
                label: 'High-risk referral',
                count: bands.highRiskReferral,
                total: data.nProfiles,
                color: t.negative,
              ),
            ],
          ),
        ),

        const SectionLabel('Lending policy'),
        _CutoffExplorer(data: data),
      ],
    );
  }
}

/// Lets a lender drag their own score cutoff and see how much of the book it
/// would let through. Credify supplies the signal; the policy stays theirs.
class _CutoffExplorer extends StatefulWidget {
  final PortfolioResponse data;
  const _CutoffExplorer({required this.data});

  @override
  State<_CutoffExplorer> createState() => _CutoffExplorerState();
}

class _CutoffExplorerState extends State<_CutoffExplorer> {
  // Snapped to the histogram's own 10-point buckets: interpolating inside a
  // bucket would invent a within-bucket distribution the data does not have.
  int _cutoff = 60;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final buckets = widget.data.scoreHistogram;

    final approved = buckets
        .where((b) => ScoreHistogramChart.lowerBound(b.bucket) >= _cutoff)
        .fold<int>(0, (sum, b) => sum + b.count);
    final scoredTotal = buckets.fold<int>(0, (sum, b) => sum + b.count);
    final belowCutoff = scoredTotal - approved;
    final pct = scoredTotal == 0 ? 0.0 : approved / scoredTotal * 100;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Approve at or above',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$_cutoff',
                style: TextStyle(
                  color: t.accentA,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                ' / 100',
                style: TextStyle(color: t.textTertiary, fontSize: 12),
              ),
            ],
          ),
          Slider(
            value: _cutoff.toDouble(),
            min: 0,
            max: 100,
            divisions: 10,
            activeColor: t.accentA,
            inactiveColor: t.hairline,
            label: '$_cutoff',
            onChanged: (v) => setState(() => _cutoff = v.round()),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _PolicyStat(
                  value: '$approved',
                  caption: 'would pass',
                  color: t.positive,
                ),
              ),
              Expanded(
                child: _PolicyStat(
                  value: '$belowCutoff',
                  caption: 'below cutoff',
                  color: t.warning,
                ),
              ),
              Expanded(
                child: _PolicyStat(
                  value: '${pct.toStringAsFixed(0)}%',
                  caption: 'of scored book',
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ScoreHistogramChart(
            buckets: buckets,
            cutoff: _cutoff,
          ),
          const SizedBox(height: 12),
          Text(
            'Volume only. Bad rate at each cutoff needs per-bucket repayment '
            'outcomes from the holdout, which this prototype does not expose — '
            'so this shows how many borrowers a policy lets through, not how '
            'many would default.',
            style: TextStyle(
              color: t.textTertiary,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyStat extends StatelessWidget {
  final String value;
  final String caption;
  final Color color;

  const _PolicyStat({
    required this.value,
    required this.caption,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: TextStyle(color: t.textSecondary, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String value;
  final String label;

  const _MetricCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 22,
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

class _BandRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _BandRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fraction = total == 0 ? 0.0 : (count / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$count  ·  ${(fraction * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
    );
  }
}
