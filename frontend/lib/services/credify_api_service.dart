import '../models/analyze_response.dart';
import '../models/portfolio_response.dart';

abstract class CredifyApiService {
  Future<AnalyzeResponse> analyzeProfile(String profileId);
  Future<PortfolioResponse> getPortfolio();
  Future<Map<String, dynamic>> getModelCard() async => const {};
  List<String> getAvailableProfileIds();
}
