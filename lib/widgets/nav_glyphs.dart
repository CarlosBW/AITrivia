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
    case AppNavIcons.apocalypse:
      return [
        _BunkerPainter(color),
        _WrenchAndCrowbarPainter(color),
        _SurvivorsPainter(color),
        _SupplyCratePainter(color),
      ];
    case AppNavIcons.cyberpunk:
      return [
        _MegablockPainter(color),
        _LightningPainter(color),
        _VisorPairPainter(color),
        _MicrochipPainter(color),
      ];
    case AppNavIcons.steampunk:
      return [
        _GearHousePainter(color),
        _MeshingGearsPainter(color),
        _AviatorPairPainter(color),
        _CashRegisterPainter(color),
      ];
    case AppNavIcons.christmas:
      return [
        _SnowyHousePainter(color),
        _CandyCanesPainter(color),
        _SnowmenPainter(color),
        _GiftPainter(color),
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

/// Home, in the Apocalypse theme: a half-buried bunker with a hatch and a
/// bent vent pipe.
class _BunkerPainter extends CustomPainter {
  final Color color;

  _BunkerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);

    const groundY = 0.84;
    const domeR = 0.38;

    canvas.drawLine(
      Offset(s * 0.04, s * groundY),
      Offset(s * 0.96, s * groundY),
      paint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s * 0.5, s * groundY), radius: s * domeR),
      math.pi,
      math.pi,
      false,
      paint,
    );

    // The pipe leaves the dome where the dome is, so the two meet cleanly.
    const pipeX = 0.70;
    final pipeBase = groundY - math.sqrt(domeR * domeR - 0.2 * 0.2);
    canvas.drawPath(
      Path()
        ..moveTo(s * pipeX, s * pipeBase)
        ..lineTo(s * pipeX, s * 0.20)
        ..lineTo(s * 0.84, s * 0.20),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.40, s * groundY)
        ..lineTo(s * 0.40, s * 0.68)
        ..arcToPoint(
          Offset(s * 0.60, s * 0.68),
          radius: Radius.circular(s * 0.10),
        )
        ..lineTo(s * 0.60, s * groundY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BunkerPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Versus, in the Apocalypse theme: a wrench and a crowbar crossed — what
/// there is to fight with.
class _WrenchAndCrowbarPainter extends CustomPainter {
  final Color color;

  _WrenchAndCrowbarPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.085);

    // Each drawn upright, then laid down on its diagonal.
    void upright(double angle, void Function() draw) {
      canvas.save();
      canvas.translate(s * 0.5, s * 0.5);
      canvas.rotate(angle);
      canvas.translate(-s * 0.5, -s * 0.5);
      draw();
      canvas.restore();
    }

    upright(math.pi / 4, () {
      canvas.drawLine(
          Offset(s * 0.5, s * 0.30), Offset(s * 0.5, s * 0.94), paint);
      // Open-ended jaw: a ring with a gap facing the tip.
      canvas.drawArc(
        Rect.fromCircle(center: Offset(s * 0.5, s * 0.18), radius: s * 0.13),
        -math.pi / 2 + 0.75,
        2 * math.pi - 1.5,
        false,
        paint,
      );
    });

    upright(-math.pi / 4, () {
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.5, s * 0.94)
          ..lineTo(s * 0.5, s * 0.24)
          ..quadraticBezierTo(s * 0.5, s * 0.06, s * 0.33, s * 0.10),
        paint,
      );
    });
  }

  @override
  bool shouldRepaint(covariant _WrenchAndCrowbarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Friends, in the Apocalypse theme: two survivors in goggles, side by side.
class _SurvivorsPainter extends CustomPainter {
  final Color color;

  _SurvivorsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.075);
    final fill = Paint()..color = color;

    const headY = 0.40;
    const headR = 0.13;

    void survivor(double cx) {
      canvas.drawCircle(Offset(s * cx, s * headY), s * headR, paint);
      // Goggles: two solid lenses, so they still read at bar size.
      for (final dx in [-0.055, 0.055]) {
        canvas.drawCircle(Offset(s * (cx + dx), s * headY), s * 0.045, fill);
      }
      canvas.drawPath(
        Path()
          ..moveTo(s * (cx - 0.19), s * 0.92)
          ..quadraticBezierTo(s * (cx - 0.19), s * 0.64, s * cx, s * 0.64)
          ..quadraticBezierTo(
              s * (cx + 0.19), s * 0.64, s * (cx + 0.19), s * 0.92),
        paint,
      );
    }

    survivor(0.27);
    survivor(0.73);
  }

  @override
  bool shouldRepaint(covariant _SurvivorsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Store, in the Apocalypse theme: a wooden supply crate, braced.
class _SupplyCratePainter extends CustomPainter {
  final Color color;

  _SupplyCratePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);
    final thin = _stroke(color, s, 0.06);

    canvas.drawRRect(
      RRect.fromLTRBR(
        s * 0.12,
        s * 0.16,
        s * 0.88,
        s * 0.86,
        Radius.circular(s * 0.04),
      ),
      paint,
    );
    // The inner frame and one brace across it: a crate, not a box.
    const inner = (l: 0.25, t: 0.29, r: 0.75, b: 0.73);
    canvas.drawRect(
      Rect.fromLTRB(s * inner.l, s * inner.t, s * inner.r, s * inner.b),
      thin,
    );
    canvas.drawLine(
      Offset(s * inner.l, s * inner.b),
      Offset(s * inner.r, s * inner.t),
      thin,
    );
  }

  @override
  bool shouldRepaint(covariant _SupplyCratePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Home, in the Cyberpunk theme: a tower block with an antenna and lit
/// windows, a lower block beside it.
class _MegablockPainter extends CustomPainter {
  final Color color;

  _MegablockPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);
    final fill = Paint()..color = color;

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.20, s * 0.92)
        ..lineTo(s * 0.20, s * 0.22)
        ..lineTo(s * 0.56, s * 0.22)
        ..lineTo(s * 0.56, s * 0.92)
        ..moveTo(s * 0.56, s * 0.48)
        ..lineTo(s * 0.84, s * 0.48)
        ..lineTo(s * 0.84, s * 0.92)
        ..moveTo(s * 0.10, s * 0.92)
        ..lineTo(s * 0.92, s * 0.92)
        ..moveTo(s * 0.38, s * 0.22)
        ..lineTo(s * 0.38, s * 0.06),
      paint,
    );

    for (final x in [0.30, 0.46]) {
      for (final y in [0.36, 0.52, 0.68]) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(s * x, s * y),
            width: s * 0.07,
            height: s * 0.07,
          ),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MegablockPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Versus, in the Cyberpunk theme: a bolt of current.
