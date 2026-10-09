import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/credify_theme.dart';
import '../../widgets/credify_shell_widgets.dart';
import 'scroll_timeline.dart';

/// Landing-only palette (dark mode): deep black stage, indigo flower, white
/// text. Neon red is reserved for later accents.
class LandingPalette {
  static const Color deepBlack = Color(0xFF08070B);
  static const Color neonRed = Color(0xFFF32E35);
  static const Color indigo = Color(0xFF4E50DE);
  static const Color white = Color(0xFFFFFFFF);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Small label text (eyebrows, captions): white in dark mode, accent in
  /// light mode.
  static Color label(BuildContext context) =>
      isDark(context) ? white : context.tokens.accentA;

  /// Headline text: white in dark mode.
  static Color headline(BuildContext context) =>
      isDark(context) ? white : context.tokens.textPrimary;
}

/// Shared motion state for everything on the landing stage.
///
/// [coord] is the smoothed frame coordinate (0..5). [intro] runs 0→1 once on
/// first load so the cover wordmark can rise in before any scrolling.
class LandingScope extends InheritedWidget {
  final ValueListenable<double> coord;
  final ValueListenable<double> intro;
  final Listenable both;
  final bool reduceMotion;

  const LandingScope({
    super.key,
    required this.coord,
    required this.intro,
    required this.both,
    required this.reduceMotion,
    required super.child,
  });

  static LandingScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LandingScope>()!;

  @override
  bool updateShouldNotify(LandingScope old) =>
      old.coord != coord ||
      old.intro != intro ||
      old.both != both ||
      old.reduceMotion != reduceMotion;
}

enum RevealFx { rise, clip, fade, line }

/// Shows [child] while frame [scene] is on stage: opacity = reveal(coord,
/// scene, delay), plus the [fx] movement. Fully hidden elements are not
/// painted and ignore pointers.
class Reveal extends StatelessWidget {
  final int scene;
  final RevealFx fx;
  final double delay;

  /// When set, also gates the element on the one-time intro (0..1) so it
  /// rises in on first load; larger values come in later.
  final double? introDelay;
  final Widget child;

  const Reveal({
    super.key,
    required this.scene,
    this.fx = RevealFx.rise,
    this.delay = 0,
    this.introDelay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final s = LandingScope.of(context);
    return ListenableBuilder(
      listenable: s.both,
      child: child,
      builder: (context, child) {
        final c = s.coord.value;
        var v = reveal(c, scene, delay);
        var dir = c < scene ? 1.0 : -1.0;
        if (introDelay != null && s.intro.value < 1) {
          final iv = clamp01((s.intro.value - introDelay!) / 0.4);
          if (iv < v) {
            v = iv;
            dir = 1;
          }
        }

        Widget out = child!;
        switch (fx) {
          case RevealFx.rise:
            final blur = !s.reduceMotion && v > 0 && v <= 0.99;
            out = Transform.translate(
              offset: Offset(0, (1 - v) * 34 * dir),
              child: ImageFiltered(
                enabled: blur,
                imageFilter: ImageFilter.blur(
                  sigmaX: math.max(0.001, (1 - v) * 8),
                  sigmaY: math.max(0.001, (1 - v) * 8),
                ),
                child: out,
              ),
            );
          case RevealFx.clip:
            out = ClipRect(
              child: FractionalTranslation(
                translation: Offset(0, (1 - v) * dir),
                child: out,
              ),
            );
          case RevealFx.fade:
            break;
          case RevealFx.line:
            out = Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.diagonal3Values(v, 1, 1),
              child: out,
            );
        }
        return IgnorePointer(
          ignoring: v <= 0,
          child: Opacity(opacity: v, child: out),
        );
      },
    );
  }
}

/// Layout facts every frame needs.
class LandingLayout {
  final Size size;
  final EdgeInsets safe;

  const LandingLayout(this.size, this.safe);

  double get w => size.width;
  double get h => size.height;

  /// Under 720 px: smaller type, no side nav.
  bool get narrow => w < 720;

  /// Portrait: text in the lower half, ribbons above (matches keyAt's tall).
  bool get tall => h > w * 1.05;

  /// Width reserved for the side nav's frame names.
  static const double navGutter = 120;

  double get pad => narrow ? 20 : math.max(32, w * 0.06);
  double get topBar => safe.top + 72;
  double get bottomPad => safe.bottom + (narrow ? 28 : 44);
}

/// The six frames, stacked on the stage.
class LandingFrames extends StatelessWidget {
  final LandingLayout layout;
  final VoidCallback onEnter;
  final VoidCallback? onTrySimulation;

  const LandingFrames({
    super.key,
    required this.layout,
    required this.onEnter,
    this.onTrySimulation,
  });

