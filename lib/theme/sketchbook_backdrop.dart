import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A sketchbook page in the theme's page colour, drawn under [child].
///
/// Put under each route by `backdropPageTransitionsTheme`, the same way the
/// paper is, so the screen coming in covers the one going out.
class SketchbookBackdrop extends StatelessWidget {
  const SketchbookBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: SketchbookPainter(base: context.decor.pageColor),
        child: child,
      ),
    );
  }
}

/// One pencil line: where it starts and ends, how dark and how thick.
@immutable
class SketchStroke {
  const SketchStroke(this.start, this.end, this.opacity, this.width);

  final Offset start;
  final Offset end;
  final double opacity;
  final double width;
}

/// Paints the page: [base], a little graphite grain, and patches of loose
/// pencil hatching, as in the margins of a sketchbook.
///
/// Static and seeded, like the other backdrops: the same page on every
/// screen and every launch, and nothing moving behind the app.
///
/// Kept faint so text reads over it, and nothing is drawn in the top
/// strip, where the app bar sits in solid page colour and a mark would be
/// cut off in a hard line under it.
class SketchbookPainter extends CustomPainter {
  const SketchbookPainter({required this.base});

  final Color base;

  static const int _seed = 20261107;
  static const int _grainCount = 500;
  static const Color _graphite = Color(0xFF2A2A2A);

  /// No marks above this share of the height; see the class comment.
  static const double _topClear = 0.15;

  /// Hatching patches as (centre in the unit square, width and height as a
  /// share of the shorter side, line angle). Mostly towards the edges, so
  /// the middle of the page, where cards sit, stays clean.
  static const _patches = [
    (Offset(0.10, 0.30), Size(0.30, 0.16), -0.9),
    (Offset(0.92, 0.48), Size(0.26, 0.22), -0.8),
    (Offset(0.14, 0.72), Size(0.34, 0.18), -1.0),
    (Offset(0.86, 0.88), Size(0.40, 0.16), -0.85),
    (Offset(0.50, 0.97), Size(0.50, 0.06), -0.95),
  ];

  /// The hatching for a canvas of [size].
  static List<SketchStroke> strokesFor(Size size) {
    final random = math.Random(_seed);
    final side = size.shortestSide;
    final top = size.height * _topClear;
    final strokes = <SketchStroke>[];

    Offset clamp(Offset p) => Offset(
          p.dx.clamp(0.0, size.width),
          p.dy.clamp(top, size.height),
        );

    for (final (center, extent, angle) in _patches) {
      final c = Offset(center.dx * size.width, center.dy * size.height);
      final w = extent.width * side;
      final h = extent.height * side;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final lines = (w / 6).round();

      for (var i = 0; i < lines; i++) {
        // Lines march across the patch, each a little uneven in length and
        // place, as a hand draws them.
        final along = -w / 2 + i * (w / lines) + random.nextDouble() * 2;
        final length = h * (0.6 + random.nextDouble() * 0.5);
        final mid = c + Offset(along, (random.nextDouble() - 0.5) * h * 0.3);
        strokes.add(SketchStroke(
          clamp(mid - direction * (length / 2)),
          clamp(mid + direction * (length / 2)),
          0.05 + random.nextDouble() * 0.06,
          0.6 + random.nextDouble() * 0.6,
        ));
      }
    }

    return strokes;
  }

  static final List<({double x, double y, double r, double o})> _unitGrain =
      () {
    final random = math.Random(_seed + 1);
    return List.generate(_grainCount, (_) {
      return (
        x: random.nextDouble(),
        y: _topClear + random.nextDouble() * (1 - _topClear),
        r: 0.3 + random.nextDouble() * 0.5,
        o: 0.03 + random.nextDouble() * 0.06,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final dot = Paint();
    for (final grain in _unitGrain) {
      dot.color = _graphite.withValues(alpha: grain.o);
      canvas.drawCircle(
        Offset(grain.x * size.width, grain.y * size.height),
        grain.r,
        dot,
      );
    }

    final line = Paint()..strokeCap = StrokeCap.round;
    for (final stroke in strokesFor(size)) {
      line
        ..color = _graphite.withValues(alpha: stroke.opacity)
        ..strokeWidth = stroke.width;
      canvas.drawLine(stroke.start, stroke.end, line);
    }
  }

  @override
  bool shouldRepaint(covariant SketchbookPainter oldDelegate) =>
      oldDelegate.base != base;
}
