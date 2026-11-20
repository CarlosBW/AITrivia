import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/answer_reveal.dart';

void main() {
  const base = Duration(seconds: 1);

  test('una respuesta correcta sigue de largo con la pausa de siempre', () {
    expect(answerRevealPause(correct: true, base: base), base);
  });

  test('una incorrecta se queda más, para ver cuál era la correcta', () {
    expect(
      answerRevealPause(correct: false, base: base),
      base + wrongAnswerExtraReveal,
    );
  });

  test('el tiempo extra alcanza para leer, sin frenar la partida', () {
    expect(wrongAnswerExtraReveal.inMilliseconds, inInclusiveRange(1000, 2000));
  });
}
