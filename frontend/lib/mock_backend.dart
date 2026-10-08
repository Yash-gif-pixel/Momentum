// mock_backend.dart — Credify · TechSurge 2k26 · PS-F02
//
// This file is a MOCK data layer. It returns hard-coded Dart objects that
// match the exact JSON contract of the FastAPI backend (POST /api/analyze
// and GET /api/portfolio). When the live backend is ready, the only change
// needed is to swap MockBackend for CredifyHttpService in main.dart
// (the `_useMock` flag). No screen widget should need changes.
//
// ─── Portfolio figures are ILLUSTRATIVE PLACEHOLDERS ──────────────────────
// The numbers in _mockPortfolio (142 profiles, 82.4 % coverage, 0.764 AUC,
// band distribution, histogram) are invented to give the UI something
// realistic to render during development. They are NOT based on the actual
// feature_table.csv or any real evaluation run. They will be replaced by
// live values returned by the backend in a later integration task.
// ──────────────────────────────────────────────────────────────────────────

import 'models/analyze_response.dart';
import 'models/portfolio_response.dart';
import 'services/credify_api_service.dart';

class MockBackend implements CredifyApiService {
  static const String disclaimerText =
      'Research prototype on synthetic data. Not a lending decision system. '
      'Decision-support signal only — final lending decision rests with the lender.';

  // ── Profile fixtures ─────────────────────────────────────────────────────

  /// Example 1 — SCORED · "Lakshmi" street-food vendor.
  /// Vitality score 91.0 matches the real trained model's score for demo_lakshmi.
  static final Map<String, dynamic> _lakshmi = {
    'profile_id': 'lakshmi_vendor_001',
    'outcome': 'SCORED',
    'vitality_score': 91.0,
    'band': 'strong_candidate',
    'confidence': 'high',
    'reason_codes': {
      'strengths': [
        {
          'feature': 'ontime_bill_payment_rate',
          'statement':
              'Rent and utility bills were paid on time 100% of the time.',
          'contribution': 0.729,
        },
        {
          'feature': 'months_would_cover_emi_of_last_24',
          'statement':
              'Income would have covered an indicative loan payment in 24 of the last 24 months.',
          'contribution': 0.549,
        },
        {
          'feature': 'trend_last_6_months',
          'statement':
              'Income is up 19% versus the same period a year earlier — growing.',
          'contribution': 0.514,
        },
      ],
      'concerns': [],
    },
    'affordability': {
      'indicative_emi_low': 8989.59,
      'indicative_emi_high': 13606.68,
      'months_would_cover_emi_of_last_24': 24,
    },
    'monthly_cashflow': [
      {'month': '2024-03', 'inflow': 42000.0, 'outflow': 32000.0, 'net': 10000.0},
      {'month': '2024-04', 'inflow': 43500.0, 'outflow': 32500.0, 'net': 11000.0},
      {'month': '2024-05', 'inflow': 44000.0, 'outflow': 33000.0, 'net': 11000.0},
      {'month': '2024-06', 'inflow': 45500.0, 'outflow': 34000.0, 'net': 11500.0},
      {'month': '2024-07', 'inflow': 46000.0, 'outflow': 34500.0, 'net': 11500.0},
      {'month': '2024-08', 'inflow': 47500.0, 'outflow': 35000.0, 'net': 12500.0},
      {'month': '2024-09', 'inflow': 47000.0, 'outflow': 35000.0, 'net': 12000.0},
      {'month': '2024-10', 'inflow': 53000.0, 'outflow': 37500.0, 'net': 15500.0},
      {'month': '2024-11', 'inflow': 55000.0, 'outflow': 38000.0, 'net': 17000.0},
      {'month': '2024-12', 'inflow': 50000.0, 'outflow': 36500.0, 'net': 13500.0},
      {'month': '2025-01', 'inflow': 48000.0, 'outflow': 35000.0, 'net': 13000.0},
      {'month': '2025-02', 'inflow': 51000.0, 'outflow': 36000.0, 'net': 15000.0},
    ],
    'coverage_reason': null,
    'disclaimer': disclaimerText,
  };

  /// Example 2 — NOT_ASSESSABLE · thin file (from task spec verbatim).
  static final Map<String, dynamic> _thinFile = {
    'profile_id': 'thin_file_002',
    'outcome': 'NOT_ASSESSABLE',
    'vitality_score': null,
    'band': null,
    'confidence': null,
    'reason_codes': {'strengths': [], 'concerns': []},
    'affordability': {
      'indicative_emi_low': 0.0,
      'indicative_emi_high': 0.0,
      'months_would_cover_emi_of_last_24': 0,
    },
    'monthly_cashflow': [],
    'coverage_reason':
        'Only 3 months of transaction history available — below the minimum '
        'needed to generate a reliable signal.',
    'disclaimer': disclaimerText,
  };

