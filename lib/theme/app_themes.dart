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

  static const List<AppThemeSpec> all = [_default, _playful];

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
