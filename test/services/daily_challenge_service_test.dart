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
  group('respuestas guardadas en el teléfono', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final answers = [
      {'questionIndex': 0, 'selectedIndex': 2},
      {'questionIndex': 3, 'selectedIndex': 1},
    ];

    test('se recuperan al volver', () async {
      await service.saveLocalProgress(
        uid: 'u1', dateId: '2026-10-21', answers: answers, correct: 1,
      );
      final saved =
          await service.loadLocalProgress(uid: 'u1', dateId: '2026-10-21');

      expect(saved, isNotNull);
      expect(saved!.answers, answers);
      expect(saved.correct, 1);
    });

    test('son de un día y una cuenta', () async {
      await service.saveLocalProgress(
        uid: 'u1', dateId: '2026-10-21', answers: answers, correct: 1,
      );

      expect(
        await service.loadLocalProgress(uid: 'u1', dateId: '2026-10-22'),
        isNull,
      );
      expect(
        await service.loadLocalProgress(uid: 'u2', dateId: '2026-10-21'),
        isNull,
      );
    });

    test('sin nada guardado no hay nada que recuperar', () async {
      expect(
        await service.loadLocalProgress(uid: 'u1', dateId: '2026-10-21'),
        isNull,
      );
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
