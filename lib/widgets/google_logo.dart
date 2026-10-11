import 'package:flutter/material.dart';

/// Google's four-colour "G", as its sign-in branding guidelines require on
/// any button that signs in with Google.
///
/// Drawn rather than shipped as an image: the mark is four filled paths on
/// a 48x48 grid, taken from Google's own SVG, and it stays sharp at any
/// size without adding an SVG dependency for a single icon. The colours
/// are Google's and deliberately not themed.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);

    final red = Path()
      ..moveTo(24, 9.5)
      ..relativeCubicTo(3.54, 0, 6.71, 1.22, 9.21, 3.6)
      ..relativeLineTo(6.85, -6.85)
      ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
      ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
      ..relativeLineTo(7.98, 6.19)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
      ..close();

    final blue = Path()
      ..moveTo(46.98, 24.55)
      ..relativeCubicTo(0, -1.57, -0.15, -3.09, -0.38, -4.55)
      ..lineTo(24, 20)
      ..relativeLineTo(0, 9.02)
      ..relativeLineTo(12.94, 0)
      ..relativeCubicTo(-0.58, 2.96, -2.26, 5.48, -4.78, 7.18)
      ..relativeLineTo(7.73, 6)
      ..relativeCubicTo(4.51, -4.18, 7.09, -10.36, 7.09, -17.65)
      ..close();

    final yellow = Path()
      ..moveTo(10.53, 28.59)
      ..relativeCubicTo(-0.48, -1.45, -0.76, -2.99, -0.76, -4.59)
      ..relativeCubicTo(0, -1.6, 0.27, -3.14, 0.76, -4.59)
      ..relativeLineTo(-7.98, -6.19)
      ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
      ..relativeCubicTo(0, 3.88, 0.92, 7.54, 2.56, 10.78)
      ..relativeLineTo(7.97, -6.19)
      ..close();

    final green = Path()
      ..moveTo(24, 48)
      ..relativeCubicTo(6.48, 0, 11.93, -2.13, 15.89, -5.81)
      ..relativeLineTo(-7.73, -6)
      ..relativeCubicTo(-2.15, 1.45, -4.92, 2.3, -8.16, 2.3)
      ..relativeCubicTo(-6.26, 0, -11.57, -4.22, -13.47, -9.91)
      ..relativeLineTo(-7.98, 6.19)
      ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
      ..close();

    canvas
      ..drawPath(red, Paint()..color = const Color(0xFFEA4335))
      ..drawPath(blue, Paint()..color = const Color(0xFF4285F4))
      ..drawPath(yellow, Paint()..color = const Color(0xFFFBBC05))
      ..drawPath(green, Paint()..color = const Color(0xFF34A853));
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter oldDelegate) => false;
}
