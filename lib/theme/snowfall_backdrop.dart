import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Snow falling over drifts, on the theme's page colour, drawn under
/// [child].
///
/// Put under each route by `backdropPageTransitionsTheme`, like the other
/// backdrops, so the screen coming in covers the one going out.
class SnowfallBackdrop extends StatelessWidget {
  const SnowfallBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: SnowfallPainter(base: context.decor.pageColor),
        child: child,
      ),
    );
  }
}

/// One flake: where it is, how big, how visible, and whether it is drawn as
/// a six-armed star rather than a dot.
@immutable
class SnowFlake {
  const SnowFlake(this.center, this.radius, this.opacity, {this.star = false});

  final Offset center;
  final double radius;
  final double opacity;
  final bool star;
}

/// Paints the night: [base], a warm glow low down like lit windows behind
/// the snow, flakes — most of them dots, a few of them stars — and soft
/// drifts along the bottom.
///
/// Static and seeded, like the other backdrops: the same snow on every
/// screen, frozen mid-fall, and nothing animating behind the app.
///
/// Nothing is drawn in the top band, where the app bar sits in solid page
/// colour and snow would stop at a hard line under it.
class SnowfallPainter extends CustomPainter {
  const SnowfallPainter({required this.base});

  final Color base;

  static const int _flakeCount = 160;
  static const int _seed = 20261225;

  /// The band at the top kept clear, as a share of the height.
  static const double _clearTop = 0.15;

  static const Color _snow = Color(0xFFF7F3EA);
  static const Color _glow = Color(0xFFF2C14E);

  static final List<({double x, double y, double r, double o, bool star})>
      _unitFlakes = () {
    final random = math.Random(_seed);
    return List.generate(_flakeCount, (_) {
      final star = random.nextDouble() < 0.08;
      return (
        x: random.nextDouble(),
        y: _clearTop + random.nextDouble() * (1 - _clearTop),
        r: star
            ? 3.5 + random.nextDouble() * 2.5
            : 0.8 + random.nextDouble() * 1.8,
        o: star
            ? 0.20 + random.nextDouble() * 0.15
            : 0.15 + random.nextDouble() * 0.35,
        star: star,
      );
    });
  }();

  /// The snow for a canvas of [size].
  static List<SnowFlake> flakesFor(Size size) {
    return [
      for (final f in _unitFlakes)
        SnowFlake(
          Offset(f.x * size.width, f.y * size.height),
          f.r,
          f.o,
          star: f.star,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = base);

    final glowCentre = Offset(size.width * 0.5, size.height * 1.05);
    final glowRadius = size.longestSide * 0.55;
    canvas.drawCircle(
      glowCentre,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _glow.withValues(alpha: 0.12),
            _glow.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: glowCentre, radius: glowRadius),
        ),
    );

    final dot = Paint();
    final arm = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (final flake in flakesFor(size)) {
      if (flake.star) {
        arm.color = _snow.withValues(alpha: flake.opacity);
        for (var i = 0; i < 3; i++) {
          final a = i * math.pi / 3;
          final d = Offset(math.cos(a), math.sin(a)) * flake.radius;
          canvas.drawLine(flake.center - d, flake.center + d, arm);
        }
      } else {
        dot.color = _snow.withValues(alpha: flake.opacity);
        canvas.drawCircle(flake.center, flake.radius, dot);
      }
    }

    // Two drifts along the bottom, the back one fainter.
    final w = size.width;
    final h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.90)
        ..quadraticBezierTo(w * 0.30, h * 0.84, w * 0.62, h * 0.90)
        ..quadraticBezierTo(w * 0.85, h * 0.94, w, h * 0.88)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = _snow.withValues(alpha: 0.05),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.95)
        ..quadraticBezierTo(w * 0.40, h * 0.91, w * 0.75, h * 0.96)
        ..quadraticBezierTo(w * 0.90, h * 0.98, w, h * 0.95)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = _snow.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant SnowfallPainter oldDelegate) =>
      oldDelegate.base != base;
}
