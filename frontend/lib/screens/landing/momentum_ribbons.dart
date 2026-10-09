import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/credify_theme.dart';
import 'scroll_timeline.dart';

/// Procedural chrome flower: four layers of 3D petals with outlines and
/// veins, a ring of stamens, and a curved stem with two leaves. It unfolds
/// on load and is drawn with a CustomPainter (no shaders, no WebGL).
///
/// The pose follows [coord] (a frame coordinate from [sceneCoord]) via
/// [keyAt]. A ticker adds idle spin, pointer tilt, drag spin and a one-time
/// bloom; with `alive: false` or reduced motion there is no ticker at all and
/// the flower is drawn fully open.
///
/// [ribbons] is the outer layer's petal count; the name is kept from the
/// earlier ribbon swirl so existing callers still compile.
class MomentumRibbons extends StatefulWidget {
  final ValueListenable<double> coord;
  final int ribbons;
  final int seed;
  final bool alive;

  /// Petal colour. Defaults to the theme accent when null.
  final Color? color;

  const MomentumRibbons({
    super.key,
    required this.coord,
    this.ribbons = 7,
    this.seed = 7,
    this.alive = true,
    this.color,
  });

  @override
  State<MomentumRibbons> createState() => _MomentumRibbonsState();
}

/// Samples along each petal.
const int _kSamples = 30;

/// Bloom (grow-in) duration in seconds.
const double _kBloomSeconds = 2.6;

class _Motion extends ChangeNotifier {
  double spin = 0;
  double tiltX = 0;
  double tiltY = 0;
  double bloom = 1;

  void tick() => notifyListeners();
}

class _MomentumRibbonsState extends State<MomentumRibbons>
    with SingleTickerProviderStateMixin {
  final _Motion _motion = _Motion();
  late List<_Petal> _geometry;
  late Listenable _repaint;

  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _elapsed = 0;
  double _targetTiltX = 0;
  double _targetTiltY = 0;
  double _spinVelocity = 0;

  @override
  void initState() {
    super.initState();
    _geometry = _buildGeometry(widget.ribbons, widget.seed);
    _repaint = Listenable.merge([widget.coord, _motion]);
  }

  @override
  void didUpdateWidget(MomentumRibbons old) {
    super.didUpdateWidget(old);
    if (old.ribbons != widget.ribbons || old.seed != widget.seed) {
      _geometry = _buildGeometry(widget.ribbons, widget.seed);
    }
    if (old.coord != widget.coord) {
      _repaint = Listenable.merge([widget.coord, _motion]);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  bool get _animated =>
      widget.alive && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  void _syncTicker() {
    if (_animated) {
      if (_ticker == null) {
        _motion.bloom = 0;
        _elapsed = 0;
        _last = Duration.zero;
        _ticker = createTicker(_onTick)..start();
      }
    } else {
      _ticker?.dispose();
      _ticker = null;
      _motion
        ..bloom = 1
        ..tiltX = 0
        ..tiltY = 0;
      _targetTiltX = 0;
      _targetTiltY = 0;
      _spinVelocity = 0;
    }
  }

  void _onTick(Duration now) {
    final dt = math.min((now - _last).inMicroseconds / 1e6, 0.1);
    _last = now;
    if (dt <= 0) return;
    _elapsed += dt;

    _motion.bloom = clamp01(_elapsed / _kBloomSeconds);
    // Drag velocity is in radians per 60 Hz frame.
    _motion.spin += dt * 0.1 + _spinVelocity * dt * 60;
    _spinVelocity *= math.exp(-dt * 3);
    final k = 1 - math.exp(-dt * 4);
    _motion.tiltX += (_targetTiltX - _motion.tiltX) * k;
    _motion.tiltY += (_targetTiltY - _motion.tiltY) * k;
    _motion.tick();
  }

  void _onHover(PointerHoverEvent e) {
    if (_ticker == null) return;
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _targetTiltX = (e.localPosition.dx / size.width * 2 - 1).clamp(-1.0, 1.0);
    _targetTiltY = (e.localPosition.dy / size.height * 2 - 1).clamp(-1.0, 1.0);
  }

  void _onDrag(DragUpdateDetails d) {
    if (_ticker == null) return;
    _spinVelocity += d.delta.dx * 0.0022;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Dark theme: brighter accent on dark bg. Light: deeper accent on light bg.
    final base = widget.color ?? t.accentA;
    final accent = dark
        ? Color.lerp(base, Colors.white, 0.15)!
        : Color.lerp(base, Colors.black, 0.15)!;
    final shadow =
        Color.lerp(base, const Color(0xFF05060A), dark ? 0.8 : 0.65)!;
    final highlight = Color.lerp(
        widget.color ?? t.accentB, const Color(0xFFF7F9FF), 0.85)!;

    return MouseRegion(
      onHover: _onHover,
      child: GestureDetector(
        // Horizontal only, so vertical drags still scroll the page.
        onHorizontalDragUpdate: _onDrag,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _FlowerPainter(
              repaint: _repaint,
              coord: widget.coord,
              motion: _motion,
              geometry: _geometry,
              shadow: shadow,
              accent: accent,
              highlight: highlight,
            ),
          ),
        ),
      ),
    );
  }
}

