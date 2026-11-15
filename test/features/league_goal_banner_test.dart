import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/leagues/league_goal_banner.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/league_goal.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

void main() {
  Future<void> pump(WidgetTester tester, LeagueGoal goal, {String? themeId}) {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemes.byId(themeId ?? AppThemes.defaultId)),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: LeagueGoalBanner(goal: goal),
          ),
        ),
      ),
    );
  }

  testWidgets('dice cuántos puntos faltan y para pasar a quién',
      (tester) async {
    await pump(
      tester,
      const LeagueGoal(rank: 3, rivalName: 'Beto', pointsToPass: 41),
    );

    expect(find.text('Te faltan 41 puntos para pasar a Beto'), findsOneWidget);
  });

  testWidgets('con un punto lo dice en singular', (tester) async {
    await pump(
      tester,
      const LeagueGoal(rank: 2, rivalName: 'Ana', pointsToPass: 1),
    );

    expect(find.text('Te falta 1 punto para pasar a Ana'), findsOneWidget);
  });

  testWidgets('en primer lugar dice la ventaja', (tester) async {
    await pump(tester, const LeagueGoal(rank: 1, lead: 260));

    expect(
      find.text('Vas primero, con 260 puntos de ventaja'),
      findsOneWidget,
    );
  });

  testWidgets('primero y empatado no presume de ventaja', (tester) async {
    await pump(tester, const LeagueGoal(rank: 1, lead: 0));

    expect(find.textContaining('empatado'), findsOneWidget);
  });

  testWidgets('primero y solo anima a seguir', (tester) async {
    await pump(tester, const LeagueGoal(rank: 1));

    expect(find.textContaining('Vas primero.'), findsOneWidget);
  });

  for (final theme in AppThemes.all) {
    testWidgets('en ${theme.id} un nombre largo cabe en pantalla angosta',
        (tester) async {
      await pump(
        tester,
        const LeagueGoal(
          rank: 7,
          rivalName: 'UnNombreDeJugadorLargo',
          pointsToPass: 1234,
        ),
        themeId: theme.id,
      );

      expect(tester.takeException(), isNull);
    });
  }
}
