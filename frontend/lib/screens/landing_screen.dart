import 'package:flutter/material.dart';
import '../theme/credify_theme.dart';
import '../widgets/credify_mark.dart';
import '../widgets/credify_shell_widgets.dart';
import '../widgets/signal_waveform.dart';

/// Landing page. Every figure on this screen is either a real backend value or
/// an explicit statement that the data is synthetic — no invented metrics.
class LandingScreen extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onEnter;

  const LandingScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 900;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 32 : 20,
                vertical: 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    children: [
                      _NavBar(
                        isDark: isDark,
                        onToggleTheme: onToggleTheme,
                        onEnter: onEnter,
                        wide: wide,
                      ),
                      const SizedBox(height: 14),
                      const _FactStrip(),
                      SizedBox(height: wide ? 54 : 40),

                      // ── Hero ───────────────────────────────────────────
                      const HeroPill(
                        icon: Icons.science_outlined,
                        label: 'RESEARCH PROTOTYPE · SYNTHETIC DATA',
                      ),
                      const SizedBox(height: 22),
                      _HeroTitle(wide: wide, tokens: t),
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          'Ten predictive cash-flow features read from 24 months '
                          'of Account-Aggregator-style transaction history, '
                          'scored by a transparent logistic scorecard. Built for '
                          'MSMEs a bureau has never heard of.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: t.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ),
                      SizedBox(height: wide ? 56 : 42),

                      // ── Signal visualiser ──────────────────────────────
                      _SignalCard(wide: wide),
                      SizedBox(height: wide ? 72 : 52),

                      // ── Pillars ────────────────────────────────────────
                      Text(
                        'HOW THE SIGNAL IS BUILT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: t.accentA,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Scoring a borrower with\nno bureau record.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: wide ? 32 : 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1.15,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const _Pillars(),
                      SizedBox(height: wide ? 72 : 52),

                      // ── Closing ────────────────────────────────────────
                      Text(
                        'Assessable is not the same\nas safe.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: wide ? 30 : 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1.2,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Text(
                          'Credify returns a score, the reasons behind it, and '
                          'an honest refusal when the data is too thin. The '
                          'lending decision stays with the lender.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: t.textSecondary,
                            height: 1.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: 240,
                        child: CredifyButton(
                          label: 'Open the demo',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: onEnter,
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTitle extends StatelessWidget {
  final bool wide;
  final CredifyTokens tokens;

  const _HeroTitle({required this.wide, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final size = wide ? 52.0 : 36.0;
    return Column(
      children: [
        Text(
          'Credit signal for the',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
            height: 1.1,
            color: tokens.textPrimary,
          ),
        ),
        ShaderMask(
          shaderCallback: (b) => LinearGradient(
            colors: [tokens.accentA, tokens.accentB],
          ).createShader(b),
          child: Text(
            'credit invisible.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.8,
              height: 1.1,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavBar extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onEnter;
  final bool wide;

  const _NavBar({
    required this.isDark,
    required this.onToggleTheme,
    required this.onEnter,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: t.accentGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(child: CredifyMark(size: 21)),
        ),
        const SizedBox(width: 10),
        Text(
          'Credify',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: t.textPrimary,
          ),
        ),
        if (wide) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.negative.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: t.negative.withValues(alpha: 0.3)),
            ),
            child: Text(
              'PROTOTYPE',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: t.negative,
              ),
            ),
          ),
        ],
        const Spacer(),
        ThemeTogglePill(isDark: isDark, onToggle: onToggleTheme),
      ],
    );
  }
}

/// Only verifiable facts here — model metrics and the data source.
class _FactStrip extends StatelessWidget {
  const _FactStrip();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      radius: 12,
      child: Wrap(
        spacing: 22,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: t.accentA, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                'MODEL CARD',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
          _fact(context, 'PROFILES', '521'),
          _fact(context, 'FEATURES', '10'),
          _fact(context, 'HOLDOUT AUC', '0.96'),
          _fact(context, 'DATA', 'Synthetic'),
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    final t = context.tokens;
    return Text.rich(
      TextSpan(
        text: '$label: ',
        style: TextStyle(fontSize: 10.5, color: t.textTertiary),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: t.accentA,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  final bool wide;
  const _SignalCard({required this.wide});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final metrics = Column(
      children: [
        _MetricTile(
          icon: Icons.show_chart_rounded,
          title: 'VITALITY SIGNAL',
          value: '91.0',
          sub: '/ 100',
          detail:
              'Lakshmi, a street food vendor with no bureau file — scored from '
              'transaction behaviour alone.',
          accent: t.positive,
        ),
        const SizedBox(height: 12),
        _MetricTile(
          icon: Icons.block_rounded,
          title: 'SUFFICIENCY GATE',
          value: 'NOT ASSESSABLE',
          sub: '',
          detail:
              'A 4-month thin file returns no score at all. Refusing to guess '
              'is a feature, not a failure.',
          accent: t.negative,
        ),
      ],
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: t.accentA, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash flow where a bureau sees nothing',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      'Simulated Account Aggregator ingestion',
                      style:
                          TextStyle(fontSize: 11, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 3, child: SignalWaveform()),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: metrics),
                ],
              ),
            )
          else ...[
            const SignalWaveform(),
            const SizedBox(height: 16),
            metrics,
          ],
          const SizedBox(height: 20),
          Divider(color: t.hairline, height: 1),
          const SizedBox(height: 16),
          Wrap(
            spacing: 26,
            runSpacing: 12,
            children: const [
              _Status(label: 'MODEL', value: 'Logistic scorecard'),
              _Status(label: 'EXPLAINABILITY', value: 'Per-feature reason codes'),
              _Status(label: 'BUREAU DEPENDENCY', value: 'None'),
              _Status(label: 'OUTCOMES', value: 'Scored / Low conf. / Gated'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final String label;
  final String value;
  const _Status({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600, color: t.textTertiary)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: t.textPrimary)),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String sub;
  final String detail;
  final Color accent;

  const _MetricTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.sub,
    required this.detail,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.hairline,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
              ),
              Icon(icon, size: 13, color: accent),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: value.length > 8 ? 15 : 22,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(sub,
                    style:
                        TextStyle(fontSize: 11, color: t.textTertiary)),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Text(
            detail,
            style: TextStyle(
                fontSize: 11, color: t.textSecondary, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Pillars extends StatelessWidget {
  const _Pillars();

  static const _items = [
    (
      Icons.insights_rounded,
      'Ten predictive features',
      'Inflow consistency, return rate, dormancy, buffer days and more — read '
          'from months 1–24 of transaction history. Twelve are extracted; two '
          'are withheld from the model on purpose, and no demographic or '
          'geographic field can ever become a feature.',
      'Fairness enforced by test',
    ),
    (
      Icons.rule_folder_outlined,
      'Coefficients become reasons',
      'A logistic scorecard was chosen over a boosted ensemble precisely so '
          'each weight maps to a sentence a credit officer can read and argue '
          'with.',
      'Per-feature reason codes',
    ),
    (
      Icons.shield_outlined,
      'A gate on data, not on risk',
      'Outcomes gate on whether there is enough history to judge — never on how '
          'risky the business looks. A risky but well-documented borrower still '
          'gets scored.',
      'Scored · Low confidence · Gated',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    if (!wide) {
      return Column(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _PillarCard(item: _items[i]),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: _PillarCard(item: _items[i])),
          ],
        ],
      ),
    );
  }
}

/// Hover reads as depth, not affordance: these cards are not tap targets, so
/// the cursor stays an arrow and there is no ripple. Promising a click they
/// do not honour would be worse than no hover at all.
///
/// Each card owns its own hover state, so the three light independently.
class _PillarCard extends StatelessWidget {
  final (IconData, String, String, String) item;
  const _PillarCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return HoverLift(
      builder: (context, hovered) => GlassCard(
        padding: const EdgeInsets.all(22),
        borderColor: hovered ? t.accentA.withValues(alpha: 0.42) : null,
        transitionDuration: const Duration(milliseconds: 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.accentA.withValues(alpha: hovered ? 0.26 : 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.$1, color: t.accentA, size: 19),
            ),
            const SizedBox(height: 18),
            Text(
              item.$2,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.$3,
              style: TextStyle(
                  fontSize: 12.5, color: t.textSecondary, height: 1.55),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Flexible(
                  child: Text(
                    item.$4,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: t.accentA,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

