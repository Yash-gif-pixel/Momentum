import 'package:flutter/material.dart';

/// The Credify glyph: a living cash-flow waveform cresting above a flat,
/// dashed baseline — the bureau file that has no record of it.
///
/// Paints the GLYPH ONLY, not the rounded gradient tile behind it. The tile
/// is left to whatever places the mark, so it picks up `t.accentGradient` and
/// the app's own corner radius and follows light/dark automatically instead
/// of carrying a second, drifting copy of the brand colours.
///
/// The geometry below is normalised to a 0..1 box and is the same set of
/// numbers used by the script that renders the favicon and PWA icons
/// (tools/mark.py), so the app icon and the in-app mark cannot diverge.
class CredifyMark extends StatelessWidget {
  final double size;
  final Color color;

  const CredifyMark({super.key, required this.size, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(color),
        // The mark is decorative wherever it appears beside the wordmark, but
        // it is the only branding in the collapsed nav, so it carries a label.
        isComplex: false,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  const _MarkPainter(this.color);

  static const _baseline = 0.615;
  static const _dashY = 0.745;
  static const _x0 = 0.165;
  static const _x1 = 0.835;

  /// Cubic segments of the wave's upper edge: (control1, control2, end).
  static const _wave = <List<Offset>>[
    [Offset(0.215, 0.560), Offset(0.250, 0.470), Offset(0.305, 0.468)],
    [Offset(0.350, 0.466), Offset(0.360, 0.545), Offset(0.400, 0.520)],
    [Offset(0.450, 0.487), Offset(0.462, 0.245), Offset(0.520, 0.245)],
    [Offset(0.578, 0.245), Offset(0.590, 0.470), Offset(0.632, 0.500)],
    [Offset(0.668, 0.525), Offset(0.688, 0.430), Offset(0.735, 0.432)],
    [Offset(0.788, 0.434), Offset(0.800, 0.560), Offset(_x1, _baseline)],
  ];

  static const _dashes = <List<double>>[
    [0.165, 0.300],
    [0.355, 0.490],
    [0.545, 0.680],
    [0.735, 0.835],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    final path = Path()..moveTo(_x0 * w, _baseline * h);
    for (final seg in _wave) {
      path.cubicTo(
        seg[0].dx * w,
        seg[0].dy * h,
        seg[1].dx * w,
        seg[1].dy * h,
        seg[2].dx * w,
        seg[2].dy * h,
      );
    }
    path
      ..lineTo(_x1 * w, _baseline * h)
      ..lineTo(_x0 * w, _baseline * h)
      ..close();
    canvas.drawPath(path, paint);

    // Dash weight is a fraction of the tile rather than a fixed width, so the
    // baseline stays visible at 24px instead of thinning away to nothing.
    // Rounded caps, but never wider than the dash is long.
    final strokeWidth = (h * 0.052).clamp(1.0, h);
    final dashPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final d in _dashes) {
      canvas.drawLine(
        Offset(d[0] * w + strokeWidth / 2, _dashY * h),
        Offset(d[1] * w - strokeWidth / 2, _dashY * h),
        dashPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
