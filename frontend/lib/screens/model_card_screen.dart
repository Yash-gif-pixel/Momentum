import 'package:flutter/material.dart';

import '../services/credify_api_service.dart';
import '../theme/credify_theme.dart';
import '../widgets/credify_shell_widgets.dart';

class ModelCardScreen extends StatefulWidget {
  final CredifyApiService service;

  const ModelCardScreen({super.key, required this.service});

  @override
  State<ModelCardScreen> createState() => _ModelCardScreenState();
}

class _ModelCardScreenState extends State<ModelCardScreen> {
  late Future<Map<String, dynamic>> _modelCard;

  @override
  void initState() {
    super.initState();
    _modelCard = widget.service.getModelCard();
  }

  void _reload() => setState(() => _modelCard = widget.service.getModelCard());

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FutureBuilder<Map<String, dynamic>>(
      future: _modelCard,
      builder: (context, snapshot) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                pillIcon: Icons.fact_check_outlined,
                eyebrow: 'MODEL TRANSPARENCY',
                title: 'What the score\ncan tell you.',
                subtitle:
                    'Training, validation, the sufficiency gate, fairness guardrails, and known limits - using the committed validation snapshot.',
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const GlassCard(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError || snapshot.data == null)
                GlassCard(
                  borderColor: t.negative.withValues(alpha: 0.4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Model validation details are unavailable.',
                        style: TextStyle(color: t.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error ?? 'No model-card data returned.'}',
                        style: TextStyle(color: t.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      CredifyButton(
                        label: 'Retry',
                        icon: Icons.refresh,
                        ghost: true,
                        onPressed: _reload,
                      ),
                    ],
                  ),
                )
              else
                _ModelCardBody(data: snapshot.data!),
            ],
          ),
        );
      },
    );
  }
}

