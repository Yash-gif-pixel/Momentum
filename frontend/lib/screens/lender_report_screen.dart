import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../features/climate/climate_api_service.dart';
import '../features/climate/climate_models.dart';
import '../models/analyze_response.dart';
import '../models/persona_meta.dart';
import '../services/report_print.dart';
import '../state/app_state.dart';
import '../theme/credify_theme.dart';
import '../widgets/credify_shell_widgets.dart';

class LenderReportScreen extends StatefulWidget {
  final ClimateApiService climateService;
  const LenderReportScreen({super.key, required this.climateService});

  @override
  State<LenderReportScreen> createState() => _LenderReportScreenState();
}

class _LenderReportScreenState extends State<LenderReportScreen> {
  static const _scenarioId = 'heavy_rain_week';
  String? _climateProfileId;
  Future<ClimateImpact>? _climateImpact;

  Future<void> _print(AnalyzeResponse result, ClimateImpact? impact) async {
    final state = context.read<AppState>();
    if (!state.consentApproved || state.analyzeResult == null) return;
    final meta = PersonaMeta.forId(state.selectedProfileId);
    final html = _reportHtml(
      meta.name,
      state.selectedProfileId,
      result,
      impact,
      state.consentReceiptId,
    );
    final opened = await printReportHtml(html);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(opened
            ? 'In the print dialog, choose Save as PDF.'
            : 'Printing is available in the web app. Use this print-ready page on this device.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Consumer<AppState>(
        builder: (context, state, _) {
          final result = state.analyzeResult;
          if (!state.consentApproved || result == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Lender report')),
              body: const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('This report is unavailable. Active borrower consent and a current analysis are required.'),
                ),
              ),
            );
          }
          if (_climateProfileId != state.selectedProfileId) {
            _climateProfileId = state.selectedProfileId;
            _climateImpact = widget.climateService
                .fetchImpact(state.selectedProfileId, _scenarioId);
          }
          final t = context.tokens;
          final meta = PersonaMeta.forId(state.selectedProfileId);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Lender report'),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Expanded(child: SectionLabel('CREDIFY · LENDER REVIEW REPORT')),
                          Text(DateFormat('dd MMM yyyy').format(DateTime.now()), style: TextStyle(color: t.textTertiary, fontSize: 11)),
                        ]),
                        Text(meta.name, style: TextStyle(color: t.textPrimary, fontSize: 23, fontWeight: FontWeight.w800)),
                        Text('Profile ${state.selectedProfileId} · Consent ${state.consentReceiptId ?? 'active'}', style: TextStyle(color: t.textSecondary, fontSize: 11)),
                        const Divider(height: 26),
                        _ReportSection(title: 'Credit signal', child: _scoreSummary(result)),
                        _ReportSection(title: 'Reasons', child: _reasons(result)),
                        _ReportSection(
                          title: 'Sufficiency status',
                          child: Text(
                            '${result.outcome.replaceAll('_', ' ')}${result.coverageReason == null ? '' : ' — ${result.coverageReason}'}',
                            style: TextStyle(color: t.textSecondary, height: 1.4),
                          ),
                        ),
                        _ReportSection(
                          title: 'Climate stress · heavy rain week',
                          child: FutureBuilder<ClimateImpact>(
                            future: _climateImpact,
                            builder: (context, snapshot) => Text(
                              snapshot.hasData
                                  ? 'Hypothetical cash-flow impact: ${_inr(snapshot.data!.estimatedCashflowImpactInr)}; ${snapshot.data!.disruptedDays} disrupted days. This scenario is separate from credit scoring.'
                                  : 'Climate scenario estimate unavailable. It is a separate hypothetical cash-flow view and never changes the credit score.',
                              style: TextStyle(color: t.textSecondary, height: 1.4),
                            ),
                          ),
                        ),
                        const Divider(height: 26),
                        Text(
                          'Disclaimer: Research prototype using synthetic/demo data. This score is decision support only, not a lending decision or guarantee. A lender must independently assess the application. Climate stress is hypothetical and does not affect the credit score. A saved PDF is a separate copy and cannot be recalled by revoking consent.',
                          style: TextStyle(color: t.textTertiary, fontSize: 10.5, height: 1.45),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              ClimateImpact? impact;
                              try { impact = await _climateImpact; } catch (_) {}
                              if (mounted) await _print(result, impact);
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Print / Save as PDF'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

  Widget _scoreSummary(AnalyzeResponse result) {
    return Wrap(spacing: 24, runSpacing: 10, children: [
      _Fact(label: 'OUTCOME', value: result.outcome.replaceAll('_', ' ')),
      _Fact(label: 'VITALITY SCORE', value: result.vitalityScore?.toStringAsFixed(0) ?? 'Not scored'),
      _Fact(label: 'BAND', value: result.band?.replaceAll('_', ' ') ?? '—'),
      _Fact(label: 'CONFIDENCE', value: result.confidence ?? '—'),
      if (result.authenticityCheck != null)
        _Fact(label: 'DATA PATTERN', value: result.authenticityCheck!.status.replaceAll('_', ' ')),
    ]);
  }

  Widget _reasons(AnalyzeResponse result) {
    final entries = [
      ...result.reasonCodes.strengths.map((reason) => ('Strength', reason)),
      ...result.reasonCodes.concerns.map((reason) => ('Concern', reason)),
    ].take(4).toList();
    if (entries.isEmpty) return const Text('No reason codes returned for this assessment.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text('• ${entry.$1}: ${entry.$2.statement} (${entry.$2.feature})', style: TextStyle(color: context.tokens.textSecondary, height: 1.35)),
      )).toList(),
    );
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _ReportSection({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(title),
          const SizedBox(height: 7),
          child,
        ]),
      );
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: context.tokens.textTertiary, fontSize: 9, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(color: context.tokens.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      );
}

