import 'climate_models.dart';

abstract class ClimateApiService {
  Future<ClimateOptions> fetchOptions();
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId);
}

class ClimateApiException implements Exception {
  final int? statusCode;
  final String message;
  const ClimateApiException({this.statusCode, required this.message});
  @override
  String toString() => message;
}