  /// Example 3 — NOT_ASSESSABLE · account dormancy gap (constructed to spec).
  static final Map<String, dynamic> _dormancyGap = {
    'profile_id': 'dormancy_gap_003',
    'outcome': 'NOT_ASSESSABLE',
    'vitality_score': null,
    'band': null,
    'confidence': null,
    'reason_codes': {'strengths': [], 'concerns': []},
    'affordability': {
      'indicative_emi_low': 0.0,
      'indicative_emi_high': 0.0,
      'months_would_cover_emi_of_last_24': 0,
    },
    'monthly_cashflow': [],
    'coverage_reason':
        'Account shows a 140-day consecutive dormancy gap exceeding the '
        '90-day maximum — the digital trail is too incomplete to generate a '
        'reliable signal.',
    'disclaimer': disclaimerText,
  };

  /// Example 4 — LOW_CONFIDENCE · seasonal carpentry business.
  static final Map<String, dynamic> _ramesh = {
    'profile_id': 'ramesh_carpentry_004',
    'outcome': 'LOW_CONFIDENCE',
    'vitality_score': 51.0,
    'band': 'manual_review',
    'confidence': 'low',
    'reason_codes': {
      'strengths': [
        {
          'feature': 'affordability',
          'statement':
              'Could absorb the indicative EMI in 16 of the last 24 months '
              'during active trading seasons.',
          'contribution': 0.14,
        },
      ],
      'concerns': [
        {
          'feature': 'income_volatility',
          'statement':
              'Revenue fluctuates sharply by over 55% month-on-month between '
              'off-season and peak season.',
          'contribution': -0.18,
        },
        {
          'feature': 'buffer_days',
          'statement':
              'Operating balance drops below 3 days of business expenses at '
              'month-ends on several occasions.',
          'contribution': -0.12,
        },
      ],
    },
    'affordability': {
      'indicative_emi_low': 1800.0,
      'indicative_emi_high': 2900.0,
      'months_would_cover_emi_of_last_24': 16,
    },
    'monthly_cashflow': [
      {'month': '2024-09', 'inflow': 32000.0, 'outflow': 29000.0, 'net': 3000.0},
      {'month': '2024-10', 'inflow': 58000.0, 'outflow': 42000.0, 'net': 16000.0},
      {'month': '2024-11', 'inflow': 31000.0, 'outflow': 29500.0, 'net': 1500.0},
      {'month': '2024-12', 'inflow': 28000.0, 'outflow': 27000.0, 'net': 1000.0},
      {'month': '2025-01', 'inflow': 33000.0, 'outflow': 30000.0, 'net': 3000.0},
      {'month': '2025-02', 'inflow': 36000.0, 'outflow': 31000.0, 'net': 5000.0},
    ],
    'coverage_reason':
        'Signal is low-confidence due to high revenue volatility and sporadic '
        'digital reconciliation — refer for manual review.',
    'disclaimer': disclaimerText,
  };

  static final Map<String, Map<String, dynamic>> _profiles = {
    'lakshmi_vendor_001': _lakshmi,
    'thin_file_002': _thinFile,
    'dormancy_gap_003': _dormancyGap,
    'ramesh_carpentry_004': _ramesh,
  };

  // ── Portfolio fixture ────────────────────────────────────────────────────
  //
  // ALL NUMBERS BELOW ARE ILLUSTRATIVE PLACEHOLDERS.
  // They are invented figures used during frontend development to give the
  // Portfolio screen something realistic to render. They are NOT derived from
  // feature_table.csv, a real model evaluation, or any actual dataset run.
  // They WILL be replaced by live values from GET /api/portfolio once the
  // FastAPI backend is integrated.
  //
  static final Map<String, dynamic> _mockPortfolio = {
    'n_profiles': 142, // PLACEHOLDER — replace with live backend value
    'coverage_pct': 82.4, // PLACEHOLDER — replace with live backend value
    'auc': 0.764, // PLACEHOLDER — replace with live backend value
    'band_distribution': {
      'strong_candidate': 68, // PLACEHOLDER
      'manual_review': 49, // PLACEHOLDER
      'high_risk_referral': 25, // PLACEHOLDER
    },
    'score_histogram': [
      {'bucket': '0–20', 'count': 8}, // PLACEHOLDER
      {'bucket': '20–40', 'count': 17}, // PLACEHOLDER
      {'bucket': '40–60', 'count': 49}, // PLACEHOLDER
      {'bucket': '60–80', 'count': 52}, // PLACEHOLDER
      {'bucket': '80–100', 'count': 16}, // PLACEHOLDER
    ],
  };

  // ── CredifyApiService implementation ─────────────────────────────────────

  @override
  List<String> getAvailableProfileIds() => _profiles.keys.toList();

  @override
  Future<AnalyzeResponse> analyzeProfile(String profileId) async {
    // Simulate realistic API round-trip latency so UI loading states are visible
    await Future.delayed(const Duration(milliseconds: 400));
    final data = _profiles[profileId] ?? _lakshmi;
    return AnalyzeResponse.fromJson(data);
  }

  @override
  Future<PortfolioResponse> getPortfolio() async {
    await Future.delayed(const Duration(milliseconds: 350));
    return PortfolioResponse.fromJson(_mockPortfolio);
  }
}
