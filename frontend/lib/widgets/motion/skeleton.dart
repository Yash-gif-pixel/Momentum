import 'package:flutter/widgets.dart';

import '../../theme/credify_theme.dart';
import '../credify_shell_widgets.dart';
import 'motion.dart';

/// A loading placeholder bar with a soft shimmer. The shimmer is the one
/// thing allowed to loop, and only while it is on screen; with reduced
/// motion it is a still grey bar.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius radius;

  const Skeleton({
    super.key,
    this.height = 14,
    this.width,
    this.radius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final base = t.textPrimary.withValues(alpha: 0.07);
    final bar = Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(color: base, borderRadius: widget.radius),
    );
    if (Motion.reduced(context)) return bar;

    final shine = t.textPrimary.withValues(alpha: 0.16);
    return AnimatedBuilder(
      animation: _controller,
      child: bar,
      builder: (context, child) {
        // A bright band sweeping left → right across the bar.
        final x = _controller.value * 3 - 1.5;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: [base, shine, base],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// A glass card holding a few skeleton lines, roughly the size of a result
/// card, for use while data loads.
class SkeletonCard extends StatelessWidget {
  final int lines;
  final double? height;

  const SkeletonCard({super.key, this.lines = 3, this.height});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Skeleton(height: 12, width: 120),
            const SizedBox(height: 16),
            for (var i = 0; i < lines; i++) ...[
              Skeleton(
                height: 14,
                width: i == lines - 1 ? 180 : null,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