class _LightningPainter extends CustomPainter {
  final Color color;

  _LightningPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);

    const points = [
      Offset(0.62, 0.06),
      Offset(0.24, 0.54),
      Offset(0.48, 0.54),
      Offset(0.38, 0.94),
      Offset(0.78, 0.42),
      Offset(0.54, 0.42),
    ];
    canvas.drawPath(
      Path()..addPolygon([for (final p in points) p * s], true),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LightningPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Friends, in the Cyberpunk theme: two people in visor shades, side by
/// side.
class _VisorPairPainter extends CustomPainter {
  final Color color;

  _VisorPairPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.075);
    final fill = Paint()..color = color;

    const headY = 0.40;
    const headR = 0.13;

    void person(double cx) {
      canvas.drawCircle(Offset(s * cx, s * headY), s * headR, paint);
      // One solid band across the eyes, a little wider than the head.
      canvas.drawRect(
        Rect.fromLTRB(
          s * (cx - 0.17),
          s * (headY - 0.05),
          s * (cx + 0.17),
          s * (headY + 0.04),
        ),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(s * (cx - 0.19), s * 0.92)
          ..quadraticBezierTo(s * (cx - 0.19), s * 0.64, s * cx, s * 0.64)
          ..quadraticBezierTo(
              s * (cx + 0.19), s * 0.64, s * (cx + 0.19), s * 0.92),
        paint,
      );
    }

    person(0.27);
    person(0.73);
  }

  @override
  bool shouldRepaint(covariant _VisorPairPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Store, in the Cyberpunk theme: a microchip — credits on a chip.
class _MicrochipPainter extends CustomPainter {
  final Color color;

  _MicrochipPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);
    final pin = _stroke(color, s, 0.07);
    final fill = Paint()..color = color;

    canvas.drawRRect(
      RRect.fromLTRBR(
        s * 0.24,
        s * 0.24,
        s * 0.76,
        s * 0.76,
        Radius.circular(s * 0.04),
      ),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(s * 0.41, s * 0.41, s * 0.59, s * 0.59),
      fill,
    );

    // Three pins on each side.
    for (final t in [0.36, 0.50, 0.64]) {
      canvas.drawLine(Offset(s * t, s * 0.24), Offset(s * t, s * 0.10), pin);
      canvas.drawLine(Offset(s * t, s * 0.76), Offset(s * t, s * 0.90), pin);
      canvas.drawLine(Offset(s * 0.24, s * t), Offset(s * 0.10, s * t), pin);
      canvas.drawLine(Offset(s * 0.76, s * t), Offset(s * 0.90, s * t), pin);
    }
  }

  @override
  bool shouldRepaint(covariant _MicrochipPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A gear's outline round [center]: [teeth] squared teeth between [inner]
/// and [outer], starting at [turn] radians.
Path _gearOutline(
  Offset center,
  double outer,
  double inner,
  int teeth, [
  double turn = 0,
]) {
  final step = 2 * math.pi / teeth;
  final path = Path();
  for (var i = 0; i < teeth; i++) {
    final a = turn + i * step;
    final corners = [
      (inner, a),
      (outer, a + step * 0.15),
      (outer, a + step * 0.45),
      (inner, a + step * 0.60),
    ];
    for (var j = 0; j < corners.length; j++) {
      final (r, angle) = corners[j];
      final p = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0 && j == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
  }
  return path..close();
}

/// Home, in the Steampunk theme: a house with a gear set in its wall and
/// a chimney letting off a puff of steam.
class _GearHousePainter extends CustomPainter {
  final Color color;

  _GearHousePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);
    final thin = _stroke(color, s, 0.06);

    // Roof, walls, and a chimney that starts and ends on the roof slope.
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.10, s * 0.50)
        ..lineTo(s * 0.50, s * 0.16)
        ..lineTo(s * 0.68, s * 0.313)
        ..lineTo(s * 0.68, s * 0.18)
        ..lineTo(s * 0.78, s * 0.18)
        ..lineTo(s * 0.78, s * 0.398)
        ..lineTo(s * 0.90, s * 0.50)
        ..moveTo(s * 0.20, s * 0.42)
        ..lineTo(s * 0.20, s * 0.88)
        ..lineTo(s * 0.80, s * 0.88)
        ..lineTo(s * 0.80, s * 0.42),
      paint,
    );
    canvas.drawCircle(Offset(s * 0.80, s * 0.07), s * 0.045, thin);

    final hub = Offset(s * 0.5, s * 0.64);
    canvas.drawPath(_gearOutline(hub, s * 0.17, s * 0.12, 8), thin);
    canvas.drawCircle(hub, s * 0.04, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GearHousePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Versus, in the Steampunk theme: two gears in mesh, teeth against teeth.
class _MeshingGearsPainter extends CustomPainter {
  final Color color;

  _MeshingGearsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.07);
    final fill = Paint()..color = color;

    final big = Offset(s * 0.38, s * 0.60);
    final small = Offset(s * 0.75, s * 0.27);
    canvas.drawPath(_gearOutline(big, s * 0.30, s * 0.22, 10), paint);
    // Turned half a tooth so its teeth fall between those of the big one.
    canvas.drawPath(
      _gearOutline(small, s * 0.20, s * 0.14, 7, math.pi / 7),
      paint,
    );
    canvas.drawCircle(big, s * 0.07, fill);
    canvas.drawCircle(small, s * 0.05, fill);
  }

  @override
  bool shouldRepaint(covariant _MeshingGearsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Friends, in the Steampunk theme: two people in top hats and aviator
/// goggles.
class _AviatorPairPainter extends CustomPainter {
  final Color color;

  _AviatorPairPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.075);
    final thin = _stroke(color, s, 0.055);
    final fill = Paint()..color = color;

    const headY = 0.52;
    const headR = 0.12;
    const brimY = headY - headR;

    void person(double cx) {
      canvas.drawCircle(Offset(s * cx, s * headY), s * headR, paint);
      // Goggles: solid lenses, and a strap running out past the head.
      canvas.drawLine(
        Offset(s * (cx - 0.17), s * headY),
        Offset(s * (cx + 0.17), s * headY),
        thin,
      );
      for (final dx in [-0.055, 0.055]) {
        canvas.drawCircle(Offset(s * (cx + dx), s * headY), s * 0.045, fill);
      }
      canvas.drawLine(
        Offset(s * (cx - 0.14), s * brimY),
        Offset(s * (cx + 0.14), s * brimY),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTRB(s * (cx - 0.08), s * 0.20, s * (cx + 0.08), s * brimY),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(s * (cx - 0.19), s * 0.96)
          ..quadraticBezierTo(s * (cx - 0.19), s * 0.72, s * cx, s * 0.72)
          ..quadraticBezierTo(
              s * (cx + 0.19), s * 0.72, s * (cx + 0.19), s * 0.96),
        paint,
      );
    }

    person(0.27);
    person(0.73);
  }

  @override
  bool shouldRepaint(covariant _AviatorPairPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Store, in the Steampunk theme: a brass cash register with its crank.
class _CashRegisterPainter extends CustomPainter {
  final Color color;

  _CashRegisterPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);
    final thin = _stroke(color, s, 0.06);
    final fill = Paint()..color = color;

    // The sign on top, on its stem.
    canvas.drawRect(
      Rect.fromLTRB(s * 0.34, s * 0.14, s * 0.66, s * 0.32),
      paint,
    );
    canvas.drawLine(Offset(s * 0.5, s * 0.32), Offset(s * 0.5, s * 0.46), thin);

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.18, s * 0.46)
        ..lineTo(s * 0.82, s * 0.46)
        ..lineTo(s * 0.88, s * 0.90)
        ..lineTo(s * 0.12, s * 0.90)
        ..close(),
      paint,
    );
    canvas.drawLine(
        Offset(s * 0.14, s * 0.76), Offset(s * 0.86, s * 0.76), thin);

    for (final x in [0.34, 0.50, 0.66]) {
      canvas.drawCircle(Offset(s * x, s * 0.60), s * 0.045, fill);
    }

    // The crank on the side.
    canvas.drawLine(
        Offset(s * 0.85, s * 0.62), Offset(s * 0.97, s * 0.62), thin);
    canvas.drawLine(
        Offset(s * 0.97, s * 0.62), Offset(s * 0.97, s * 0.50), thin);
  }

  @override
  bool shouldRepaint(covariant _CashRegisterPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Home, in the Christmas theme: a house with snow heaped on the roof.
class _SnowyHousePainter extends CustomPainter {
  final Color color;

  _SnowyHousePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);
    final fill = Paint()..color = color;

    // The roof is a solid cap of snow, with a drip at each eave.
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.06, s * 0.50)
        ..lineTo(s * 0.50, s * 0.10)
        ..lineTo(s * 0.94, s * 0.50)
        ..lineTo(s * 0.86, s * 0.54)
        ..lineTo(s * 0.50, s * 0.24)
        ..lineTo(s * 0.14, s * 0.54)
        ..close(),
      fill,
    );
    for (final x in [0.12, 0.88]) {
      canvas.drawCircle(Offset(s * x, s * 0.58), s * 0.04, fill);
    }

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.22, s * 0.50)
        ..lineTo(s * 0.22, s * 0.88)
        ..lineTo(s * 0.78, s * 0.88)
        ..lineTo(s * 0.78, s * 0.50)
        ..moveTo(s * 0.42, s * 0.88)
        ..lineTo(s * 0.42, s * 0.66)
        ..lineTo(s * 0.58, s * 0.66)
        ..lineTo(s * 0.58, s * 0.88),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SnowyHousePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Versus, in the Christmas theme: two candy canes crossed, hooks out.