  @override
  Widget build(BuildContext context) {
    final l = layout;
    return Stack(
      children: [
        Positioned.fill(child: _CoverFrame(l)),
        Positioned.fill(child: _ProblemFrame(l)),
        Positioned.fill(
          child: _ModuleFrame(
            l,
            scene: 2,
            right: false,
            eyebrow: '01 · Momentum credit signal',
            title: 'Scored from cash flow, not a credit history.',
            bullets: const [
              'Ten cash-flow features read from UPI transaction history',
              'Reason codes a credit team can actually discuss',
              'A sufficiency gate: too little data means no score, not a guess',
            ],
          ),
        ),
        Positioned.fill(
          child: _ModuleFrame(
            l,
            scene: 3,
            right: true,
            eyebrow: '02 · Scam Guard',
            title: 'One check before the UPI PIN.',
            bullets: const [
              'Flags fake KYC, refund bait and brand impersonation',
              'Runs on the phone in milliseconds — the payment details stay '
                  'on the device',
              'Can plug into any UPI app (see the simulation)',
            ],
          ),
        ),
        Positioned.fill(
          child: _ModuleFrame(
            l,
            scene: 4,
            right: false,
            eyebrow: '03 · Climate cash-flow',
            title: "Rain shouldn't sink a small business.",
            bullets: const [
              "Uses IMD's heavy-rain threshold of 64.5 mm a day",
              'Estimates the cash-flow hit and a resilience buffer',
              'Never changes the credit score',
            ],
          ),
        ),
        Positioned.fill(
          child: _StartFrame(
            l,
            onEnter: onEnter,
            onTrySimulation: onTrySimulation,
          ),
        ),
      ],
    );
  }
}

/// Places a frame's content box, scaling it down rather than overflowing
/// when a short window cannot fit it.
class _FrameBox extends StatelessWidget {
  final LandingLayout l;
  final Alignment alignment;
  final double maxWidth;
  final double maxHeight;
  final Widget child;

  const _FrameBox({
    required this.l,
    required this.alignment,
    required this.maxWidth,
    required this.maxHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Keep clear of the right-side frame nav on wide layouts.
    final right = l.pad + (l.narrow ? 0 : LandingLayout.navGutter);
    final availW = math.max(0.0, l.w - l.pad - right);
    final availH = math.max(0.0, l.h - l.topBar - l.bottomPad);
    final mw = math.min(maxWidth, availW);
    final mh = math.min(maxHeight, availH);
    return Padding(
      padding: EdgeInsets.fromLTRB(l.pad, l.topBar, right, l.bottomPad),
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: mw, maxHeight: mh),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            child: SizedBox(width: mw, child: child),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final double size;

  const _Bullet(this.text, {required this.size});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: size * 0.55, right: 12),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              gradient: t.accentGradient,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: size,
                height: 1.45,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 0 · Cover ───────────────────────────────────────────────────────────────

class _CoverFrame extends StatelessWidget {
  final LandingLayout l;
  const _CoverFrame(this.l);

  static const _list = [
    'Credit signal without a bureau file',
    'Scam Guard before the UPI PIN',
    'Climate cash-flow stress',
    'Research prototype · synthetic data',
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final big = math.min(l.w * 0.21, l.h * 0.33);
    final body = l.narrow ? 14.5 : 16.0;

    final paragraph = Reveal(
      scene: 0,
      delay: 0.15,
      introDelay: 0.55,
      child: Text(
        "Financial resilience for India's informal workers and "
        'micro-businesses — fair credit, safer payments and climate-ready '
        'cash flow, in one toolkit.',
        style: TextStyle(fontSize: body, height: 1.55, color: t.textSecondary),
      ),
    );
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _list.length; i++)
          Reveal(
            scene: 0,
            fx: RevealFx.fade,
            delay: 0.2 + i * 0.05,
            introDelay: 0.6 + i * 0.05,
            child: _Bullet(_list[i], size: body - 1),
          ),
      ],
    );

    return _FrameBox(
      l: l,
      alignment: Alignment.bottomLeft,
      maxWidth: 1600,
      maxHeight: l.tall ? l.h * 0.6 : l.h * 0.66,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(
            scene: 0,
            fx: RevealFx.fade,
            delay: 0.1,
            introDelay: 0.1,
            child: Text(
              'VISTERA 2026 · Team Clover',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: LandingPalette.label(context),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            label: 'Momentum',
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 'Momentum'.length; i++)
                      Reveal(
                        scene: 0,
                        delay: i * 0.03,
                        introDelay: i * 0.06,
                        child: Text(
                          'Momentum'[i],
                          style: TextStyle(
                            fontSize: big,
                            height: 1.0,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -big * 0.045,
                            color: LandingPalette.headline(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: l.narrow ? 14 : 22),
          if (l.narrow || l.tall) ...[
            paragraph,
            const SizedBox(height: 14),
            list,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: paragraph),
                const SizedBox(width: 48),
                Expanded(flex: 4, child: list),
              ],
            ),
        ],
      ),
    );
  }
}

// ── 1 · Problem ─────────────────────────────────────────────────────────────

class _ProblemFrame extends StatelessWidget {
  final LandingLayout l;
  const _ProblemFrame(this.l);

  static const _lines = [
    'Invisible to credit bureaus.',
    "One scam away from losing a week's earnings.",
    'One heavy-rain week away from missing an EMI.',
  ];

