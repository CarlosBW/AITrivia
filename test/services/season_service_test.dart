import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/league_service.dart';
import 'package:trivia_ia_flutter/services/season_service.dart';
import 'package:trivia_ia_flutter/services/weekly_league_service.dart';

/// Season payouts exist twice: here, for what the app promises, and in
/// `claimWeeklySeasonRewards` in `index.ts`, for what actually lands in the
/// player's balance. `index.ts` even says it mirrors this file — but
/// nothing enforced it, so the last group reads the server's table instead
/// of restating it.
void main() {
  final service = SeasonService.instance;
  final indexTs = File('functions/src/index.ts').readAsStringSync();

  LeagueInfo leagueById(String id) =>
      LeagueService.leagues.firstWhere((league) => league.id == id);

  group('currentSeasonId', () {
    test('una temporada es la semana de liga', () {
      final now = DateTime(2026, 8, 19);

      expect(
        service.currentSeasonId(now),
        WeeklyLeagueService.instance.currentWeekId(now),
      );
    });
  });

  group('rewardForLeague', () {
    test('la base sube con la liga', () {
      final bronze = service.rewardForLeague(leagueById('bronze'), 50).coins;
      final gold = service.rewardForLeague(leagueById('gold'), 50).coins;
      final master = service.rewardForLeague(leagueById('master'), 50).coins;

      expect(gold, greaterThan(bronze));
      expect(master, greaterThan(gold));
    });

    test('el campeón cobra el doble de la base', () {
      final generic = service.rewardForLeague(leagueById('gold'), 50).coins;
      final champion = service.rewardForLeague(leagueById('gold'), 1).coins;

      expect(champion, generic * 2);
    });

    test('los escalones premian mejor cuanto más arriba', () {
      final gold = leagueById('gold');

      final first = service.rewardForLeague(gold, 1).coins;
      final third = service.rewardForLeague(gold, 3).coins;
      final tenth = service.rewardForLeague(gold, 10).coins;
      final eleventh = service.rewardForLeague(gold, 11).coins;

      expect(first, greaterThan(third));
      expect(third, greaterThan(tenth));
      expect(tenth, greaterThan(eleventh));
    });

    test('los bordes de cada escalón caen del lado correcto', () {
      final gold = leagueById('gold');

      expect(
        service.rewardForLeague(gold, 3).coins,
        service.rewardForLeague(gold, 2).coins,
      );
      expect(
        service.rewardForLeague(gold, 4).coins,
        service.rewardForLeague(gold, 10).coins,
      );
    });

    test('fuera del top 10 solo se cobra la base', () {
      final gold = leagueById('gold');

      expect(
        service.rewardForLeague(gold, 999).coins,
        service.rewardForLeague(gold, 11).coins,
      );
    });
  });

  group('el pago coincide con el que hace el servidor', () {
    // Acotado al bloque `baseCoins` y no buscado en todo el archivo: hay
    // otro switch por liga mas arriba (las recompensas de temporada PvP,
    // con cifras distintas), y una busqueda suelta leia ese por error.
    final baseCoinsBlock = RegExp(
      r'const baseCoins = \(\(\): number => \{([\s\S]*?)\}\)\(\);',
    ).firstMatch(indexTs)?.group(1);

    for (final leagueId in ['bronze', 'silver', 'gold', 'diamond', 'master']) {
      test('base de $leagueId', () {
        expect(
          baseCoinsBlock,
          isNotNull,
          reason: 'index.ts ya no declara `const baseCoins` en '
              'claimWeeklySeasonRewards. Si cambió de forma, actualiza este '
              'test para que siga vigilando el pago.',
        );

        final match = RegExp('case "$leagueId": return (\\d+);')
            .firstMatch(baseCoinsBlock!);

        expect(
          match,
          isNotNull,
          reason: 'la tabla de baseCoins ya no cubre "$leagueId".',
        );

        // Fuera del top 10 el cliente no suma bonus, asi que lo que
        // devuelve es exactamente la base.
        expect(
          service.rewardForLeague(leagueById(leagueId), 999).coins,
          int.parse(match!.group(1)!),
        );
      });
    }
  });
}