String _inr(double value) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(value);

String _reportHtml(String name, String profileId, AnalyzeResponse result, ClimateImpact? impact, String? receipt) {
  String escape(String value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
  final reasons = [
    ...result.reasonCodes.strengths.map((r) => 'Strength: ${r.statement} (${r.feature})'),
    ...result.reasonCodes.concerns.map((r) => 'Concern: ${r.statement} (${r.feature})'),
  ].take(4).map((r) => '<li>${escape(r)}</li>').join();
  final climate = impact == null
      ? 'Unavailable; hypothetical stress is separate from credit scoring.'
      : 'Hypothetical cash-flow impact ${escape(_inr(impact.estimatedCashflowImpactInr))}; ${impact.disruptedDays} disrupted days. Does not affect credit score.';
  final status = '${result.outcome}${result.coverageReason == null ? '' : ' — ${result.coverageReason}'}';
  return '''<!doctype html><html><head><meta charset="utf-8"><title>Credify lender report</title><style>
  @page{size:A4;margin:16mm}body{font:12px Arial,sans-serif;color:#17202a;max-width:760px;margin:0 auto}h1{font-size:24px;margin:5px 0}h2{font-size:14px;border-bottom:1px solid #ccd2d8;padding-bottom:5px;margin:18px 0 7px}.muted{color:#53616f}.facts{display:flex;gap:30px;flex-wrap:wrap}.facts b{display:block;font-size:9px;color:#53616f}.facts span{font-size:16px;font-weight:bold}.disclaimer{border-top:1px solid #ccd2d8;margin-top:18px;padding-top:10px;font-size:10px;line-height:1.45}@media print{body{max-width:none}}
  </style></head><body><div class="muted">CREDIFY · LENDER REVIEW REPORT · ${DateFormat('dd MMM yyyy').format(DateTime.now())}</div><h1>${escape(name)}</h1><div class="muted">Profile ${escape(profileId)} · Consent ${escape(receipt ?? 'active')}</div>
  <h2>Credit signal</h2><div class="facts"><div><b>OUTCOME</b><span>${escape(result.outcome.replaceAll('_', ' '))}</span></div><div><b>VITALITY SCORE</b><span>${result.vitalityScore?.toStringAsFixed(0) ?? 'Not scored'}</span></div><div><b>BAND</b><span>${escape(result.band?.replaceAll('_', ' ') ?? '—')}</span></div><div><b>CONFIDENCE</b><span>${escape(result.confidence ?? '—')}</span></div></div>
  <h2>Reasons</h2><ul>${reasons.isEmpty ? '<li>No reason codes returned.</li>' : reasons}</ul><h2>Sufficiency status</h2><p>${escape(status)}</p><h2>Climate stress · heavy rain week</h2><p>${climate}</p>
  <div class="disclaimer">Research prototype using synthetic/demo data. This score is decision support only, not a lending decision or guarantee. A lender must independently assess the application. Climate stress is hypothetical and does not affect the credit score. A saved PDF is a separate copy and cannot be recalled by revoking consent.</div></body></html>''';
}
