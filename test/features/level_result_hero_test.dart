import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/solo/level_result_hero.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// El final de un nivel: el resultado se lee de un vistazo sobre el
/// degradado del tema, y "progreso guardado" va con la estetica del juego.
void main() {
  ThemeData testTheme(AppThemeSpec spec) => ThemeData(
        colorScheme: spec.colorScheme,
        extensions: [
          const AppTypography(heading: TextStyle()),
          spec.semanticColors,
          spec.shapes,
          spec.surfaces,
          spec.decor,
        ],
      );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    String themeId = AppThemes.defaultId,
  }) async {
    tester.view.physicalSize = const Size(360 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: testTheme(AppThemes.byId(themeId)),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  LevelResultHero hero({int correct = 8, int stars = 2}) => LevelResultHero(
        title: '¡Nivel aprobado!',
        stars: stars,
        correct: correct,
        total: 10,
        rankLabel: 'Avanzado',
      );

  testWidgets('muestra el titulo, los aciertos y el rango', (tester) async {
    await pump(tester, hero());

    expect(find.text('¡Nivel aprobado!'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('/ 10'), findsOneWidget);
    expect(find.text('Avanzado'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('las estrellas ganadas van llenas y el resto vacias',
      (tester) async {
    await pump(tester, hero(stars: 2));
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
  });

  Color starColor(WidgetTester tester) =>
      tester.widget<Icon>(find.byIcon(Icons.star_rounded).first).color!;

  testWidgets('las estrellas ganadas van en el color de recompensa',
      (tester) async {
    await pump(tester, hero(stars: 3));
    expect(
      starColor(tester),
      AppThemes.byId(AppThemes.defaultId).semanticColors.reward,
    );
  });

  testWidgets('en Boceto, donde ese color es tinta, van en blanco',
      (tester) async {
    // Su color de recompensa es casi negro, como su banner.
    await pump(tester, hero(stars: 3), themeId: AppThemes.sketchId);
    final sketch = AppThemes.byId(AppThemes.sketchId).semanticColors;
    expect(starColor(tester), isNot(sketch.reward));
    expect(starColor(tester), sketch.onAccent);
  });

  testWidgets('sin aprobar no hay destellos de celebracion', (tester) async {
    await pump(tester, hero(correct: 2, stars: 0));
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(3));
  });

  testWidgets('progreso guardado es una etiqueta del tema, sin emoji',
      (tester) async {
    await pump(tester, const ProgressSavedChip(label: 'Progreso guardado'));
    expect(find.text('Progreso guardado'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
  });

  testWidgets('el texto de "progreso guardado" ya no trae el ✅', (tester) async {
    expect(
      lookupAppLocalizations(const Locale('es')).levelPlayProgressSaved,
      isNot(contains('✅')),
    );
    expect(
      lookupAppLocalizations(const Locale('en')).levelPlayProgressSaved,
      isNot(contains('✅')),
    );
  });

  testWidgets('cabe en un telefono angosto con todos los temas',
      (tester) async {
    for (final spec in AppThemes.all) {
      await pump(
        tester,
        Column(children: [
          hero(),
          const ResultNote(text: 'Este nivel ya había sido aprobado antes.'),
          const ProgressSavedChip(label: 'Progreso guardado'),
        ]),
        themeId: spec.id,
      );
      expect(tester.takeException(), isNull, reason: spec.id);
    }
  });
}
