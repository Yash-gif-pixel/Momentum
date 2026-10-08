import 'package:credify_frontend/features/climate/climate_api_service.dart';
import 'package:credify_frontend/features/climate/climate_models.dart';
import 'package:credify_frontend/features/climate/climate_portfolio_panel.dart';
import 'package:credify_frontend/features/climate/mock_climate_service.dart';
import 'package:credify_frontend/theme/credify_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PortfolioService implements ClimateApiService {
  final MockClimateService _mock = MockClimateService();
  final List<String> portfolioRequests = [];
  bool failPortfolio = false;

  @override
  Future<ClimateOptions> fetchOptions() => _mock.fetchOptions();

  @override
  Future<ClimateImpact> fetchImpact(String profileId, String scenarioId) =>
      _mock.fetchImpact(profileId, scenarioId);

  @override
  Future<ClimatePortfolio> fetchPortfolio(String scenarioId) {
    portfolioRequests.add(scenarioId);
    if (failPortfolio) {
      throw const ClimateApiException(
        statusCode: 503,
        message: 'Portfolio service unavailable',
      );
    }
    return _mock.fetchPortfolio(scenarioId);
  }
}

Widget _app(
  ClimateApiService service, {
  void Function(String profileId)? onBorrowerTap,
}) => MaterialApp(
  theme: CredifyTheme.dark,
  home: Scaffold(
    body: SingleChildScrollView(
      child: ClimatePortfolioPanel(
        service: service,
        onBorrowerTap: onBorrowerTap,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'portfolio panel shows summary totals, exposure order, and status chips',
    (tester) async {
      await tester.pumpWidget(_app(_PortfolioService()));
      await tester.pumpAndSettle();

      expect(find.text('Borrowers exposed'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Estimated cash at risk'), findsOneWidget);
      expect(find.text('₹22,400'), findsOneWidget);
      expect(find.text('Suggested buffers'), findsOneWidget);
      expect(find.text('₹16,800'), findsOneWidget);

      final firstExposedY = tester.getTopLeft(find.text('arjun_kirana_006')).dy;
      final secondExposedY = tester
          .getTopLeft(find.text('lakshmi_vendor_001'))
          .dy;
      final notExposedY = tester.getTopLeft(find.text('meera_tailor_005')).dy;
      expect(firstExposedY, lessThan(secondExposedY));
      expect(secondExposedY, lessThan(notExposedY));
      expect(find.text('Exposed'), findsNWidgets(2));
      expect(find.text('Not exposed'), findsOneWidget);
      expect(find.text('Mumbai'), findsOneWidget);
      expect(find.text('Pune'), findsOneWidget);
      expect(find.text('Does not change credit scores'), findsOneWidget);
    },
  );

  testWidgets('changing scenario re-fetches and updates portfolio totals', (
    tester,
  ) async {
    final service = _PortfolioService();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(find.text('₹22,400'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flash flood').last);
    await tester.pumpAndSettle();

    expect(service.portfolioRequests, ['heavy_rain_week', 'flash_flood']);
    expect(find.text('₹33,215'), findsOneWidget);
  });

  testWidgets('tapping a borrower calls the callback with its profile id', (
    tester,
  ) async {
    String? tappedProfileId;
    await tester.pumpWidget(
      _app(
        _PortfolioService(),
        onBorrowerTap: (profileId) => tappedProfileId = profileId,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('meera_tailor_005'));
    expect(tappedProfileId, 'meera_tailor_005');
  });

  testWidgets('portfolio errors show the message and Retry requests again', (
    tester,
  ) async {
    final service = _PortfolioService()..failPortfolio = true;
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Portfolio service unavailable'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(service.portfolioRequests, ['heavy_rain_week']);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(service.portfolioRequests, ['heavy_rain_week', 'heavy_rain_week']);
  });
}
