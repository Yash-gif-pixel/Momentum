import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/credify_theme.dart';
import 'particle_shapes.dart';
import 'scroll_timeline.dart';

/// "Momentum particles": glowing dots that morph between six shapes as the
/// frame coordinate changes — ₹ coin → shattered cloud → cash-flow chart →
/// shield → storm (cloud, rain, lightning) → ₹ coin. Drawn with a
/// CustomPainter; no shaders.
///
/// A ticker adds time (twinkle), idle coin spin, pointer tilt
/// and a one-time intro where the dots assemble into the coin. With
/// `alive: false` or reduced motion there is no ticker: a static frame at
/// [coord].
///
/// [interactive] dots are pushed away from the mouse and spring back. A
/// still (`alive: false`) field only runs a ticker while dots are moving.
/// Pass [pointer] (global position, null when the mouse leaves) when the
/// particles sit under other widgets that would swallow hover events;
/// otherwise they track the mouse themselves. Reduced motion turns the
/// interaction off.
class MomentumParticles extends StatefulWidget {
  final ValueListenable<double> coord;
  final int count;
  final int seed;
  final bool alive;
  final bool interactive;
  final ValueListenable<Offset?>? pointer;

  /// A count this widget may be switched to later (e.g. the other theme's).
  /// Its layout is built ahead of time when the app is idle, so the switch
  /// doesn't hitch.
  final int? warmCount;

  const MomentumParticles({
    super.key,
    required this.coord,
    this.count = 640,
    this.seed = 7,
    this.alive = true,
    this.interactive = true,
    this.pointer,
    this.warmCount,
  });

  @override
  State<MomentumParticles> createState() => _MomentumParticlesState();
}

/// Advances the idle spin by [dt] seconds at frame coordinate [coord].
///
/// The coin spins (0.35 rad/s) only while it is on stage (coord < 0.6 or
/// > 4.4). Elsewhere the spin eases to the nearest full turn, so the chart,
/// shield face the viewer — otherwise a half-turned shield shows its
/// back and the check mark reads mirrored.
double stepIdleSpin(double spin, double coord, double dt) {
  const turn = 2 * math.pi;
  if (coord < 0.6 || coord > 4.4) return (spin + dt * 0.35) % turn;
  final target = (spin / turn).round() * turn;
  return spin + (target - spin) * (1 - math.exp(-dt * 3));
}

/// Lightning brightness (0..1) at time [t] seconds: every 3.4 s a quick
/// double flicker (strike, dip, strike), then a fast fade, then dark.
double lightningFlash(double t) {
  final ph = t % 3.4;
  if (ph < 0.07) return 1;
  if (ph < 0.13) return 0.25;
  if (ph < 0.20) return 0.95;
  if (ph < 0.75) return math.exp(-(ph - 0.20) * 9);
  return 0;
}

/// Storm colours from the theme: grey cloud and rain drawn from the text and
/// background tokens; the bolt is white-hot in dark mode and electric blue in
/// light mode (white would vanish on ivory).
({Color cloudColor, Color rainColor, Color boltColor}) _stormColors(
    BuildContext context) {
  final t = context.tokens;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return (
    cloudColor: Color.lerp(t.textPrimary, t.bg, dark ? 0.35 : 0.30)!,
    rainColor: Color.lerp(t.textPrimary, t.bg, dark ? 0.25 : 0.35)!,
    boltColor: dark ? const Color(0xFFEFF4FF) : const Color(0xFF2457D6),
  );
}

/// Seconds for the intro (shatter → coin).
const double _kIntroSeconds = 1.8;

class _Motion extends ChangeNotifier {
  double t = 0;
  double spin = 0;
  double tiltX = 0;
  double tiltY = 0;

  /// Intro progress; 1 = done.
  double intro = 1;
  bool animating = false;

  /// Wall clock for the pointer physics (advances in every ticker mode).
  double clock = 0;

