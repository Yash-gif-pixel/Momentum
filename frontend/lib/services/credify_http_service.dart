import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/analyze_response.dart';
import '../models/portfolio_response.dart';
import 'credify_api_service.dart';

class CredifyHttpService implements CredifyApiService {
  final String baseUrl;
  final http.Client _client;

  CredifyHttpService({
    this.baseUrl = 'http://localhost:8000',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  List<String> getAvailableProfileIds() {
    // Mirrors DEMO_PROFILES in backend/api/dependencies.py. Kept in sync by
    // hand: the backend exposes no endpoint that lists demo profiles, so
    // adding one there without adding it here leaves it unreachable from the UI.
    return const [
      'lakshmi_vendor_001',
      'meera_tailor_005',
      'arjun_kirana_006',
      'thin_file_002',
      'dormancy_gap_003',
      'ramesh_carpentry_004',
      'uniform_trail_007',
    ];
  }

  @override
  Future<AnalyzeResponse> analyzeProfile(String profileId) async {
    final uri = Uri.parse('$baseUrl/api/profiles/$profileId');
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return AnalyzeResponse.fromJson(data);
    } else {
      throw Exception(
        'Failed to analyze profile ($profileId): HTTP ${response.statusCode} - ${response.body}',
      );
    }
  }

  @override
  Future<PortfolioResponse> getPortfolio() async {
    final uri = Uri.parse('$baseUrl/api/portfolio');
    final response = await _client.get(uri);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return PortfolioResponse.fromJson(data);
    } else {
      throw Exception(
        'Failed to load portfolio metrics: HTTP ${response.statusCode} - ${response.body}',
      );
    }
  }
}
