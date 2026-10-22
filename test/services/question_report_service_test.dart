import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/question_report_service.dart';

/// The review list is what the player reports from, so each entry has to
/// carry the right question, the right picked option and the right target.
void main() {
  final questions = [
    {'q': '¿2+2?', 'options': ['3', '4', '5'], 'answerIndex': 1},
    {'q': '¿Capital de Perú?', 'options': ['Lima', 'Cusco'], 'answerIndex': 0},
    {'q': '¿Color del cielo?', 'options': ['Azul', 'Verde'], 'answerIndex': 0},
  ];

  Map<String, dynamic> target(int i, Map<String, dynamic> q) =>
      {'mode': 'solo', 'questionIndex': i};

  group('reviewedQuestions', () {
    test('marca lo que eligió el jugador en cada pregunta', () {
      final review = reviewedQuestions(
        questions: questions,
        answers: [
          {'questionIndex': 0, 'selectedIndex': 2},
          {'questionIndex': 1, 'selectedIndex': 0},
        ],
        targetFor: target,
      );

      expect(review.length, 3);
      expect(review[0].text, '¿2+2?');
      expect(review[0].correctIndex, 1);
      expect(review[0].selectedIndex, 2);
      expect(review[1].selectedIndex, 0);
      expect(review[2].selectedIndex, isNull, reason: 'sin responder');
      expect(review[2].reportTarget, {'mode': 'solo', 'questionIndex': 2});
    });

    test('un tiempo agotado (-1) sale como sin responder', () {
      final review = reviewedQuestions(
        questions: questions,
        answers: [
          {'questionIndex': 0, 'selectedIndex': -1},
        ],
        targetFor: target,
      );
      expect(review[0].selectedIndex, isNull);
    });

    test('con onlyAnswered deja fuera las que no vio', () {
      final review = reviewedQuestions(
        questions: questions,
        answers: [
          {'questionIndex': 2, 'selectedIndex': 1},
        ],
        targetFor: target,
        onlyAnswered: true,
      );
      expect(review.map((q) => q.text), ['¿Color del cielo?']);
      expect(review.single.reportTarget['questionIndex'], 2);
    });

    test('se salta una pregunta mal formada sin perder los índices', () {
      final review = reviewedQuestions(
        questions: [
          {'q': '', 'options': ['a'], 'answerIndex': 0},
          questions[1],
        ],
        answers: const [],
        targetFor: target,
      );
      expect(review.single.text, '¿Capital de Perú?');
      expect(review.single.reportTarget['questionIndex'], 1);
    });
  });
}
