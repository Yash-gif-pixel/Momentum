import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/credify_theme.dart';
import '../widgets/credify_mark.dart';
import '../widgets/credify_shell_widgets.dart';
import 'landing/landing_frames.dart';
import 'landing/interactive_glow_button.dart';
import 'landing/momentum_particles.dart';
import 'landing/scroll_timeline.dart';

/// Scroll-driven landing: six frames told over a pinned "stage".
///
/// The page is a tall scrollable; the stage is positioned at the current
/// scroll offset so it stays put while scroll progress drives the frame
/// coordinate (see scroll_timeline.dart). No figures here beyond the copy
/// the team signed off — nothing invented.
class LandingScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onEnter;

  /// Opens the Scam Guard simulation. The button is hidden when null.
  final VoidCallback? onTrySimulation;

  const LandingScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.onEnter,
    this.onTrySimulation,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

const _kNavLabels = [
  '01 Cover',
  '02 Problem',
  '03 Credit',
  '04 Scam Guard',
  '05 Climate',
  '06 Start',
];

/// Seconds for the one-time cover intro.
const double _kIntroSeconds = 1.4;

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _coord = ValueNotifier<double>(0);
  final ValueNotifier<Offset?> _pointer = ValueNotifier<Offset?>(null);
  final ValueNotifier<double> _intro = ValueNotifier<double>(0);
  late final Listenable _both = Listenable.merge([_coord, _intro]);

  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _target = 0;
  bool _reduce = false;
  double _viewportH = 0;
  double _totalH = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.of(context).disableAnimations;
    if (_reduce) {
      _ticker?.stop();
      _intro.value = 1;
      _coord.value = _target;
    } else {
      _ensureTicking();
    }
  }

  double get _travel => math.max(0, _totalH - _viewportH);

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _target = sceneCoord(
      progressFrom(_scroll.offset, _totalH, _viewportH),
      kLandingScenes,
      kLandingHold,
    );
    if (_reduce) {
      _coord.value = _target;
    } else {
      _ensureTicking();
    }
  }

  void _ensureTicking() {
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) {
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  void _onTick(Duration now) {
    final dt = math.min((now - _last).inMicroseconds / 1e6, 0.1);
    _last = now;
    if (dt <= 0) return;

    if (_intro.value < 1) {
      _intro.value = clamp01(_intro.value + dt / _kIntroSeconds);
    }
    final diff = _target - _coord.value;
    if (diff.abs() < 1e-4) {
      if (_coord.value != _target) _coord.value = _target;
      if (_intro.value >= 1) _ticker!.stop();
    } else {
      _coord.value += diff * (1 - math.exp(-dt * 9));
    }
  }

  /// Scrolls to frame [k] (0..5).
  void _goTo(int k) {
    if (!_scroll.hasClients) return;
    final offset = k / (kLandingScenes - 1) * _travel;
    if (_reduce) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _coord.dispose();
    _pointer.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: widget.isDark ? LandingPalette.deepBlack : t.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final vh = size.height;
          final totalH = vh * (1 + (kLandingScenes - 1) * kSceneScroll);
          if (vh != _viewportH || totalH != _totalH) {
            _viewportH = vh;
            _totalH = totalH;
            // Window resized: recompute the frame for the same offset.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _onScroll();
            });
          }
          final layout = LandingLayout(size, mq.padding);

          final stage = LandingScope(
            coord: _coord,
            intro: _intro,
            both: _both,
            reduceMotion: _reduce,
            child: _Stage(
              layout: layout,
              coord: _coord,
              pointer: _pointer,
              isDark: widget.isDark,
              onToggleTheme: widget.onToggleTheme,
              onEnter: widget.onEnter,
              onTrySimulation: widget.onTrySimulation,
              onGoTo: _goTo,
            ),
          );

          return SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              width: size.width,
              height: totalH,
              child: Stack(
                children: [
                  // Only the stage's position follows the scroll; its
                  // contents listen to the frame coordinate instead.
                  AnimatedBuilder(
                    animation: _scroll,
                    child: stage,
                    builder: (context, child) {
                      final offset = _scroll.hasClients
                          ? _scroll.offset
                                .clamp(0.0, math.max(0.0, totalH - vh))
                                .toDouble()
                          : 0.0;
                      return Positioned(
                        top: offset,
                        left: 0,
                        width: size.width,
                        height: vh,
                        child: child!,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  final LandingLayout layout;
  final ValueNotifier<double> coord;

  /// Mouse position (global) over the stage, for the particles to react to.
  final ValueNotifier<Offset?> pointer;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onEnter;
  final VoidCallback? onTrySimulation;
  final ValueChanged<int> onGoTo;

  const _Stage({
    required this.layout,
    required this.coord,
    required this.pointer,
    required this.isDark,
    required this.onToggleTheme,
    required this.onEnter,
    required this.onTrySimulation,
    required this.onGoTo,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = layout;
    // The whole stage reports the mouse, so dots react even under the text.
    return MouseRegion(
      opaque: false,
      onHover: (e) => pointer.value = e.position,
      onExit: (_) => pointer.value = null,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: isDark ? LandingPalette.deepBlack : t.bg),
          ),
          Positioned.fill(
            child: ExcludeSemantics(
              // Dense enough for the ₹ on the cover coin to read clearly. Light
              // mode needs more: the dots read fainter on the pale background.
              child: MomentumParticles(
                coord: coord,
                count: isDark ? 1800 : 2600,
                // The other theme's layout is prepared ahead of a toggle.
                warmCount: isDark ? 2600 : 1800,
                pointer: pointer,
                // Keep the dot morph animation, but make the dots ignore hover.
                interactive: false,
              ),
            ),
          ),
          Positioned.fill(
            child: LandingFrames(
              layout: l,
              onEnter: onEnter,
              onTrySimulation: onTrySimulation,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: l.safe.bottom + 10,
            child: _ScrollHint(coord: coord),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _TopBar(
              layout: l,
              isDark: isDark,
              onToggleTheme: onToggleTheme,
              onEnter: onEnter,
            ),
          ),
          if (!l.narrow)
            Positioned(
              right: math.max(14, l.pad * 0.4),
              top: l.topBar,
              bottom: l.bottomPad,
              child: Center(
                child: _FrameNav(coord: coord, onGoTo: onGoTo),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final LandingLayout layout;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onEnter;

  const _TopBar({
    required this.layout,
    required this.isDark,
    required this.onToggleTheme,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = layout;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        l.narrow ? 16 : l.pad,
        l.safe.top + 16,
        l.narrow ? 16 : l.pad,
        0,
      ),
      child: Row(
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
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'MOMENTUM',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: t.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Scales down instead of overflowing on very narrow windows.
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemeTogglePill(isDark: isDark, onToggle: onToggleTheme),
                    const SizedBox(width: 10),
                    InteractiveGlowButton(
                      key: const ValueKey('landing-topbar-enter'),
                      label: 'Open the demo',
                      onPressed: onEnter,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollHint extends StatelessWidget {
  final ValueListenable<double> coord;
  const _ScrollHint({required this.coord});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: coord,
        builder: (context, c, child) =>
            Opacity(opacity: clamp01(1 - c * 3), child: child),
        child: Center(
          child: Text(
            'Scroll ↓',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: t.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FrameNav extends StatelessWidget {
  final ValueListenable<double> coord;
  final ValueChanged<int> onGoTo;

  const _FrameNav({required this.coord, required this.onGoTo});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: coord,
      builder: (context, c, _) {
        final active = c.round().clamp(0, kLandingScenes - 1);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _kNavLabels.length; i++)
              _NavTick(
                key: ValueKey('landing-nav-$i'),
                label: _kNavLabels[i],
                active: i == active,
                onTap: () => onGoTo(i),
              ),
          ],
        );
      },
    );
  }
}

class _NavTick extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTick({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavTick> createState() => _NavTickState();
}

class _NavTickState extends State<_NavTick> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.of(context).disableAnimations;
    final d = reduce ? Duration.zero : const Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.label,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            // Names only: the active frame is bold and in the label colour,
            // the rest dim and brighten on hover.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: d,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.4,
                  color: widget.active
                      ? LandingPalette.label(context)
                      : (_hover ? t.textSecondary : t.textTertiary),
                ),
                child: Text(widget.label, textAlign: TextAlign.right),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
