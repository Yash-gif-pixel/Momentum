import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/credify_theme.dart';

/// A dark landing-page button whose edge glow follows the pointer.
class InteractiveGlowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool compact;

  const InteractiveGlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
  });

  @override
  State<InteractiveGlowButton> createState() => _InteractiveGlowButtonState();
}

class _InteractiveGlowButtonState extends State<InteractiveGlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  final ValueNotifier<Offset?> _pointer = ValueNotifier(null);
  bool _hovered = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _glow.value = _hovered ? 1 : 0;
    } else if (_hovered) {
      _glow.forward();
    }
  }

  void _updatePointer(PointerEvent event) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _pointer.value = box.globalToLocal(event.position);
    }
  }

  void _onEnter(PointerEnterEvent event) {
    _hovered = true;
    _updatePointer(event);
    if (_reduceMotion) {
      _glow.value = 1;
    } else {
      _glow.forward();
    }
    setState(() {});
  }

  void _onHover(PointerHoverEvent event) => _updatePointer(event);

  void _onExit(PointerExitEvent event) {
    _hovered = false;
    _pointer.value = null;
    if (_reduceMotion) {
      _glow.value = 0;
    } else {
      _glow.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _glow.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));
    final tokens = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topColor = dark
        ? Color.lerp(tokens.bg, tokens.textPrimary, 0.08)!
        : Color.lerp(tokens.bg, Colors.white, 0.45)!;
    final bottomColor = dark
        ? tokens.bg
        : Color.lerp(tokens.bg, tokens.accentB, 0.12)!;
    final outlineColor = dark
        ? Colors.white.withValues(alpha: 0.3)
        : tokens.accentA.withValues(alpha: 0.42);
    return MouseRegion(
      onEnter: _onEnter,
      onHover: _onHover,
      onExit: _onExit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: tokens.accentA.withValues(alpha: 0.17),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: CustomPaint(
          foregroundPainter: _GlowPainter(
            _glow,
            _pointer,
            tokens.accentA,
            radius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onPressed,
              child: Ink(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 16 : 24,
                  vertical: widget.compact ? 9 : 15,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [topColor, bottomColor],
                  ),
                  borderRadius: radius,
                  border: Border.all(color: outlineColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 17, color: tokens.textPrimary),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: widget.compact ? 12.5 : 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
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
}

/// Adds the same pointer-following accent glow to an existing control surface.
class InteractiveGlowRegion extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color glowColor;

  const InteractiveGlowRegion({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.glowColor,
  });

  @override
  State<InteractiveGlowRegion> createState() => _InteractiveGlowRegionState();
}

class _InteractiveGlowRegionState extends State<InteractiveGlowRegion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  final ValueNotifier<Offset?> _pointer = ValueNotifier(null);
  bool _hovered = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _glow.value = _hovered ? 1 : 0;
    } else if (_hovered) {
      _glow.forward();
    }
  }

  void _updatePointer(PointerEvent event) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _pointer.value = box.globalToLocal(event.position);
    }
  }

  void _onEnter(PointerEnterEvent event) {
    _hovered = true;
    _updatePointer(event);
    if (_reduceMotion) {
      _glow.value = 1;
    } else {
      _glow.forward();
    }
    setState(() {});
  }

  void _onExit(PointerExitEvent event) {
    _hovered = false;
    _pointer.value = null;
    if (_reduceMotion) {
      _glow.value = 0;
    } else {
      _glow.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _glow.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onHover: _updatePointer,
      onExit: _onExit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.glowColor.withValues(alpha: 0.16),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: CustomPaint(
          foregroundPainter: _GlowPainter(
            _glow,
            _pointer,
            widget.glowColor,
            widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final Animation<double> glow;
  final ValueListenable<Offset?> pointer;
  final Color accent;
  final BorderRadius borderRadius;

  _GlowPainter(this.glow, this.pointer, this.accent, this.borderRadius)
    : super(repaint: Listenable.merge([glow, pointer]));

  @override
  void paint(Canvas canvas, Size size) {
    final point = pointer.value;
    final strength = glow.value;
    if (point == null || strength <= 0 || size.isEmpty) return;

    final rect = Offset.zero & size;
    final radius = borderRadius.toRRect(rect);
    final halo = Paint()
      ..color = accent.withValues(alpha: 0.22 * strength)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        math.max(5.0, size.height * 0.22),
      );
    canvas.drawCircle(point, size.height * 0.35, halo);

    final center = Alignment(
      (point.dx / size.width * 2 - 1).clamp(-1.0, 1.0).toDouble(),
      (point.dy / size.height * 2 - 1).clamp(-1.0, 1.0).toDouble(),
    );
    final fill = Paint()
      ..shader = RadialGradient(
        center: center,
        radius: 1.1,
        colors: [
          accent.withValues(alpha: 0.16 * strength),
          accent.withValues(alpha: 0.045 * strength),
          Colors.transparent,
        ],
        stops: const [0, 0.32, 1],
      ).createShader(rect);
    canvas.drawRRect(radius, fill);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = RadialGradient(
        center: center,
        radius: 1.25,
        colors: [
          Color.lerp(
            accent,
            Colors.white,
            0.42,
          )!.withValues(alpha: 0.9 * strength),
          accent.withValues(alpha: 0.25 * strength),
          Colors.transparent,
        ],
        stops: const [0, 0.42, 1],
      ).createShader(rect);
    canvas.drawRRect(radius.deflate(0.6), edge);
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.glow != glow ||
      oldDelegate.pointer != pointer ||
      oldDelegate.accent != accent;
}