/// One petal's (or leaf's) shape parameters. Points are generated per paint
/// because petals unfold (their lift angle changes) during the bloom.
class _Petal {
  final int layer;
  final double phi; // angle around the flower's axis
  final double length; // world units from the centre to the tip
  final double lift; // open angle above horizontal, radians
  final double cup; // extra upward curl towards the tip, radians
  final double width; // max half-width
  final double tone; // per-petal brightness jitter, −1..1

  const _Petal({
    required this.layer,
    required this.phi,
    required this.length,
    required this.lift,
    required this.cup,
    required this.width,
    required this.tone,
  });
}

/// Small deterministic RNG (mulberry32) so the same seed always produces the
/// same flower on every platform, independent of dart:math's Random.
class _Rng {
  int _state;
  _Rng(int seed) : _state = seed & 0xFFFFFFFF;

  double next() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    t &= 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0;
  }

  static int _imul(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = (((a >> 16) & 0xFFFF) * b) & 0xFFFF;
    return (lo + (hi << 16)) & 0xFFFFFFFF;
  }
}

/// Geometry: four layers of petals around the vertical axis, alternate
/// layers offset by half a petal so the gaps are filled.
///   1 — n+3 petals, long, nearly flat (lift 0.10 rad)
///   2 — n+1 petals, raised (lift 0.45 rad)
///   3 — n petals, steep (lift 0.85 rad)
///   4 — n−2 petals, short, almost upright (lift 1.20 rad)
/// Seeded jitter varies each petal's angle (±0.06 rad), length (±7%), curl
/// and tone so no two petals are identical.
List<_Petal> _buildGeometry(int n, int seed) {
  final rng = _Rng(seed);
  final out = <_Petal>[];
  final layers = [
    // count, length, lift, cup, width
    [math.max(4, n + 3), 1.30, 0.10, 0.65, 0.34],
    [math.max(4, n + 1), 1.08, 0.45, 0.55, 0.31],
    [math.max(3, n), 0.84, 0.85, 0.40, 0.26],
    [math.max(3, n - 2), 0.56, 1.20, 0.25, 0.19],
  ];
  for (var l = 0; l < layers.length; l++) {
    final spec = layers[l];
    final count = spec[0].toInt();
    for (var i = 0; i < count; i++) {
      final phi = (i + (l.isOdd ? 0.5 : 0.0)) / count * 2 * math.pi +
          (rng.next() - 0.5) * 0.12;
      out.add(_Petal(
        layer: l,
        phi: phi,
        length: spec[1] * (0.93 + 0.14 * rng.next()),
        lift: spec[2].toDouble(),
        cup: spec[3] * (0.85 + 0.3 * rng.next()),
        width: spec[4].toDouble(),
        tone: rng.next() * 2 - 1,
      ));
    }
  }
  return out;
}

enum _Kind { petal, leaf, stem, stamen }

