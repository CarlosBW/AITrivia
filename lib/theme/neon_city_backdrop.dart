import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A city at night in the theme's page colour, drawn under [child].
///
/// Put under each route by `backdropPageTransitionsTheme`, like the other
/// backdrops, so the screen coming in covers the one going out.
class NeonCityBackdrop extends StatelessWidget {
  const NeonCityBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: NeonCityPainter(base: context.decor.pageColor),
        child: child,
      ),
    );
  }
}

/// Paints the city: [base], a magenta and a cyan glow in the haze, a
/// skyline of dark towers along the bottom with a few lit windows, a neon
/// edge on some rooftops, and faint scanlines.
///
/// Static and seeded, like the other backdrops: the same skyline on every
/// screen and every launch, and nothing animating behind the app.
///
/// The skyline stays in the lower part of the screen, under the content
/// rather than behind the headings, and nothing is drawn in the top band,
/// where the app bar sits in solid page colour.
class NeonCityPainter extends CustomPainter {
  const NeonCityPainter({required this.base});

  final Color base;

  static const int _seed = 20771120;

  /// The band at the top kept clear, as a share of the height.
  static const double _clearTop = 0.15;

  static const Color _magenta = Color(0xFFFF2E97);
  static const Color _cyan = Color(0xFF00F0FF);
  static const Color _amber = Color(0xFFFFC94D);
  static const Color _tower = Color(0xFF07050F);

  static const double _windowSize = 2.5;
  static const double _windowGap = 5;

  /// The towers in the unit square, left to right, as (left, width,
  /// height), heights as a share of the canvas height.
  static final List<({double left, double width, double height})> _unitTowers =
      () {
    final random = math.Random(_seed);
    final towers = <({double left, double width, double height})>[];
    var x = 0.0;
    while (x < 1) {
      final width = math.min(0.06 + random.nextDouble() * 0.10, 1 - x);
      towers.add((
        left: x,
        width: width,
        height: 0.08 + random.nextDouble() * 0.24,
      ));
      x += width;
    }
    return towers;
  }();

  // Glows in the haze, as (centre in the unit square, radius as a share of
  // the longer side, colour). None sits in the top band.
  static const _glows = [
    (Offset(0.15, 0.60), 0.45, Color(0x24FF2E97)),
    (Offset(0.85, 0.78), 0.40, Color(0x1F00F0FF)),
    (Offset(0.55, 0.95), 0.30, Color(0x1AFF2E97)),
  ];

  /// The towers for a canvas of [size], each standing on the bottom edge.
  static List<Rect> buildingsFor(Size size) {
    return [
      for (final t in _unitTowers)
        Rect.fromLTRB(
          t.left * size.width,
          size.height * (1 - t.height),
          math.min((t.left + t.width) * size.width, size.width),
          size.height,
        ),
    ];
  }

  /// The lit windows for a canvas of [size], each inside a tower.
  ///
  /// Laid out on a grid in pixels rather than in the unit square, so a
  /// window is the same size on every screen.
  static List<Rect> windowsFor(Size size) {
    final random = math.Random(_seed + 1);
    final windows = <Rect>[];
    for (final tower in buildingsFor(size)) {
      for (var y = tower.top + 6;
          y + _windowSize < tower.bottom;
          y += _windowGap) {
        for (var x = tower.left + 4;
            x + _windowSize < tower.right - 3;
            x += _windowGap) {
          if (random.nextDouble() < 0.16) {
            windows.add(Rect.fromLTWH(x, y, _windowSize, _windowSize));
          }
        }
      }
    }
    return windows;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // The glows are wider than the canvas near its edges.
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = base);

    final longest = size.longestSide;
    for (final (center, radius, color) in _glows) {
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

    // Faint scanlines, below the top band only.
    final scan = Paint()
      ..color = Colors.white.withValues(alpha: 0.018)
      ..strokeWidth = 1;
    for (var y = size.height * _clearTop; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scan);
    }

    final towers = buildingsFor(size);
    final towerPaint = Paint()..color = _tower.withValues(alpha: 0.85);
    for (final tower in towers) {
      canvas.drawRect(tower, towerPaint);
    }

    // A neon edge on every third rooftop, alternating colours.
    for (var i = 0; i < towers.length; i += 3) {
      final tower = towers[i];
      canvas.drawLine(
        tower.topLeft,
        tower.topRight,
        Paint()
          ..color = (i.isEven ? _magenta : _cyan).withValues(alpha: 0.45)
          ..strokeWidth = 1.2,
      );
    }

    const windowColours = [_cyan, _magenta, _amber];
    final window = Paint();
    final windows = windowsFor(size);
    for (var i = 0; i < windows.length; i++) {
      window.color = windowColours[i % 3].withValues(alpha: 0.35);
      canvas.drawRect(windows[i], window);
    }
  }

  @override
  bool shouldRepaint(covariant NeonCityPainter oldDelegate) =>
      oldDelegate.base != base;
}
