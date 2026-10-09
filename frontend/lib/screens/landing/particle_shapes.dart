import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'scroll_timeline.dart';

/// Shape generators for the landing particles.
///
/// Every shape lives in normalised 3D space (x right, y up, z towards the
/// viewer), centred on the origin and roughly within radius 1. Each generator
/// returns exactly `n` points as a Float32List of interleaved x, y, z and is
/// deterministic for a given seed.
///
/// Points are ordered by angle around the centre (in [_kAngleBins] sectors),
/// then by radius, so particle i sits in a similar region in every shape and
/// morphs travel coherently instead of criss-crossing.

const int _kAngleBins = 48;

/// Small deterministic PRNG (mulberry32): 32-bit state, one multiply-xorshift
/// round per draw. Same seed → same sequence on every platform, independent
/// of dart:math's Random.
class ShapeRng {
  int _state;
  ShapeRng(int seed) : _state = seed & 0xFFFFFFFF;

  /// Uniform in [0, 1).
  double next() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    t &= 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0;
  }

  /// Uniform in [a, b).
  double range(double a, double b) => a + (b - a) * next();

  static int _imul(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = (((a >> 16) & 0xFFFF) * b) & 0xFFFF;
    return (lo + (hi << 16)) & 0xFFFFFFFF;
  }
}

/// Sorts interleaved points by angle sector, then radius. [tags], when given,
/// is reordered alongside so per-point markers stay attached.
Float32List _order(Float32List pts, [List<int>? tags]) {
  final n = pts.length ~/ 3;
  final bin = Int32List(n);
  final rad = Float64List(n);
  for (var i = 0; i < n; i++) {
    final x = pts[i * 3], y = pts[i * 3 + 1];
    final a = (math.atan2(y, x) + math.pi) / (2 * math.pi);
    bin[i] = math.min(_kAngleBins - 1, (a * _kAngleBins).floor());
    rad[i] = math.sqrt(x * x + y * y);
  }
  final idx = List<int>.generate(n, (i) => i)
    ..sort((p, q) {
      final c = bin[p].compareTo(bin[q]);
      return c != 0 ? c : rad[p].compareTo(rad[q]);
    });
  final out = Float32List(n * 3);
  final oldTags = tags == null ? null : List<int>.of(tags);
  for (var k = 0; k < n; k++) {
    final i = idx[k];
    out[k * 3] = pts[i * 3];
    out[k * 3 + 1] = pts[i * 3 + 1];
    out[k * 3 + 2] = pts[i * 3 + 2];
    if (tags != null) tags[k] = oldTags![i];
  }
  return out;
}

/// Splits [n] into parts proportional to [weights] (largest remainder), so
/// the parts always sum to exactly [n].
List<int> _split(int n, List<double> weights) {
  final total = weights.fold<double>(0, (a, b) => a + b);
  final raw = [for (final w in weights) n * w / total];
  final out = [for (final r in raw) r.floor()];
  var left = n - out.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(weights.length, (i) => i)
    ..sort((a, b) => (raw[b] - raw[b].floor()).compareTo(raw[a] - raw[a].floor()));
  for (var k = 0; left > 0; k = (k + 1) % order.length, left--) {
    out[order[k]]++;
  }
  return out;
}

/// Samples [count] points evenly by arc length along a polyline.
void _alongPolyline(List<Offset> line, int count, ShapeRng rng,
    void Function(double x, double y) emit) {
  if (count <= 0) return;
  final lens = <double>[];
  var total = 0.0;
  for (var i = 0; i < line.length - 1; i++) {
    final l = (line[i + 1] - line[i]).distance;
    lens.add(l);
    total += l;
  }
  for (var k = 0; k < count; k++) {
    var d = (k + rng.next()) / count * total;
    var i = 0;
    while (i < lens.length - 1 && d > lens[i]) {
      d -= lens[i];
      i++;
    }
    final t = lens[i] == 0 ? 0.0 : clamp01(d / lens[i]);
    final p = Offset.lerp(line[i], line[i + 1], t)!;
    emit(p.dx, p.dy);
  }
}

class _Builder {
  final Float32List pts;
  int _k = 0;
  _Builder(int n) : pts = Float32List(n * 3);

  void add(double x, double y, double z) {
    pts[_k * 3] = x;
    pts[_k * 3 + 1] = y;
    pts[_k * 3 + 2] = z;
    _k++;
  }
}

