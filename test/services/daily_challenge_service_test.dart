import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trivia_ia_flutter/services/daily_challenge_service.dart';

/// The pure helpers and the on-device run progress are covered here — the
/// rest of the service talks to Firestore. `todayDateId` is the one that matters most: it names
/// the document a day's challenge lives in, and the server refuses a
/// submission whose date id it doesn't consider plausible, so a formatting
/// slip means a player simply can't play that day.
void main() {
  final service = DailyChallengeService.instance;

  group('todayDateId', () {
    test('usa el formato AAAA-MM-DD', () {
      expect(service.todayDateId(DateTime(2026, 8, 22)), '2026-08-22');
    });

    test('rellena mes y día con cero a la izquierda', () {
      expect(service.todayDateId(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('la hora del día no cambia el identificador', () {
      expect(
        service.todayDateId(DateTime(2026, 8, 22, 0, 0, 0)),
        service.todayDateId(DateTime(2026, 8, 22, 23, 59, 59)),
      );
    });

    test('días consecutivos dan identificadores distintos', () {
      expect(
        service.todayDateId(DateTime(2026, 8, 22)),
        isNot(service.todayDateId(DateTime(2026, 8, 23))),
      );
    });

    test('cruza fin de mes y de año', () {
      expect(service.todayDateId(DateTime(2026, 12, 31)), '2026-12-31');
      expect(service.todayDateId(DateTime(2027, 1, 1)), '2027-01-01');
    });

    test('el 29 de febrero de un bisiesto', () {
      expect(service.todayDateId(DateTime(2028, 2, 29)), '2028-02-29');
    });
  });

  group('calculateCoinsEarned', () {
    final perBlock = DailyChallengeService.correctPerCoinBlock;
    final coins = DailyChallengeService.coinsPerBlock;

    test('sin aciertos no paga', () {
      expect(service.calculateCoinsEarned(0), 0);
    });

    test('un bloque incompleto todavía no paga', () {
      expect(service.calculateCoinsEarned(perBlock - 1), 0);
    });

    test('el bloque exacto paga una vez', () {
      expect(service.calculateCoinsEarned(perBlock), coins);
    });

    test('paga por bloque completo, sin fracciones', () {
      expect(service.calculateCoinsEarned(perBlock * 2), coins * 2);
      expect(service.calculateCoinsEarned(perBlock * 2 + 1), coins * 2);
    });

    test('crece de forma monótona', () {
      var previous = 0;
      for (var correct = 0; correct <= perBlock * 4; correct++) {
        final earned = service.calculateCoinsEarned(correct);
        expect(earned, greaterThanOrEqualTo(previous));
        previous = earned;
      }
    });
  });

  // The run's answers used to live only in the screen: leaving mid-run
  // lost them, and coming back after the clock ran out submitted an empty
  // run, a zero for a day already played.
  // The run is resumed from what the server already judged: answers on
  // the device could be lost, and on the server they are final anyway.
  group('retomar el reto desde el servidor', () {
    DailyChallengeSession read(Map<String, dynamic> data) =>
        DailyChallengeSession.fromData(
          '2026-10-21',
          data,
          defaultDurationSeconds: 120,
        );

    test('recupera las respuestas y cuántas fueron correctas', () {
      final session = read({
        'questions': [
          {'q': 'a', 'options': ['x', 'y']},
          {'q': 'b', 'options': ['x', 'y']},
          {'q': 'c', 'options': ['x', 'y']},
        ],
        'answers': {'2': 1, '0': 0},
        'results': {
          '0': {'correct': true, 'correctIndex': 0},
          '2': {'correct': false, 'correctIndex': 0},
        },
      });

      expect(session.answers, [
        {'questionIndex': 0, 'selectedIndex': 0},
        {'questionIndex': 2, 'selectedIndex': 1},
      ]);
      expect(session.correct, 1);
      expect(session.correctIndexByQuestion, {0: 0, 2: 0});
    });

    test('sin respuestas empieza de cero', () {
      final session = read({'questions': const []});
      expect(session.answers, isEmpty);
      expect(session.correct, 0);
      expect(session.durationSeconds, 120);
    });
  });

  group('recordatorio diario', () {
    test('sin jugar hoy, el recordatorio es para hoy', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await service.playedTodayOnThisDevice(), isFalse);
    });

    test('jugado hoy, el recordatorio pasa a mañana', () async {
      SharedPreferences.setMockInitialValues(
        {'daily_last_played_date': service.todayDateId()},
      );
      expect(await service.playedTodayOnThisDevice(), isTrue);
    });

    test('jugado ayer no cuenta', () async {
      final yesterday = service.todayDateId(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      SharedPreferences.setMockInitialValues(
        {'daily_last_played_date': yesterday},
      );
      expect(await service.playedTodayOnThisDevice(), isFalse);
    });
  });
}
