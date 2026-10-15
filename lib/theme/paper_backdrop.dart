import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Aged paper in the theme's page colour, drawn under [child].
///
/// Put under each route by `backdropPageTransitionsTheme`, the same way the
/// starfield is, so the screen coming in covers the one going out.
class PaperBackdrop extends StatelessWidget {
  const PaperBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: PaperPainter(base: context.decor.pageColor),
        child: child,
      ),
    );
  }
}

/// One mark in the paper's grain: where it is, how big, and whether it is a
/// darker fleck or a lighter one.
@immutable
class PaperSpeck {
  const PaperSpeck(this.center, this.radius, this.opacity, {this.dark = true});

  final Offset center;
  final double radius;
  final double opacity;
  final bool dark;
}

/// Paints the paper: [base], uneven tone, grain, a few fibres and age spots,
/// and a darkening towards the bottom edge.
///
/// Static and seeded, like the starfield: the same sheet on every screen
/// and every launch, and nothing animating behind the app.
///
/// Everything is kept faint and nothing is drawn darker along the top,
/// where the app bar sits in solid page colour and a change of tone would
/// end in a hard line under it.
class PaperPainter extends CustomPainter {
  const PaperPainter({required this.base});

  final Color base;

  static const int _speckCount = 900;
  static const int _fibreCount = 40;
  static const int _seed = 19251015;

  static const Color _darkInk = Color(0xFF5A3D1E);
  static const Color _lightFleck = Color(0xFFFFFBF0);

  /// Grain in the unit square, scaled to the canvas, so a phone and a
  /// tablet get the same sheet.
  static final List<({double x, double y, double r, double o, bool dark})>
      _unitSpecks = () {
    final random = math.Random(_seed);
    return List.generate(_speckCount, (_) {
      final dark = random.nextDouble() < 0.7;
      return (
        x: random.nextDouble(),
        y: random.nextDouble(),
        r: 0.3 + random.nextDouble() * 0.7,
        o: dark
            ? 0.04 + random.nextDouble() * 0.08
            : 0.25 + random.nextDouble() * 0.35,
        dark: dark,
      );
    });
  }();

  static final List<({double x, double y, double length, double angle})>
      _unitFibres = () {
    final random = math.Random(_seed + 1);
    return List.generate(_fibreCount, (_) {
      return (
        x: random.nextDouble(),
        y: random.nextDouble(),
        length: 6 + random.nextDouble() * 14,
        angle: random.nextDouble() * math.pi,
      );
    });
  }();

  // Soft patches of uneven tone, as (centre in the unit square, radius as a
  // share of the longer side, colour). The age spots are the small dark
  // ones; none sits near the top edge.
  static const _patches = [
    (Offset(0.15, 0.55), 0.45, Color(0x33FFF8E6)),
    (Offset(0.85, 0.30), 0.40, Color(0x29FFF8E6)),
    (Offset(0.70, 0.80), 0.35, Color(0x14B08850)),
    (Offset(0.22, 0.86), 0.030, Color(0x1A9A6A30)),
    (Offset(0.78, 0.62), 0.022, Color(0x179A6A30)),
    (Offset(0.55, 0.40), 0.016, Color(0x129A6A30)),
    (Offset(0.90, 0.92), 0.026, Color(0x1A9A6A30)),
  ];

  /// The grain for a canvas of [size].
  static List<PaperSpeck> specksFor(Size size) {
    return [
      for (final speck in _unitSpecks)
        PaperSpeck(
          Offset(speck.x * size.width, speck.y * size.height),
          speck.r,
          speck.o,
          dark: speck.dark,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);

    final longest = size.longestSide;
    for (final (center, radius, color) in _patches) {
      final c = Offset(center.dx * size.width, center.dy * size.height);
      final r = radius * longest;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final dot = Paint();
    for (final speck in specksFor(size)) {
      dot.color = (speck.dark ? _darkInk : _lightFleck)
          .withValues(alpha: speck.opacity);
      canvas.drawCircle(speck.center, speck.radius, dot);
    }

    final fibre = Paint()
      ..color = _darkInk.withValues(alpha: 0.07)
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;
    for (final f in _unitFibres) {
      final start = Offset(f.x * size.width, f.y * size.height);
      final end = start +
          Offset(math.cos(f.angle) * f.length, math.sin(f.angle) * f.length);
      canvas.drawLine(start, end, fibre);
    }

    // The bottom edge browns a little, as old paper does at the margin
    // held most. Only the bottom: see the class comment about the top.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.7, 1.0],
          colors: [
            _darkInk.withValues(alpha: 0),
            _darkInk.withValues(alpha: 0.12),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant PaperPainter oldDelegate) =>
      oldDelegate.base != base;
}
