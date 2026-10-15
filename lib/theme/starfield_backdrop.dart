import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'paper_backdrop.dart';

/// Page transitions that put the theme's backdrop — a [StarfieldBackdrop]
/// or a [PaperBackdrop] — under every route.
///
/// The backdrop goes on each route rather than once behind the whole app on
/// purpose. Behind the app, every scaffold would be transparent over the
/// same sky, and during a transition the screen coming in and the one going
/// out would show through each other. Under each route, the incoming screen
/// brings its own opaque sky and covers the outgoing one, exactly as a
/// solid scaffold did — and not one of the ~40 screens has to know.
///
/// Dialogs and bottom sheets aren't page routes, so they keep their own
/// surfaces and draw no sky.
const PageTransitionsTheme backdropPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _BackdropPageTransitionsBuilder(),
    TargetPlatform.iOS: _BackdropPageTransitionsBuilder(),
    TargetPlatform.macOS: _BackdropPageTransitionsBuilder(),
    TargetPlatform.windows: _BackdropPageTransitionsBuilder(),
    TargetPlatform.linux: _BackdropPageTransitionsBuilder(),
    TargetPlatform.fuchsia: _BackdropPageTransitionsBuilder(),
  },
);

class _BackdropPageTransitionsBuilder extends PageTransitionsBuilder {
  const _BackdropPageTransitionsBuilder();

  /// Whatever the platform would have used. A plain [PageTransitionsTheme]
  /// carries the platform defaults, so the motion is the one the app
  /// already had; only what is under the page changes.
  static const PageTransitionsTheme _platformDefaults = PageTransitionsTheme();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Whichever backdrop the theme sells; the routing is the same for all.
    final page = switch (context.decor.backdrop) {
      AppBackdrop.starfield => StarfieldBackdrop(child: child),
      AppBackdrop.paper => PaperBackdrop(child: child),
      AppBackdrop.plain => child,
    };

    return _platformDefaults.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      page,
    );
  }
}

/// A fixed night sky in the theme's page colour, drawn under [child].
class StarfieldBackdrop extends StatelessWidget {
  const StarfieldBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: StarfieldPainter(base: context.decor.pageColor),
        child: child,
      ),
    );
  }
}

/// One star: where it is, how big and how bright.
@immutable
class Star {
  const Star(this.center, this.radius, this.opacity, {this.glows = false});

  final Offset center;
  final double radius;
  final double opacity;

  /// The few bright ones that get a halo and a four-point sparkle.
  final bool glows;
}

/// Paints the sky: [base], a faint nebula, and the stars.
///
/// Static on purpose — a twinkle would keep an animation running behind
/// every screen for as long as the app is open.
class StarfieldPainter extends CustomPainter {
  const StarfieldPainter({required this.base});

  final Color base;

  static const int _starCount = 170;
  static const int _glowingCount = 7;

  /// The same seed every time, so the sky doesn't rearrange itself between
  /// screens or launches.
  static const int _seed = 20261015;

  /// Positions are drawn in the unit square and scaled, so a phone and a
  /// tablet get the same constellations, just spread out.
  static final List<({double x, double y, double r, double o})> _unitStars =
      () {
    final random = math.Random(_seed);
    return List.generate(_starCount, (i) {
      final glows = i < _glowingCount;
      return (
        x: random.nextDouble(),
        y: random.nextDouble(),
        // Mostly pinpricks, a few larger.
        r: glows
            ? 1.4 + random.nextDouble() * 0.8
            : 0.4 + random.nextDouble() * random.nextDouble() * 1.2,
        o: glows ? 1.0 : 0.3 + random.nextDouble() * 0.6,
      );
    });
  }();

  /// The stars for a canvas of [size].
  static List<Star> starsFor(Size size) {
    return [
      for (var i = 0; i < _unitStars.length; i++)
        Star(
          Offset(_unitStars[i].x * size.width, _unitStars[i].y * size.height),
          _unitStars[i].r,
          _unitStars[i].o,
          glows: i < _glowingCount,
        ),
    ];
  }

  // Nebula clouds, as (centre in the unit square, radius as a share of the
  // longer side, colour). Kept low and away from the top, where the app bar
  // sits in solid page colour and a cloud would end in a hard line.
  static const _nebulae = [
    (Offset(0.88, 0.72), 0.55, Color(0x405A3FD0)),
    (Offset(0.08, 0.42), 0.45, Color(0x2E2A8BD8)),
    (Offset(0.35, 0.98), 0.40, Color(0x26C2338A)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);

    final longest = size.longestSide;
    for (final (center, radius, color) in _nebulae) {
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
    for (final star in starsFor(size)) {
      if (star.glows) _paintGlow(canvas, star);
      dot.color = Colors.white.withValues(alpha: star.opacity);
      canvas.drawCircle(star.center, star.radius, dot);
    }
  }

  void _paintGlow(Canvas canvas, Star star) {
    final halo = star.radius * 5;
    canvas.drawCircle(
      star.center,
      halo,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x66BFD8FF), Color(0x00BFD8FF)],
        ).createShader(Rect.fromCircle(center: star.center, radius: halo)),
    );

    final spike = star.radius * 4;
    final line = Paint()
      ..color = const Color(0x99DCE8FF)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(star.center.translate(-spike, 0),
        star.center.translate(spike, 0), line);
    canvas.drawLine(star.center.translate(0, -spike),
        star.center.translate(0, spike), line);
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) =>
      oldDelegate.base != base;
}