  @override
  Widget build(BuildContext context) {
    final size = l.narrow ? 27.0 : math.min(l.w * 0.04, 54.0);
    return _FrameBox(
      l: l,
      alignment: Alignment.bottomLeft,
      maxWidth: l.narrow || l.tall ? l.w : l.w * 0.8,
      // Below the swirl's centre (mid-screen on this frame).
      maxHeight: l.h * 0.42,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Reveal(
                scene: 1,
                fx: RevealFx.clip,
                delay: i * 0.15,
                child: _HoverLine(_lines[i], size: size),
              ),
            ),
          const SizedBox(height: 18),
          Reveal(
            scene: 1,
            fx: RevealFx.fade,
            delay: 0.45,
            child: Text(
              'Three risks. One borrower. Momentum looks at all three.',
              style: TextStyle(
                fontSize: l.narrow ? 14 : 16,
                fontWeight: FontWeight.w600,
                color: LandingPalette.label(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A problem line: all three sit dim and medium-weight; the one under the
/// mouse turns bold and dark (white in dark mode).
class _HoverLine extends StatefulWidget {
  final String text;
  final double size;
  const _HoverLine(this.text, {required this.size});

  @override
  State<_HoverLine> createState() => _HoverLineState();
}

class _HoverLineState extends State<_HoverLine> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.of(context).disableAnimations;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedDefaultTextStyle(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
        style: TextStyle(
          fontSize: widget.size,
          height: 1.15,
          fontWeight: _hover ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: -widget.size * 0.025,
          color: _hover ? LandingPalette.headline(context) : t.textSecondary,
        ),
        child: Text(widget.text),
      ),
    );
  }
}

// ── 2–4 · Modules ───────────────────────────────────────────────────────────

class _ModuleFrame extends StatelessWidget {
  final LandingLayout l;
  final int scene;
  final bool right;
  final String eyebrow;
  final String title;
  final List<String> bullets;

  const _ModuleFrame(
    this.l, {
    required this.scene,
    required this.right,
    required this.eyebrow,
    required this.title,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final stacked = l.narrow || l.tall;
    final titleSize = stacked ? 30.0 : math.min(l.w * 0.036, 54.0);
    final body = l.narrow ? 14.5 : 16.0;

    return _FrameBox(
      l: l,
      // Wide: beside the swirl, never over its centre. Tall: lower half.
      alignment: stacked
          ? Alignment.bottomLeft
          : (right ? Alignment.centerRight : Alignment.centerLeft),
      maxWidth: stacked ? 640 : l.w * 0.4,
      maxHeight: stacked ? l.h * 0.48 : l.h,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(
            scene: scene,
            fx: RevealFx.fade,
            child: Text(
              eyebrow.toUpperCase(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: LandingPalette.label(context),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Reveal(
            scene: scene,
            fx: RevealFx.line,
            delay: 0.05,
            child: Container(
              width: 56,
              height: 2,
              decoration: BoxDecoration(gradient: t.accentGradient),
            ),
          ),
          const SizedBox(height: 18),
          Reveal(
            scene: scene,
            delay: 0.08,
            child: Text(
              title,
              style: TextStyle(
                fontSize: titleSize,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -titleSize * 0.025,
                color: LandingPalette.headline(context),
              ),
            ),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < bullets.length; i++)
            Reveal(
              scene: scene,
              delay: 0.14 + i * 0.06,
              child: _Bullet(bullets[i], size: body),
            ),
        ],
      ),
    );
  }
}

// ── 5 · Start ───────────────────────────────────────────────────────────────

class _StartFrame extends StatelessWidget {
  final LandingLayout l;
  final VoidCallback onEnter;
  final VoidCallback? onTrySimulation;

  const _StartFrame(
    this.l, {
    required this.onEnter,
    required this.onTrySimulation,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final titleSize = math.min(l.w * 0.085, l.h * 0.13);

    final primary = SizedBox(
      width: 240,
      child: CredifyButton(
        label: 'Open the demo',
        icon: Icons.arrow_forward_rounded,
        onPressed: onEnter,
      ),
    );
    final secondary = onTrySimulation == null
        ? null
        : SizedBox(
            width: 290,
            child: CredifyButton(
              label: 'Try the Scam Guard simulation',
              icon: Icons.shield_outlined,
              ghost: true,
              onPressed: onTrySimulation,
            ),
          );

    return _FrameBox(
      l: l,
      alignment: Alignment.bottomCenter,
      maxWidth: 820,
      maxHeight: l.h * 0.6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Reveal(
            scene: 5,
            child: Text(
              'Build momentum.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: titleSize,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -titleSize * 0.035,
                color: LandingPalette.headline(context),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Reveal(
            scene: 5,
            delay: 0.1,
            child: l.narrow
                ? Column(
                    children: [
                      primary,
                      if (secondary != null) ...[
                        const SizedBox(height: 12),
                        secondary,
                      ],
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      primary,
                      if (secondary != null) ...[
                        const SizedBox(width: 14),
                        secondary,
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 30),
          Reveal(
            scene: 5,
            fx: RevealFx.fade,
            delay: 0.2,
            child: Text(
              'Research prototype on synthetic data. Not a lending decision '
              'system, not a regulated entity — the final lending decision '
              'rests with the lender.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
