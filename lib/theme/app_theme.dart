import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The semantic palette — reward, success, danger — carried on the theme
/// so it can be swapped.
///
/// These live in [AppColors] as `static const`, which is what a constant
/// is good at and exactly wrong for a theme: a purchasable skin has to be
/// able to restyle "reward gold" or "danger red", and a compile-time
/// constant can't change at runtime. [AppColors] stays as the default
/// palette this is built from; screens read the theme instead.
///
/// Distinct from the brand `ColorScheme` on purpose, same as before: a
/// semantic colour shouldn't double as the brand colour.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.reward,
    required this.rewardBg,
    required this.success,
    required this.successBg,
    required this.danger,
    required this.dangerBg,
    required this.onAccent,
    required this.onScrim,
    required this.onReward,
  });

  final Color reward;
  final Color rewardBg;
  final Color success;
  final Color successBg;
  final Color danger;
  final Color dangerBg;

  /// Foreground for text and icons sitting on a saturated brand surface —
  /// the gradient cards, the accent buttons, the coloured chips.
  ///
  /// Those call sites used `Colors.white` directly, which is right only for
  /// as long as the surface underneath stays dark. A theme that repaints
  /// those cards in a pale palette needs to move the foreground with them,
  /// and it cannot if the white is written into the screen.
  final Color onAccent;

  /// Foreground for the blocking overlay drawn while a screen is busy,
  /// over [ColorScheme.scrim].
  ///
  /// Separate from [onAccent] even though both ship white: a theme can
  /// lighten its cards without touching the scrim, and vice versa.
  final Color onScrim;

  /// Foreground for text sitting on [reward] — the coin popups, the streak
  /// badge, the level-up pill.
  ///
  /// Ships black rather than white because [reward] is a bright gold, which
  /// is exactly why it cannot share [onAccent]: a single "foreground on a
  /// coloured surface" token would have to be wrong on one of the two.
  final Color onReward;

  /// The palette the app ships with.
  static const AppSemanticColors standard = AppSemanticColors(
    reward: AppColors.reward,
    rewardBg: AppColors.rewardBg,
    success: AppColors.success,
    successBg: AppColors.successBg,
    danger: AppColors.danger,
    dangerBg: AppColors.dangerBg,
    onAccent: Colors.white,
    onScrim: Colors.white,
    onReward: Colors.black,
  );

  @override
  AppSemanticColors copyWith({
    Color? reward,
    Color? rewardBg,
    Color? success,
    Color? successBg,
    Color? danger,
    Color? dangerBg,
    Color? onAccent,
    Color? onScrim,
    Color? onReward,
  }) {
    return AppSemanticColors(
      reward: reward ?? this.reward,
      rewardBg: rewardBg ?? this.rewardBg,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      onAccent: onAccent ?? this.onAccent,
      onScrim: onScrim ?? this.onScrim,
      onReward: onReward ?? this.onReward,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      reward: Color.lerp(reward, other.reward, t) ?? reward,
      rewardBg: Color.lerp(rewardBg, other.rewardBg, t) ?? rewardBg,
      success: Color.lerp(success, other.success, t) ?? success,
      successBg: Color.lerp(successBg, other.successBg, t) ?? successBg,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t) ?? dangerBg,
      onAccent: Color.lerp(onAccent, other.onAccent, t) ?? onAccent,
      onScrim: Color.lerp(onScrim, other.onScrim, t) ?? onScrim,
      onReward: Color.lerp(onReward, other.onReward, t) ?? onReward,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  /// The semantic palette for the active theme.
  AppSemanticColors get appColors =>
      Theme.of(this).extension<AppSemanticColors>() ??
      AppSemanticColors.standard;
}

/// The display face, carried on the theme so it can be swapped.
///
/// Screens used to call `GoogleFonts.baloo2(...)` directly — 98 times — so
/// the font was hardcoded at every call site and the `textTheme` defined
/// below was almost never consulted. Nothing could restyle the app's
/// typography, which is what a purchasable theme would need to do.
///
/// [heading] deliberately carries **no colour**. Call sites sit on both the
/// page background and saturated cards, and rely on inheriting the
/// surrounding text colour; Material's own `textTheme` entries bake in
/// `onSurface`, which would have turned white-on-purple labels dark.
///
/// It also carries its own weight rather than being restyled per call:
/// google_fonts encodes the weight in the family name (`Baloo2_800` vs
/// `Baloo2_regular`), so a style built at one weight and `copyWith`n to
/// another renders a synthetic bold instead of the real face.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({required this.heading});

  /// Headings, scores, and anything meant to read as "game".
  final TextStyle heading;

  @override
  AppTypography copyWith({TextStyle? heading}) =>
      AppTypography(heading: heading ?? this.heading);

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      heading: TextStyle.lerp(heading, other.heading, t) ?? heading,
    );
  }
}

extension AppTypographyContext on BuildContext {
  /// The display face with no size of its own, for the few call sites that
  /// only wanted the family and inherit their size from the surrounding
  /// text style.
  TextStyle get headingFace =>
      Theme.of(this).extension<AppTypography>()?.heading ??
      const TextStyle(fontWeight: FontWeight.w800);

  /// The display style at [fontSize], for what used to be a direct
  /// `GoogleFonts.baloo2(...)` call.
  ///
  /// Passing no [color] keeps the inherited one, exactly as before.
  TextStyle heading(
    double fontSize, {
    Color? color,
    FontWeight? fontWeight,
    double? height,
  }) {
    final base = Theme.of(this).extension<AppTypography>()?.heading ??
        const TextStyle(fontWeight: FontWeight.w800);

    return base.copyWith(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: height,
    );
  }
}

/// Shared corner-radius scale, replacing the ~11 ad hoc values used
/// across the app before this design system existed.
class AppRadius {
  AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double pill = 999;
}