/// A ₹ coin: 45% on the edge (rings at radius 1.0 and 0.93, z = ±0.05), 55% on
/// the glyph in the face plane (z = 0.02), fitted inside radius 0.62.
///
/// [glyph] holds sampled glyph points in −1..1 (y up). When null or empty the
/// face falls back to three concentric rings (radii 0.25 / 0.4 / 0.55).
Float32List coinShape(int n, int seed, {List<Offset>? glyph}) {
  final rng = ShapeRng(seed ^ 0xC011);
  final b = _Builder(n);
  final edge = (n * 0.45).round();
  final face = n - edge;

  for (var k = 0; k < edge; k++) {
    final a = (k + rng.next() * 0.6) / math.max(1, edge) * 2 * math.pi;
    final r = k.isEven ? 1.0 : 0.93;
    b.add(r * math.cos(a), r * math.sin(a), rng.next() < 0.5 ? 0.05 : -0.05);
  }

  if (glyph != null && glyph.isNotEmpty) {
    var maxR = 0.0;
    for (final p in glyph) {
      maxR = math.max(maxR, p.distance);
    }
    final s = maxR > 0 ? 0.62 / maxR : 0.62;
    for (var k = 0; k < face; k++) {
      // Even coverage when there are more particles than glyph samples.
      final p = glyph[(k * glyph.length) ~/ math.max(1, face)];
      final jx = (rng.next() - 0.5) * 0.01, jy = (rng.next() - 0.5) * 0.01;
      final x = p.dx * s + jx, y = p.dy * s + jy;
      // Jitter must not push a point outside the 0.62 face.
      final r = math.sqrt(x * x + y * y);
      final f = r > 0.62 ? 0.62 / r : 1.0;
      b.add(x * f, y * f, 0.02);
    }
  } else {
    const radii = [0.25, 0.4, 0.55];
    final parts = _split(face, radii);
    for (var ring = 0; ring < radii.length; ring++) {
      for (var k = 0; k < parts[ring]; k++) {
        final a = (k + rng.next() * 0.5) / math.max(1, parts[ring]) * 2 * math.pi;
        b.add(radii[ring] * math.cos(a), radii[ring] * math.sin(a), 0.02);
      }
    }
  }
  return _order(b.pts);
}

/// Scattered dots: a thick spherical shell, radius 1.3–2.1.
Float32List shatterShape(int n, int seed) {
  final rng = ShapeRng(seed ^ 0x5A77);
  final b = _Builder(n);
  for (var k = 0; k < n; k++) {
    // Uniform direction on the sphere.
    final z = rng.range(-1, 1);
    final a = rng.range(0, 2 * math.pi);
    final s = math.sqrt(1 - z * z);
    final r = rng.range(1.3, 2.1);
    b.add(r * s * math.cos(a), r * s * math.sin(a), r * z);
  }
  return _order(b.pts);
}

const List<double> _kBarHeights = [0.25, 0.35, 0.3, 0.5, 0.55, 0.75, 0.95];

/// Cash-flow chart: seven rising bars (75% filled) and a line over the bar
/// tops (25%), z jitter ±0.04.
Float32List chartShape(int n, int seed) {
  final rng = ShapeRng(seed ^ 0xC4A7);
  final b = _Builder(n);
  const slot = 1.8 / 7;
  const half = slot * 0.31;
  const base = -0.9;
  final fill = (n * 0.75).round();
  final line = n - fill;

  final parts = _split(fill, _kBarHeights);
  final tops = <Offset>[];
  for (var k = 0; k < _kBarHeights.length; k++) {
    final cx = -0.9 + slot * (k + 0.5);
    final h = _kBarHeights[k] * 1.8;
    for (var j = 0; j < parts[k]; j++) {
      b.add(cx + rng.range(-half, half), base + rng.next() * h,
          rng.range(-0.04, 0.04));
    }
    tops.add(Offset(cx, base + h + 0.06));
  }
  _alongPolyline(tops, line, rng,
      (x, y) => b.add(x, y, rng.range(-0.04, 0.04)));
  return _order(b.pts);
}

/// The shield outline as a closed polyline (y up).
List<Offset> shieldOutline() {
  final pts = <Offset>[];
  // Top edge, bowing up by 0.06 at the centre.
  for (var k = 0; k <= 16; k++) {
    final x = -0.75 + 1.5 * k / 16;
    pts.add(Offset(x, 0.8 + 0.06 * (1 - (x / 0.75) * (x / 0.75))));
  }
  // Right side straight down to y 0.1, then a quadratic to the bottom point.
  pts.add(const Offset(0.75, 0.1));
  for (var k = 1; k <= 16; k++) {
    final t = k / 16;
    final u = 1 - t;
    pts.add(Offset(
      u * u * 0.75 + 2 * u * t * 0.72 + t * t * 0,
      u * u * 0.1 + 2 * u * t * -0.55 + t * t * -0.95,
    ));
  }
  // Mirror back up the left side.
  for (var k = 15; k >= 0; k--) {
    final t = k / 16;
    final u = 1 - t;
    pts.add(Offset(
      -(u * u * 0.75 + 2 * u * t * 0.72),
      u * u * 0.1 + 2 * u * t * -0.55 + t * t * -0.95,
    ));
  }
  pts.add(const Offset(-0.75, 0.8));
  return pts;
}