/// One drawable item (a quad, or a stamen dot), reused across paints.
class _Seg {
  _Kind kind = _Kind.petal;
  double depth = 0;
  double x0 = 0, y0 = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, x3 = 0, y3 = 0;
  // Midrib (vein) for petals and leaves; highlight stripe for the stem;
  // stalk start for stamens.
  double mx0 = 0, my0 = 0, mx1 = 0, my1 = 0;
  double radius = 0; // stamen dot radius
  bool vein = false;
  Color color = const Color(0x00000000);
  Color edge = const Color(0x00000000);
}

class _FlowerPainter extends CustomPainter {
  final ValueListenable<double> coord;
  final _Motion motion;
  final List<_Petal> geometry;
  final Color shadow;
  final Color accent;
  final Color highlight;

  /// Stem and leaves: the flower colour pulled darker so the bloom leads.
  final Color stemDark;
  final Color stemLight;

  // Reused per paint to keep allocations out of the hot path. Object-space
  // samples are written into o*/q* by the shape builders; _emit rotates and
  // projects them into c*/w* (camera space) and l*/r* (screen edges).
  final List<_Seg> _segs;
  final Float64List _ox = Float64List(_kSamples);
  final Float64List _oy = Float64List(_kSamples);
  final Float64List _oz = Float64List(_kSamples);
  final Float64List _qx = Float64List(_kSamples);
  final Float64List _qy = Float64List(_kSamples);
  final Float64List _qz = Float64List(_kSamples);
  final Float64List _cx = Float64List(_kSamples);
  final Float64List _cy = Float64List(_kSamples);
  final Float64List _cz = Float64List(_kSamples);
  final Float64List _wx = Float64List(_kSamples);
  final Float64List _wy = Float64List(_kSamples);
  final Float64List _wz = Float64List(_kSamples);
  final Float64List _sx = Float64List(_kSamples);
  final Float64List _sy = Float64List(_kSamples);
  final Float64List _lx = Float64List(_kSamples);
  final Float64List _ly = Float64List(_kSamples);
  final Float64List _rx = Float64List(_kSamples);
  final Float64List _ry = Float64List(_kSamples);
  final Float64List _pd = Float64List(_kSamples);
  final List<_Seg> _order = <_Seg>[];
  final Path _path = Path();
  final Path _edgePath = Path();
  // Quads are filled without anti-aliasing so neighbours meet without hairline
  // seams; the anti-aliased outline strokes keep the silhouettes smooth.
  final Paint _fill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;
  final Paint _dot = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  final Paint _glow = Paint();
  final Paint _heart = Paint();

  static const int _kStamens = 18;
  static const int _kLeaves = 2;

  static const double _camDist = 4.5;
  static final double _focal = 1 / math.tan(15 * math.pi / 180); // 30° FOV
  static const double _worldRadius = 1.3; // outer petal length

  /// Visible radius as a share of key.size·min(W, H). At 1.0 the outer petals
  /// overflow the viewport on most frames, so the flower is drawn at half.
  static const double _sizeScale = 0.5;

  /// Petal base height: the flower sits slightly below its pivot.
  static const double _baseY = -0.2;

  /// Stem: drops this far below the petal base, with a gentle S-curve.
  static const double _stemLength = 2.6;
  static const double _stemRadius = 0.045;

  // Light from upper-left-front in camera space (camera looks down −z), and
  // the half-vector between it and the view direction for the highlight.
  static const double _lx0 = -0.42, _ly0 = 0.68, _lz0 = 0.6;
  static final double _lLen =
      math.sqrt(_lx0 * _lx0 + _ly0 * _ly0 + _lz0 * _lz0);
  static final double _hx = _lx0 / _lLen;
  static final double _hy = _ly0 / _lLen;
  static final double _hz = _lz0 / _lLen + 1;
  static final double _hLen = math.sqrt(_hx * _hx + _hy * _hy + _hz * _hz);

  // Per-paint pose, set at the top of paint().
  double _ox0 = 0, _oy0 = 0, _scale = 1;
  double _cyw = 1, _syw = 0, _cp = 1, _sp = 0;
  int _count = 0;

