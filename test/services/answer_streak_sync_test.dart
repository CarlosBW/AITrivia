import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/answer_streak.dart';

/// Los escalones de la racha existen dos veces: aquí, para lo que la
/// pantalla celebra, y en `ANSWER_STREAK_BONUSES` de `rewards.ts`, que es
/// lo que paga. Si se separan, la app celebra un hito que el servidor no
/// premia.
void main() {
  final source = File('functions/src/rewards.ts').readAsStringSync();

  test('los escalones de la racha cuadran con el servidor', () {
    final block = RegExp(
      r'export const ANSWER_STREAK_BONUSES = \[([\s\S]*?)\] as const;',
    ).firstMatch(source)?.group(1);

    expect(
      block,
      isNotNull,
      reason: 'rewards.ts ya no declara `ANSWER_STREAK_BONUSES`. Si cambió '
          'de forma, actualiza este test.',
    );

    final server = {
      for (final m
          in RegExp(r'streak: (\d+), xp: (\d+)').allMatches(block!))
        int.parse(m.group(1)!): int.parse(m.group(2)!),
    };

    expect(server, isNotEmpty);
    expect(AnswerStreak.bonuses, server);
  });
}