class _CandyCanesPainter extends CustomPainter {
  final Color color;

  _CandyCanesPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.09);

    // One cane drawn upright with its hook to the left, then tilted; the
    // other is its mirror image.
    for (final mirror in [false, true]) {
      canvas.save();
      canvas.translate(s * 0.5, s * 0.5);
      if (mirror) canvas.scale(-1, 1);
      canvas.rotate(-0.45);
      canvas.translate(-s * 0.5, -s * 0.5);
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.5, s * 0.96)
          ..lineTo(s * 0.5, s * 0.26)
          ..arcToPoint(
            Offset(s * 0.28, s * 0.26),
            radius: Radius.circular(s * 0.11),
            clockwise: false,
          )
          ..lineTo(s * 0.28, s * 0.34),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CandyCanesPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Friends, in the Christmas theme: two snowmen in top hats.
class _SnowmenPainter extends CustomPainter {
  final Color color;

  _SnowmenPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.07);
    final fill = Paint()..color = color;

    void snowman(double cx) {
      canvas.drawCircle(Offset(s * cx, s * 0.76), s * 0.16, paint);
      canvas.drawCircle(Offset(s * cx, s * 0.48), s * 0.11, paint);
      canvas.drawLine(
        Offset(s * (cx - 0.13), s * 0.37),
        Offset(s * (cx + 0.13), s * 0.37),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTRB(s * (cx - 0.07), s * 0.22, s * (cx + 0.07), s * 0.37),
        fill,
      );
    }

    snowman(0.27);
    snowman(0.73);
  }

  @override
  bool shouldRepaint(covariant _SnowmenPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Store, in the Christmas theme: a wrapped present with a bow.
class _GiftPainter extends CustomPainter {
  final Color color;

  _GiftPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = _stroke(color, s, 0.08);
    final thin = _stroke(color, s, 0.065);

    canvas.drawRect(
      Rect.fromLTRB(s * 0.10, s * 0.32, s * 0.90, s * 0.48),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.18, s * 0.48)
        ..lineTo(s * 0.18, s * 0.90)
        ..lineTo(s * 0.82, s * 0.90)
        ..lineTo(s * 0.82, s * 0.48),
      paint,
    );
    canvas.drawLine(Offset(s * 0.5, s * 0.32), Offset(s * 0.5, s * 0.90), thin);

    // The bow: two loops meeting over the ribbon.
    for (final dx in [-0.12, 0.12]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s * (0.5 + dx), s * 0.21),
          width: s * 0.22,
          height: s * 0.15,
        ),
        thin,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GiftPainter oldDelegate) =>
      oldDelegate.color != color;
}