  _FlowerPainter({
    required Listenable repaint,
    required this.coord,
    required this.motion,
    required this.geometry,
    required this.shadow,
    required this.accent,
    required this.highlight,
  })  : stemDark = Color.lerp(accent, shadow, 0.85)!,
        stemLight = Color.lerp(accent, shadow, 0.5)!,
        _segs = List.generate(
            (geometry.length + _kLeaves + 1) * (_kSamples - 1) + _kStamens,
            (_) => _Seg(),
            growable: false),
        super(repaint: repaint);

  // Rotate Y (yaw) then X (pitch). Returns into the given out-arrays.
  void _rotate(double x, double y, double z, Float64List ox, Float64List oy,
      Float64List oz, int j) {
    final x1 = x * _cyw + z * _syw;
    final z1 = -x * _syw + z * _cyw;
    ox[j] = x1;
    oy[j] = y * _cp - z1 * _sp;
    oz[j] = y * _sp + z1 * _cp;
  }

  double _proj(double z) =>
      _focal / math.max(_camDist - z, 0.1) * _scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final key = keyAt(coord.value, tall: h > w * 1.05);
    final minSide = math.min(w, h);
    final radiusPx = key.size * minSide * _sizeScale;
    _ox0 = (0.5 + key.ox / 2) * w;
    _oy0 = (0.5 - key.oy / 2) * h;
    _scale = radiusPx / (_worldRadius * _focal / _camDist);

    // Glow behind the flower.
    _glow.shader = RadialGradient(
      colors: [accent.withValues(alpha: 0.14), accent.withValues(alpha: 0)],
    ).createShader(
        Rect.fromCircle(center: Offset(_ox0, _oy0), radius: radiusPx * 1.6));
    canvas.drawCircle(Offset(_ox0, _oy0), radiusPx * 1.6, _glow);

    final yaw = motion.spin + key.spin + motion.tiltX * 0.35;
    final pitch = (key.elevationDeg + motion.tiltY * 9) * math.pi / 180;
    _cyw = math.cos(yaw);
    _syw = math.sin(yaw);
    _cp = math.cos(pitch);
    _sp = math.sin(pitch);
    _count = 0;

    final bloom = motion.bloom;
    _buildStem();
    _buildLeaves(bloom);
    for (final petal in geometry) {
      // Outer petals open first; each layer unfolds from upright to its lift.
      final open = clamp01(bloom * 1.6 - petal.layer * 0.18);
      if (open <= 0) continue;
      _buildPetal(petal, open);
      _emitSurface(_Kind.petal, petal.tone, veinTo: 0.82);
    }
    _buildStamens(bloom);

    // Flower heart: the projected centre, drawn at its own depth.
    final hy = _baseY + 0.05;
    final heartDepth = _camDist - hy * _sp;
    final hf = _focal / heartDepth * _scale;
    final heartC = Offset(_ox0, _oy0 - hy * _cp * hf);
    final heartR = 0.14 * hf * clamp01(bloom * 2);
    var heartDrawn = heartR <= 0;

