import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/versus/pvp_season_screen.dart';
import 'package:trivia_ia_flutter/features/versus/pvp_season_widgets.dart';
import 'package:trivia_ia_flutter/services/pvp_league_service.dart';

void main() {
  Widget app(Widget child, {double width = 360}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  group('pointsToNextLeague', () {
    const leagues = PvpLeagueService.leagues;

    test('lo que falta para el mínimo de la liga de arriba', () {
      final gold = leagues.firstWhere((l) => l.id == 'gold');
      final next = leagues[leagues.indexOf(gold) + 1];
      expect(
        pointsToNextLeague(gold.minRating + 84, next),
        next.minRating - gold.minRating - 84,
      );
    });

    test('en la liga más alta no hay siguiente', () {
      expect(pointsToNextLeague(3000, null), isNull);
    });

    test('nunca dice que faltan cero o menos puntos', () {
      final next = leagues[1];
      expect(pointsToNextLeague(next.minRating, next), isNull);
      expect(pointsToNextLeague(next.minRating + 50, next), isNull);
    });
  });

  group('SeasonHeroCard', () {
    testWidgets('dice la liga, el MMR, el cambio y lo que falta',
        (tester) async {
      await tester.pumpWidget(app(const SeasonHeroCard(
        seasonLabel: 'Temporada: noviembre 2026',
        leagueEmoji: '🥇',
        leagueTitle: 'Liga Oro',
        leagueColor: Color(0xFFFFA000),
        rating: 1284,
        deltaText: '+18',
        progress: 0.42,
        progressLabel: 'Faltan 116 MMR para Platino',
      )));

      expect(find.text('Liga Oro'), findsOneWidget);
      expect(find.textContaining('1284'), findsOneWidget);
      expect(find.text('+18'), findsOneWidget);
      expect(find.text('Faltan 116 MMR para Platino'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.42,
      );
    });

    testWidgets('sin partida reciente no inventa un cambio', (tester) async {
      await tester.pumpWidget(app(const SeasonHeroCard(
        seasonLabel: 'Temporada',
        leagueEmoji: '🥉',
        leagueTitle: 'Liga Bronce',
        leagueColor: Color(0xFF8D6E63),
        rating: 1000,
        progress: 0,
        progressLabel: 'Faltan 200 MMR para Oro',
      )));

      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('cabe en un teléfono estrecho con letra grande',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: SeasonHeroCard(
                  seasonLabel: 'Temporada: noviembre 2026',
                  leagueEmoji: '💎',
                  leagueTitle: 'Liga Platino II',
                  leagueColor: Color(0xFF00ACC1),
                  rating: 1584,
                  deltaText: '-24',
                  deltaPositive: false,
                  progress: 0.9,
                  progressLabel: 'Faltan 16 MMR para Diamante',
                ),
              ),
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  });

  group('SeasonRankRow', () {
    Future<void> pump(
      WidgetTester tester,
      int position, {
      bool isMe = false,
      VoidCallback? onTap,
    }) {
      return tester.pumpWidget(app(SeasonRankRow(
        position: position,
        avatar: '🚀',
        name: 'Valentina',
        leagueLine: '💎 Platino • 42 partidas',
        recordLine: '30 G / 10 P / 2 E',
        rating: 1512,
        leagueColor: const Color(0xFF00ACC1),
        isMe: isMe,
        onTap: onTap,
      )));
    }

    testWidgets('muestra el puesto, el nombre, el récord y el MMR',
        (tester) async {
      await pump(tester, 7);

      expect(find.text('7'), findsOneWidget);
      expect(find.text('Valentina'), findsOneWidget);
      expect(find.text('30 G / 10 P / 2 E'), findsOneWidget);
      expect(find.text('1512'), findsOneWidget);
    });

    testWidgets('tocar la fila abre las acciones del jugador', (tester) async {
      var taps = 0;
      await pump(tester, 2, onTap: () => taps++);

      await tester.tap(find.text('Valentina'));
      expect(taps, 1);
    });

    testWidgets('un nombre larguísimo no desborda la fila', (tester) async {
      await tester.pumpWidget(app(
        const SeasonRankRow(
          position: 100,
          avatar: '🧠',
          name: 'UnNombreDeUsuarioMuyLargo_20',
          leagueLine: '🥇 Oro • 1234 partidas clasificatorias',
          recordLine: '1000 G / 200 P / 34 E',
          rating: 2999,
          leagueColor: Color(0xFFFFA000),
          trailing: Icon(Icons.person_add),
        ),
        width: 320,
      ));

      expect(tester.takeException(), isNull);
    });
  });

  group('SeasonLeagueRewardRow', () {
    testWidgets('la liga propia lleva su etiqueta; las demás no',
        (tester) async {
      await tester.pumpWidget(app(const Column(children: [
        SeasonLeagueRewardRow(
          emoji: '🥇',
          title: 'Liga Oro',
          range: '1200-1399 MMR',
          coinsText: '+150 monedas',
          leagueColor: Color(0xFFFFA000),
          currentLabel: 'Recompensa proyectada actual',
        ),
        SeasonLeagueRewardRow(
          emoji: '🥈',
          title: 'Liga Plata',
          range: '1000-1199 MMR',
          coinsText: '+80 monedas',
          leagueColor: Color(0xFF78909C),
        ),
      ])));

      expect(find.text('Recompensa proyectada actual'), findsOneWidget);
      expect(find.text('+150 monedas'), findsOneWidget);
      expect(find.text('+80 monedas'), findsOneWidget);
    });
  });

  group('SeasonStepsCard', () {
    testWidgets('quita la viñeta del texto: el ícono ya la reemplaza',
        (tester) async {
      await tester.pumpWidget(app(const SeasonStepsCard(
        title: 'Cómo funciona',
        steps: [(Icons.shield, '• Tu liga se calcula según tu MMR actual.')],
      )));

      expect(
        find.text('Tu liga se calcula según tu MMR actual.'),
        findsOneWidget,
      );
    });
  });

  group('SeasonPillTabBar', () {
    testWidgets('cambia de pestaña al tocar', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            body: Column(children: [
              SeasonPillTabBar(tabs: [
                SeasonPillTab(label: 'Amigos', icon: Icons.group),
                SeasonPillTab(label: 'Global', icon: Icons.public),
              ]),
              Expanded(
                child: TabBarView(children: [Text('lista A'), Text('lista B')]),
              ),
            ]),
          ),
        ),
      ));

      expect(find.text('lista A'), findsOneWidget);
      await tester.tap(find.text('Global'));
      await tester.pumpAndSettle();
      expect(find.text('lista B'), findsOneWidget);
    });
  });
}
