import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/daily_missions.dart';

void main() {
  group('DailyMissions.dateId', () {
    // El día de las misiones es el de Lima para todos.
    test('de noche en Lima sigue siendo el mismo día', () {
      expect(
        DailyMissions.dateId(DateTime.parse('2026-11-14T23:30:00-05:00')),
        '2026-11-14',
      );
    });

    test('cambia a la medianoche de Lima, no a la de UTC', () {
      expect(
        DailyMissions.dateId(DateTime.utc(2026, 11, 15, 4, 59)),
        '2026-11-14',
      );
      expect(
        DailyMissions.dateId(DateTime.utc(2026, 11, 15, 5, 0)),
        '2026-11-15',
      );
    });

    test('el reinicio es la siguiente medianoche de Lima', () {
      expect(
        DailyMissions.nextReset(DateTime.utc(2026, 11, 15, 4, 59)),
        DateTime.utc(2026, 11, 15, 5),
      );
      expect(
        DailyMissions.nextReset(DateTime.utc(2026, 11, 15, 5)),
        DateTime.utc(2026, 11, 16, 5),
      );
    });
  });

  group('DailyMissions.forDate', () {
    test('un día tiene una misión de cada grupo', () {
      final missions = DailyMissions.forDate('2026-11-14');

      expect(missions, hasLength(DailyMissions.slots.length));
      for (var i = 0; i < missions.length; i++) {
        expect(DailyMissions.slots[i], contains(missions[i]));
      }
    });

    // Los mismos días que fija daily_missions.test.ts: la app y el
    // servidor tienen que elegir las mismas misiones.
    test('elige las mismas que el servidor', () {
      List<String> ids(String dateId) =>
          [for (final m in DailyMissions.forDate(dateId)) m.id];

      expect(ids('2026-11-14'),
          ['correct_20', 'solo_levels_3', 'great_level']);
      expect(ids('2026-11-15'), ['correct_15', 'play_daily', 'streak_level']);
      expect(ids('2026-11-16'),
          ['correct_25', 'solo_levels_2', 'great_level']);
    });

    test('una fecha que no lo es no tiene misiones', () {
      expect(DailyMissions.forDate('hoy'), isEmpty);
    });
  });

  group('MissionsDay', () {
    const dateId = '2026-11-15'; // correct_15, play_daily, streak_level

    test('un día sin documento empieza en cero', () {
      final day = MissionsDay.fromDoc(dateId, null);

      expect(day.doneCount, 0);
      expect(day.allDone, isFalse);
      expect(day.chestReady, isFalse);
      expect(day.progress(day.missions.first), 0);
    });

    test('el progreso no pasa de la meta', () {
      final day = MissionsDay.fromDoc(dateId, {
        'stats': {'correct': 40},
      });

      expect(day.progress(day.missions.first), 15);
      expect(day.doneCount, 1);
    });

    test('con las tres hechas el cofre está listo', () {
      final day = MissionsDay.fromDoc(dateId, {
        'stats': {'correct': 15, 'dailyPlayed': 1, 'streakLevels': 1},
      });

      expect(day.allDone, isTrue);
      expect(day.chestReady, isTrue);
    });

    test('un cofre ya abierto no vuelve a estar listo', () {
      final day = MissionsDay.fromDoc(dateId, {
        'stats': {'correct': 15, 'dailyPlayed': 1, 'streakLevels': 1},
        'chestClaimed': true,
      });

      expect(day.allDone, isTrue);
      expect(day.chestReady, isFalse);
    });

    test('lo hecho para otras misiones no cuenta para las de hoy', () {
      final day = MissionsDay.fromDoc(dateId, {
        'stats': {'correct': 15, 'soloLevels': 9, 'weeklyRounds': 3},
      });

      expect(day.doneCount, 1);
      expect(day.chestReady, isFalse);
    });

    test('una cuenta que no es un número se lee como cero', () {
      final day = MissionsDay.fromDoc(dateId, {
        'stats': {'correct': 'x', 'dailyPlayed': -1},
      });

      expect(day.doneCount, 0);
    });
  });
}