    // Painter's algorithm: far first.
    _order
      ..clear()
      ..addAll(_segs.take(_count))
      ..sort((p, q) => q.depth.compareTo(p.depth));
    for (final s in _order) {
      if (!heartDrawn && s.depth < heartDepth) {
        _drawHeart(canvas, heartC, heartR);
        heartDrawn = true;
      }
      _draw(canvas, s);
    }
    if (!heartDrawn) _drawHeart(canvas, heartC, heartR);
  }

  /// Fills o*/q* with a petal: centreline leaves the centre at `lift` and
  /// curls up towards the tip; the width runs around the axis.
  void _buildPetal(_Petal p, double open) {
    final lift = p.lift + (1 - open) * (math.pi / 2 - 0.1 - p.lift);
    final len = p.length * (0.35 + 0.65 * open);
    final cphi = math.cos(p.phi), sphi = math.sin(p.phi);
    for (var j = 0; j < _kSamples; j++) {
      final s = j / (_kSamples - 1);
      final a = lift + p.cup * s * s;
      final r = len * s * math.cos(a);
      _ox[j] = r * cphi;
      _oy[j] = _baseY + len * s * math.sin((a + lift) / 2);
      _oz[j] = r * sphi;
      // Narrow base, rounded belly, pointed tip.
      final hw = p.width *
          (len / p.length) *
          math.pow(math.sin(math.pi * math.pow(s, 0.78)), 0.7);
      _qx[j] = -sphi * hw;
      _qy[j] = 0;
      _qz[j] = cphi * hw;
    }
  }

  /// Stem centreline in o*; drawn as a tube (screen-facing width).
  void _buildStem() {
    for (var j = 0; j < _kSamples; j++) {
      final s = j / (_kSamples - 1);
      final x = 0.14 * math.sin(s * math.pi * 1.15);
      final z = 0.07 * math.sin(s * math.pi * 0.8);
      _rotate(x, _baseY - s * _stemLength, z, _cx, _cy, _cz, j);
    }
    // Tube: width perpendicular to the projected centreline.
    for (var j = 0; j < _kSamples; j++) {
      final f = _proj(_cz[j]);
      _sx[j] = _ox0 + _cx[j] * f;
      _sy[j] = _oy0 - _cy[j] * f;
      _pd[j] = _camDist - _cz[j];
    }
    for (var j = 0; j < _kSamples; j++) {
      final a = math.max(0, j - 1), b = math.min(_kSamples - 1, j + 1);
      final dx = _sx[b] - _sx[a], dy = _sy[b] - _sy[a];
      final len = math.max(math.sqrt(dx * dx + dy * dy), 1e-6);
      // Slightly thicker at the base of the flower, tapering down.
      final r = _stemRadius * (1.25 - 0.35 * j / (_kSamples - 1)) *
          _proj(_cz[j]);
      final nx = -dy / len * r, ny = dx / len * r;
      _lx[j] = _sx[j] + nx;
      _ly[j] = _sy[j] + ny;
      _rx[j] = _sx[j] - nx;
      _ry[j] = _sy[j] - ny;
    }
    for (var j = 0; j < _kSamples - 1; j++) {
      final seg = _segs[_count++];
      final s = (j + 0.5) / (_kSamples - 1);
      seg
        ..kind = _Kind.stem
        ..depth = (_pd[j] + _pd[j + 1]) / 2
        ..x0 = _lx[j]
        ..y0 = _ly[j]
        ..x1 = _lx[j + 1]
        ..y1 = _ly[j + 1]
        ..x2 = _rx[j + 1]
        ..y2 = _ry[j + 1]
        ..x3 = _rx[j]
        ..y3 = _ry[j]
        // Highlight stripe along the lit (left) side of the tube.
        ..mx0 = _sx[j] + (_lx[j] - _sx[j]) * 0.45
        ..my0 = _sy[j] + (_ly[j] - _sy[j]) * 0.45
        ..mx1 = _sx[j + 1] + (_lx[j + 1] - _sx[j + 1]) * 0.45
        ..my1 = _sy[j + 1] + (_ly[j + 1] - _sy[j + 1]) * 0.45
        ..color = Color.lerp(stemLight, stemDark, s * 0.6)!
        ..edge = Color.lerp(stemLight, accent, 0.5)!;
    }
  }

  /// Two leaves on the stem, curling up and out on opposite sides.
  void _buildLeaves(double bloom) {
    final grow = clamp01(bloom * 1.4);
    if (grow <= 0) return;
    const at = [0.42, 0.68]; // position down the stem, 0..1
    const phis = [0.35, math.pi + 0.5];
    for (var k = 0; k < _kLeaves; k++) {
      final s0 = at[k];
      final bx = 0.14 * math.sin(s0 * math.pi * 1.15);
      final bz = 0.07 * math.sin(s0 * math.pi * 0.8);
      final by = _baseY - s0 * _stemLength;
      final cphi = math.cos(phis[k]), sphi = math.sin(phis[k]);
      final len = 0.95 * grow;
      for (var j = 0; j < _kSamples; j++) {
        final s = j / (_kSamples - 1);
        // Out from the stem at 25°, curling upwards towards the tip.
        final a = 0.45 + 0.9 * s * s;
        final r = len * s * math.cos(a);
        _ox[j] = bx + r * cphi;
        _oy[j] = by + len * s * math.sin(a) * 0.8;
        _oz[j] = bz + r * sphi;
        final hw = 0.2 * grow * math.pow(math.sin(math.pi * math.pow(s, 0.85)), 0.8);
        _qx[j] = -sphi * hw;
        _qy[j] = hw * 0.25;
        _qz[j] = cphi * hw;
      }
      _emitSurface(_Kind.leaf, 0, veinTo: 0.9);
    }
  }

  /// Rotates and projects o*/q* and emits one quad per segment.
  void _emitSurface(_Kind kind, double tone, {required double veinTo}) {
    for (var j = 0; j < _kSamples; j++) {
      _rotate(_ox[j], _oy[j], _oz[j], _cx, _cy, _cz, j);
      final x1 = _qx[j] * _cyw + _qz[j] * _syw;
      final z1 = -_qx[j] * _syw + _qz[j] * _cyw;
      _wx[j] = x1;
      _wy[j] = _qy[j] * _cp - z1 * _sp;
      _wz[j] = _qy[j] * _sp + z1 * _cp;
      final fc = _proj(_cz[j]);
      final fl = _proj(_cz[j] + _wz[j]);
      final fr = _proj(_cz[j] - _wz[j]);
      _sx[j] = _ox0 + _cx[j] * fc;
      _sy[j] = _oy0 - _cy[j] * fc;
      _lx[j] = _ox0 + (_cx[j] + _wx[j]) * fl;
      _ly[j] = _oy0 - (_cy[j] + _wy[j]) * fl;
      _rx[j] = _ox0 + (_cx[j] - _wx[j]) * fr;
      _ry[j] = _oy0 - (_cy[j] - _wy[j]) * fr;
      _pd[j] = _camDist - _cz[j];
    }

    final leaf = kind == _Kind.leaf;
    final lo = leaf ? stemDark : shadow;
    final mid = leaf ? stemLight : accent;

    for (var j = 0; j < _kSamples - 1; j++) {
      // Surface normal = along × across (camera space).
      final ax = _cx[j + 1] - _cx[j];
      final ay = _cy[j + 1] - _cy[j];
      final az = _cz[j + 1] - _cz[j];
      final bx = _wx[j] + _wx[j + 1];
      final by = _wy[j] + _wy[j + 1];
      final bz = _wz[j] + _wz[j + 1];
      var nx = ay * bz - az * by;
      var ny = az * bx - ax * bz;
      var nz = ax * by - ay * bx;
      final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (nl < 1e-9) {
        nx = 0;
        ny = 0;
        nz = 1;
      } else {
        nx /= nl;
        ny /= nl;
        nz /= nl;
      }
      // Two-sided lighting: petals are seen from both faces.
      final diffuse = (nx * _lx0 + ny * _ly0 + nz * _lz0).abs() / _lLen;
      final spec = math
          .pow((nx * _hx + ny * _hy + nz * _hz).abs() / _hLen, 28)
          .toDouble();
      final rim = 1 - nz.abs();
      final s = (j + 0.5) / (_kSamples - 1);
      // Darker at the base, lighter towards the tip, plus per-petal tone.
      final b = clamp01(
          0.08 + 0.55 * diffuse + 0.2 * rim + 0.22 * s + 0.06 * tone);

      var c = Color.lerp(lo, mid, b)!;
      final hot = clamp01(math.max(spec * 1.3, (b - 0.86) / 0.14));
      if (hot > 0 && !leaf) c = Color.lerp(c, highlight, hot)!;

      // Neighbouring quads share edge points, so outlines are smooth.
      final seg = _segs[_count++];
      seg
        ..kind = kind
        ..depth = (_pd[j] + _pd[j + 1]) / 2
        ..x0 = _lx[j]
        ..y0 = _ly[j]
        ..x1 = _lx[j + 1]
        ..y1 = _ly[j + 1]
        ..x2 = _rx[j + 1]
        ..y2 = _ry[j + 1]
        ..x3 = _rx[j]
        ..y3 = _ry[j]
        ..mx0 = _sx[j]
        ..my0 = _sy[j]
        ..mx1 = _sx[j + 1]
        ..my1 = _sy[j + 1]
        ..vein = s < veinTo
        ..color = c
        // Edges a touch brighter than the face: crisp petal outlines.
        ..edge = Color.lerp(c, leaf ? stemLight : highlight, 0.45)!;
    }
  }

  /// A ring of stamens around the heart: short stalks with bright tips.
  void _buildStamens(double bloom) {
    final grow = clamp01(bloom * 2 - 0.9);
    if (grow <= 0) return;
    final hy = _baseY + 0.05;
    for (var k = 0; k < _kStamens; k++) {
      final a = k / _kStamens * 2 * math.pi + (k.isOdd ? 0.12 : 0);
      final rr = (0.13 + (k.isOdd ? 0.05 : 0)) * grow;
      final tipY = hy + (0.2 + (k % 3) * 0.03) * grow;
      _rotate(rr * math.cos(a), tipY, rr * math.sin(a), _cx, _cy, _cz, 0);
      _rotate(rr * 0.35 * math.cos(a), hy, rr * 0.35 * math.sin(a), _cx, _cy,
          _cz, 1);
      final f0 = _proj(_cz[0]), f1 = _proj(_cz[1]);
      final seg = _segs[_count++];
      seg
        ..kind = _Kind.stamen
        ..depth = _camDist - _cz[0]
        ..x0 = _ox0 + _cx[0] * f0
        ..y0 = _oy0 - _cy[0] * f0
        ..mx0 = _ox0 + _cx[1] * f1
        ..my0 = _oy0 - _cy[1] * f1
        ..radius = 0.028 * f0
        ..color = highlight
        ..edge = accent;
    }
  }

  void _draw(Canvas canvas, _Seg s) {
    switch (s.kind) {
      case _Kind.stamen:
        _stroke
          ..color = s.edge
          ..strokeWidth = math.max(0.8, s.radius * 0.45);
        canvas.drawLine(Offset(s.mx0, s.my0), Offset(s.x0, s.y0), _stroke);
        _dot.color = s.color;
        canvas.drawCircle(Offset(s.x0, s.y0), s.radius, _dot);
        return;
      case _Kind.petal:
      case _Kind.leaf:
      case _Kind.stem:
        _path
          ..reset()
          ..moveTo(s.x0, s.y0)
          ..lineTo(s.x1, s.y1)
          ..lineTo(s.x2, s.y2)
          ..lineTo(s.x3, s.y3)
          ..close();
        _fill.color = s.color;
        canvas.drawPath(_path, _fill);
    }

    if (s.kind == _Kind.stem) {
      _edgePath
        ..reset()
        ..moveTo(s.x0, s.y0)
        ..lineTo(s.x1, s.y1)
        ..moveTo(s.x3, s.y3)
        ..lineTo(s.x2, s.y2);
      _stroke
        ..color = s.color
        ..strokeWidth = 1.0;
      canvas.drawPath(_edgePath, _stroke);
      _stroke
        ..color = s.edge
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(s.mx0, s.my0), Offset(s.mx1, s.my1), _stroke);
      return;
    }

    // Outline along both long edges.
    _edgePath
      ..reset()
      ..moveTo(s.x0, s.y0)
      ..lineTo(s.x1, s.y1)
      ..moveTo(s.x3, s.y3)
      ..lineTo(s.x2, s.y2);
    _stroke
      ..color = s.edge
      ..strokeWidth = 1.1;
    canvas.drawPath(_edgePath, _stroke);

    // Midrib vein.
    if (s.vein) {
      _stroke
        ..color = s.edge.withValues(alpha: 0.55)
        ..strokeWidth = 0.9;
      canvas.drawLine(Offset(s.mx0, s.my0), Offset(s.mx1, s.my1), _stroke);
    }
  }

  void _drawHeart(Canvas canvas, Offset c, double r) {
    _heart.shader = RadialGradient(
      center: const Alignment(-0.3, -0.35),
      colors: [highlight, accent, shadow],
      stops: const [0, 0.5, 1],
    ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, _heart);
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.geometry != geometry ||
      old.shadow != shadow ||
      old.accent != accent ||
      old.highlight != highlight ||
      old.coord != coord;
}
