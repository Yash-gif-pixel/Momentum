import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:credify_frontend/models/analyze_response.dart';
import 'package:credify_frontend/models/portfolio_response.dart';
import 'package:credify_frontend/mock_backend.dart';
import 'package:credify_frontend/services/credify_http_service.dart';

void main() {
  group('AnalyzeResponse model', () {
    test('deserializes SCORED response correctly', () {
      const json = {
        'profile_id': 'lakshmi_vendor_001',
        'outcome': 'SCORED',
        'vitality_score': 71.5,
        'band': 'strong_candidate',
        'confidence': 'high',
        'reason_codes': {
          'strengths': [
            {
              'feature': 'income_regularity',
              'statement': 'Very steady income.',
              'contribution': 0.31,
            }
          ],
          'concerns': [
            {
              'feature': 'buffer_days',
              'statement': 'Thin cash buffer.',
              'contribution': -0.08,
            }
          ]
        },
        'affordability': {
          'indicative_emi_low': 2800.0,
          'indicative_emi_high': 4200.0,
          'months_would_cover_emi_of_last_24': 22,
        },
        'monthly_cashflow': [
          {'month': '2025-01', 'inflow': 48000.0, 'outflow': 35000.0, 'net': 13000.0},
        ],
        'coverage_reason': null,
        'disclaimer': 'Research prototype.',
      };

      final response = AnalyzeResponse.fromJson(json);

      expect(response.profileId, 'lakshmi_vendor_001');
      expect(response.outcome, 'SCORED');
      expect(response.isScored, isTrue);
      expect(response.isNotAssessable, isFalse);
      expect(response.vitalityScore, closeTo(71.5, 0.001));
      expect(response.band, 'strong_candidate');
      expect(response.confidence, 'high');
      expect(response.reasonCodes.strengths, hasLength(1));
      expect(response.reasonCodes.strengths[0].feature, 'income_regularity');
      expect(response.reasonCodes.strengths[0].contribution, closeTo(0.31, 0.001));
      expect(response.reasonCodes.concerns, hasLength(1));
      expect(response.reasonCodes.concerns[0].contribution, closeTo(-0.08, 0.001));
      expect(response.affordability.indicativeEmiLow, closeTo(2800.0, 0.001));
      expect(response.affordability.indicativeEmiHigh, closeTo(4200.0, 0.001));
      expect(response.affordability.monthsWouldCoverEmiOfLast24, 22);
      expect(response.monthlyCashflow, hasLength(1));
      expect(response.monthlyCashflow[0].month, '2025-01');
      expect(response.monthlyCashflow[0].inflow, closeTo(48000.0, 0.001));
      expect(response.coverageReason, isNull);
    });

    test('deserializes NOT_ASSESSABLE response correctly', () {
      const json = {
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
        'coverage_reason': 'Only 3 months of history available.',
        'disclaimer': 'Research prototype.',
      };

      final response = AnalyzeResponse.fromJson(json);

      expect(response.isNotAssessable, isTrue);
      expect(response.isScored, isFalse);
      expect(response.vitalityScore, isNull);
      expect(response.band, isNull);
      expect(response.confidence, isNull);
      expect(response.coverageReason, 'Only 3 months of history available.');
      expect(response.monthlyCashflow, isEmpty);
      expect(response.reasonCodes.strengths, isEmpty);
      expect(response.reasonCodes.concerns, isEmpty);
    });

    test('round-trips through toJson/fromJson', () {
      const originalJson = {
        'profile_id': 'test_001',
        'outcome': 'SCORED',
        'vitality_score': 55.0,
        'band': 'manual_review',
        'confidence': 'low',
        'reason_codes': {'strengths': [], 'concerns': []},
        'affordability': {
          'indicative_emi_low': 1000.0,
          'indicative_emi_high': 2000.0,
          'months_would_cover_emi_of_last_24': 10,
        },
        'monthly_cashflow': [],
        'coverage_reason': 'Low confidence.',
        'disclaimer': 'Prototype.',
      };

      final obj = AnalyzeResponse.fromJson(originalJson);
      final roundTripped = AnalyzeResponse.fromJson(obj.toJson());

      expect(roundTripped.profileId, obj.profileId);
      expect(roundTripped.outcome, obj.outcome);
      expect(roundTripped.vitalityScore, obj.vitalityScore);
      expect(roundTripped.band, obj.band);
    });
  });

  group('PortfolioResponse model', () {
    test('deserializes correctly', () {
      const json = {
        'n_profiles': 100,
        'coverage_pct': 78.5,
        'auc': 0.72,
        'band_distribution': {
          'strong_candidate': 40,
          'manual_review': 35,
          'high_risk_referral': 25,
        },
        'score_histogram': [
          {'bucket': '0-20', 'count': 5},
          {'bucket': '20-40', 'count': 15},
          {'bucket': '40-60', 'count': 30},
          {'bucket': '60-80', 'count': 35},
          {'bucket': '80-100', 'count': 15},
        ],
      };

      final response = PortfolioResponse.fromJson(json);

      expect(response.nProfiles, 100);
      expect(response.coveragePct, closeTo(78.5, 0.001));
      expect(response.auc, closeTo(0.72, 0.001));
      expect(response.bandDistribution.strongCandidate, 40);
      expect(response.bandDistribution.manualReview, 35);
      expect(response.bandDistribution.highRiskReferral, 25);
      expect(response.scoreHistogram, hasLength(5));
      expect(response.scoreHistogram[2].bucket, '40-60');
      expect(response.scoreHistogram[2].count, 30);
    });

    test('handles null auc', () {
      const json = {
        'n_profiles': 10,
        'coverage_pct': 50.0,
        'auc': null,
        'band_distribution': {
          'strong_candidate': 5,
          'manual_review': 3,
          'high_risk_referral': 2,
        },
        'score_histogram': [],
      };

      final response = PortfolioResponse.fromJson(json);
      expect(response.auc, isNull);
    });
  });

  group('MockBackend', () {
    late MockBackend backend;

    setUp(() {
      backend = MockBackend();
    });

    test('returns all 4 profile ids', () {
      final ids = backend.getAvailableProfileIds();
      expect(ids, containsAll([
        'lakshmi_vendor_001',
        'thin_file_002',
        'dormancy_gap_003',
        'ramesh_carpentry_004',
      ]));
    });

    test('analyzeProfile returns SCORED for lakshmi', () async {
      final result = await backend.analyzeProfile('lakshmi_vendor_001');
      expect(result.outcome, 'SCORED');
      expect(result.vitalityScore, closeTo(91.0, 0.001));
      expect(result.band, 'strong_candidate');
      expect(result.disclaimer, isNotEmpty);
    });

    test('analyzeProfile returns NOT_ASSESSABLE for thin_file', () async {
      final result = await backend.analyzeProfile('thin_file_002');
      expect(result.outcome, 'NOT_ASSESSABLE');
      expect(result.vitalityScore, isNull);
      expect(result.coverageReason, isNotEmpty);
    });

    test('analyzeProfile returns NOT_ASSESSABLE for dormancy_gap', () async {
      final result = await backend.analyzeProfile('dormancy_gap_003');
      expect(result.outcome, 'NOT_ASSESSABLE');
      expect(result.vitalityScore, isNull);
    });

    test('analyzeProfile returns LOW_CONFIDENCE for ramesh', () async {
      final result = await backend.analyzeProfile('ramesh_carpentry_004');
      expect(result.outcome, 'LOW_CONFIDENCE');
      expect(result.confidence, 'low');
      expect(result.band, 'manual_review');
    });

    test('getPortfolio returns valid data', () async {
      final portfolio = await backend.getPortfolio();
      expect(portfolio.nProfiles, greaterThan(0));
      expect(portfolio.coveragePct, greaterThan(0));
      expect(portfolio.scoreHistogram, isNotEmpty);
    });

    test('disclaimer is non-empty on all profiles', () async {
      for (final id in backend.getAvailableProfileIds()) {
        final result = await backend.analyzeProfile(id);
        expect(result.disclaimer, isNotEmpty,
            reason: 'Disclaimer missing on $id');
      }
    });

    test('SCORED profiles have non-null vitalityScore and band', () async {
      final ids = backend.getAvailableProfileIds();
      for (final id in ids) {
        final result = await backend.analyzeProfile(id);
        if (result.outcome == 'SCORED') {
          expect(result.vitalityScore, isNotNull,
              reason: '$id is SCORED but vitalityScore is null');
          expect(result.band, isNotNull,
              reason: '$id is SCORED but band is null');
        }
      }
    });

    test('NOT_ASSESSABLE profiles have null vitalityScore', () async {
      final ids = backend.getAvailableProfileIds();
      for (final id in ids) {
        final result = await backend.analyzeProfile(id);
        if (result.outcome == 'NOT_ASSESSABLE') {
          expect(result.vitalityScore, isNull,
              reason: '$id is NOT_ASSESSABLE but vitalityScore is non-null');
        }
      }
    });
  });

  group('CredifyHttpService', () {
    test('analyzeProfile GETs /api/profiles/{id} (not POST /api/analyze)', () async {
      late http.Request sent;
      final service = CredifyHttpService(
        client: MockClient((req) async {
          sent = req;
          return http.Response(
            jsonEncode({
              'profile_id': 'thin_file_002',
              'outcome': 'NOT_ASSESSABLE',
              'vitality_score': null,
              'band': null,
              'confidence': null,
              'reason_codes': {'strengths': [], 'concerns': []},
              'affordability': {
                'indicative_emi_low': 30203.87,
                'indicative_emi_high': 36915.84,
                'months_would_cover_emi_of_last_24': 5,
              },
              'monthly_cashflow': [],
              'coverage_reason': 'Not assessable: only 5 months of history.',
              'disclaimer': 'Research prototype on synthetic data.',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await service.analyzeProfile('thin_file_002');

      expect(sent.method, 'GET');
      expect(sent.url.toString(), 'http://localhost:8000/api/profiles/thin_file_002');
      expect(sent.headers['Accept'], 'application/json');
      expect(result.profileId, 'thin_file_002');
      expect(result.outcome, 'NOT_ASSESSABLE');
    });

    test('analyzeProfile throws on a non-2xx response', () async {
      final service = CredifyHttpService(
        client: MockClient((_) async => http.Response('{"detail":"unknown"}', 404)),
      );
      expect(service.analyzeProfile('nope'), throwsException);
    });
  });
}
