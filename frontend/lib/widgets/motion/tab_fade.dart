import 'package:flutter/widgets.dart';

import 'motion.dart';

/// For tabs in an IndexedStack: fades and nudges [child] in when [active]
/// becomes true; hides it instantly when it goes inactive. The child keeps
/// its State — nothing here changes keys or rebuilds it from scratch.
class TabFade extends StatelessWidget {
  final bool active;
  final Widget child;

  const TabFade({super.key, required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    final run = active && !Motion.reduced(context) ? Motion.base : Duration.zero;
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: run,
      curve: Motion.enter,
      child: AnimatedSlide(
        offset: active ? Offset.zero : const Offset(0, 0.012),
        duration: run,
        curve: Motion.enter,
        child: child,
      ),
    );
  }
}
