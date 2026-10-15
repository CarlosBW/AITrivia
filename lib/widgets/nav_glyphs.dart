import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bottom bar's four glyphs for [icons], in the bar's order: home,
/// versus, friends, store. The centre button is the app's logo in every
/// theme and isn't one of them.
///
/// Drawn rather than taken from `Icons` so a theme can bring its own set:
/// the bar asks the theme which set it is wearing and paints that one.
List<CustomPainter> navGlyphPainters(AppNavIcons icons, Color color) {
  switch (icons) {
    case AppNavIcons.classic:
      return [
        _HomeIconPainter(color),
        _SwordsPainter(color),
        _UsersIconPainter(color),
        _StoreIconPainter(color),
      ];
    case AppNavIcons.space:
      return [
        _PlanetPainter(color),
        _RocketPainter(color),
        _ConstellationPainter(color),
        _CrystalPainter(color),
      ];
    case AppNavIcons.vintage:
      return [
        _TownhousePainter(color),
        _FoilsPainter(color),
        _HattedPairPainter(color),
        _ShopSignPainter(color),
      ];
  }
}

Paint _stroke(Color color, double s, [double width = 0.085]) => Paint()
  ..color = color
  ..strokeWidth = s * width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

class _HomeIconPainter extends CustomPainter {
  final Color color;

  _HomeIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.10, s * 0.52)
        ..lineTo(s * 0.44, s * 0.16)
        ..quadraticBezierTo(s * 0.5, s * 0.10, s * 0.56, s * 0.16)
        ..lineTo(s * 0.90, s * 0.52),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.20, s * 0.44)
        ..lineTo(s * 0.20, s * 0.80)
        ..quadraticBezierTo(s * 0.20, s * 0.88, s * 0.28, s * 0.88)
        ..lineTo(s * 0.72, s * 0.88)
        ..quadraticBezierTo(s * 0.80, s * 0.88, s * 0.80, s * 0.80)
        ..lineTo(s * 0.80, s * 0.44),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.42, s * 0.88)
        ..lineTo(s * 0.42, s * 0.64)
        ..quadraticBezierTo(s * 0.42, s * 0.60, s * 0.46, s * 0.60)
        ..lineTo(s * 0.54, s * 0.60)
        ..quadraticBezierTo(s * 0.58, s * 0.60, s * 0.58, s * 0.64)
        ..lineTo(s * 0.58, s * 0.88),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// Ported 1:1 from the Tabler "swords" outline icon (24x24 viewBox).
class _SwordsPainter extends CustomPainter {
  final Color color;

  _SwordsPainter(this.color);

  static const _path1 = [
    Offset(21, 3),
    Offset(21, 8),
    Offset(10, 17),
    Offset(6, 21),
    Offset(3, 18),
    Offset(7, 14),
    Offset(16, 3),
    Offset(21, 3),
  ];
  static const _path2 = [Offset(5, 13), Offset(11, 19)];
  static const _path3 = [
    Offset(14.32, 17.32),
    Offset(18, 21),
    Offset(21, 18),
    Offset(17.635, 14.635),
  ];
  static const _path4 = [
    Offset(10, 5.5),
    Offset(8, 3),
    Offset(3, 3),
    Offset(3, 8),
    Offset(6, 10.5),
  ];

