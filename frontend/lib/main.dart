import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'mock_backend.dart';
import 'services/credify_api_service.dart';
import 'services/credify_http_service.dart';
import 'state/app_state.dart';
import 'theme/credify_theme.dart';
import 'screens/lender_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/portfolio_screen.dart';
import 'screens/borrower_screen.dart';
import 'screens/landing_screen.dart';
import 'widgets/credify_mark.dart';
import 'widgets/credify_shell_widgets.dart';

// Live FastAPI backend by default. Run with --dart-define=CREDIFY_USE_MOCK=true
// to use the in-memory MockBackend instead, and --dart-define=CREDIFY_API_URL=...
// to point at a server other than http://localhost:8000.
const bool _useMock = bool.fromEnvironment('CREDIFY_USE_MOCK');
const String _kBaseUrl =
    String.fromEnvironment('CREDIFY_API_URL', defaultValue: 'http://localhost:8000');

void main() {
  final CredifyApiService service =
      _useMock ? MockBackend() : CredifyHttpService(baseUrl: _kBaseUrl);

  runApp(CredifyApp(service: service));
}

class CredifyApp extends StatefulWidget {
  final CredifyApiService service;
  const CredifyApp({super.key, required this.service});

  @override
  State<CredifyApp> createState() => _CredifyAppState();
}

class _CredifyAppState extends State<CredifyApp> {
  bool _isDark = true;
  bool _entered = false;

  void _toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(widget.service),
      child: MaterialApp(
        title: 'Credify — Alternative Credit Signal',
        debugShowCheckedModeBanner: false,
        theme: CredifyTheme.light,
        darkTheme: CredifyTheme.dark,
        themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
        home: _entered
            ? CredifyShell(
                service: widget.service,
                isDark: _isDark,
                onToggleTheme: _toggleTheme,
              )
            : LandingScreen(
                isDark: _isDark,
                onToggleTheme: _toggleTheme,
                onEnter: () => setState(() => _entered = true),
              ),
      ),
    );
  }
}

class CredifyShell extends StatefulWidget {
  final CredifyApiService service;
  final bool isDark;
  final VoidCallback onToggleTheme;

  const CredifyShell({
    super.key,
    required this.service,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<CredifyShell> createState() => _CredifyShellState();
}

class _CredifyShellState extends State<CredifyShell> {
  // Tab order: 0 = Consent, 1 = Lender, 2 = Borrower, 3 = Portfolio
  int _tabIndex = 0;

  void goToTab(int index) => setState(() => _tabIndex = index);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  isDark: widget.isDark,
                  onToggleTheme: widget.onToggleTheme,
                ),
                const _DisclaimerStrip(),
                Expanded(
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      ConsentScreen(onContinue: () => goToTab(1)),
                      const LenderScreen(),
                      const BorrowerScreen(),
                      PortfolioScreen(service: widget.service),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: _GlassNavBar(
                index: _tabIndex,
                onSelect: goToTab,
                tokens: t,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const _TopBar({required this.isDark, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: t.accentGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: CredifyMark(size: 17)),
          ),
          const SizedBox(width: 10),
          Text(
            'CREDIFY',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: t.negative.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.negative.withValues(alpha: 0.3)),
            ),
            child: Text(
              'PROTOTYPE',
              style: TextStyle(
                color: t.negative,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          ThemeTogglePill(isDark: isDark, onToggle: onToggleTheme),
        ],
      ),
    );
  }
}

class _DisclaimerStrip extends StatelessWidget {
  const _DisclaimerStrip();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 13, color: t.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Research prototype on synthetic data. Not a lending decision '
              'system, not a regulated entity — the final lending decision '
              'rests with the lender.',
              style: TextStyle(
                color: t.textTertiary,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final CredifyTokens tokens;

  const _GlassNavBar({
    required this.index,
    required this.onSelect,
    required this.tokens,
  });

  static const _items = [
    (Icons.verified_user_outlined, Icons.verified_user, 'Consent'),
    (Icons.account_balance_outlined, Icons.account_balance, 'Lender'),
    (Icons.person_outline, Icons.person, 'Borrower'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Portfolio'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 32;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: width > 440 ? 440 : width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: tokens.navFill,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: tokens.glassBorder, width: 1),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: i == index ? _items[i].$2 : _items[i].$1,
                    label: _items[i].$3,
                    active: i == index,
                    tokens: tokens,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final CredifyTokens tokens;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? tokens.accentA.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? tokens.textPrimary : tokens.textTertiary,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: active ? tokens.textPrimary : tokens.textTertiary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
