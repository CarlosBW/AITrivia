import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/home/daily_missions_card.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/daily_missions.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

void main() {
  const dateId = '2026-11-15'; // correct_15, play_daily, streak_level
  late int claims;

  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic>? doc, {
    bool claiming = false,
    String? themeId,
    double width = 360,
  }) {
    claims = 0;
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemes.byId(themeId ?? AppThemes.defaultId)),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DailyMissionsCard(
              day: MissionsDay.fromDoc(dateId, doc),
              claiming: claiming,
              onClaim: () => claims++,
            ),
          ),
        ),
      ),
    );
  }

  const allDone = {
    'stats': {'correct': 15, 'dailyPlayed': 1, 'streakLevels': 1},
  };

  testWidgets('un día sin empezar muestra las tres misiones y el premio',
      (tester) async {
    await pump(tester, null);

    expect(find.text('Misiones de hoy'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    expect(find.text('Acierta 15 preguntas'), findsOneWidget);
    expect(find.text('Juega el reto diario'), findsOneWidget);
    expect(
      find.text('Encadena 5 aciertos seguidos en un nivel'),
      findsOneWidget,
    );
    expect(find.textContaining('+10 monedas'), findsOneWidget);
    expect(find.text('Abrir el cofre'), findsNothing);
  });

  testWidgets('a medias muestra cuánto lleva cada una', (tester) async {
    await pump(tester, {
      'stats': {'correct': 7, 'dailyPlayed': 1},
    });

    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('7/15'), findsOneWidget);
    expect(find.text('Abrir el cofre'), findsNothing);
  });

  testWidgets('con las tres hechas ofrece abrir el cofre', (tester) async {
    await pump(tester, allDone);

    expect(find.text('3/3'), findsOneWidget);
    await tester.tap(find.text('Abrir el cofre'));
    expect(claims, 1);
  });

  testWidgets('mientras se abre el cofre no se puede volver a tocar',
      (tester) async {
    await pump(tester, allDone, claiming: true);

    await tester.tap(find.text('Abrir el cofre'));
    expect(claims, 0);
  });

  testWidgets('con el cofre abierto ya no lo ofrece', (tester) async {
    await pump(tester, {...allDone, 'chestClaimed': true});

    expect(find.text('Abrir el cofre'), findsNothing);
    expect(find.textContaining('Cofre abierto'), findsOneWidget);
  });

  for (final theme in AppThemes.all) {
    testWidgets('en ${theme.id} cabe en un teléfono angosto', (tester) async {
      await pump(
        tester,
        {
          'stats': {'correct': 7},
        },
        themeId: theme.id,
        width: 320,
      );

      expect(tester.takeException(), isNull);
    });
  }
}
