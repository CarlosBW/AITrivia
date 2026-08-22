import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/pvp_league_service.dart';
import 'package:trivia_ia_flutter/services/pvp_season_service.dart';

/// PvP seasons are monthly, and their payout is mirrored inside
/// `claimPvpSeasonRewards` in `index.ts` — the comment there even names
/// this file. Master is the interesting case: it has no rating ceiling, so
/// the reward scales by tier instead of being flat.
void main() {
  final service = PvpSeasonService.instance;
  final leagues = PvpLeagueService.instance;
  final indexTs = File('functions/src/index.ts').readAsStringSync();

  group('currentSeason', () {
    test('va del primero del mes al primero del siguiente', () {
      final season = service.currentSeason(DateTime(2026, 8, 22, 17, 30));

      expect(season.id, 'pvp_2026_08');
      expect(season.start, DateTime(2026, 8, 1));
      expect(season.end, DateTime(2026, 9, 1));
    });

    test('el mes se rellena a dos dígitos', () {
      expect(service.currentSeason(DateTime(2026, 1, 15)).id, 'pvp_2026_01');
    });

    test('cualquier día del mes cae en la misma temporada', () {
      expect(
        service.currentSeason(DateTime(2026, 8, 1)).id,
        service.currentSeason(DateTime(2026, 8, 31, 23, 59)).id,
      );
    });

    test('diciembre cierra contra enero del año siguiente', () {
      final season = service.currentSeason(DateTime(2026, 12, 10));

      expect(season.id, 'pvp_2026_12');
      expect(season.end, DateTime(2027, 1, 1));
    });
  });

  group('previousSeason', () {
    test('es el mes anterior', () {
      final season = service.previousSeason(DateTime(2026, 8, 22));

      expect(season.id, 'pvp_2026_07');
      expect(season.start, DateTime(2026, 7, 1));
      expect(season.end, DateTime(2026, 8, 1));
    });

    // Enero tiene que retroceder de año, no quedarse en un mes cero.
    test('desde enero retrocede a diciembre del año anterior', () {
      final season = service.previousSeason(DateTime(2026, 1, 5));

      expect(season.id, 'pvp_2025_12');
      expect(season.start, DateTime(2025, 12, 1));
    });

    test('termina justo donde empieza la actual', () {
      final now = DateTime(2026, 8, 22);

      expect(
        service.previousSeason(now).end,
        service.currentSeason(now).start,
      );
    });
  });

  group('rewardForRating', () {
    test('por debajo de maestro paga lo de su liga', () {
      final gold = leagues.leagueForRating(1250);

      expect(
        service.rewardForRating(1250).coins,
        service.rewardForLeague(gold).coins,
      );
    });

    // El motivo de que esta funcion exista: con un pago plano, subir de
    // rating dentro de maestro dejaba de valer la pena.
    test('dentro de maestro el pago sube por tramo', () {
      final tier1 = service.rewardForRating(1900).coins;
      final tier2 = service.rewardForRating(2050).coins;
      final tier3 = service.rewardForRating(2200).coins;

      expect(tier2, greaterThan(tier1));
      expect(tier3, greaterThan(tier2));
    });

    test('los bordes de tramo caen del lado correcto', () {
      expect(
        service.rewardForRating(2049).coins,
        service.rewardForRating(1900).coins,
      );
      expect(
        service.rewardForRating(2199).coins,
        service.rewardForRating(2050).coins,
      );
    });
  });

  group('rewardForLeague', () {
    test('paga más cuanto más alta la liga', () {
      int coinsFor(String id) => service
          .rewardForLeague(leagues.leagueById(id))
          .coins;

      expect(coinsFor('silver'), greaterThan(coinsFor('bronze')));
      expect(coinsFor('gold'), greaterThan(coinsFor('silver')));
      expect(coinsFor('platinum'), greaterThan(coinsFor('gold')));
      expect(coinsFor('diamond'), greaterThan(coinsFor('platinum')));
      expect(coinsFor('master'), greaterThan(coinsFor('diamond')));
    });
  });

  group('el pago coincide con el que hace el servidor', () {
    // Acotado a `claimPvpSeasonRewards`: hay otra tabla por liga mas abajo
    // (las recompensas de temporada semanal) con cifras distintas.
    final block = RegExp(
      r'const rewardForLeague = \(league: PvpLeagueInfo, rating: number\)'
      r': number => \{([\s\S]*?)\n    \};',
    ).firstMatch(indexTs)?.group(1);

    for (final entry in {
      'diamond': 'diamond',
      'platinum': 'platinum',
      'gold': 'gold',
      'silver': 'silver',
    }.entries) {
      test('base de ${entry.key}', () {
        expect(
          block,
          isNotNull,
          reason: 'index.ts ya no declara `rewardForLeague` dentro de '
              'claimPvpSeasonRewards. Si cambió de forma, actualiza este '
              'test para que siga vigilando el pago.',
        );

        final match = RegExp('case "${entry.value}": return (\\d+);')
            .firstMatch(block!);

        expect(match, isNotNull, reason: 'la tabla no cubre ${entry.key}');

        expect(
          service.rewardForLeague(leagues.leagueById(entry.key)).coins,
          int.parse(match!.group(1)!),
        );
      });
    }

    test('los tramos de maestro', () {
      expect(block, isNotNull);

      final tiers = RegExp(r'if \(rating >= (\d+)\) return (\d+);')
          .allMatches(block!)
          .map((m) => [int.parse(m.group(1)!), int.parse(m.group(2)!)])
          .toList();

      expect(tiers, hasLength(2), reason: 'se esperaban dos tramos');

      for (final tier in tiers) {
        expect(
          service.rewardForRating(tier[0]).coins,
          tier[1],
          reason: 'rating ${tier[0]} debería pagar ${tier[1]}',
        );
      }
    });
  });

  group('formatTimeLeft', () {
    test('con días muestra las tres unidades', () {
      expect(
        service.formatTimeLeft(
          const Duration(days: 2, hours: 3, minutes: 4),
        ),
        '2d 3h 4m',
      );
    });

    test('sin días omite los días', () {
      expect(
        service.formatTimeLeft(const Duration(hours: 5, minutes: 9)),
        '5h 9m',
      );
    });

    test('bajo una hora solo quedan minutos', () {
      expect(service.formatTimeLeft(const Duration(minutes: 42)), '42m');
    });

    test('cero se muestra como cero minutos', () {
      expect(service.formatTimeLeft(Duration.zero), '0m');
    });
  });
}
