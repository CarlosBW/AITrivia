import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/versus/pvp_result_card.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// La tarjeta de resultado de un duelo: quien gano se nota de un vistazo,
/// y se lee bien en un telefono angosto con cualquier tema.
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
    PvpResultCard card, {
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
      home: Scaffold(body: card),
    ));
    await tester.pumpAndSettle();
  }

  PvpResultCard card({
    PvpResultState state = PvpResultState.victory,
    int myScore = 11,
    int? opponentScore = 10,
  }) =>
      PvpResultCard(
        state: state,
        title: '¡Ganaste!',
        subtitle: 'Buen duelo.',
        myName: 'blaky_2',
        opponentName: 'CarlosBW1989',
        myScore: myScore,
        opponentScore: opponentScore,
        primaryButtonText: 'Salir',
        onPrimaryPressed: () {},
        secondaryButtonText: 'Revancha',
        onSecondaryPressed: () {},
      );

  testWidgets('muestra a los dos jugadores con su puntaje final',
      (tester) async {
    await pump(tester, card());

    expect(find.text('¡Ganaste!'), findsOneWidget);
    expect(find.text('blaky_2'), findsOneWidget);
    expect(find.text('CarlosBW1989'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('el ganador lleva la corona, y solo el', (tester) async {
    await pump(tester, card());
    expect(find.byIcon(Icons.workspace_premium), findsOneWidget);

    final crown = tester.getCenter(find.byIcon(Icons.workspace_premium));
    final me = tester.getCenter(find.text('blaky_2'));
    final rival = tester.getCenter(find.text('CarlosBW1989'));
    expect((crown.dx - me.dx).abs() < (crown.dx - rival.dx).abs(), isTrue,
        reason: 'la corona va sobre quien gano');
  });

  testWidgets('si gano el rival, la corona va con el', (tester) async {
    await pump(
      tester,
      card(state: PvpResultState.defeat, myScore: 4, opponentScore: 9),
    );
    final crown = tester.getCenter(find.byIcon(Icons.workspace_premium));
    final rival = tester.getCenter(find.text('CarlosBW1989'));
    final me = tester.getCenter(find.text('blaky_2'));
    expect((crown.dx - rival.dx).abs() < (crown.dx - me.dx).abs(), isTrue);
  });

  testWidgets('en un empate nadie lleva corona', (tester) async {
    await pump(
      tester,
      card(state: PvpResultState.draw, myScore: 7, opponentScore: 7),
    );
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
  });

  testWidgets('esperando al rival no hay corona ni barra de puntos',
      (tester) async {
    await pump(
      tester,
      card(state: PvpResultState.waiting, opponentScore: null),
    );
    expect(find.byIcon(Icons.workspace_premium), findsNothing);
    expect(find.byKey(const ValueKey('pvp-score-bar')), findsNothing);
    expect(find.text('CarlosBW1989'), findsOneWidget);
  });

  testWidgets('con puntajes, la barra muestra quien se llevo mas',
      (tester) async {
    await pump(tester, card());
    expect(find.byKey(const ValueKey('pvp-score-bar')), findsOneWidget);
  });

  testWidgets('cabe en un telefono angosto con todos los temas',
      (tester) async {
    for (final spec in AppThemes.all) {
      await pump(tester, card(), themeId: spec.id);
      expect(tester.takeException(), isNull, reason: spec.id);
    }
  });
}
