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

  static const Color pageBackground = Color(0xFF16101F);

  static const Color reward = Color(0xFFEF9F27);
  static const Color rewardBg = Color(0xFF2E2712);

  static const Color success = Color(0xFF1D9E75);
  static const Color successBg = Color(0xFF04342C);

  static const Color warning = Color(0xFFEF9F27);
  static const Color warningBg = Color(0xFF2E2712);

  static const Color danger = Color(0xFFE24B4A);
  static const Color dangerBg = Color(0xFF4A1B0C);
}

/// One (icon-on-tint, tint bg, progress) triad for a category-style card —
/// see `CategoryAccent.forIndex`.
class CategoryAccent {
  final Color foreground;
  final Color background;
  final Color progress;

  const CategoryAccent({
    required this.foreground,
    required this.background,
    required this.progress,
  });

  static const List<CategoryAccent> _cycle = [
    CategoryAccent(
      foreground: Color(0xFFF0997B),
      background: Color(0xFF4A1B0C),
      progress: Color(0xFFD85A30),
    ),
    CategoryAccent(
      foreground: Color(0xFF5DCAA5),
      background: Color(0xFF04342C),
      progress: Color(0xFF1D9E75),
    ),
    CategoryAccent(
      foreground: Color(0xFF85B7EB),
      background: Color(0xFF042C53),
      progress: Color(0xFF378ADD),
    ),
    CategoryAccent(
      foreground: Color(0xFFED93B1),
      background: Color(0xFF4B1528),
      progress: Color(0xFFD4537E),
    ),
    CategoryAccent(
      foreground: Color(0xFFEF9F27),
      background: Color(0xFF2E2712),
      progress: Color(0xFFBA7517),
    ),
    CategoryAccent(
      foreground: Color(0xFFAFA9EC),
      background: Color(0xFF211E33),
      progress: Color(0xFF7F77DD),
    ),
  ];

  /// Cycles through a fixed 6-color set so any list of categories (fixed
  /// or AI-generated, unknown length) gets visually distinct cards.
  static CategoryAccent forIndex(int index) {
    return _cycle[index % _cycle.length];
  }
}

/// TriviaIA's app-wide theme: a dark, saturated "game app" look (deep
/// violet surfaces, color-blocked accents) replacing the earlier
/// Material-default seed theme. Baloo 2 carries headings/scores; Manrope
/// carries body/UI text — swapped in for the previous default Roboto for a
/// cleaner, more deliberate look.
ThemeData buildAppTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF7F77DD),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF4A3792),
    onPrimaryContainer: Color(0xFFF3EEFF),
    secondary: Color(0xFFAFA9EC),
    onSecondary: Color(0xFF211E33),
    secondaryContainer: Color(0xFF211E33),
    onSecondaryContainer: Color(0xFFE4E0F9),
    tertiary: Color(0xFFEF9F27),
    onTertiary: Color(0xFF2E2712),
    surface: Color(0xFF1F1B2E),
    onSurface: Color(0xFFF3EEFF),
    surfaceContainerHighest: Color(0xFF2E2740),
    onSurfaceVariant: Color(0xFF9C93C9),
    outline: Color(0xFF3A3350),
    outlineVariant: Color(0xFF2E2740),
    error: Color(0xFFE24B4A),
    onError: Colors.white,
    errorContainer: Color(0xFF4A1B0C),
    onErrorContainer: Color(0xFFF5DCD2),
    inverseSurface: Color(0xFFF3EEFF),
    onInverseSurface: Color(0xFF1F1B2E),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

  final bodyFont = GoogleFonts.manropeTextTheme(base.textTheme);
  final headingFont = GoogleFonts.baloo2TextTheme(base.textTheme);

  final textTheme = bodyFont.copyWith(
    displayLarge: headingFont.displayLarge,
    displayMedium: headingFont.displayMedium,
    displaySmall: headingFont.displaySmall,
    headlineLarge: headingFont.headlineLarge,
    headlineMedium: headingFont.headlineMedium,
    headlineSmall: headingFont.headlineSmall,
    titleLarge: headingFont.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium:
        headingFont.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.pageBackground,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.pageBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: colorScheme.onSurface,
      // Built directly (not chained off headingFont.headlineSmall, which can
      // silently resolve to null and drop this styling entirely) so the
      // AppBar title is reliably large/bold regardless of text theme merge
      // order.
      titleTextStyle: GoogleFonts.baloo2(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: colorScheme.onSurface,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: colorScheme.primary, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.surfaceContainerHighest,
      circularTrackColor: colorScheme.surfaceContainerHighest,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color:
              selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color:
              selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: colorScheme.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
  );
}
