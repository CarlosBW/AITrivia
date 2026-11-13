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

  // Las estrellas aparecían ya llenas. Ahora se cuentan una por una.
  group('las estrellas se llenan una por una', () {
    Future<void> open(WidgetTester tester, LevelResultHero widget) async {
      tester.view.physicalSize = const Size(360 * 3, 760 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: testTheme(AppThemes.byId(AppThemes.defaultId)),
        home: Scaffold(body: SingleChildScrollView(child: widget)),
      ));
    }

    int filled(WidgetTester tester) =>
        tester.widgetList(find.byIcon(Icons.star_rounded)).length;

    testWidgets('al abrir, las tres están vacías', (tester) async {
      await open(tester, hero(correct: 10, stars: 3));

      expect(filled(tester), 0);
      expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(3));

      await tester.pumpAndSettle();
    });

    testWidgets('se van llenando en orden, con una pausa entre cada una',
        (tester) async {
      await open(tester, hero(correct: 10, stars: 3));

      await tester.pump(Duration(milliseconds: starFillStartMs(0) + 20));
      expect(filled(tester), 1);

      await tester.pump(const Duration(milliseconds: 450));
      expect(filled(tester), 2);

      await tester.pump(const Duration(milliseconds: 450));
      expect(filled(tester), 3);

      await tester.pumpAndSettle();
    });

    testWidgets('solo se llenan las que se ganaron', (tester) async {
      await open(tester, hero(correct: 5, stars: 1));
      await tester.pumpAndSettle();

      expect(filled(tester), 1);
      expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(2));
    });

    testWidgets('la celebración espera a la tercera estrella', (tester) async {
      await open(
        tester,
        const LevelResultHero(
          title: '¡Nivel aprobado!',
          stars: 3,
          correct: 10,
          total: 10,
          rankLabel: 'Experto',
          celebration: Text('PERFECTO'),
        ),
      );

      await tester.pump(Duration(milliseconds: starFillStartMs(1) + 20));
      expect(find.text('PERFECTO'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('PERFECTO'), findsOneWidget);
    });
  });

  test('cada estrella empieza después de la anterior', () {
    expect(starsFilledAt(0, 3), 0);
    expect(starsFilledAt(starFillStartMs(0), 3), 1);
    expect(starsFilledAt(starFillStartMs(1) - 1, 3), 1);
    expect(starsFilledAt(starFillStartMs(2), 3), 3);
    // Nunca más de las ganadas, por mucho que pase el tiempo.
    expect(starsFilledAt(60000, 2), 2);
    expect(starsFilledAt(60000, 0), 0);
  });
}
