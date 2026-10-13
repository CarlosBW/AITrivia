import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// Oceano, Atardecer y Bosque son el clasico con otra paleta: nada de como
/// se dibujan las superficies cambia. Por eso cuestan menos que Jugueton y
/// Noche, y por eso lo unico que puede fallarles es el color — que no se
/// lea, o que dos de ellos no se distingan.
void main() {
  final classic = AppThemes.byId(AppThemes.defaultId);
  final recolors = [
    AppThemes.byId(AppThemes.oceanId),
    AppThemes.byId(AppThemes.sunsetId),
    AppThemes.byId(AppThemes.forestId),
  ];

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  test('estan los tres en el catalogo', () {
    expect(
      recolors.map((s) => s.id),
      [AppThemes.oceanId, AppThemes.sunsetId, AppThemes.forestId],
    );
  });

  for (final spec in recolors) {
    group('el tema ${spec.id}', () {
      final scheme = spec.colorScheme;
      final colors = spec.semanticColors;

      test('cuesta 250, menos que los temas que cambian mas que el color', () {
        expect(spec.price, 250);
        expect(spec.price, lessThan(AppThemes.byId(AppThemes.playfulId).price));
        expect(spec.price, lessThan(AppThemes.byId(AppThemes.nightId).price));
      });

      test('es claro y solo cambia la paleta', () {
        expect(scheme.brightness, Brightness.light);
        expect(spec.surfaces, classic.surfaces);
        expect(spec.shapes, classic.shapes);
        expect(scheme.primary, isNot(classic.colorScheme.primary));
        expect(spec.scaffoldBackground, isNot(classic.scaffoldBackground));
      });

      test('el texto se lee sobre la pagina y sobre las tarjetas', () {
        for (final bg in [
          spec.scaffoldBackground,
          scheme.surface,
          scheme.surfaceContainerHighest,
        ]) {
          expect(contrast(scheme.onSurface, bg), greaterThanOrEqualTo(4.5));
          expect(
            contrast(scheme.onSurfaceVariant, bg),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      test('los botones y los enlaces se leen', () {
        expect(
          contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.primary, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('las tarjetas de degradado llevan su paleta y se leen', () {
        // Eran violeta y rosa escritos en cada pantalla: en un tema verde
        // habrian seguido siendo violeta.
        expect(colors.brandGradientStart, scheme.primary);
        expect(
          colors.heroGradientStart,
          isNot(classic.semanticColors.heroGradientStart),
        );

        // 3:1 — titulos grandes en negrita sobre el degradado, igual que
        // el clasico en sus extremos mas claros.
        for (final stop in [
          colors.brandGradientStart,
          colors.brandGradientEnd,
          colors.heroGradientStart,
          colors.heroGradientEnd,
        ]) {
          expect(contrast(colors.onAccent, stop), greaterThanOrEqualTo(3));
        }
      });

      test('trae tres muestras que empiezan por su color de marca', () {
        expect(spec.preview, hasLength(3));
        expect(spec.preview.first, scheme.primary);
      });
    });
  }

  test('ningun tema comparte color de marca con otro salvo Jugueton', () {
    // Jugueton conserva la paleta del clasico a proposito.
    final primaries = AppThemes.all
        .where((s) => s.id != AppThemes.playfulId)
        .map((s) => s.colorScheme.primary)
        .toList();

    expect(primaries.toSet().length, primaries.length);
  });

  test('el clasico conserva los degradados que estaban en las pantallas', () {
    const colors = AppSemanticColors.standard;

    expect(colors.brandGradientStart, const Color(0xFF6C4FF2));
    expect(colors.brandGradientEnd, const Color(0xFF8A6BFF));
    expect(colors.heroGradientStart, const Color(0xFF8A6BFF));
    expect(colors.heroGradientEnd, const Color(0xFFFF5C93));
  });

  test('cada tema tiene nombre y descripcion en los dos idiomas', () {
    final es = lookupAppLocalizations(const Locale('es'));
    final en = lookupAppLocalizations(const Locale('en'));

    expect(es.themeNameOcean, 'Océano');
    expect(en.themeNameOcean, 'Ocean');
    expect(es.themeNameSunset, 'Atardecer');
    expect(en.themeNameSunset, 'Sunset');
    expect(es.themeNameForest, 'Bosque');
    expect(en.themeNameForest, 'Forest');

    for (final description in [
      es.themeDescriptionOcean,
      es.themeDescriptionSunset,
      es.themeDescriptionForest,
      en.themeDescriptionOcean,
      en.themeDescriptionSunset,
      en.themeDescriptionForest,
    ]) {
      expect(description, isNotEmpty);
    }
  });
}
