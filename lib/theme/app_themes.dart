import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A theme the player can own and equip.
///
/// A theme is code, not data: it carries a [ColorScheme] and the theme
/// extensions the screens read. So the catalogue lives here and Firestore
/// only ever stores which ids a player owns and which one is equipped —
/// storing the colours themselves would let a modified client paint
/// anything, and would strand old clients on ids they can't render.
///
/// [price] is duplicated in `THEME_PRICES` in `functions/src/index.ts`,
/// which is the one that actually charges. This copy is only what the store
/// shows; `theme_catalog_sync_test.dart` keeps the two honest.
@immutable
class AppThemeSpec {
  const AppThemeSpec({
    required this.id,
    required this.price,
    required this.colorScheme,
    required this.semanticColors,
    required this.shapes,
    required this.surfaces,
    required this.scaffoldBackground,
    required this.preview,
  });

  /// Stored in Firestore, so it must stay stable once shipped.
  final String id;

  /// In coins. Zero means the theme every player starts with.
  final int price;

  final ColorScheme colorScheme;
  final AppSemanticColors semanticColors;
  final AppShapes shapes;
  final AppSurfaces surfaces;
  final Color scaffoldBackground;

  /// The swatches the store card shows. Three colours, most prominent
  /// first — enough to tell two themes apart without rendering either.
  final List<Color> preview;

  bool get isFree => price == 0;
}

/// Every theme in the game.
class AppThemes {
  AppThemes._();

  /// The theme a player has before buying anything. Its id is also what a
  /// user doc means when it carries no `equippedTheme` at all.
  static const String defaultId = 'default';

  /// The mockup's "game piece" treatment: same palette, but thick dark
  /// outlines and a solid unblurred shadow, so surfaces read as physical
  /// tokens instead of Material cards.
  static const String playfulId = 'playful';

  /// The ink the playful theme outlines everything with. It is the palette's
  /// existing `onSurface`, not a new colour — the design deliberately added
  /// depth without adding hues.
  static const Color _playfulInk = Color(0xFF241A38);

  static const AppThemeSpec _default = AppThemeSpec(
    id: defaultId,
    price: 0,
    colorScheme: appColorScheme,
    semanticColors: AppSemanticColors.standard,
    shapes: AppShapes.standard,
    surfaces: AppSurfaces.standard,
    scaffoldBackground: AppColors.pageBackground,
    preview: [
      Color(0xFF6C4FF2),
      Color(0xFFF2A93B),
      AppColors.pageBackground,
    ],
  );

  static const AppThemeSpec _playful = AppThemeSpec(
    id: playfulId,
    price: 400,
    // Same palette on purpose. The design note was explicit that the
    // colours were already right and that what the app lacked was weight
    // and depth, so this theme changes how surfaces are drawn, not what
    // colour they are.
    colorScheme: appColorScheme,
    semanticColors: AppSemanticColors.standard,
    // Rounder on the small elements, tighter on the large ones — the
    // mockup's 12/14/18/20 instead of 8/12/18/24.
    shapes: AppShapes(xs: 12, sm: 14, md: 18, lg: 20, pill: AppRadius.pill),
    surfaces: AppSurfaces(
      borderWidth: 2.5,
      borderColor: _playfulInk,
      shadowColor: _playfulInk,
      // No blur, short offset: a solid block under the surface.
      shadowBlur: 0,
      shadowOffset: Offset(0, 4),
      buttonLip: 3,
      overridesSurfaces: true,
    ),
    scaffoldBackground: AppColors.pageBackground,
    preview: [
      _playfulInk,
      Color(0xFF6C4FF2),
      Color(0xFFF2A93B),
    ],
  );

  /// The first theme to change the palette rather than how surfaces are
  /// drawn, and the only dark one. The brand hues stay — violet, amber,
  /// coral — on a near-black page with a violet cast, so it still reads as
  /// TriviaIA and not as a generic dark mode.
  static const String nightId = 'night';

  static const Color _nightPage = Color(0xFF15111F);
  static const Color _nightSurface = Color(0xFF211A33);

