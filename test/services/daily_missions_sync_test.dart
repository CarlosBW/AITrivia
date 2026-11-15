import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/daily_missions.dart';

/// Las misiones existen dos veces: aquí, para lo que el Home dibuja, y en
/// `daily_missions.ts`, que es lo que cuenta el progreso y paga el cofre.
/// Si se separan, la app muestra una misión que el servidor no tiene.
void main() {
  final source = File('functions/src/daily_missions.ts').readAsStringSync();

  String block(String pattern) {
    final match = RegExp(pattern).firstMatch(source);
    expect(
      match,
      isNotNull,
      reason: 'daily_missions.ts ya no declara lo que busca `$pattern`. '
          'Si cambió de forma, actualiza este test.',
    );
    return match!.group(1)!;
  }

  test('los grupos de misiones cuadran con el servidor', () {
    final slots = block(
      r'export const MISSION_SLOTS[^=]*= \[([\s\S]*?)\n\];',
    );

    final server = [
      for (final slot in RegExp(r'\[([^\[\]]*)\]').allMatches(slots))
        [
          for (final m in RegExp(
            r'id: "(\w+)", stat: "(\w+)", target: (\d+)',
          ).allMatches(slot.group(1)!))
            '${m.group(1)}|${m.group(2)}|${m.group(3)}',
        ],
    ];

    final app = [
      for (final slot in DailyMissions.slots)
        [for (final m in slot) '${m.id}|${m.stat.name}|${m.target}'],
    ];

    expect(server, isNotEmpty);
    expect(app, server);
  });

  test('cada cuenta se llama igual que en el servidor', () {
    final stats = block(r'export const MISSION_STATS[^=]*= \[([\s\S]*?)\];');
    final server = [
      for (final m in RegExp(r'"(\w+)"').allMatches(stats)) m.group(1)!,
    ];

    expect([for (final s in MissionStat.values) s.name], server);
  });

  test('el cofre y los umbrales cuadran con el servidor', () {
    expect(
      source,
      contains('DAILY_MISSIONS_CHEST = {coins: ${DailyMissions.chestCoins}, '
          'xp: ${DailyMissions.chestXp}}'),
    );
    expect(
      source,
      contains('GREAT_LEVEL_PERCENT = ${DailyMissions.greatLevelPercent / 100}'),
    );
    expect(
      source,
      contains('STREAK_LEVEL_RUN = ${DailyMissions.streakLevelRun}'),
    );
    expect(source, contains('MISSIONS_TIME_ZONE = "America/Lima"'));
  });
}
