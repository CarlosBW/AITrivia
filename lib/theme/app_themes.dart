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
    this.backdrop = AppBackdrop.plain,
    this.navIcons = AppNavIcons.classic,
    this.headingFace = AppHeadingFace.rounded,
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

  /// What is painted behind the screens. Plain unless a theme sells one.
  final AppBackdrop backdrop;

  /// The bottom bar's glyphs. Classic unless a theme sells its own.
  final AppNavIcons navIcons;

  /// The face of headings and scores. Rounded unless a theme sells another.
  final AppHeadingFace headingFace;

  /// The drawn parts of the theme, as the screens read them.
  AppDecor get decor => AppDecor(
        pageColor: scaffoldBackground,
        backdrop: backdrop,
        navIcons: navIcons,
      );

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

  /// The first theme that draws as well as colours: a night sky behind
  /// every screen, space glyphs in the bottom bar, and surfaces lit by a
  /// thin glowing edge instead of a shadow, like panels on a ship.
  ///
  /// Dark, like Night, so everything that already follows a dark theme's
  /// lightness — tints, inks, league colours — follows this one too. It is
  /// cooler and bluer than Night so the two don't read as one theme.
  static const String spaceId = 'space';

  static const Color _spacePage = Color(0xFF0B1026);
  static const Color _spaceSurface = Color(0xFF161B3A);
  static const Color _spacePrimary = Color(0xFF6E7BFF);
  static const Color _spaceGlow = Color(0xFF47D7F0);

  static const AppThemeSpec _space = AppThemeSpec(
    id: spaceId,
    price: 400,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: _spacePrimary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF262E66),
      onPrimaryContainer: Color(0xFFDDE1FF),
      secondary: Color(0xFF9FB4FF),
      onSecondary: Color(0xFF111A4A),
      secondaryContainer: Color(0xFF1E2550),
      onSecondaryContainer: Color(0xFFDDE1FF),
      tertiary: _spaceGlow,
      onTertiary: Color(0xFF00313A),
      surface: _spaceSurface,
      onSurface: Color(0xFFEEF1FF),
      surfaceContainerHighest: Color(0xFF20264A),
      onSurfaceVariant: Color(0xFFA9B0D6),
      outline: Color(0xFF2E3566),
      outlineVariant: Color(0xFF20264A),
      error: Color(0xFFFF8A7A),
      onError: Color(0xFF3D0F09),
      errorContainer: Color(0xFF3D1A20),
      onErrorContainer: Color(0xFFFFDAD4),
      inverseSurface: Color(0xFFEEF1FF),
      onInverseSurface: _spaceSurface,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: Color(0xFFFFD166),
      rewardBg: Color(0xFF3A3112),
      success: Color(0xFF5DE0B5),
      successBg: Color(0xFF0E3A30),
      danger: Color(0xFFFF8A7A),
      dangerBg: Color(0xFF3D1A20),
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      // Nebula colours: deep violet into magenta for the brand cards, deep
      // blue into magenta for the ones meant to stand out.
      brandGradientStart: Color(0xFF4B36C9),
      brandGradientEnd: Color(0xFF8A2FB8),
      heroGradientStart: Color(0xFF2F47C2),
      heroGradientEnd: Color(0xFFB02C7E),
    ),
    shapes: AppShapes.standard,
    surfaces: AppSurfaces(
      borderWidth: 1,
      borderColor: Color(0x8047D7F0),
      // A glow, not a shadow: centred under the surface, so it lights all
      // four edges instead of dropping below one.
      shadowColor: Color(0x4047D7F0),
      shadowBlur: 14,
      shadowOffset: Offset.zero,
      buttonLip: 0,
      overridesSurfaces: true,
    ),
    scaffoldBackground: _spacePage,
    backdrop: AppBackdrop.starfield,
    navIcons: AppNavIcons.space,
    preview: [_spacePage, _spacePrimary, _spaceGlow],
  );

  /// Old print: titles set in a high-contrast serif, sepia ink on aged
  /// paper, cards ruled with a fine ink line and pressed onto the page with
  /// a hard offset shadow, and squarer corners, the way a printed card was
  /// cut.
  ///
  /// Light, like the classic theme, so everything already tuned for a
  /// light theme applies. The page is a warm cream rather than white, and
  /// the brand colour is an oxblood red, dark enough to sit under white
  /// text and to read as text on the paper itself.
  static const String vintageId = 'vintage';

  static const Color _vintagePage = Color(0xFFF2E6CC);
  static const Color _vintageSurface = Color(0xFFFAF3E3);
  static const Color _vintageInk = Color(0xFF3A2A1C);
  static const Color _vintagePrimary = Color(0xFF8B2E2A);
  static const Color _vintageGold = Color(0xFFC08A1E);

  static const AppThemeSpec _vintage = AppThemeSpec(
    id: vintageId,
    price: 400,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: _vintagePrimary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEBCFC2),
      onPrimaryContainer: Color(0xFF4A1A16),
      secondary: Color(0xFFB38B4D),
      onSecondary: Color(0xFF2E1F0E),
      secondaryContainer: Color(0xFFEFE2C6),
      onSecondaryContainer: _vintageInk,
      tertiary: Color(0xFF3E6B5C),
      onTertiary: Colors.white,
      surface: _vintageSurface,
      onSurface: _vintageInk,
      surfaceContainerHighest: Color(0xFFEADBBF),
      onSurfaceVariant: Color(0xFF6B5640),
      outline: Color(0xFFCDB892),
      outlineVariant: Color(0xFFE3D3B0),
      error: Color(0xFF9E2B25),
      onError: Colors.white,
      errorContainer: Color(0xFFF3D9CF),
      onErrorContainer: Color(0xFF5A1410),
      inverseSurface: _vintageInk,
      onInverseSurface: _vintageSurface,
      shadow: Color(0xFF2A1A0A),
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: _vintageGold,
      rewardBg: Color(0xFFF3E2B8),
      success: Color(0xFF3D6B35),
      successBg: Color(0xFFDDE8CF),
      danger: Color(0xFF9E2B25),
      dangerBg: Color(0xFFF3D9CF),
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      // Oxblood into rust for the brand cards; walnut into tobacco for the
      // ones meant to stand out.
      brandGradientStart: _vintagePrimary,
      brandGradientEnd: Color(0xFFA6472E),
      heroGradientStart: Color(0xFF5B3A24),
      heroGradientEnd: Color(0xFF8B5A2B),
    ),
    // Squarer than the classic 8/12/18/24: a printed card, not a chip.
    // Pills stay pills.
    shapes: AppShapes(xs: 3, sm: 5, md: 8, lg: 10, pill: AppRadius.pill),
    surfaces: AppSurfaces(
      borderWidth: 1.2,
      borderColor: Color(0xFF9C8462),
      // A hard offset shadow, like a card pressed onto the page, rather
      // than a soft one floating above it.
      shadowColor: Color(0x332A1A0A),
      shadowBlur: 0,
      shadowOffset: Offset(2, 3),
      buttonLip: 0,
      overridesSurfaces: true,
    ),
    scaffoldBackground: _vintagePage,
    backdrop: AppBackdrop.paper,
    navIcons: AppNavIcons.vintage,
    headingFace: AppHeadingFace.serif,
    preview: [_vintagePrimary, _vintageGold, _vintagePage],
  );

  /// After the end of the world: soot-dark cracked concrete, rust for the
  /// brand colour, hazard yellow for rewards and a radioactive green for
  /// right answers. Headings are sprayed in a military stencil, cards are
  /// bolted-on metal plates with a hard shadow, and the bar has survivor
  /// icons.
  ///
  /// Dark, like Night and Space, so everything that already follows a dark
  /// theme's lightness follows this one too. Warmer and browner than both,
  /// so the three don't read as one theme.
  static const String apocalypseId = 'apocalypse';

  static const Color _apocalypsePage = Color(0xFF1A1714);
  static const Color _apocalypseSurface = Color(0xFF26221D);
  static const Color _apocalypseInk = Color(0xFFEDE3D1);
  static const Color _apocalypseRust = Color(0xFFE07A35);
  static const Color _apocalypseHazard = Color(0xFFF2C230);

  static const AppThemeSpec _apocalypse = AppThemeSpec(
    id: apocalypseId,
    price: 400,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: _apocalypseRust,
      onPrimary: Color(0xFF1A0C02),
      primaryContainer: Color(0xFF4A2A14),
      onPrimaryContainer: Color(0xFFFFD9BF),
      secondary: Color(0xFFC9B48A),
      onSecondary: Color(0xFF2A2010),
      secondaryContainer: Color(0xFF3A3226),
      onSecondaryContainer: _apocalypseInk,
      tertiary: Color(0xFF9BD645),
      onTertiary: Color(0xFF1A2A05),
      surface: _apocalypseSurface,
      onSurface: _apocalypseInk,
      surfaceContainerHighest: Color(0xFF332D26),
      onSurfaceVariant: Color(0xFFB8AB95),
      outline: Color(0xFF4A4036),
      outlineVariant: Color(0xFF332D26),
      error: Color(0xFFFF7F66),
      onError: Color(0xFF3A0E05),
      errorContainer: Color(0xFF40201A),
      onErrorContainer: Color(0xFFFFDAD2),
      inverseSurface: _apocalypseInk,
      onInverseSurface: _apocalypseSurface,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: _apocalypseHazard,
      rewardBg: Color(0xFF3A3012),
      success: Color(0xFF9BD645),
      successBg: Color(0xFF223015),
      danger: Color(0xFFFF7F66),
      dangerBg: Color(0xFF40201A),
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      // Rust into dried rust for the brand cards; army olive into rust for
      // the ones meant to stand out.
      brandGradientStart: Color(0xFF9A3F12),
      brandGradientEnd: Color(0xFF6E2E10),
      heroGradientStart: Color(0xFF3F4A2A),
      heroGradientEnd: Color(0xFF7A4A1A),
    ),
    // Nearly square: cut sheet metal, not a chip. Pills stay pills.
    shapes: AppShapes(xs: 2, sm: 3, md: 4, lg: 6, pill: AppRadius.pill),
    surfaces: AppSurfaces(
      borderWidth: 1.5,
      borderColor: Color(0xFF5A4A38),
      // A hard drop straight down, like a plate bolted a little proud of
      // the wall.
      shadowColor: Color(0x99000000),
      shadowBlur: 0,
      shadowOffset: Offset(0, 3),
      buttonLip: 0,
      overridesSurfaces: true,
    ),
    scaffoldBackground: _apocalypsePage,
    backdrop: AppBackdrop.wasteland,
    navIcons: AppNavIcons.apocalypse,
    headingFace: AppHeadingFace.stencil,
    preview: [_apocalypseRust, _apocalypseHazard, _apocalypsePage],
  );

  /// Neon over a city at night: magenta for the brand colour, cyan for the
  /// edges, electric yellow for rewards. Headings are set in a squared-off
  /// technical face, cards are outlined in cyan with a hard magenta shadow
  /// knocked sideways, like a frame with a glitch in the signal, and the
  /// bar has its own icons.
  ///
  /// Dark, like Night, Space and Apocalypse. Bluer and more violet than
  /// Apocalypse and more saturated than Space, so none of them read as
  /// another.
  static const String cyberpunkId = 'cyberpunk';

  static const Color _cyberpunkPage = Color(0xFF0D0A1A);
  static const Color _cyberpunkSurface = Color(0xFF17122B);
  static const Color _cyberpunkInk = Color(0xFFF0EAFF);
  static const Color _cyberpunkMagenta = Color(0xFFFF2E97);
  static const Color _cyberpunkCyan = Color(0xFF00F0FF);

  static const AppThemeSpec _cyberpunk = AppThemeSpec(
    id: cyberpunkId,
    price: 400,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: _cyberpunkMagenta,
      onPrimary: Color(0xFF2A0016),
      primaryContainer: Color(0xFF4A1238),
      onPrimaryContainer: Color(0xFFFFD6EC),
      secondary: Color(0xFF9F8CFF),
      onSecondary: Color(0xFF1A1040),
      secondaryContainer: Color(0xFF261C4A),
      onSecondaryContainer: _cyberpunkInk,
      tertiary: _cyberpunkCyan,
      onTertiary: Color(0xFF00363A),
      surface: _cyberpunkSurface,
      onSurface: _cyberpunkInk,
      surfaceContainerHighest: Color(0xFF221A3D),
      onSurfaceVariant: Color(0xFFB3A8D9),
      outline: Color(0xFF3A2E66),
      outlineVariant: Color(0xFF221A3D),
      error: Color(0xFFFF6B4A),
      onError: Color(0xFF3A0E05),
      errorContainer: Color(0xFF401A1A),
      onErrorContainer: Color(0xFFFFDAD2),
      inverseSurface: _cyberpunkInk,
      onInverseSurface: _cyberpunkSurface,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: Color(0xFFF5E733),
      rewardBg: Color(0xFF3A3510),
      success: Color(0xFF39FF88),
      successBg: Color(0xFF0E3A26),
      danger: Color(0xFFFF6B4A),
      dangerBg: Color(0xFF401A1A),
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      // Deep magenta into violet for the brand cards; indigo into deep
      // teal for the ones meant to stand out.
      brandGradientStart: Color(0xFF8A1A6B),
      brandGradientEnd: Color(0xFF4A1FA8),
      heroGradientStart: Color(0xFF2A1F8A),
      heroGradientEnd: Color(0xFF0B5E7A),
    ),
    // Nearly square, like a HUD panel. Pills stay pills.
    shapes: AppShapes(xs: 0, sm: 2, md: 3, lg: 4, pill: AppRadius.pill),
    surfaces: AppSurfaces(
      borderWidth: 1,
      borderColor: Color(0xCC00F0FF),
      // A hard magenta copy knocked down and sideways: the colour split of
      // a frame with a glitch in the signal.
      shadowColor: Color(0x99FF2E97),
      shadowBlur: 0,
      shadowOffset: Offset(3, 3),
      buttonLip: 0,
      overridesSurfaces: true,
    ),
    scaffoldBackground: _cyberpunkPage,
    backdrop: AppBackdrop.neonCity,
    navIcons: AppNavIcons.cyberpunk,
    headingFace: AppHeadingFace.tech,
    preview: [_cyberpunkMagenta, _cyberpunkCyan, _cyberpunkPage],
  );

  /// A Victorian workshop: brass, copper and verdigris on dark leather,
  /// faint gears behind every screen, headings in engraved capitals, and
  /// cards framed like brass plates with a thick rim.
  ///
  /// Dark, like the other drawn themes. Brown and gold where Apocalypse is
  /// soot and rust, so the two don't read as one.
  static const String steampunkId = 'steampunk';

  static const Color _steampunkPage = Color(0xFF1C140E);
  static const Color _steampunkSurface = Color(0xFF2A1F16);
  static const Color _steampunkInk = Color(0xFFF2E3C8);
  static const Color _steampunkBrass = Color(0xFFD4A04A);
  static const Color _steampunkVerdigris = Color(0xFF5FB3A0);

  static const AppThemeSpec _steampunk = AppThemeSpec(
    id: steampunkId,
    price: 400,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: _steampunkBrass,
      onPrimary: Color(0xFF2A1A06),
      primaryContainer: Color(0xFF4A3618),
      onPrimaryContainer: Color(0xFFFFE6B8),
      secondary: Color(0xFFC8743C),
      onSecondary: Color(0xFF2A1406),
      secondaryContainer: Color(0xFF3D2A1C),
      onSecondaryContainer: _steampunkInk,
      tertiary: _steampunkVerdigris,
      onTertiary: Color(0xFF0E2A24),
      surface: _steampunkSurface,
      onSurface: _steampunkInk,
      surfaceContainerHighest: Color(0xFF36291D),
      onSurfaceVariant: Color(0xFFC4AE8A),
      outline: Color(0xFF5A4630),
      outlineVariant: Color(0xFF36291D),
      error: Color(0xFFFF7A5C),
      onError: Color(0xFF3A0E05),
      errorContainer: Color(0xFF40201A),
      onErrorContainer: Color(0xFFFFDAD2),
      inverseSurface: _steampunkInk,
      onInverseSurface: _steampunkSurface,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: Color(0xFFF2C14E),
      rewardBg: Color(0xFF3A2E12),
      success: Color(0xFF6FCFA8),
      successBg: Color(0xFF16342A),
      danger: Color(0xFFFF7A5C),
      dangerBg: Color(0xFF40201A),
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      // Copper into dark copper for the brand cards; verdigris into
      // tarnished brass for the ones meant to stand out.
      brandGradientStart: Color(0xFF8A4A1E),
      brandGradientEnd: Color(0xFF5E3414),
      heroGradientStart: Color(0xFF2F5A50),
      heroGradientEnd: Color(0xFF6B4A1E),
    ),
    shapes: AppShapes(xs: 4, sm: 6, md: 10, lg: 14, pill: AppRadius.pill),
    surfaces: AppSurfaces(
      // The thickest rim of any theme: a brass frame round each plate.
      borderWidth: 2,
      borderColor: Color(0xFFA67C3A),
      shadowColor: Color(0x80000000),
      shadowBlur: 6,
      shadowOffset: Offset(0, 3),
      buttonLip: 0,
      overridesSurfaces: true,
    ),
    scaffoldBackground: _steampunkPage,
    backdrop: AppBackdrop.gears,
    navIcons: AppNavIcons.steampunk,
    headingFace: AppHeadingFace.engraved,
    preview: [_steampunkBrass, _steampunkVerdigris, _steampunkPage],
  );

  /// A snowy night among the pines: snow falling behind every screen, red,
  /// gold and green, festive hand-drawn headings, and soft round cards with
  /// a gold thread.
  ///
  /// Dark so the snow shows. Red text on dark green is the hard part, so
  /// the brand red is a bright one and buttons carry dark text on it.
  static const String christmasId = 'christmas';

  static const Color _christmasPage = Color(0xFF0E2A20);
  static const Color _christmasSurface = Color(0xFF16382B);
  static const Color _christmasSnow = Color(0xFFF7F3EA);
  static const Color _christmasRed = Color(0xFFFF6B6B);
  static const Color _christmasGold = Color(0xFFF2C14E);

  static const AppThemeSpec _christmas = AppThemeSpec(
    id: christmasId,
    price: 400,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: _christmasRed,
      onPrimary: Color(0xFF3A0808),
      primaryContainer: Color(0xFF5A1A1E),
      onPrimaryContainer: Color(0xFFFFDAD8),
      secondary: _christmasGold,
      onSecondary: Color(0xFF2A2006),
      secondaryContainer: Color(0xFF2A3A20),
      onSecondaryContainer: _christmasSnow,
      tertiary: Color(0xFF8FD6A8),
      onTertiary: Color(0xFF0A2A18),
      surface: _christmasSurface,
      onSurface: _christmasSnow,
      surfaceContainerHighest: Color(0xFF1E4535),
      onSurfaceVariant: Color(0xFFBCD3C6),
      outline: Color(0xFF2E5A46),
      outlineVariant: Color(0xFF1E4535),
      error: Color(0xFFFF8F5C),
      onError: Color(0xFF3A1205),
      errorContainer: Color(0xFF43211A),
      onErrorContainer: Color(0xFFFFDACC),
      inverseSurface: _christmasSnow,
      onInverseSurface: _christmasSurface,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    semanticColors: AppSemanticColors(
      reward: _christmasGold,
      rewardBg: Color(0xFF3A3012),
      success: Color(0xFF7EE0A0),
      successBg: Color(0xFF123A26),
      danger: Color(0xFFFF8F5C),
      dangerBg: Color(0xFF43211A),
      onAccent: Colors.white,
      onScrim: Colors.white,
      onReward: Colors.black,
      // Holly red into deep red for the brand cards; pine into deep pine
      // for the ones meant to stand out.
      brandGradientStart: Color(0xFFA8202A),
      brandGradientEnd: Color(0xFF6E1420),
      heroGradientStart: Color(0xFF1E6B43),
      heroGradientEnd: Color(0xFF0E4A3A),
    ),
    // Rounder than the classic theme: soft, like something wrapped.
    shapes: AppShapes(xs: 10, sm: 14, md: 22, lg: 28, pill: AppRadius.pill),
    surfaces: AppSurfaces(
      borderWidth: 1.5,
      borderColor: Color(0x99F2C14E),
      shadowColor: Color(0x66000000),
      shadowBlur: 10,
      shadowOffset: Offset(0, 4),
      buttonLip: 0,
      overridesSurfaces: true,
    ),
    scaffoldBackground: _christmasPage,
    backdrop: AppBackdrop.snowfall,
    navIcons: AppNavIcons.christmas,
    headingFace: AppHeadingFace.festive,
    preview: [_christmasRed, _christmasGold, _christmasPage],
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
    _space,
    _vintage,
    _apocalypse,
    _cyberpunk,
    _steampunk,
    _christmas,
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
