import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/connectivity_service.dart';
import 'package:trivia_ia_flutter/services/practice_pack.dart';

Map<String, dynamic> q(int i) => {
      'categoryId': 'geo',
      'q': 'Pregunta $i',
      'options': ['a', 'b', 'c', 'd'],
      'answerIndex': i % 4,
    };

void main() {
  final now = DateTime(2026, 11, 19, 12);

  group('parsePracticeQuestions', () {
    test('se queda con las preguntas que se pueden jugar', () {
      final parsed = parsePracticeQuestions([
        q(0),
        {'q': '', 'options': ['a', 'b'], 'answerIndex': 0},
        {'q': 'Sin opciones', 'options': ['a'], 'answerIndex': 0},
        {'q': 'Respuesta fuera', 'options': ['a', 'b'], 'answerIndex': 2},
        'basura',
        q(1),
      ]);

      expect(parsed.map((e) => e['q']), ['Pregunta 0', 'Pregunta 1']);
    });

    test('lo que no es una lista no trae preguntas', () {
      expect(parsePracticeQuestions(null), isEmpty);
      expect(parsePracticeQuestions({'questions': []}), isEmpty);
    });
  });

  group('guardar y leer el paquete', () {
    test('lo guardado se lee igual', () {
      final pack = PracticePack(questions: [q(0), q(1)], fetchedAt: now);
      final read = decodePracticePack(encodePracticePack(pack));

      expect(read!.questions, pack.questions);
      expect(read.fetchedAt, now);
    });

    test('nada guardado, o algo ilegible, es no tener paquete', () {
      expect(decodePracticePack(null), isNull);
      expect(decodePracticePack(''), isNull);
      expect(decodePracticePack('{no es json'), isNull);
      expect(decodePracticePack('{"fetchedAt": 1, "questions": []}'), isNull);
    });
  });

  group('shouldRefreshPracticePack', () {
    test('sin paquete hay que pedir uno', () {
      expect(shouldRefreshPracticePack(null, now), isTrue);
    });

    test('uno de hoy sirve; uno de ayer se renueva', () {
      expect(
        shouldRefreshPracticePack(
            now.subtract(const Duration(hours: 3)), now),
        isFalse,
      );
      expect(
        shouldRefreshPracticePack(
            now.subtract(const Duration(hours: 25)), now),
        isTrue,
      );
    });
  });

  group('practiceRound', () {
    final pack = [for (var i = 0; i < 25; i++) q(i)];

    test('cada ronda sigue donde quedó la anterior', () {
      final first = practiceRound(pack, 0);
      expect(first.questions.first['q'], 'Pregunta 0');
      expect(first.questions.length, practiceRoundSize);
      expect(first.nextCursor, 10);

      final second = practiceRound(pack, first.nextCursor);
      expect(second.questions.first['q'], 'Pregunta 10');
    });

    test('al llegar al final vuelve a empezar sin repetir en la ronda', () {
      final round = practiceRound(pack, 20);
      expect(
        round.questions.map((e) => e['q']),
        [
          for (final i in [20, 21, 22, 23, 24, 0, 1, 2, 3, 4]) 'Pregunta $i',
        ],
      );
      expect(round.nextCursor, 5);
    });

    test('un paquete corto da una ronda corta, no preguntas repetidas', () {
      final round = practiceRound(pack.sublist(0, 4), 2);
      expect(round.questions.length, 4);
      expect(round.questions.map((e) => e['q']).toSet().length, 4);
    });

    test('un cursor viejo o roto no rompe nada', () {
      expect(practiceRound(pack, 999).questions.length, practiceRoundSize);
      expect(practiceRound(pack, -3).questions.first['q'], 'Pregunta 0');
      expect(practiceRound(const [], 0).questions, isEmpty);
    });
  });

  group('isOffline', () {
    test('sin ninguna red está sin conexión', () {
      expect(isOffline(const [ConnectivityResult.none]), isTrue);
      expect(isOffline(const []), isTrue);
    });

    test('con wifi o datos no', () {
      expect(isOffline(const [ConnectivityResult.wifi]), isFalse);
      expect(
        isOffline(const [ConnectivityResult.none, ConnectivityResult.mobile]),
        isFalse,
      );
    });
  });
}
