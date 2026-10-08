import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/credify_theme.dart';

/// The product metaphor in one picture: a flat line where a bureau file would
/// be, and a living waveform built from real transaction behaviour.
class SignalWaveform extends StatefulWidget {
  const SignalWaveform({super.key});

  @override
  State<SignalWaveform> createState() => _SignalWaveformState();
}

class _SignalWaveformState extends State<SignalWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: t.hairline,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.glassBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 12,
            left: 14,
            child: Row(
              children: [
                Icon(Icons.circle, size: 7, color: t.accentA),
                const SizedBox(width: 6),
                Text(
                  'CASH-FLOW SIGNAL',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 14,
            child: Text(
              '24 months · 612 transactions',
              style: TextStyle(fontSize: 10, color: t.textTertiary),
            ),
          ),
          Positioned.fill(
            top: 34,
            bottom: 34,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(
                painter: _WavePainter(
                  phase: _c.value,
                  wave: t.accentA,
                  waveEnd: t.accentB,
                  floor: t.textTertiary,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 14,
            child: Text(
              'Decoded cash-flow stream',
              style: TextStyle(fontSize: 10, color: t.textSecondary),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 14,
            child: Text(
              'Bureau file — no record',
              style: TextStyle(fontSize: 10, color: t.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase;
  final Color wave;
  final Color waveEnd;
  final Color floor;

  _WavePainter({
    required this.phase,
    required this.wave,
    required this.waveEnd,
    required this.floor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Flat "no bureau record" reference line.
    final floorY = size.height * 0.82;
    final floorPaint = Paint()
      ..color = floor
      ..strokeWidth = 1.2;
    const dash = 6.0;
    for (double x = 0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, floorY),
        Offset(math.min(x + dash, size.width), floorY),
        floorPaint,
      );
    }

    // Composite wave: a slow seasonal swell plus faster weekly variation, so it
    // reads as business cash flow rather than a pure sine.
    final path = Path();
    final fill = Path();
    final mid = size.height * 0.45;
    final shift = phase * 2 * math.pi;

    for (double x = 0; x <= size.width; x += 2) {
      final nx = x / size.width;
      final y = mid -
          26 * math.sin(nx * 2 * math.pi + shift) -
          10 * math.sin(nx * 6 * math.pi + shift * 1.7) -
          4 * math.sin(nx * 13 * math.pi + shift * 2.3);
      if (x == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, floorY);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, floorY);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            wave.withValues(alpha: 0.28),
            wave.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(colors: [wave, waveEnd])
            .createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Two highlighted readings on the curve.
    for (final nx in [0.34, 0.71]) {
      final x = size.width * nx;
      final y = mid -
          26 * math.sin(nx * 2 * math.pi + shift) -
          10 * math.sin(nx * 6 * math.pi + shift * 1.7) -
          4 * math.sin(nx * 13 * math.pi + shift * 2.3);
      canvas.drawCircle(
          Offset(x, y), 7, Paint()..color = wave.withValues(alpha: 0.35));
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.phase != phase;
}
