import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared corner-radius scale, replacing the ~11 ad hoc values used
/// across the app before this design system existed.
class AppRadius {
  AppRadius._();

  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double pill = 999;
}

/// Semantic colors that sit alongside the brand ColorScheme — reward,
/// success/warning/danger feedback. Distinct from the brand accent on
/// purpose (semantic color shouldn't double as the brand color).
class AppColors {
  AppColors._();

  static const Color reward = Color(0xFFF5A623);
  static const Color success = Color(0xFF2E9E5B);
  static const Color warning = Color(0xFFD98A2B);
  static const Color danger = Color(0xFFD9483D);
}

/// TriviaIA's app-wide theme: formalizes the informal deepPurple brand
/// color used ad hoc across screens into a real ColorScheme, and adds a
/// rounded, friendlier display face (Baloo 2) for headings/titles/scores
/// while leaving body text on the default face for in-question legibility.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6E4FCE)),
  );

  final headingFont = GoogleFonts.baloo2TextTheme(base.textTheme);

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: headingFont.headlineSmall,
      titleLarge: headingFont.titleLarge,
      titleMedium: headingFont.titleMedium,
    ),
  );
}
