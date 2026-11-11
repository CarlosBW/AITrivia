import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/profile/match_history_card.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// Una partida del historial en el Perfil: el resultado, el rival y el
/// marcador se leen de un vistazo, en una sola fila.
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
    Widget card, {
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
      home: Scaffold(body: ListView(children: [card])),
    ));
    await tester.pumpAndSettle();
  }

  MatchHistoryCard card({
    String result = 'victory',
    int? ratingDelta,
    VoidCallback? onMore,
  }) =>
      MatchHistoryCard(
        result: result,
        resultLabel: result == 'victory' ? 'Victoria' : 'Derrota',
        opponentLine: 'vs CarlosBW1989',
        myScore: 7,
        opponentScore: 5,
        modeLabel: ratingDelta == null ? 'Casual' : 'Clasificatoria',
        ratingDelta: ratingDelta,
        playedAt: DateTime(2026, 11, 9),
        onMore: onMore,
        moreTooltip: 'Opciones',
      );

  testWidgets('muestra el resultado, el rival y el marcador', (tester) async {
    await pump(tester, card());

    expect(find.text('Victoria'), findsOneWidget);
    expect(find.text('vs CarlosBW1989'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
  });

  testWidgets('el MMR solo aparece en las clasificatorias, con su signo',
      (tester) async {
    await pump(tester, card());
    expect(find.textContaining('MMR'), findsNothing);

    await pump(tester, card(ratingDelta: 18));
    expect(find.text('+18 MMR'), findsOneWidget);

    await pump(tester, card(result: 'defeat', ratingDelta: -12));
    expect(find.text('-12 MMR'), findsOneWidget);
  });

  testWidgets('el menu del rival solo aparece si hay a quien reportar',
      (tester) async {
    await pump(tester, card());
    expect(find.byTooltip('Opciones'), findsNothing);

    var opened = false;
    await pump(tester, card(onMore: () => opened = true));
    await tester.tap(find.byTooltip('Opciones'));
    expect(opened, isTrue);
  });

  testWidgets('cabe en un telefono angosto con todos los temas',
      (tester) async {
    for (final spec in AppThemes.all) {
      await pump(
        tester,
        card(ratingDelta: -12, onMore: () {}),
        themeId: spec.id,
      );
      expect(tester.takeException(), isNull, reason: spec.id);
    }
  });
}
