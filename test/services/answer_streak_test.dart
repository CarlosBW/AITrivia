import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/answer_streak.dart';

void main() {
  group('currentAnswerStreak', () {
    test('sin respuestas no hay racha', () {
      expect(currentAnswerStreak(const []), 0);
      expect(currentAnswerStreak(const [null, null, null]), 0);
    });

    test('cuenta los aciertos seguidos hasta la última respuesta', () {
      expect(currentAnswerStreak(const [true, true, true, null, null]), 3);
    });

    test('un fallo la corta, y vuelve a empezar después', () {
      expect(currentAnswerStreak(const [true, true, false, null]), 0);
      expect(currentAnswerStreak(const [true, true, false, true, true]), 2);
    });

    // Al retomar un nivel a medias, la racha es la que traía.
    test('se lee de los veredictos, no de cuántas veces se contó', () {
      expect(
        currentAnswerStreak(const [false, true, true, true, true, null]),
        4,
      );
    });

    // Una pregunta sin veredicto en medio no se da por acertada.
    test('una pregunta sin responder en medio corta la racha', () {
      expect(currentAnswerStreak(const [true, true, null, true]), 1);
    });
  });

  group('AnswerStreak', () {
    test('un solo acierto todavía no es una racha que mostrar', () {
      expect(AnswerStreak.shownFrom, greaterThan(1));
    });

    test('solo los escalones que pagan son hitos', () {
      for (final step in AnswerStreak.bonuses.keys) {
        expect(AnswerStreak.isMilestone(step), isTrue);
        expect(AnswerStreak.isMilestone(step + 1),
            AnswerStreak.bonuses.containsKey(step + 1));
      }
      expect(AnswerStreak.isMilestone(0), isFalse);
      expect(AnswerStreak.isMilestone(2), isFalse);
    });

    test('la racha se calienta un grado por escalón alcanzado', () {
      expect(AnswerStreak.heat(2), 0);
      expect(AnswerStreak.heat(3), 1);
      expect(AnswerStreak.heat(6), 2);
      expect(AnswerStreak.heat(99), AnswerStreak.bonuses.length);
    });
  });
}
