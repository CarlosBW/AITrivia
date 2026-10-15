import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Cracked concrete in the theme's page colour, drawn under [child].
///
/// Put under each route by `backdropPageTransitionsTheme`, the same way the
/// starfield and the paper are, so the screen coming in covers the one going
/// out.
class WastelandBackdrop extends StatelessWidget {
  const WastelandBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: WastelandPainter(base: context.decor.pageColor),
        child: child,
      ),
    );
  }
}

/// One grain of dust on the concrete: where it is, how big, how visible.
@immutable
class DustMote {
  const DustMote(this.center, this.radius, this.opacity);

  final Offset center;
  final double radius;
  final double opacity;
}

/// Paints the concrete: [base], soot and rust stains, dust, a few cracks,
/// and a dull orange haze along the bottom, like a smoggy horizon.
///
/// Static and seeded, like the starfield and the paper: the same slab on
/// every screen and every launch, and nothing animating behind the app.
///
/// Everything is kept faint so text over it reads as it would on a flat
/// page, and nothing is drawn in the top band, where the app bar sits in
/// solid page colour and a crack would end in a hard line under it.
class WastelandPainter extends CustomPainter {
  const WastelandPainter({required this.base});

  final Color base;

  static const int _dustCount = 700;
  static const int _crackCount = 9;
  static const int _seed = 20771015;

  /// The band at the top kept clear of cracks, as a share of the height.
  static const double _clearTop = 0.15;

  static const Color _dust = Color(0xFFE8DCC4);
  static const Color _soot = Color(0xFF000000);
  static const Color _haze = Color(0xFFB8561F);

  static final List<({double x, double y, double r, double o})> _unitDust = () {
    final random = math.Random(_seed);
    return List.generate(_dustCount, (_) {
      return (
        x: random.nextDouble(),
        y: random.nextDouble(),
        r: 0.3 + random.nextDouble() * 0.8,
        o: 0.03 + random.nextDouble() * 0.09,
      );
    });
  }();

  /// Each crack as a jagged polyline in the unit square: a start, then a
  /// handful of short steps that wander around one heading.
  static final List<List<Offset>> _unitCracks = () {
    final random = math.Random(_seed + 1);
    return List.generate(_crackCount, (_) {
      var point = Offset(
        random.nextDouble(),
        _clearTop + 0.05 + random.nextDouble() * (0.95 - _clearTop),
      );
      final heading = random.nextDouble() * 2 * math.pi;
      final steps = 4 + random.nextInt(5);
      final points = [point];
      for (var i = 0; i < steps; i++) {
        final angle = heading + (random.nextDouble() - 0.5) * 1.4;
        final length = 0.02 + random.nextDouble() * 0.04;
        point = Offset(
          (point.dx + math.cos(angle) * length).clamp(0.0, 1.0),
          (point.dy + math.sin(angle) * length).clamp(_clearTop, 1.0),
        );
        points.add(point);
      }
      return points;
    });
  }();

  // Soft stains, as (centre in the unit square, radius as a share of the
  // longer side, colour): soot patches and rust. None sits in the top band.
  static const _stains = [
    (Offset(0.18, 0.42), 0.38, Color(0x26000000)),
    (Offset(0.82, 0.68), 0.42, Color(0x22000000)),
    (Offset(0.70, 0.30), 0.18, Color(0x1A8A3B12)),
    (Offset(0.25, 0.80), 0.14, Color(0x1F8A3B12)),
    (Offset(0.55, 0.55), 0.05, Color(0x1A9A4A18)),
    (Offset(0.92, 0.45), 0.04, Color(0x1A9A4A18)),
  ];

  /// The dust for a canvas of [size].
  static List<DustMote> dustFor(Size size) {
    return [
      for (final mote in _unitDust)
        DustMote(
          Offset(mote.x * size.width, mote.y * size.height),
          mote.r,
          mote.o,
        ),
    ];
  }

  /// The cracks for a canvas of [size], each a polyline of two or more
  /// points.
  static List<List<Offset>> cracksFor(Size size) {
    return [
      for (final crack in _unitCracks)
        [
          for (final p in crack) Offset(p.dx * size.width, p.dy * size.height),
        ],
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // The stains are wider than the canvas near its edges.
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = base);

    final longest = size.longestSide;
    for (final (center, radius, color) in _stains) {
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
    for (final mote in dustFor(size)) {
      dot.color = _dust.withValues(alpha: mote.opacity);
      canvas.drawCircle(mote.center, mote.radius, dot);
    }

    // A crack is a dark line with a faint light edge beside it, the way a
    // broken edge catches the light.
    final crackDark = Paint()
      ..color = _soot.withValues(alpha: 0.45)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final crackLight = Paint()
      ..color = _dust.withValues(alpha: 0.07)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (final crack in cracksFor(size)) {
      final path = Path()..addPolygon(crack, false);
      canvas.drawPath(path.shift(const Offset(0.8, 0.8)), crackLight);
      canvas.drawPath(path, crackDark);
    }

    // Smog on the horizon. Only the bottom: see the class comment about
    // the top.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.65, 1.0],
          colors: [
            _haze.withValues(alpha: 0),
            _haze.withValues(alpha: 0.10),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant WastelandPainter oldDelegate) =>
      oldDelegate.base != base;
}
