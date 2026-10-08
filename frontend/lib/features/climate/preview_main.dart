import 'package:flutter/material.dart';
import '../../theme/credify_theme.dart';
import 'climate_http_service.dart';
import 'climate_screen.dart';
import 'mock_climate_service.dart';

const bool _live = bool.fromEnvironment('CLIMATE_LIVE');
const String _apiUrl = String.fromEnvironment('CLIMATE_API_URL', defaultValue: 'http://localhost:8000');

void main() => runApp(MaterialApp(debugShowCheckedModeBanner: false, title: 'Climate Impact', theme: CredifyTheme.light, darkTheme: CredifyTheme.dark, themeMode: ThemeMode.dark, home: ClimateScreen(service: _live ? ClimateHttpService(baseUrl: _apiUrl) : MockClimateService())));