bool _insidePolygon(List<Offset> poly, double x, double y) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > y) != (b.dy > y) &&
        x < (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Width of the check mark's stroke on the shield.
const double _kCheckBrush = 0.15;

/// Width of the shield outline's stroke.
const double _kOutlineBrush = 0.05;

/// Shield: 34% on the outline, 34% filling it, 32% forming a bold check
/// mark. Outline and check are brush strokes ([_kOutlineBrush],
/// [_kCheckBrush] wide), not hairlines.
Float32List shieldShape(int n, int seed) {
  final rng = ShapeRng(seed ^ 0x5E1D);
  final b = _Builder(n);
  final outline = shieldOutline();
  final edge = (n * 0.34).round();
  final check = (n * 0.32).round();
  final fill = n - edge - check;

  _alongPolyline(outline, edge, rng, (x, y) {
    final r = _kOutlineBrush / 2 * math.sqrt(rng.next());
    final a = rng.range(0, 2 * math.pi);
    b.add(x + r * math.cos(a), y + r * math.sin(a), rng.range(-0.04, 0.04));
  });
  var placed = 0;
  while (placed < fill) {
    final x = rng.range(-0.75, 0.75), y = rng.range(-0.95, 0.86);
    if (_insidePolygon(outline, x, y)) {
      b.add(x, y, rng.range(-0.04, 0.04));
      placed++;
    }
  }
  // Each check point lands somewhere in a round brush around the line, so
  // the stroke is thick with rounded ends and corner.
  _alongPolyline(
      const [Offset(-0.32, -0.02), Offset(-0.08, -0.28), Offset(0.38, 0.28)],
      check, rng, (x, y) {
    final r = _kCheckBrush / 2 * math.sqrt(rng.next());
    final a = rng.range(0, 2 * math.pi);
    b.add(x + r * math.cos(a), y + r * math.sin(a), rng.range(-0.04, 0.04));
  });
  return _order(b.pts);
}

/// What each point of the storm frame is. Stored per point so the role
/// survives ordering.
abstract final class StormPart {
  static const int cloud = 0;
  static const int rain = 1;
  static const int bolt = 2;
}

/// Uniform x/y scale applied to the whole storm scene so it sits in the same
/// footprint as the other shapes.
const double kStormScale = 0.78;

/// Rain falls between these heights (before [kStormScale]).
const double kStormRainTop = 0.35;
const double kStormRainBottom = -1.0;

/// The storm band: overlapping puffs (x, y, r) across the top.
const List<List<double>> _kStormPuffs = [
  [-0.88, 0.52, 0.26],
  [-0.62, 0.66, 0.32],
  [-0.30, 0.58, 0.36],
  [0.02, 0.70, 0.38],
  [0.34, 0.58, 0.34],
  [0.64, 0.66, 0.30],
  [0.88, 0.52, 0.24],
  // A flatter, heavier underside.
  [-0.55, 0.42, 0.28],
  [-0.10, 0.40, 0.32],
  [0.38, 0.42, 0.30],
];

/// Lightning: a jagged main bolt from the cloud base to the ground, and two
/// forks.
const List<List<Offset>> _kBolt = [
  [
    Offset(0.05, 0.36),
    Offset(-0.06, 0.16),
    Offset(0.08, 0.02),
    Offset(-0.10, -0.22),
    Offset(0.00, -0.35),
    Offset(-0.18, -0.60),
    Offset(-0.10, -0.72),
    Offset(-0.28, -0.98),
  ],
  [Offset(0.08, 0.02), Offset(0.25, -0.18), Offset(0.20, -0.32), Offset(0.34, -0.46)],
  [Offset(-0.10, -0.22), Offset(-0.30, -0.35), Offset(-0.38, -0.52)],
];

/// The climate frame: a storm, with per-point roles.
class StormShape {
  final Float32List points;

  /// One [StormPart] per point.
  final List<int> parts;
  const StormShape(this.points, this.parts);

  List<bool> get rain => [for (final k in parts) k == StormPart.rain];
  List<bool> get bolt => [for (final k in parts) k == StormPart.bolt];
}

/// A storm: 50% a wide, thick cloud band (puffs as 3D balls), 30% rain
/// (x −0.95..0.95, y [kStormRainBottom]..[kStormRainTop]) and 20% a forked
/// lightning bolt (main bolt 75%, forks 25%).
StormShape stormShape(int n, int seed) {
  final rng = ShapeRng(seed ^ 0x570A);
  final b = _Builder(n);
  final parts = <int>[];
  final rainCount = (n * 0.30).round();
  final boltCount = (n * 0.20).round();
  final cloudCount = n - rainCount - boltCount;

  var placed = 0;
  while (placed < cloudCount) {
    final x = rng.range(-1.12, 1.12), y = rng.range(0.1, 1.08);
    for (final c in _kStormPuffs) {
      final dx = x - c[0], dy = y - c[1];
      final d2 = dx * dx + dy * dy;
      if (d2 <= c[2] * c[2]) {
        final zr = math.sqrt(c[2] * c[2] - d2) * 0.7;
        b.add(x, y, rng.range(-zr, zr));
        parts.add(StormPart.cloud);
        placed++;
        break;
      }
    }
  }

  for (var k = 0; k < rainCount; k++) {
    b.add(rng.range(-0.95, 0.95), rng.range(kStormRainBottom, kStormRainTop),
        rng.range(-0.2, 0.2));
    parts.add(StormPart.rain);
  }

  final main = (boltCount * 0.75).round();
  final forks = _split(boltCount - main, const [0.6, 0.4]);
  final counts = [main, forks[0], forks[1]];
  for (var i = 0; i < _kBolt.length; i++) {
    _alongPolyline(_kBolt[i], counts[i], rng, (x, y) {
      b.add(x + rng.range(-0.012, 0.012), y + rng.range(-0.012, 0.012),
          rng.range(-0.02, 0.02));
      parts.add(StormPart.bolt);
    });
  }

  for (var i = 0; i < b.pts.length; i++) {
    if (i % 3 != 2) b.pts[i] *= kStormScale;
  }
  final ordered = _order(b.pts, parts);
  return StormShape(ordered, parts);
}

/// All six frames' shapes, in frame order: coin, shatter, chart, shield,
/// storm, coin (the same coin as frame 0).
class ParticleFrames {
  final List<Float32List> shapes;

  /// Per particle: is it rain / lightning on the storm frame.
  final List<bool> rain;
  final List<bool> bolt;
  int get count => shapes.first.length ~/ 3;
  const ParticleFrames(this.shapes, this.rain, this.bolt);

  factory ParticleFrames.build(int n, int seed, {List<Offset>? glyph}) {
    final coin = coinShape(n, seed, glyph: glyph);
    final storm = stormShape(n, seed);
    return ParticleFrames([
      coin,
      shatterShape(n, seed),
      chartShape(n, seed),
      shieldShape(n, seed),
      storm.points,
      coin,
    ], storm.rain, storm.bolt);
  }
}

/// Morphs particles between shapes [a] and [b] at progress [f] (0..1) into
/// [out]. Particle p starts after its [stagger] (0..0.3), eases over 0.7, and
/// swings out along its unit vector in [swirl] (x, y, z interleaved) by
/// sin(π·g)·0.35 so dots fly through space. At g == 0 / 1 the result is
/// exactly [a] / [b].
void morphBetween(Float32List a, Float32List b, double f, Float32List stagger,
    Float32List swirl, Float32List out) {
  final n = stagger.length;
  for (var p = 0; p < n; p++) {
    final g = easeInOut(clamp01((f - stagger[p]) / 0.7));
    final i = p * 3;
    if (g <= 0) {
      out[i] = a[i];
      out[i + 1] = a[i + 1];
      out[i + 2] = a[i + 2];
    } else if (g >= 1) {
      out[i] = b[i];
      out[i + 1] = b[i + 1];
      out[i + 2] = b[i + 2];
    } else {
      final s = math.sin(math.pi * g) * 0.35;
      out[i] = a[i] + (b[i] - a[i]) * g + s * swirl[i];
      out[i + 1] = a[i + 1] + (b[i + 1] - a[i + 1]) * g + s * swirl[i + 1];
      out[i + 2] = a[i + 2] + (b[i + 2] - a[i + 2]) * g + s * swirl[i + 2];
    }
  }
}

/// Particle positions at frame coordinate [coord] (0..5) into [out].
void morphPositions(List<Float32List> shapes, double coord,
    Float32List stagger, Float32List swirl, Float32List out) {
  final c = coord.isNaN ? 0.0 : coord.clamp(0.0, shapes.length - 1.0);
  final i = c.floor().clamp(0, shapes.length - 2);
  morphBetween(shapes[i], shapes[i + 1], c - i, stagger, swirl, out);
}
