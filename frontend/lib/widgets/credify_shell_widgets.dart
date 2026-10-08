import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/credify_theme.dart';

const _themeCurve = Cubic(0.22, 1, 0.36, 1);

/// Soft mesh-gradient orbs behind every screen. Uses radial gradients rather
/// than ImageFilter.blur — same look, far cheaper on Flutter web.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -180,
            left: -160,
            child: _Orb(color: t.orb1, size: 480, opacity: t.orbOpacity),
          ),
          Positioned(
            bottom: -200,
            right: -140,
            child: _Orb(color: t.orb2, size: 440, opacity: t.orbOpacity),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _Orb({required this.color, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 480),
      curve: _themeCurve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

/// Frosted panel — the single glass material used across the app.
/// Lifts and glows whatever it wraps while the pointer is over it.
///
/// The [builder] receives the hover state so each caller decides what else
/// changes — a border colour, an icon tint — instead of this trying to guess.
///
/// The lift is an [AnimatedSlide], a PAINT-time transform, deliberately not
/// padding or margin: these cards live in IntrinsicHeight rows with
/// CrossAxisAlignment.stretch, where anything that changes a card's laid-out
/// size would resize its neighbours on every hover.
///
/// Honours the OS reduce-motion setting: whatever the builder does with
/// colour still happens, the movement does not.
class HoverLift extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;

  /// Logical pixels to rise. Converted to a fraction of the child's height,
  /// so a tall card and a short one move by a comparable-looking amount.
  final double lift;

  /// Whether to cast an accent glow beneath the raised card.
  final bool glow;

  const HoverLift({
    super.key,
    required this.builder,
    this.lift = 6.0,
    this.glow = true,
  });

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  /// Quick enough to feel attached to the pointer. The 480ms used elsewhere
  /// is the theme crossfade, which is a different kind of motion and would
  /// feel sluggish tracking a cursor.
  static const _duration = Duration(milliseconds: 200);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final rise = (_hovered && !reduceMotion) ? -widget.lift : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        offset: Offset(0, rise / 100),
        duration: _duration,
        curve: _curve,
        child: AnimatedContainer(
          duration: _duration,
          curve: _curve,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: (_hovered && widget.glow)
                ? [
                    BoxShadow(
                      color: t.accentA.withValues(alpha: 0.22),
                      blurRadius: 28,
                      spreadRadius: -6,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : const [],
          ),
          child: widget.builder(context, _hovered),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? borderColor;
  final VoidCallback? onTap;

  /// How long the fill and border take to reach a new value.
  ///
  /// Defaults to the theme crossfade, which is what this is for nearly
  /// everywhere: the card's colours follow light/dark in step with the rest
  /// of the shell. A caller that drives [borderColor] from something faster
  /// than a theme change -- a hover, say -- should pass its own duration,
  /// otherwise the edge lags the motion going in and lingers coming out.
  final Duration transitionDuration;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.radius = 24,
    this.borderColor,
    this.onTap,
    this.transitionDuration = const Duration(milliseconds: 480),
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final border = BorderRadius.circular(radius);

    Widget content = ClipRRect(
      borderRadius: border,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: transitionDuration,
          curve: _themeCurve,
          padding: padding,
          decoration: BoxDecoration(
            color: t.cardFill,
            borderRadius: border,
            border: Border.all(color: borderColor ?? t.glassBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: border,
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Container(margin: margin, child: content);
  }
}

/// Floating pill with a thumb that slides between the sun and the moon.
class ThemeTogglePill extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggle;

  const ThemeTogglePill({
    super.key,
    required this.isDark,
    required this.onToggle,
  });

  static const _icon = 26.0;
  static const _gap = 6.0;
  static const _pad = 5.0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Toggle dark or light mode',
      child: GestureDetector(
        onTap: onToggle,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(_pad),
              decoration: BoxDecoration(
                color: t.pillFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.glassBorder, width: 1),
              ),
              child: SizedBox(
                width: _icon * 2 + _gap,
                height: _icon,
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 504),
                      curve: _themeCurve,
                      alignment:
                          isDark ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: _icon,
                        height: _icon,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: t.accentGradient,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _slot(Icons.light_mode_rounded, !isDark, t),
                        const SizedBox(width: _gap),
                        _slot(Icons.dark_mode_rounded, isDark, t),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(IconData icon, bool active, CredifyTokens t) {
    return SizedBox(
      width: _icon,
      height: _icon,
      child: Icon(
        icon,
        size: 14,
        color: active ? Colors.white : t.textTertiary,
      ),
    );
  }
}

/// Rounded glass chip used above a screen title.
class HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const HeroPill({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: t.cardFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: t.accentA),
              const SizedBox(width: 7),
              // Flexible, not a bare Text: the Row is mainAxisSize.min, so a
              // label longer than the screen has nothing to shrink and
              // overflows instead. Same fix CredifyButton already carries.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.accentA,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gentle vertical drift, for hero cards that should feel alive.
class FloatingCard extends StatefulWidget {
  final Widget child;
  const FloatingCard({super.key, required this.child});

  @override
  State<FloatingCard> createState() => _FloatingCardState();
}

class _FloatingCardState extends State<FloatingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drift = Tween<double>(begin: -7, end: 7)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
    return AnimatedBuilder(
      animation: drift,
      builder: (_, child) =>
          Transform.translate(offset: Offset(0, drift.value), child: child),
      child: widget.child,
    );
  }
}

/// Apple-style slide-to-confirm track. Fires [onAuthorized] once the thumb is
/// dragged past three quarters of the track.
class SlideToAuthorize extends StatefulWidget {
  final String label;
  final String doneLabel;
  final VoidCallback onAuthorized;

  const SlideToAuthorize({
    super.key,
    required this.label,
    required this.doneLabel,
    required this.onAuthorized,
  });

  @override
  State<SlideToAuthorize> createState() => _SlideToAuthorizeState();
}

class _SlideToAuthorizeState extends State<SlideToAuthorize> {
  /// Outer height of the pill.
  static const _track = 56.0;

  /// The thumb is deliberately smaller than the track and inset from it.
  ///
  /// It used to be exactly [_track], which does not fit: the track Container
  /// carries a 1px border, so the Stack it wraps is only 54px tall and 2px
  /// narrower than its own constraints. A 56px circle inside that overhangs
  /// the rounded edge on every side, and at full travel it pushed past the
  /// right end as well, because maxDrag was measured against the OUTER width.
  static const _thumb = 48.0;
  static const _inset = (_track - 2 - _thumb) / 2; // 1px border top and bottom

  double _pos = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (_done) {
      return SizedBox(
        height: _track,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: t.positive, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.doneLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.positive,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Travel is measured inside the border (hence -2) and stops an equal
        // inset short of the right end, so the thumb lands symmetrically.
        final maxDrag = constraints.maxWidth - 2 - _thumb - _inset * 2;
        return Container(
          height: _track,
          decoration: BoxDecoration(
            color: t.hairline,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: t.glassBorder),
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  // Clear the thumb's full footprint so the label stays
                  // centred in the space that is actually left over.
                  padding: const EdgeInsets.only(left: _thumb + _inset * 2),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: Duration(milliseconds: _pos == 0 ? 280 : 0),
                curve: const Cubic(0.22, 1, 0.36, 1),
                left: _inset + _pos,
                top: _inset,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    setState(() {
                      _pos = (_pos + d.delta.dx).clamp(0.0, maxDrag);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_pos >= maxDrag * 0.75) {
                      setState(() => _done = true);
                      widget.onAuthorized();
                    } else {
                      setState(() => _pos = 0);
                    }
                  },
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: t.accentGradient,
                      boxShadow: [
                        BoxShadow(
                          color: t.accentA.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact figure + caption, used in the trust-stats strip.
class StatTile extends StatelessWidget {
  final String value;
  final String caption;

  const StatTile({super.key, required this.value, required this.caption});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(color: t.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

/// Eyebrow + big title + subtitle, the header pattern on every screen.
class PageHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData? pillIcon;

  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.pillIcon,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pillIcon != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: HeroPill(icon: pillIcon!, label: eyebrow),
          )
        else ...[
          Text(
            eyebrow,
            style: TextStyle(
              color: t.accentA,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
            height: 1.02,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          subtitle,
          style: TextStyle(
            color: t.textSecondary,
            fontSize: 15,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// Small uppercase label used above groups of content.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.tokens.textSecondary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// Outcome chip — SCORED / manual review / gated.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Gradient pill button (primary) and glass pill button (ghost).
class CredifyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool ghost;

  const CredifyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.ghost = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
            decoration: BoxDecoration(
              gradient: ghost ? null : t.accentGradient,
              // A white-on-white ghost button disappears against a light glass
              // card, so tint it with the accent instead of the card fill.
              color: ghost ? t.accentA.withValues(alpha: 0.10) : null,
              borderRadius: BorderRadius.circular(999),
              border: ghost
                  ? Border.all(
                      color: t.accentA.withValues(alpha: 0.40),
                      width: 1.2,
                    )
                  : null,
              boxShadow: ghost || !enabled
                  ? null
                  : [
                      BoxShadow(
                        color: t.accentA.withValues(alpha: 0.35),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 17,
                    color: ghost ? t.textPrimary : Colors.white,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ghost ? t.textPrimary : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
