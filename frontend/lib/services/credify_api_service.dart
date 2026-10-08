import '../models/analyze_response.dart';
import '../models/portfolio_response.dart';

abstract class CredifyApiService {
  Future<AnalyzeResponse> analyzeProfile(String profileId);
  Future<PortfolioResponse> getPortfolio();
  List<String> getAvailableProfileIds();
}
