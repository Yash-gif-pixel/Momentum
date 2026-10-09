import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Fades [child] in and slides it up by [offsetY] px, once, when it first
/// appears. [delay] is part of the same controller (an [Interval]), not a
/// timer, so nothing is left pending in tests.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offsetY;
  final Duration? duration;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 8,
    this.duration,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final run = widget.duration ?? Motion.base;
    final total = widget.delay + run;
    _controller = AnimationController(vsync: this, duration: total);
    final start = total == Duration.zero
        ? 0.0
        : widget.delay.inMicroseconds / total.inMicroseconds;
    _t = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: Motion.enter),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context) || _controller.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.offsetY),
            child: child,
          ),
        );
      },
    );
  }
}

/// Wraps each child in a [FadeSlideIn] that starts [step] after the one
/// before, capped at [max], so long lists don't keep the last item waiting.
List<Widget> staggered(
  List<Widget> children, {
  Duration step = const Duration(milliseconds: 40),
  Duration max = const Duration(milliseconds: 400),
}) {
  return [
    for (var i = 0; i < children.length; i++)
      FadeSlideIn(
        delay: Duration(
          microseconds:
              math.min(step.inMicroseconds * i, max.inMicroseconds),
        ),
        child: children[i],
      ),
  ];
}
