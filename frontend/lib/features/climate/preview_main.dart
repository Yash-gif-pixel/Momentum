import 'package:flutter/material.dart';

import '../../theme/credify_theme.dart';
import 'climate_api_service.dart';
import 'climate_borrower_tip.dart';
import 'climate_http_service.dart';
import 'climate_portfolio_panel.dart';
import 'climate_screen.dart';
import 'climate_stress_card.dart';
import 'mock_climate_service.dart';

const bool _live = bool.fromEnvironment('CLIMATE_LIVE');
const String _apiUrl = String.fromEnvironment(
  'CLIMATE_API_URL',
  defaultValue: 'http://localhost:8000',
);

void main() {
  final service = _live
      ? ClimateHttpService(baseUrl: _apiUrl)
      : MockClimateService();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Climate Impact',
      theme: CredifyTheme.light,
      darkTheme: CredifyTheme.dark,
      themeMode: ThemeMode.dark,
      home: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Climate Impact'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Full screen'),
                Tab(text: 'Borrower card'),
                Tab(text: 'Portfolio'),
                Tab(text: 'Borrower tip'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              ClimateScreen(service: service),
              _BorrowerCardPreview(service: service),
              _PortfolioPreview(service: service),
              _BorrowerTipPreview(service: service),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BorrowerCardPreview extends StatelessWidget {
  const _BorrowerCardPreview({required this.service});

  final ClimateApiService service;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Lakshmi Vendor', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Card(
        color: context.tokens.cardFill,
        child: const ListTile(
          leading: Icon(Icons.speed),
          title: Text('Credit score'),
          subtitle: Text('712 · Good'),
        ),
      ),
      ClimateStressCard(service: service, profileId: 'lakshmi_vendor_001'),
    ],
  );
}

class _PortfolioPreview extends StatelessWidget {
  const _PortfolioPreview({required this.service});

  final ClimateApiService service;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [ClimatePortfolioPanel(service: service)],
  );
}

class _BorrowerTipPreview extends StatelessWidget {
  const _BorrowerTipPreview({required this.service});

  final ClimateApiService service;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      ClimateBorrowerTip(service: service, profileId: 'lakshmi_vendor_001'),
    ],
  );
}