class _ModelCardBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ModelCardBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final validation = _map(data['validation']);
    final coverage = _map(validation['coverage']);
    final counts = _map(coverage['counts']);
    final percentages = _map(coverage['pct']);
    final stability = _map(validation['stability_12_vs_24_months']);
    final training = _map(data['training']);
    final gate = _map(data['sufficiency_gate']);
    final fairness = _map(data['fairness']);
    final predictors = _strings(training['predictive_features']);
    final excluded = _strings(fairness['excluded_fields']);
    final testGuardrails = _strings(fairness['test_guardrails']);
    final limits = _strings(data['known_limits']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          margin: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Validation snapshot'),
              Text(
                'Committed from ${data['source'] ?? 'the backend validation artifact'}',
                style: TextStyle(color: t.textTertiary, fontSize: 11),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricTile(
                    label: 'TEST AUC',
                    value: _number(validation['auc_test'], 4),
                  ),
                  _MetricTile(
                    label: 'TRAIN / TEST',
                    value: '${validation['n_train'] ?? '—'} / ${validation['n_test'] ?? '—'}',
                  ),
                  _MetricTile(
                    label: 'SCORED COVERAGE',
                    value: '${_number(percentages['SCORED'], 2)}%',
                  ),
                  _MetricTile(
                    label: 'VALIDATION PROFILES',
                    value: '${coverage['n_profiles'] ?? '—'}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'AUC measures ranking on a held-out synthetic test set. It is not a promise of real-world accuracy, approval odds, or probability calibration.',
                style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 8),
              Text(
                'Coverage: ${counts['SCORED'] ?? 0} scored (${_number(percentages['SCORED'], 2)}%), ${counts['LOW_CONFIDENCE'] ?? 0} low confidence, ${counts['NOT_ASSESSABLE'] ?? 0} not assessable.',
                style: TextStyle(color: t.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('How it was trained'),
              Text(
                '${training['algorithm'] ?? 'Logistic regression'} on synthetic business cash-flow data. The model uses ${predictors.length} predictive features; the committed run used seed ${validation['train_seed'] ?? '—'} and a profile-level train/test split.',
                style: TextStyle(color: t.textPrimary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 10),
              Text(
                'Predictive inputs',
                style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: predictors.map((name) => _Chip(label: name)).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                'Digital-versus-cash channel shares are excluded from scoring. The pipeline also excludes held-out transactions from feature construction and training.',
                style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Sufficiency gate - before scoring'),
              _GateRow(
                label: 'NOT ASSESSABLE',
                detail: 'Either fewer than ${gate['not_assessable_below_months'] ?? 6} months of history or fewer than ${_number(gate['not_assessable_below_transactions_per_month'], 0)} real transactions per month.',
                color: t.negative,
              ),
              const SizedBox(height: 10),
              _GateRow(
                label: 'LOW CONFIDENCE',
                detail: 'Assessable trail, but not both more than ${gate['full_confidence_requires_months_above'] ?? 12} months and more than ${_number(gate['full_confidence_requires_transactions_per_month_above'], 0)} transactions per month.',
                color: t.warning,
              ),
              const SizedBox(height: 10),
              _GateRow(
                label: 'FULL',
                detail: 'Requires more than ${gate['full_confidence_requires_months_above'] ?? 12} months and more than ${_number(gate['full_confidence_requires_transactions_per_month_above'], 0)} real transactions per month.',
                color: t.positive,
              ),
              const SizedBox(height: 10),
              Text(
                'The gate runs before the model. Too little data produces no score, rather than treating missing history as a poor borrower signal.',
                style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Fairness guardrails'),
              for (final control in testGuardrails)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: t.positive),
                      const SizedBox(width: 8),
                      Expanded(child: Text(control, style: TextStyle(color: t.textSecondary, fontSize: 12, height: 1.4))),
                    ],
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 10),
                title: Text('Excluded fields (${excluded.length})', style: TextStyle(color: t.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                children: [
                  Text(excluded.join(', '), style: TextStyle(color: t.textSecondary, fontSize: 11, height: 1.5)),
                ],
              ),
              Text(
                '${fairness['limitation'] ?? 'Group-level fairness metrics are not available.'}',
                style: TextStyle(color: t.warning, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Known limits - stability check'),
              Text(
                '${stability['n_swung_more_than_threshold'] ?? 0} of ${stability['n_checked'] ?? 0} profiles moved by more than ${stability['swing_threshold'] ?? 20} score points when the raw model was given 12 instead of 24 months. Mean absolute change: ${_number(stability['mean_abs_diff'], 2)}; maximum: ${_number(stability['max_abs_diff'], 0)}.',
                style: TextStyle(color: t.textPrimary, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                '${stability['caveat'] ?? 'This sensitivity check is not production behavior.'}',
                style: TextStyle(color: t.textSecondary, fontSize: 11, height: 1.45),
              ),
              const SizedBox(height: 10),
              for (final limit in limits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('- $limit', style: TextStyle(color: t.textSecondary, fontSize: 11.5, height: 1.4)),
                ),
            ],
          ),
        ),
        Text(
          'Research prototype on synthetic data. Decision support only; the lender remains responsible for the final lending decision.',
          style: TextStyle(color: t.textTertiary, fontSize: 11, height: 1.45),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 135,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.pillFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textTertiary, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: t.textPrimary, fontSize: 19, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _GateRow extends StatelessWidget {
  final String label;
  final String detail;
  final Color color;
  const _GateRow({required this.label, required this.detail, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 10.5)),
          ),
          Expanded(child: Text(detail, style: TextStyle(color: context.tokens.textSecondary, fontSize: 12, height: 1.4))),
        ],
      );
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: context.tokens.pillFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.tokens.hairline),
        ),
        child: Text(label, style: TextStyle(color: context.tokens.textSecondary, fontSize: 10)),
      );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

String _number(Object? value, int decimals) {
  if (value is! num) return '—';
  return value.toStringAsFixed(decimals);
}
