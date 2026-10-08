import 'dart:convert';
import 'package:http/http.dart' as http;
import 'climate_api_service.dart';
import 'climate_models.dart';

class ClimateHttpService implements ClimateApiService {
  final String baseUrl;
  final http.Client _client;
  ClimateHttpService({this.baseUrl = 'http://localhost:8000', http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path', queryParameters: query);
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    late http.Response response;
    try {
      response = await _client.get(uri, headers: {'Accept': 'application/json'});
    } catch (error) {
      throw ClimateApiException(message: 'Network error: $error');
    }
    Map<String, dynamic>? body;
    try { body = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClimateApiException(statusCode: response.statusCode, message: body?['detail']?.toString() ?? 'Request failed (HTTP ${response.statusCode})');
    }
    if (body == null) throw const ClimateApiException(message: 'Invalid response from climate service.');
    return body;
  }

  @override
  Future<ClimateOptions> fetchOptions() async => ClimateOptions.fromJson(await _get(_uri('/api/climate/scenarios')));

  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) async => ClimateImpact.fromJson(await _get(_uri('/api/climate/impact/${Uri.encodeComponent(profileId)}', {'scenario_id': scenarioId})));
}