  static const AppThemeSpec _night = AppThemeSpec(
    id: nightId,
    price: 400,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      // A step lighter than the classic violet: that one is tuned to sit
      // on white, and against a dark card it loses the contrast a link or
      // a button outline needs. White still reads on it.
      primary: Color(0xFF7F66FF),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF2E2552),
      onPrimaryContainer: Color(0xFFDCD3FF),
      secondary: Color(0xFFB4A8F5),
      onSecondary: Color(0xFF1E1640),
      secondaryContainer: Color(0xFF2A2342),
      onSecondaryContainer: Color(0xFFDCD3FF),
      tertiary: Color(0xFFF2A93B),
      onTertiary: Color(0xFF4A3200),
      surface: _nightSurface,
      onSurface: Color(0xFFF3EFFF),
      surfaceContainerHighest: Color(0xFF2D2545),
      onSurfaceVariant: Color(0xFFA79DC4),
      outline: Color(0xFF3A3158),
      outlineVariant: Color(0xFF2D2545),
      error: Color(0xFFFF8A7A),
      onError: Color(0xFF3D0F09),
      errorContainer: Color(0xFF3D1A16),
      onErrorContainer: Color(0xFFFFDAD4),
      inverseSurface: Color(0xFFF3EFFF),
      onInverseSurface: _nightSurface,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    // The classic semantic colours are dark inks on pale washes. Here the
    // washes are dark, so each ink moves to the light end of its own hue.
    semanticColors: AppSemanticColors(
      reward: Color(0xFFF5C469),
      rewardBg: Color(0xFF3A2E12),
      success: Color(0xFF5DCAA5),
      successBg: Color(0xFF0F3A2E),
      danger: Color(0xFFFF8A7A),
      dangerBg: Color(0xFF3D1A16),
      // Still white: these sit on the saturated gradient cards, which keep
      // their colours in every theme.
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
    ),
    shapes: AppShapes.standard,
    surfaces: AppSurfaces.standard,
    scaffoldBackground: _nightPage,
    preview: [
      _nightPage,
      Color(0xFF7F66FF),
      Color(0xFFF5C469),
    ],
  );

  /// The three below are the classic theme in another palette: surfaces and
  /// shapes are untouched, which is why they cost less than the two above.
  /// Each brand colour is dark enough for white text on it and for itself
  /// as text on a white card — `color_themes_test.dart` holds them to it.
  static const String oceanId = 'ocean';
  static const String sunsetId = 'sunset';
  static const String forestId = 'forest';

  static const int _recolorPrice = 250;

  static const Color _oceanPrimary = Color(0xFF0E7C9B);
  static const Color _oceanPage = Color(0xFFF2FAFB);

  static const AppThemeSpec _ocean = AppThemeSpec(
    id: oceanId,
    price: _recolorPrice,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: _oceanPrimary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD3EEF5),
      onPrimaryContainer: Color(0xFF073B4A),
      secondary: Color(0xFF8FCBDB),
      onSecondary: Color(0xFF073B4A),
      secondaryContainer: Color(0xFFE6F6FA),
      onSecondaryContainer: Color(0xFF073B4A),
      tertiary: Color(0xFFFF7A59),
      onTertiary: Color(0xFF4A1505),
      surface: Colors.white,
      onSurface: Color(0xFF0E2A33),
      surfaceContainerHighest: Color(0xFFE6F6FA),
      onSurfaceVariant: Color(0xFF55707A),
      outline: Color(0xFFD2E6EC),
      outlineVariant: Color(0xFFE3F1F5),
      error: Color(0xFFB3392C),
      onError: Colors.white,
      errorContainer: Color(0xFFFFEDE9),
      onErrorContainer: Color(0xFF7A2A20),
      inverseSurface: Color(0xFF12333D),
      onInverseSurface: Colors.white,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: AppColors.reward,
      rewardBg: AppColors.rewardBg,
      success: AppColors.success,
      successBg: AppColors.successBg,
      danger: AppColors.danger,
      dangerBg: AppColors.dangerBg,
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      brandGradientStart: _oceanPrimary,
      brandGradientEnd: Color(0xFF1593B3),
      // Open water into the shallows: teal to sea green.
      heroGradientStart: _oceanPrimary,
      heroGradientEnd: Color(0xFF1FA38F),
    ),
    shapes: AppShapes.standard,
    surfaces: AppSurfaces.standard,
    scaffoldBackground: _oceanPage,
    preview: [_oceanPrimary, Color(0xFFFF7A59), _oceanPage],
  );

  static const Color _sunsetPrimary = Color(0xFFD6336C);
  static const Color _sunsetPage = Color(0xFFFFF6F1);

  static const AppThemeSpec _sunset = AppThemeSpec(
    id: sunsetId,
    price: _recolorPrice,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: _sunsetPrimary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFD9E4),
      onPrimaryContainer: Color(0xFF5C0F2B),
      secondary: Color(0xFFF3A5BC),
      onSecondary: Color(0xFF5C0F2B),
      secondaryContainer: Color(0xFFFFEEF2),
      onSecondaryContainer: Color(0xFF5C0F2B),
      tertiary: Color(0xFFF28C28),
      onTertiary: Color(0xFF4A2600),
      surface: Colors.white,
      onSurface: Color(0xFF3A1626),
      surfaceContainerHighest: Color(0xFFFFEEF2),
      onSurfaceVariant: Color(0xFF7D5A66),
      outline: Color(0xFFF2D9E0),
      outlineVariant: Color(0xFFF8E6EB),
      error: Color(0xFFB3392C),
      onError: Colors.white,
      errorContainer: Color(0xFFFFEDE9),
      onErrorContainer: Color(0xFF7A2A20),
      inverseSurface: Color(0xFF3F1C2B),
      onInverseSurface: Colors.white,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: AppColors.reward,
      rewardBg: AppColors.rewardBg,
      success: AppColors.success,
      successBg: AppColors.successBg,
      danger: AppColors.danger,
      dangerBg: AppColors.dangerBg,
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      brandGradientStart: _sunsetPrimary,
      brandGradientEnd: Color(0xFFE8527F),
      // The sky itself: rose at the top, orange at the horizon.
      heroGradientStart: _sunsetPrimary,
      heroGradientEnd: Color(0xFFF0653F),
    ),
    shapes: AppShapes.standard,
    surfaces: AppSurfaces.standard,
    scaffoldBackground: _sunsetPage,
    preview: [_sunsetPrimary, Color(0xFFF28C28), _sunsetPage],
  );

  static const Color _forestPrimary = Color(0xFF2B7A4B);
  static const Color _forestPage = Color(0xFFF5FAF1);

  static const AppThemeSpec _forest = AppThemeSpec(
    id: forestId,
    price: _recolorPrice,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: _forestPrimary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD5EEDD),
      onPrimaryContainer: Color(0xFF0E3A21),
      secondary: Color(0xFF9CCFAE),
      onSecondary: Color(0xFF0E3A21),
      secondaryContainer: Color(0xFFE8F5EC),
      onSecondaryContainer: Color(0xFF0E3A21),
      tertiary: Color(0xFFE0A526),
      onTertiary: Color(0xFF4A3200),
      surface: Colors.white,
      onSurface: Color(0xFF16301F),
      surfaceContainerHighest: Color(0xFFE8F5EC),
      onSurfaceVariant: Color(0xFF587163),
      outline: Color(0xFFD5E6DA),
      outlineVariant: Color(0xFFE5F1E8),
      error: Color(0xFFB3392C),
      onError: Colors.white,
      errorContainer: Color(0xFFFFEDE9),
      onErrorContainer: Color(0xFF7A2A20),
      inverseSurface: Color(0xFF1B3B26),
      onInverseSurface: Colors.white,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: AppColors.reward,
      rewardBg: AppColors.rewardBg,
      success: AppColors.success,
      successBg: AppColors.successBg,
      danger: AppColors.danger,
      dangerBg: AppColors.dangerBg,
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      brandGradientStart: _forestPrimary,
      brandGradientEnd: Color(0xFF3E9A62),
      // Deep shade into new leaves.
      heroGradientStart: _forestPrimary,
      heroGradientEnd: Color(0xFF5C9E2E),
    ),
    shapes: AppShapes.standard,
    surfaces: AppSurfaces.standard,
    scaffoldBackground: _forestPage,
    preview: [_forestPrimary, Color(0xFFE0A526), _forestPage],
  );

  // Cheapest first after the free one, so the first thing a player sees
  // for sale is the one they are closest to affording.
  static const List<AppThemeSpec> all = [
    _default,
    _ocean,
    _sunset,
    _forest,
    _playful,
    _night,
  ];

  /// The spec for [id], falling back to the default for an id this build
  /// doesn't know — a player who bought a theme on a newer version should
  /// see the base app, not a crash.
  static AppThemeSpec byId(String? id) {
    return all.firstWhere(
      (spec) => spec.id == id,
      orElse: () => _default,
    );
  }

  static bool exists(String id) => all.any((spec) => spec.id == id);
}
