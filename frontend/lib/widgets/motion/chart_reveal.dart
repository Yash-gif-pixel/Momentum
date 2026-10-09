import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Reveals [child] left → right once, by clipping. The child's layout size
/// never changes, only how much of it is painted.
class ChartReveal extends StatefulWidget {
  final Widget child;
  final Duration? duration;

  const ChartReveal({super.key, required this.child, this.duration});

  @override
  State<ChartReveal> createState() => _ChartRevealState();
}

class _ChartRevealState extends State<ChartReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration ?? Motion.count,
    );
    _t = CurvedAnimation(parent: _controller, curve: Motion.enter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
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
    return ClipRect(clipper: RevealClipper(_t), child: widget.child);
  }
}

/// Clips to the left [progress] fraction of the box; reclips as it moves.
class RevealClipper extends CustomClipper<Rect> {
  final Animation<double> progress;
  RevealClipper(this.progress) : super(reclip: progress);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress.value.clamp(0.0, 1.0),
          size.height);

  @override
  bool shouldReclip(RevealClipper old) => old.progress != progress;
}