  /// Mouse position in local pixels; NaN when there is none.
  double px = double.nan;
  double py = double.nan;

  /// Set by the painter: true once the dots have stopped moving.
  bool settled = true;

  void tick() => notifyListeners();
}

/// Per-particle constants, generated once from the seed.
class _Traits {
  final Float32List stagger; // 0..0.3
  final Float32List swirl; // unit vectors, x/y/z interleaved
  final Float32List radius; // 1.1..2.4 px
  final Float32List phase; // twinkle phase

  _Traits(int n, int seed)
      : stagger = Float32List(n),
        swirl = Float32List(n * 3),
        radius = Float32List(n),
        phase = Float32List(n) {
    final rng = ShapeRng(seed ^ 0x7A17);
    for (var p = 0; p < n; p++) {
      stagger[p] = rng.range(0, 0.3);
      final z = rng.range(-1, 1);
      final a = rng.range(0, 2 * math.pi);
      final s = math.sqrt(1 - z * z);
      swirl[p * 3] = s * math.cos(a);
      swirl[p * 3 + 1] = s * math.sin(a);
      swirl[p * 3 + 2] = z;
      radius[p] = rng.range(1.1, 2.4);
      phase[p] = rng.range(0, 2 * math.pi);
    }
  }
}

class _MomentumParticlesState extends State<MomentumParticles>
    with SingleTickerProviderStateMixin {
  final _Motion _motion = _Motion();
  late ParticleFrames _frames;
  late Float32List _shatter;
  late _Traits _traits;
  late Listenable _repaint;
  List<Offset>? _glyph;
  bool _glyphRequested = false;

  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _elapsed = 0;
  double _targetTiltX = 0;
  double _targetTiltY = 0;

  @override
  void initState() {
    super.initState();
    _build();
    _repaint = Listenable.merge([widget.coord, _motion]);
    widget.pointer?.addListener(_onPointer);
  }

  void _onPointer() => _setPointer(widget.pointer?.value);

  /// Cached in didChangeDependencies: pointer callbacks run outside build.
  bool _reduceMotion = false;

  bool get _interactive => widget.interactive && !_reduceMotion;

  /// Records the mouse (global coordinates, or null when it leaves) and wakes
  /// the physics.
  void _setPointer(Offset? global) {
    if (!mounted || !_interactive) return;
    final box = context.findRenderObject();
    if (global == null || box is! RenderBox || !box.hasSize) {
      _motion
        ..px = double.nan
        ..py = double.nan;
    } else {
      final local = box.globalToLocal(global);
      final inside = (Offset.zero & box.size).inflate(40).contains(local);
      _motion
        ..px = inside ? local.dx : double.nan
        ..py = inside ? local.dy : double.nan;
      if (_motion.animating && inside) {
        _targetTiltX = (local.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0);
        _targetTiltY = (local.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0);
      }
    }
    _motion.settled = false;
    _ensureTicking();
  }

  void _ensureTicking() {
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) {
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  // Built layouts, reused: the landing switches dot count with the theme,
  // and rebuilding thousands of points on every light/dark toggle caused a
  // visible hitch. Keyed by count, seed and the glyph samples in use.
  static final Map<String, ParticleFrames> _framesCache = {};
  static final Map<String, _Traits> _traitsCache = {};

  /// Builds the [MomentumParticles.warmCount] layout when the app is idle.
  void _warm() {
    final n = widget.warmCount;
    if (n == null || n == widget.count) return;
    final glyph = _glyph;
    SchedulerBinding.instance.scheduleTask(() {
      final key = '$n:${widget.seed}:'
          '${glyph == null ? 0 : identityHashCode(glyph)}';
      _framesCache.putIfAbsent(
          key, () => ParticleFrames.build(n, widget.seed, glyph: glyph));
      _traitsCache.putIfAbsent(
          '$n:${widget.seed}', () => _Traits(n, widget.seed));
    }, Priority.idle);
  }

  void _build() {
    final key = '${widget.count}:${widget.seed}:'
        '${_glyph == null ? 0 : identityHashCode(_glyph)}';
    if (_framesCache.length > 8) _framesCache.clear();
    _frames = _framesCache.putIfAbsent(key,
        () => ParticleFrames.build(widget.count, widget.seed, glyph: _glyph));
    _shatter = _frames.shapes[1];
    _traits = _traitsCache.putIfAbsent('${widget.count}:${widget.seed}',
        () => _Traits(widget.count, widget.seed));
  }

  @override
  void didUpdateWidget(MomentumParticles old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count || old.seed != widget.seed) _build();
    if (old.coord != widget.coord) {
      _repaint = Listenable.merge([widget.coord, _motion]);
    }
    if (old.pointer != widget.pointer) {
      old.pointer?.removeListener(_onPointer);
      widget.pointer?.addListener(_onPointer);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncTicker();
    if (!_glyphRequested) {
      _glyphRequested = true;
      _sampleGlyph(DefaultTextStyle.of(context).style);
    }
  }

  /// Renders '₹' off-screen and samples its opaque pixels into −1..1 points
  /// (y up). Any failure leaves the fallback rings in place.
  Future<void> _sampleGlyph(TextStyle base) async {
    ui.Image? image;
    try {
      const side = 240;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final tp = TextPainter(
        text: TextSpan(
          text: '₹',
          style: base.copyWith(
            fontSize: 200,
            fontWeight: FontWeight.w800,
            color: const Color(0xFFFFFFFF),
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset((side - tp.width) / 2, (side - tp.height) / 2));
      tp.dispose();
      final picture = recorder.endRecording();
      image = await picture.toImage(side, side);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return;

      final hits = <Offset>[];
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          if (data.getUint8((y * side + x) * 4 + 3) > 128) {
            hits.add(Offset((x - side / 2) / (side / 2),
                (side / 2 - y) / (side / 2)));
          }
        }
      }
      if (hits.isEmpty) return;
      // Pick at random (seeded): at least 400, and enough for every coin-face
      // particle to get its own sample so dense coins stay crisp.
      final rng = ShapeRng(widget.seed ^ 0x6170);
      final picked = <Offset>[];
      final keep =
          math.min(math.max(400, (widget.count * 0.55).ceil()), hits.length);
      for (var k = 0; k < keep; k++) {
        final j = k + (rng.next() * (hits.length - k)).floor();
        final tmp = hits[k];
        hits[k] = hits[j];
        hits[j] = tmp;
        picked.add(hits[k]);
      }
      if (!mounted) return;
      // One rebuild when the glyph arrives, so the painter gets the new coin.
      setState(() {
        _glyph = picked;
        _build();
      });
      _warm();
    } catch (_) {
      // Keep the fallback rings.
    } finally {
      image?.dispose();
    }
  }

  bool get _animated =>
      widget.alive &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  void _syncTicker() {
    if (_animated) {
      if (!_motion.animating) {
        _motion
          ..intro = 0
          ..animating = true;
        _elapsed = 0;
        _ensureTicking();
      }
    } else {
      // Kept, not disposed: a still field restarts it for the mouse.
      _ticker?.stop();
      _motion
        ..intro = 1
        ..animating = false
        ..t = 0
        ..spin = 0
        ..tiltX = 0
        ..tiltY = 0;
      _targetTiltX = 0;
      _targetTiltY = 0;
    }
  }

  void _onTick(Duration now) {
    final dt = math.min((now - _last).inMicroseconds / 1e6, 0.1);
    _last = now;
    if (dt <= 0) return;
    _motion.clock += dt;

    if (!_motion.animating) {
      // Still field: run only until the dots stop moving.
      if (_motion.settled) {
        _ticker?.stop();
        return;
      }
      _motion.tick();
      return;
    }
    _elapsed += dt;

    final c = widget.coord.value;
    _motion
      ..t += dt
      ..intro = clamp01(_elapsed / _kIntroSeconds);
    _motion.spin = stepIdleSpin(_motion.spin, c, dt);
    final k = 1 - math.exp(-dt * 4);
    _motion
      ..tiltX += (_targetTiltX - _motion.tiltX) * k
      ..tiltY += (_targetTiltY - _motion.tiltY) * k
      ..tick();
  }

  @override
  void dispose() {
    widget.pointer?.removeListener(_onPointer);
    _ticker?.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final storm = _stormColors(context);
    return MouseRegion(
      // With an external [pointer] the parent reports the mouse instead.
      onHover: widget.pointer == null ? (e) => _setPointer(e.position) : null,
      onExit: widget.pointer == null ? (_) => _setPointer(null) : null,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ParticlePainter(
            repaint: _repaint,
            coord: widget.coord,
            motion: _motion,
            frames: _frames,
            shatter: _shatter,
            traits: _traits,
            colors: [
              t.accentA,
              t.warning,
              t.accentA,
              // The shield's green: 30% lighter in dark mode, 25% darker in
              // light mode, so it stands out on either background.
              Theme.of(context).brightness == Brightness.dark
                  ? Color.lerp(t.positive, Colors.white, 0.30)!
                  : Color.lerp(t.positive, Colors.black, 0.25)!,
              t.accentA,
              t.accentA,
            ],
            cloudColor: storm.cloudColor,
            rainColor: storm.rainColor,
            boltColor: storm.boltColor,
          ),
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final ValueListenable<double> coord;
  final _Motion motion;
  final ParticleFrames frames;
  final Float32List shatter;
  final _Traits traits;
  final List<Color> colors;

  /// Storm frame: the cloud, the rain and the lightning.
  final Color cloudColor;
  final Color rainColor;
  final Color boltColor;

  // Reused per paint.
  final Float32List _pos;
  final Float32List _tmp;
  final Float32List _sx;
  final Float32List _sy;
  final Float32List _sz;
  final Float32List _ss;
  final Float32List _zSorted;

  final List<int> _order;

  /// Pointer push: per-particle screen offset and velocity (px, px/s).
  final Float32List _ox;
  final Float32List _oy;
  final Float32List _vx;
  final Float32List _vy;
  double _lastClock = -1;
  final Paint _dot = Paint()..isAntiAlias = true;
  final Paint _glow = Paint();
  final Paint _flashGlow = Paint();
  final Paint _streak = Paint()
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round;

  static const double _cam = 4;

  /// Rain: fall speed (units/s), wind drift (x per unit fallen), streak length
  /// (px at perspective 1) and slant.
  static const double _kRainSpeed = 1.6;

  /// Lightning dot size (core and glow), 20% under the original.
  static const double _kBoltDot = 0.8;
  static const double _kWind = 0.22;
  static const double _kStreak = 18;
  static const double _rainTop = kStormRainTop * kStormScale;
  static const double _rainBand =
      (kStormRainTop - kStormRainBottom) * kStormScale;

  _ParticlePainter({
    required Listenable repaint,
    required this.coord,
    required this.motion,
    required this.frames,
    required this.shatter,
    required this.traits,
    required this.colors,
    required this.cloudColor,
    required this.rainColor,
    required this.boltColor,
  })  : _pos = Float32List(frames.count * 3),
        _tmp = Float32List(frames.count * 3),
        _sx = Float32List(frames.count),
        _sy = Float32List(frames.count),
        _sz = Float32List(frames.count),
        _ss = Float32List(frames.count),
        _zSorted = Float32List(frames.count),
        _order = List<int>.generate(frames.count, (i) => i),
        _ox = Float32List(frames.count),
        _oy = Float32List(frames.count),
        _vx = Float32List(frames.count),
        _vy = Float32List(frames.count),
        super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final n = frames.count;
    final w = size.width, h = size.height;
    final c = coord.value.isNaN ? 0.0 : coord.value.clamp(0.0, 5.0);
    final key = keyAt(c, tall: h > w * 1.05);
    final r = key.size * math.min(w, h);
    final cx = (0.5 + key.ox / 2) * w;
    final cy = (0.5 - key.oy / 2) * h;

    final i = c.floor().clamp(0, 4);
    final f = c - i;
    final color = Color.lerp(colors[i], colors[i + 1], f)!;

    // Glow behind the shape.
    _glow.shader = RadialGradient(
      colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0)],
    ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.3));
    canvas.drawCircle(Offset(cx, cy), r * 1.3, _glow);

    // Positions: scroll morph, then the intro assembling from the shatter.
    morphPositions(frames.shapes, c, traits.stagger, traits.swirl, _pos);
    var pos = _pos;
    if (motion.intro < 1) {
      morphBetween(shatter, _pos, motion.intro, traits.stagger, traits.swirl,
          _tmp);
      pos = _tmp;
    }

    // Storm: how present it is, and the lightning flash (0..1). Without
    // animation the bolt simply stays lit.
    final stormW = clamp01(1 - (c - 4).abs());
    final flash = motion.animating ? lightningFlash(motion.t) : 1.0;
    final storm = frames.shapes[4];
    if (stormW > 0 && flash > 0) {
      // The flash lights the whole sky behind the cloud.
      final fc = Offset(cx, cy - r * 0.35);
      _flashGlow.shader = RadialGradient(colors: [
        boltColor.withValues(alpha: 0.28 * flash * stormW),
        boltColor.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: fc, radius: r * 1.6));
      canvas.drawCircle(fc, r * 1.6, _flashGlow);
    }

    final yaw = key.spin + motion.spin + motion.tiltX * 0.35;
    final pitch = (key.elevationDeg + motion.tiltY * 8) * math.pi / 180;
    final cyw = math.cos(yaw), syw = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);

    for (var p = 0; p < n; p++) {
      var x = pos[p * 3];
      var y = pos[p * 3 + 1];
      final z = pos[p * 3 + 2];
      if (motion.animating && stormW > 0 && frames.rain[p]) {
        // Drops fall from the cloud to the ground and wrap; the wind pushes
        // them left as they fall.
        final y0 = storm[p * 3 + 1];
        final m = (_rainTop - y0 + motion.t * _kRainSpeed) % _rainBand;
        final dy = (_rainTop - m - y0) * stormW;
        y += dy;
        x += dy * _kWind;
      }
      final x1 = x * cyw + z * syw;
      final z1 = -x * syw + z * cyw;
      final y2 = y * cp - z1 * sp;
      final z2 = y * sp + z1 * cp;
      final s = _cam / math.max(_cam - z2, 0.2);
      _sx[p] = cx + x1 * s * r;
      _sy[p] = cy - y2 * s * r;
      _sz[p] = z2;
      _ss[p] = s;
      _zSorted[p] = z2;
    }

    _pushFromPointer(n, math.min(w, h));

    // Nearest ~15% get a soft glow.
    _zSorted.sort();
    final glowZ = _zSorted[(n * 0.85).floor().clamp(0, n - 1)];
    // Far → near.
    _order.sort((a, b) => _sz[a].compareTo(_sz[b]));

    for (final p in _order) {
      final depth = clamp01((_sz[p] + 1.2) / 2.4);
      var alpha = 0.55 + 0.45 * depth;
      if (motion.animating) {
        alpha *= 0.75 + 0.25 * math.sin(motion.t * 2 + traits.phase[p]);
      }
      var rad = traits.radius[p] * _ss[p];
      final o = Offset(_sx[p], _sy[p]);

      if (stormW > 0) {
        if (frames.rain[p]) {
          // Thin streaks trailing up-right from the drop (into the wind).
          final len = _kStreak * _ss[p] * stormW;
          _streak
            ..color = Color.lerp(color, rainColor, stormW)!
                .withValues(alpha: alpha * 0.65)
            ..strokeWidth = math.max(0.8, rad * (1 - 0.5 * stormW));
          canvas.drawLine(
              o, Offset(o.dx + len * _kWind, o.dy - len), _streak);
          continue;
        }
        if (frames.bolt[p]) {
          // Lightning shows only while it flashes.
          final a = alpha * (1 - stormW + stormW * flash);
          if (a <= 0.01) continue;
          final bc = Color.lerp(color, boltColor, stormW)!;
          _dot.color = bc.withValues(alpha: a * 0.25);
          canvas.drawCircle(o, rad * 3.2 * _kBoltDot, _dot);
          _dot.color = bc.withValues(alpha: a);
          canvas.drawCircle(o, rad * 1.1 * _kBoltDot, _dot);
          continue;
        }
        // Cloud: bigger, denser dots that light up with the flash.
        rad *= 1 + 0.7 * stormW;
        final cc = Color.lerp(color, cloudColor, stormW)!;
        final lit = Color.lerp(cc, boltColor, 0.5 * flash * stormW)!;
        _dot.color = lit.withValues(alpha: alpha * 0.9);
        canvas.drawCircle(o, rad, _dot);
        continue;
      }

      if (_sz[p] >= glowZ) {
        _dot.color = color.withValues(alpha: alpha * 0.12);
        canvas.drawCircle(o, rad * 3, _dot);
      }
      _dot.color = color.withValues(alpha: alpha);
      canvas.drawCircle(o, rad, _dot);
    }
  }

  /// Pushes dots away from the mouse and springs them back (damped spring per
  /// dot, in screen pixels), then applies the offsets to _sx/_sy.
  void _pushFromPointer(int n, double minSide) {
    final dt = _lastClock < 0
        ? 0.0
        : (motion.clock - _lastClock).clamp(0.0, 1 / 30).toDouble();
    _lastClock = motion.clock;
    final px = motion.px, py = motion.py;
    final hasPointer = !px.isNaN;
    final radius = (minSide * 0.16).clamp(90.0, 170.0);
    final r2 = radius * radius;

    if (dt > 0) {
      var speed = 0.0;
      for (var p = 0; p < n; p++) {
        var ax = -_kSpring * _ox[p] - _kDamping * _vx[p];
        var ay = -_kSpring * _oy[p] - _kDamping * _vy[p];
        if (hasPointer) {
          final dx = _sx[p] + _ox[p] - px;
          final dy = _sy[p] + _oy[p] - py;
          final d2 = dx * dx + dy * dy;
          if (d2 < r2) {
            final d = math.sqrt(d2) + 0.001;
            final fall = 1 - d / radius;
            final f = fall * fall * _kPush;
            ax += dx / d * f;
            ay += dy / d * f;
          }
        }
        _vx[p] += ax * dt;
        _vy[p] += ay * dt;
        _ox[p] = (_ox[p] + _vx[p] * dt).clamp(-_kMaxPush, _kMaxPush);
        _oy[p] = (_oy[p] + _vy[p] * dt).clamp(-_kMaxPush, _kMaxPush);
        speed += _vx[p].abs() + _vy[p].abs();
      }
      motion.settled = speed / math.max(1, n) < 0.4;
    }
    for (var p = 0; p < n; p++) {
      _sx[p] += _ox[p];
      _sy[p] += _oy[p];
    }
  }

  /// Push strength (px/s²) at the cursor, spring back, damping, max offset.
  static const double _kPush = 5200;
  static const double _kSpring = 22;
  static const double _kDamping = 7.5;
  static const double _kMaxPush = 90;

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.frames != frames ||
      old.coord != coord ||
      old.cloudColor != cloudColor ||
      old.rainColor != rainColor ||
      old.boltColor != boltColor ||
      !listEquals(old.colors, colors);
}
