import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/shop/theme_preview_screen.dart';
import 'package:trivia_ia_flutter/features/shop/theme_shop_section.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/sketchbook_backdrop.dart';
import 'package:trivia_ia_flutter/theme/snowfall_backdrop.dart';

/// Antes de gastar cientos de monedas en un tema, el jugador puede verlo
/// puesto: la vista previa pinta una pantalla de juego con ese tema, sin
/// equiparlo.
void main() {
  // buildAppTheme resuelve las letras con google_fonts, que en los tests
  // intenta bajarlas; esto arma lo mismo que leen las pantallas.
  ThemeData testTheme(AppThemeSpec spec) => ThemeData(
        colorScheme: spec.colorScheme,
        scaffoldBackgroundColor: spec.decor.backdrop == AppBackdrop.plain
            ? spec.scaffoldBackground
            : Colors.transparent,
        extensions: [
          const AppTypography(heading: TextStyle()),
          spec.semanticColors,
          spec.shapes,
          spec.surfaces,
          spec.decor,
        ],
      );

  Widget app(Widget home) => MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: testTheme(AppThemes.byId(AppThemes.defaultId)),
        home: home,
      );

  testWidgets('la vista previa se pinta con el tema que se mira',
      (tester) async {
    final sketch = AppThemes.byId(AppThemes.sketchId);

    await tester.pumpWidget(app(ThemePreviewScreen(
      spec: sketch,
      name: 'Boceto',
      owned: false,
      themeFor: testTheme,
    )));

    expect(find.byType(SketchbookBackdrop), findsOneWidget);
    expect(find.byType(SnowfallBackdrop), findsNothing);

    final scheme = Theme.of(tester.element(find.byType(SketchbookBackdrop)))
        .colorScheme;
    expect(scheme.primary, sketch.colorScheme.primary);
  });

  testWidgets('comprar desde la vista previa vuelve a la tienda con un si',
      (tester) async {
    bool? result;
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => ThemePreviewScreen(
                spec: AppThemes.byId(AppThemes.sketchId),
                name: 'Boceto',
                owned: false,
                themeFor: testTheme,
              ),
            ),
          );
        },
        child: const Text('abrir'),
      ),
    )));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('400'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('un tema que ya es tuyo no ofrece comprarlo', (tester) async {
    await tester.pumpWidget(app(ThemePreviewScreen(
      spec: AppThemes.byId(AppThemes.sketchId),
      name: 'Boceto',
      owned: true,
      themeFor: testTheme,
    )));

    expect(find.text('400'), findsNothing);
  });

  testWidgets('cada tema de la tienda tiene su boton de vista previa',
      (tester) async {
    var previewed = false;
    await tester.pumpWidget(app(Scaffold(
      body: ThemeCard(
        spec: AppThemes.byId(AppThemes.sketchId),
        name: 'Boceto',
        description: 'Blanco y negro',
        owned: false,
        equipped: false,
        busy: false,
        affordable: true,
        onEquip: () {},
        onBuy: () {},
        onPreview: () => previewed = true,
      ),
    )));

    await tester.tap(find.text('Vista previa'));
    expect(previewed, isTrue);
  });
}