  void _drawPolyline(
    Canvas canvas,
    Paint paint,
    List<Offset> points,
    double s,
  ) {
    final path = Path()
      ..moveTo(points.first.dx / 24 * s, points.first.dy / 24 * s);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx / 24 * s, p.dy / 24 * s);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * (2 / 24)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    _drawPolyline(canvas, paint, _path1, s);
    _drawPolyline(canvas, paint, _path2, s);
    _drawPolyline(canvas, paint, _path3, s);
    _drawPolyline(canvas, paint, _path4, s);
  }

  @override
  bool shouldRepaint(covariant _SwordsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _UsersIconPainter extends CustomPainter {
  final Color color;

  _UsersIconPainter(this.color);

  void _drawPerson(
    Canvas canvas,
    Paint paint,
    Offset headCenter,
    double headR,
    Offset shoulderCenter,
    double shoulderR,
  ) {
    canvas.drawCircle(headCenter, headR, paint);
    canvas.drawArc(
      Rect.fromCircle(center: shoulderCenter, radius: shoulderR),
      math.pi,
      math.pi,
      false,
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    _drawPerson(
      canvas,
      paint,
      Offset(s * 0.30, s * 0.30),
      s * 0.15,
      Offset(s * 0.30, s * 0.80),
      s * 0.22,
    );
    _drawPerson(
      canvas,
      paint,
      Offset(s * 0.72, s * 0.34),
      s * 0.12,
      Offset(s * 0.72, s * 0.80),
      s * 0.18,
    );
  }

  @override
  bool shouldRepaint(covariant _UsersIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Storefront with an awning, for the store tab. Replaced the person glyph
/// when the profile moved out of the bar and into the header avatar.
///
/// The awning's scalloped edge is drawn as three arcs rather than a plain
/// line: at this size it is the detail that makes the shape read as a shop
/// instead of a house.
class _StoreIconPainter extends CustomPainter {
  final Color color;

  _StoreIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Alto igualado al del resto de la barra: la casa ocupa de 0.10 a 0.88
    // y los amigos de 0.15 a 0.80. Este iba de 0.28 a 0.84 — mas corto y
    // con el centro 7 puntos mas abajo, que es por lo que se veia
    // descolgado respecto a sus vecinos.
    const awningTop = 0.14;
    const awningBottom = 0.38;
    const bodyTop = 0.44;
    const bodyBottom = 0.86;

    const awningLeft = 0.08;
    const awningRight = 0.92;

    // Toldo: se ensancha hacia abajo y sobresale del cuerpo. Sin trazar su
    // base, que la cierra el feston.
    final awning = Path()
      ..moveTo(s * awningLeft, s * awningBottom)
      ..lineTo(s * 0.18, s * awningTop)
      ..lineTo(s * 0.82, s * awningTop)
      ..lineTo(s * awningRight, s * awningBottom);
    canvas.drawPath(awning, paint);

    // Feston: cuatro ondas que hacen las veces de borde inferior del toldo.
    const scallops = 4;
    const scallopWidth = (awningRight - awningLeft) / scallops;
    for (var i = 0; i < scallops; i++) {
      final left = awningLeft + scallopWidth * i;
      canvas.drawArc(
        Rect.fromLTRB(
          s * left,
          s * (awningBottom - 0.06),
          s * (left + scallopWidth),
          s * (awningBottom + 0.06),
        ),
        0,
        math.pi,
        false,
        paint,
      );
    }

    // Cuerpo en forma de U: el feston ya cierra la parte de arriba, asi que
    // trazar tambien su techo duplicaria la linea.
    final body = Path()
      ..moveTo(s * 0.18, s * bodyTop)
      ..lineTo(s * 0.18, s * bodyBottom)
      ..lineTo(s * 0.82, s * bodyBottom)
      ..lineTo(s * 0.82, s * bodyTop);
    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(covariant _StoreIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Home, in the Space theme: a ringed planet.
///
/// The half of the ring behind the planet is only drawn where it shows past
/// the planet's edge — that gap is what makes it read as a ring around a
/// sphere rather than a line through a circle.
class _PlanetPainter extends CustomPainter {
  final Color color;

  _PlanetPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s);
    final center = Offset(s * 0.5, s * 0.5);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.4);

    canvas.drawCircle(Offset.zero, s * 0.24, paint);

    final ring = Rect.fromCenter(
      center: Offset.zero,
      width: s * 0.92,
      height: s * 0.30,
    );
    // Front half, crossing the planet.
    canvas.drawArc(ring, 0, math.pi, false, paint);
    // Back half: only the two ends that stick out past the planet.
    canvas.drawArc(ring, math.pi, 0.62, false, paint);
    canvas.drawArc(ring, 2 * math.pi - 0.62, 0.62, false, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlanetPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Versus, in the Space theme: a rocket climbing to the upper right.
class _RocketPainter extends CustomPainter {
  final Color color;

  _RocketPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);

    // Drawn upright, then tilted: the shapes stay symmetric that way.
    canvas.save();
    canvas.translate(s * 0.5, s * 0.5);
    canvas.rotate(math.pi / 4);
    canvas.scale(0.92);
    canvas.translate(-s * 0.5, -s * 0.5);

    final body = Path()
      ..moveTo(s * 0.5, s * 0.06)
      ..quadraticBezierTo(s * 0.66, s * 0.20, s * 0.64, s * 0.40)
      ..lineTo(s * 0.64, s * 0.66)
      ..lineTo(s * 0.36, s * 0.66)
      ..lineTo(s * 0.36, s * 0.40)
      ..quadraticBezierTo(s * 0.34, s * 0.20, s * 0.5, s * 0.06)
      ..close();
    canvas.drawPath(body, paint);

    canvas.drawCircle(Offset(s * 0.5, s * 0.36), s * 0.07, paint);

    final leftFin = Path()
      ..moveTo(s * 0.36, s * 0.48)
      ..lineTo(s * 0.22, s * 0.62)
      ..lineTo(s * 0.22, s * 0.74)
      ..lineTo(s * 0.36, s * 0.66);
    final rightFin = Path()
      ..moveTo(s * 0.64, s * 0.48)
      ..lineTo(s * 0.78, s * 0.62)
      ..lineTo(s * 0.78, s * 0.74)
      ..lineTo(s * 0.64, s * 0.66);
    canvas.drawPath(leftFin, paint);
    canvas.drawPath(rightFin, paint);

    final flame = Path()
      ..moveTo(s * 0.43, s * 0.76)
      ..lineTo(s * 0.5, s * 0.94)
      ..lineTo(s * 0.57, s * 0.76);
    canvas.drawPath(flame, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RocketPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Friends, in the Space theme: a constellation — separate stars that
/// belong together.
class _ConstellationPainter extends CustomPainter {
  final Color color;

  _ConstellationPainter(this.color);

  static const _stars = [
    Offset(0.12, 0.72),
    Offset(0.34, 0.36),
    Offset(0.60, 0.52),
    Offset(0.88, 0.18),
    Offset(0.74, 0.86),
  ];

  // Pairs of indexes into [_stars].
  static const _links = [(0, 1), (1, 2), (2, 3), (2, 4)];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final line = _stroke(color, s, 0.055);
    final dot = Paint()..color = color;

    for (final (a, b) in _links) {
      canvas.drawLine(_stars[a] * s, _stars[b] * s, line);
    }
    for (var i = 0; i < _stars.length; i++) {
      // The middle star is the brightest: it is where the lines meet.
      canvas.drawCircle(_stars[i] * s, s * (i == 2 ? 0.1 : 0.075), dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Store, in the Space theme: a cut crystal — something to collect.
class _CrystalPainter extends CustomPainter {
  final Color color;

  _CrystalPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s);
    final facet = _stroke(color, s, 0.06);

    const top = 0.18;
    const girdle = 0.40;
    const tip = Offset(0.5, 0.88);

    final outline = Path()
      ..moveTo(s * 0.30, s * top)
      ..lineTo(s * 0.70, s * top)
      ..lineTo(s * 0.90, s * girdle)
      ..lineTo(s * tip.dx, s * tip.dy)
      ..lineTo(s * 0.10, s * girdle)
      ..close();
    canvas.drawPath(outline, paint);

    canvas.drawLine(
        Offset(s * 0.10, s * girdle), Offset(s * 0.90, s * girdle), facet);
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.30, s * top)
        ..lineTo(s * 0.40, s * girdle)
        ..lineTo(s * tip.dx, s * tip.dy)
        ..moveTo(s * 0.70, s * top)
        ..lineTo(s * 0.60, s * girdle)
        ..lineTo(s * tip.dx, s * tip.dy),
      facet,
    );
  }

  @override
  bool shouldRepaint(covariant _CrystalPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Home, in the Vintage theme: a townhouse with a chimney, an arched door
/// and a round window in the gable.
class _TownhousePainter extends CustomPainter {
  final Color color;

  _TownhousePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);

    // The chimney starts and ends on the roof's slope, so the two meet
    // without a gap or an overhang.
    final house = Path()
      ..moveTo(s * 0.10, s * 0.48)
      ..lineTo(s * 0.50, s * 0.14)
      ..lineTo(s * 0.68, s * 0.293)
      ..lineTo(s * 0.68, s * 0.12)
      ..lineTo(s * 0.78, s * 0.12)
      ..lineTo(s * 0.78, s * 0.378)
      ..lineTo(s * 0.90, s * 0.48)
      ..moveTo(s * 0.20, s * 0.40)
      ..lineTo(s * 0.20, s * 0.88)
      ..lineTo(s * 0.80, s * 0.88)
      ..lineTo(s * 0.80, s * 0.40);
    canvas.drawPath(house, paint);

    final door = Path()
      ..moveTo(s * 0.42, s * 0.88)
      ..lineTo(s * 0.42, s * 0.68)
      ..arcToPoint(Offset(s * 0.58, s * 0.68),
          radius: Radius.circular(s * 0.08))
      ..lineTo(s * 0.58, s * 0.88);
    canvas.drawPath(door, paint);

    canvas.drawCircle(
        Offset(s * 0.5, s * 0.42), s * 0.06, _stroke(color, s, 0.06));
  }

  @override
  bool shouldRepaint(covariant _TownhousePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Versus, in the Vintage theme: two fencing foils crossed, bell guards
/// down — a duel by the rules.
class _FoilsPainter extends CustomPainter {
  final Color color;

  _FoilsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.065);
    final fill = Paint()..color = color;

    // One foil drawn upright, then laid down at each diagonal.
    for (final angle in [math.pi / 4, -math.pi / 4]) {
      canvas.save();
      canvas.translate(s * 0.5, s * 0.5);
      canvas.rotate(angle);
      canvas.translate(-s * 0.5, -s * 0.5);

      canvas.drawLine(
          Offset(s * 0.5, s * 0.06), Offset(s * 0.5, s * 0.94), paint);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(s * 0.5, s * 0.74), radius: s * 0.15),
        math.pi,
        math.pi,
        true,
        fill,
      );
      // The button on the tip that makes it a foil and not a sword.
      canvas.drawCircle(Offset(s * 0.5, s * 0.06), s * 0.05, fill);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FoilsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Friends, in the Vintage theme: two gentlemen side by side, one in a top
/// hat and one in a bowler.
class _HattedPairPainter extends CustomPainter {
  final Color color;

  _HattedPairPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.075);
    final fill = Paint()..color = color;

    const headY = 0.55;
    const headR = 0.10;
    const brimY = headY - headR;

    void bust(double cx) {
      canvas.drawCircle(Offset(s * cx, s * headY), s * headR, paint);
      canvas.drawPath(
        Path()
          ..moveTo(s * (cx - 0.17), s * 0.92)
          ..quadraticBezierTo(s * (cx - 0.17), s * 0.70, s * cx, s * 0.70)
          ..quadraticBezierTo(
              s * (cx + 0.17), s * 0.70, s * (cx + 0.17), s * 0.92),
        paint,
      );
      canvas.drawLine(
        Offset(s * (cx - 0.15), s * brimY),
        Offset(s * (cx + 0.15), s * brimY),
        paint,
      );
    }

    // Top hat: a tall crown, filled so it still reads at bar size.
    bust(0.30);
    canvas.drawRect(
      Rect.fromLTRB(s * 0.21, s * 0.18, s * 0.39, s * brimY),
      fill,
    );

    // Bowler: a low dome.
    bust(0.70);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s * 0.70, s * brimY), radius: s * 0.10),
      math.pi,
      math.pi,
      true,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _HattedPairPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Store, in the Vintage theme: a shop sign hanging from a wall bracket,
/// with a coin painted on the board.
class _ShopSignPainter extends CustomPainter {
  final Color color;

  _ShopSignPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.075);
    final thin = _stroke(color, s, 0.055);

    final bracket = Path()
      ..moveTo(s * 0.12, s * 0.92)
      ..lineTo(s * 0.12, s * 0.08)
      ..moveTo(s * 0.12, s * 0.16)
      ..lineTo(s * 0.90, s * 0.16)
      ..moveTo(s * 0.12, s * 0.38)
      ..lineTo(s * 0.36, s * 0.16);
    canvas.drawPath(bracket, paint);

    canvas.drawLine(
        Offset(s * 0.38, s * 0.16), Offset(s * 0.38, s * 0.40), thin);
    canvas.drawLine(
        Offset(s * 0.78, s * 0.16), Offset(s * 0.78, s * 0.40), thin);

    canvas.drawRRect(
      RRect.fromLTRBR(
        s * 0.28,
        s * 0.40,
        s * 0.88,
        s * 0.80,
        Radius.circular(s * 0.06),
      ),
      paint,
    );
    canvas.drawCircle(Offset(s * 0.58, s * 0.60), s * 0.09, thin);
  }

  @override
  bool shouldRepaint(covariant _ShopSignPainter oldDelegate) =>
      oldDelegate.color != color;
}
