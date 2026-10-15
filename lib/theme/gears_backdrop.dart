import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Brass gears in the dark, in the theme's page colour, drawn under
/// [child].
///
/// Put under each route by `backdropPageTransitionsTheme`, like the other
/// backdrops, so the screen coming in covers the one going out.
class GearsBackdrop extends StatelessWidget {
  const GearsBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: GearsPainter(base: context.decor.pageColor),
        child: child,
      ),
    );
  }
}

/// One gear on the backdrop: where it sits, its outer radius, how many
/// teeth and how far it is turned.
@immutable
class BackdropGear {
  const BackdropGear(this.center, this.radius, this.teeth, this.turn);

  final Offset center;
  final double radius;
  final int teeth;
  final double turn;

  @override
  bool operator ==(Object other) =>
      other is BackdropGear &&
      other.center == center &&
      other.radius == radius &&
      other.teeth == teeth &&
      other.turn == turn;

  @override
  int get hashCode => Object.hash(center, radius, teeth, turn);

  @override
  String toString() => 'BackdropGear($center, r: $radius, teeth: $teeth)';
}

/// Paints the workshop: [base], a warm lamp glow, faint brass gears — some
/// running off the sides and the bottom as if the machine carried on past
/// the screen — and a copper pipe with its joints.
///
/// Static, like the other backdrops: the same machine on every screen and
/// nothing turning behind the app.
///
/// Everything is kept faint so text reads as it would on a flat page, and
/// nothing is drawn in the top band, where the app bar sits in solid page
/// colour.
class GearsPainter extends CustomPainter {
  const GearsPainter({required this.base});

  final Color base;

  static const Color _brass = Color(0xFFD4A04A);
  static const Color _copper = Color(0xFFC8743C);

  // The gears as (centre in the unit square, radius as a share of the
  // width, teeth, turn in radians). Sized against the width so a tall
  // phone doesn't stretch them; the centres sit low enough that none
  // reaches the top band on a phone.
  static const _unitGears = [
    (Offset(0.92, 0.80), 0.34, 14, 0.0),
    (Offset(0.30, 0.90), 0.22, 10, 0.2),
    (Offset(0.05, 0.55), 0.20, 9, 0.1),
    (Offset(0.62, 0.62), 0.12, 8, 0.3),
    (Offset(0.80, 0.35), 0.08, 7, 0.0),
  ];

  /// The gears for a canvas of [size].
  static List<BackdropGear> gearsFor(Size size) {
    return [
      for (final (center, radius, teeth, turn) in _unitGears)
        BackdropGear(
          Offset(center.dx * size.width, center.dy * size.height),
          radius * size.width,
          teeth,
          turn,
        ),
    ];
  }

  /// A gear's outline: [teeth] squared teeth round a rim, and a hub.
  static Path gearPath(BackdropGear gear) {
    final outer = gear.radius;
    final inner = gear.radius * 0.82;
    final step = 2 * math.pi / gear.teeth;
    final path = Path();
    for (var i = 0; i < gear.teeth; i++) {
      final a = gear.turn + i * step;
      // Each tooth: up the leading flank, across the top, down the
      // trailing flank, then along the rim to the next one.
      final points = [
        (inner, a),
        (outer, a + step * 0.12),
        (outer, a + step * 0.42),
        (inner, a + step * 0.54),
      ];
      for (var j = 0; j < points.length; j++) {
        final (r, angle) = points[j];
        final p =
            gear.center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0 && j == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    path.close();
    path.addOval(Rect.fromCircle(center: gear.center, radius: outer * 0.22));
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = base);

    // A lamp somewhere off to the left, warming the middle of the page.
    final glowCentre = Offset(size.width * 0.25, size.height * 0.55);
    final glowRadius = size.longestSide * 0.6;
    canvas.drawCircle(
      glowCentre,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _brass.withValues(alpha: 0.10),
            _brass.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: glowCentre, radius: glowRadius),
        ),
    );

    final fill = Paint()..color = _brass.withValues(alpha: 0.05);
    final edge = Paint()
      ..color = _brass.withValues(alpha: 0.16)
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final gear in gearsFor(size)) {
      final path = gearPath(gear);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }

    // A copper pipe across the lower part, with a joint every so often.
    final pipeY = size.height * 0.70;
    final pipe = Paint()
      ..color = _copper.withValues(alpha: 0.14)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(Offset(0, pipeY), Offset(size.width * 0.55, pipeY), pipe);
    final joint = Paint()..color = _copper.withValues(alpha: 0.20);
    for (final x in [0.12, 0.34, 0.55]) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(size.width * x, pipeY),
          width: 8,
          height: 12,
        ),
        joint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GearsPainter oldDelegate) =>
      oldDelegate.base != base;
}