/// The corner-radius scale, carried on the theme so it can be swapped.
///
/// Same reasoning as [AppSemanticColors]: [AppRadius] is `static const`, so
/// a skin that wants sharper or rounder corners can't touch it. The
/// constants stay as the default this is built from.
@immutable
class AppShapes extends ThemeExtension<AppShapes> {
  const AppShapes({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.pill,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;

  /// Fully rounded. Left out of any theme's scaling — a pill that stops
  /// being a pill is a different component, not a restyled one.
  final double pill;

  static const AppShapes standard = AppShapes(
    xs: AppRadius.xs,
    sm: AppRadius.sm,
    md: AppRadius.md,
    lg: AppRadius.lg,
    pill: AppRadius.pill,
  );

  @override
  AppShapes copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? pill,
  }) {
    return AppShapes(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppShapes lerp(ThemeExtension<AppShapes>? other, double t) {
    if (other is! AppShapes) return this;

    // Interpolado a mano en vez de con `lerpDouble`: son dobles no nulos,
    // así que traer `dart:ui` solo por esto no compensa.
    double at(double a, double b) => a + (b - a) * t;

    return AppShapes(
      xs: at(xs, other.xs),
      sm: at(sm, other.sm),
      md: at(md, other.md),
      lg: at(lg, other.lg),
      pill: at(pill, other.pill),
    );
  }
}

extension AppShapesContext on BuildContext {
  /// The corner-radius scale for the active theme.
  AppShapes get radii =>
      Theme.of(this).extension<AppShapes>() ?? AppShapes.standard;
}

/// Semantic colors that sit alongside the brand ColorScheme — reward,
/// success/warning/danger feedback. Distinct from the brand accent on
/// purpose (semantic color shouldn't double as the brand color).
class AppColors {
  AppColors._();

  static const Color pageBackground = Color(0xFFFFFBF5);

  static const Color reward = Color(0xFFF2A93B);
  static const Color rewardBg = Color(0xFFFFF3D6);

  static const Color success = Color(0xFF0F6E56);
  static const Color successBg = Color(0xFFE1F5EE);

  static const Color warning = Color(0xFFF2A93B);
  static const Color warningBg = Color(0xFFFFF3D6);

  static const Color danger = Color(0xFFB3392C);
  static const Color dangerBg = Color(0xFFFFEDE9);
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
      foreground: Color(0xFFD85A30),
      background: Color(0xFFFAECE7),
      progress: Color(0xFFD85A30),
    ),
    CategoryAccent(
      foreground: Color(0xFF0F6E56),
      background: Color(0xFFE1F5EE),
      progress: Color(0xFF1D9E75),
    ),
    CategoryAccent(
      foreground: Color(0xFF185FA5),
      background: Color(0xFFE6F1FB),
      progress: Color(0xFF378ADD),
    ),
    CategoryAccent(
      foreground: Color(0xFF993556),
      background: Color(0xFFFBEAF0),
      progress: Color(0xFFD4537E),
    ),
    CategoryAccent(
      foreground: Color(0xFF854F0B),
      background: Color(0xFFFAEEDA),
      progress: Color(0xFFBA7517),
    ),
    CategoryAccent(
      foreground: Color(0xFF534AB7),
      background: Color(0xFFEEEDFE),
      progress: Color(0xFF7F77DD),
    ),
  ];

  /// Cycles through a fixed 6-color set so any list of categories (fixed
  /// or AI-generated, unknown length) gets visually distinct cards.
  static CategoryAccent forIndex(int index) {
    return _cycle[index % _cycle.length];
  }
}

/// TriviaIA's app-wide theme: a light, vibrant "game app" look (warm cream
/// page, saturated purple/amber/coral accents) replacing the earlier dark
/// violet theme — the dark theme read as serious/professional rather than
/// playful. Baloo 2 carries headings/scores; Manrope carries body/UI text.
/// The brand palette the default theme is built from.
///
/// Top-level rather than local to [buildAppTheme] so it can be read without
/// building the whole theme — [buildAppTheme] resolves its typography
/// through google_fonts, which needs the font at runtime and so cannot run
/// in a unit test.
const ColorScheme appColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF6C4FF2),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFE4DBFF),
  onPrimaryContainer: Color(0xFF2B1A66),
  secondary: Color(0xFFB4A8F5),
  onSecondary: Color(0xFF2B1A66),
  secondaryContainer: Color(0xFFF1EEFF),
  onSecondaryContainer: Color(0xFF2B1A66),
  tertiary: Color(0xFFF2A93B),
  onTertiary: Color(0xFF4A3200),
  surface: Colors.white,
  onSurface: Color(0xFF241A38),
  surfaceContainerHighest: Color(0xFFF1EEFF),
  onSurfaceVariant: Color(0xFF6B6280),
  outline: Color(0xFFE3DFF2),
  outlineVariant: Color(0xFFEDEAFF),
  error: Color(0xFFB3392C),
  onError: Colors.white,
  errorContainer: Color(0xFFFFEDE9),
  onErrorContainer: Color(0xFF7A2A20),
  inverseSurface: Color(0xFF2B2140),
  onInverseSurface: Colors.white,
  shadow: Colors.black,
  scrim: Colors.black,
);

ThemeData buildAppTheme() {
  const colorScheme = appColorScheme;

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
    titleMedium: headingFont.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.pageBackground,
    // Resolved once here so the family lives on the theme instead of at 98
    // call sites. Built at w800 on purpose — see [AppTypography].
    extensions: <ThemeExtension<dynamic>>[
      AppTypography(
        heading: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
      ),
      AppSemanticColors.standard,
      AppShapes.standard,
    ],
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          color: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
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
