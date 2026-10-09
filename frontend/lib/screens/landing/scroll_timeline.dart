import 'dart:math' as math;

/// Scroll timeline for the scroll-driven landing page.
///
/// Scroll progress (0..1) maps to a "frame coordinate" in 0..[kLandingScenes]-1.
/// Each whole number is a frame; around it the coordinate holds still for
/// [kLandingHold] of the frame's scroll, then eases to the next frame.

const int kLandingScenes = 6;
const double kLandingHold = 0.34;

/// Viewport-heights of scroll per frame.
const double kSceneScroll = 1.2;

double clamp01(double x) => x <= 0 ? 0 : (x > 1 ? 1 : x);

double smoothstep(double a, double b, double x) {
  final t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

double easeInOut(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

/// Scroll progress 0..1 for a scrollable of [totalHeight] seen through a
/// viewport of [viewportHeight].
double progressFrom(double offset, double totalHeight, double viewportHeight) {
  final travel = totalHeight - viewportHeight;
  return travel <= 0 ? 0 : clamp01(offset / travel);
}

/// Frame coordinate for progress [p] across [n] frames, holding still for
/// [hold] of each step around every whole frame.
double sceneCoord(double p, int n, double hold) {
  if (n <= 1) return 0;
  final t = clamp01(p) * (n - 1);
  final i = math.min(t.floor(), n - 2);
  final h = hold / 2;
  return i + easeInOut(clamp01((t - i - h) / (1 - 2 * h)));
}

/// Visibility 0..1 of the content for [scene] at frame coordinate [coord].
/// [delay] staggers entry (coming in) against exit (going out).
double reveal(double coord, int scene, double delay) {
  final d = coord - scene;
  final lag = d < 0 ? delay : 1 - delay;
  return clamp01((0.6 - d.abs() - lag * 0.2) / 0.25);
}

/// Pose of the stage centrepiece at one frame.
///
/// [ox]/[oy] are in -1..1 with +y up; the shape centre lands at
/// ((0.5 + ox/2)·W, (0.5 - oy/2)·H). [size] is the shape radius as a fraction
/// of min(W, H).
class StageKey {
  final double spin;
  final double elevationDeg;
  final double size;
  final double ox;
  final double oy;

  const StageKey({
    required this.spin,
    required this.elevationDeg,
    required this.size,
    required this.ox,
    required this.oy,
  });

  static StageKey lerp(StageKey a, StageKey b, double t) => StageKey(
        spin: a.spin + (b.spin - a.spin) * t,
        elevationDeg: a.elevationDeg + (b.elevationDeg - a.elevationDeg) * t,
        size: a.size + (b.size - a.size) * t,
        ox: a.ox + (b.ox - a.ox) * t,
        oy: a.oy + (b.oy - a.oy) * t,
      );
}

const List<StageKey> kStageKeysWide = [
  StageKey(spin: 0, elevationDeg: 8, size: 0.62, ox: 0, oy: 0.22),
  StageKey(spin: 0.6, elevationDeg: 20, size: 0.70, ox: 0, oy: 0.05),
  StageKey(spin: 0, elevationDeg: 0, size: 0.48, ox: 0.52, oy: 0),
  StageKey(spin: 0, elevationDeg: 0, size: 0.48, ox: -0.52, oy: 0),
  StageKey(spin: 0, elevationDeg: 0, size: 0.50, ox: 0.52, oy: 0.05),
  StageKey(spin: 0, elevationDeg: 8, size: 0.55, ox: 0, oy: 0.55),
];

const List<StageKey> kStageKeysTall = [
  StageKey(spin: 0, elevationDeg: 8, size: 0.70, ox: 0, oy: 0.32),
  StageKey(spin: 0.6, elevationDeg: 20, size: 0.80, ox: 0, oy: 0.15),
  StageKey(spin: 0, elevationDeg: 0, size: 0.50, ox: 0, oy: 0.45),
  StageKey(spin: 0, elevationDeg: 0, size: 0.50, ox: 0, oy: 0.45),
  StageKey(spin: 0, elevationDeg: 0, size: 0.55, ox: 0, oy: 0.45),
  StageKey(spin: 0, elevationDeg: 8, size: 0.60, ox: 0, oy: 0.55),
];

/// Stage pose at frame coordinate [coord], linearly interpolated between the
/// surrounding frames. [tall] selects the portrait key list.
StageKey keyAt(double coord, {required bool tall}) {
  final keys = tall ? kStageKeysTall : kStageKeysWide;
  final last = keys.length - 1;
  final c = coord.isNaN ? 0.0 : coord.clamp(0.0, last.toDouble());
  final i = c.floor();
  if (i >= last) return keys[last];
  return StageKey.lerp(keys[i], keys[i + 1], c - i);
}
