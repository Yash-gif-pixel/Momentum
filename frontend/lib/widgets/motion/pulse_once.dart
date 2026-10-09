import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Plays one soft pulse (scale 1 → 1.06 → 1, glow 0 → 0.35 → 0) when it
/// first appears and again whenever [trigger] changes — e.g. a new result.
/// No pulse with reduced motion.
class PulseOnce extends StatefulWidget {
  final Widget child;
  final Color color;
  final Object? trigger;
  final BorderRadius radius;

  const PulseOnce({
    super.key,
    required this.child,
    required this.color,
    required this.trigger,
    this.radius = const BorderRadius.all(Radius.circular(999)),
  });

  @override
  State<PulseOnce> createState() => _PulseOnceState();
}

class _PulseOnceState extends State<PulseOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _pulse();
  }

  @override
  void didUpdateWidget(PulseOnce old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _pulse();
  }

  void _pulse() {
    if (Motion.reduced(context)) {
      _controller.value = 0;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // 0 → 1 → 0 over the run; 0 at rest (start and end).
        final p = _controller.isAnimating
            ? math.sin(math.pi * Motion.change.transform(_controller.value))
            : 0.0;
        return Transform.scale(
          scale: 1 + 0.06 * p,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.radius,
              boxShadow: p <= 0
                  ? null
                  : [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.35 * p),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}
