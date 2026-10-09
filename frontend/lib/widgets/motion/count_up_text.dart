import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Shows [value] formatted by [format], counting up to it: from 0 the first
/// time, then from whatever was on screen when [value] changes.
class CountUpText extends StatefulWidget {
  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration? duration;

  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.textAlign,
    this.duration,
  });

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;
  double _from = 0;
  double _to = 0;
  bool _started = false;

  double get _shown => lerpDouble(_from, _to, _t.value) ?? _to;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration ?? Motion.count,
    );
    _t = CurvedAnimation(parent: _controller, curve: Motion.enter);
    _to = widget.value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run();
  }

  void _run() {
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _shown;
      _to = widget.value;
      _run();
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
      builder: (context, _) => Text(
        widget.format(_shown),
        style: widget.style,
        textAlign: widget.textAlign,
      ),
    );
  }
}
