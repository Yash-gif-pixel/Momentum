import 'package:flutter/widgets.dart';

export 'chart_reveal.dart';
export 'count_up_text.dart';
export 'fade_slide_in.dart';
export 'pulse_once.dart';
export 'skeleton.dart';
export 'tab_fade.dart';

/// Shared timing for the app's motion. Every kit widget reads these, so the
/// whole app moves at one rhythm.
abstract final class Motion {
  /// Hover and press feedback.
  static const Duration fast = Duration(milliseconds: 150);

  /// Tab switches and fades.
  static const Duration base = Duration(milliseconds: 220);

  /// Landing → app.
  static const Duration slow = Duration(milliseconds: 450);

  /// Counting numbers and drawing charts.
  static const Duration count = Duration(milliseconds: 900);

  /// Things arriving on screen.
  static const Curve enter = Curves.easeOutCubic;

  /// Things changing state.
  static const Curve change = Curves.easeInOut;

  /// True when the OS asks for reduced motion: kit widgets then show their
  /// final state immediately and run no controller.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
