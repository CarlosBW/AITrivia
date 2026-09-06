import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/player_level_service.dart';

/// La curva de nivel existe dos veces: aquí, para pintar la barra de
/// progreso, y en `functions/src/rewards.ts`, que es la que decide el nivel
/// que queda escrito en la cuenta y dispara la recompensa por subir.
///
/// Nada las ataba. Y a diferencia de un precio mal sincronizado, esto no
/// falla de forma visible: la barra diría "te faltan 40 XP" y el servidor
/// subiría de nivel en otro punto, o no subiría. El jugador solo percibe
/// que el juego cuenta mal.
///
/// Igual que `economy_sync_test.dart`, lee la fórmula del servidor en vez
/// de repetirla: la única forma de hacerlo pasar es cambiar los dos lados.
void main() {
  final service = PlayerLevelService.instance;

  final rewardsTs = File('functions/src/rewards.ts').readAsStringSync();

  group('la curva de XP coincide con la del servidor', () {
    test('el primer nivel cuesta lo mismo', () {
      final match = RegExp(r'if \(level <= 1\) return (\d+);')
          .firstMatch(rewardsTs);

      expect(
        match,
        isNotNull,
        reason: 'rewards.ts ya no declara el caso base de '
            '`xpRequiredForLevel`. Si cambió de forma, actualiza este test '
            'para que siga vigilando la curva.',
      );

      expect(service.xpRequiredForLevel(1), int.parse(match!.group(1)!));
    });

    test('la pendiente es la misma', () {
      // `Math.round(100 * (1.18 * (level - 1)))` en el servidor.
      final match = RegExp(r'Math\.round\((\d+) \* \(([\d.]+) \* \(level - 1\)\)\)')
          .firstMatch(rewardsTs);

      expect(
        match,
        isNotNull,
        reason: 'rewards.ts ya no calcula la curva con la misma forma. Si la '
            'reescribiste, actualiza este test.',
      );

      final base = int.parse(match!.group(1)!);
      final factor = double.parse(match.group(2)!);

      // Se recalcula con los números del servidor y se contrasta contra el
      // cliente en todo el rango que un jugador puede alcanzar.
      for (var level = 2; level <= 100; level++) {
        expect(
          service.xpRequiredForLevel(level),
          (base * (factor * (level - 1))).round(),
          reason: 'el nivel $level difiere entre cliente y servidor',
        );
      }
    });
  });

  group('propiedades de la curva', () {
    test('nunca pide menos de 100 XP', () {
      // Es lo que garantiza que el bucle de `levelForXp` en el servidor
      // termine: cada vuelta descuenta al menos esa cantidad.
      for (var level = 1; level <= 200; level++) {
        expect(service.xpRequiredForLevel(level), greaterThanOrEqualTo(100));
      }
    });

    test('no baja al avanzar de nivel', () {
      for (var level = 2; level <= 200; level++) {
        expect(
          service.xpRequiredForLevel(level),
          greaterThanOrEqualTo(service.xpRequiredForLevel(level - 1)),
          reason: 'el nivel $level pide menos que el ${level - 1}',
        );
      }
    });

    test('getLevelInfo es la inversa de la curva', () {
      var acumulado = 0;
      for (var level = 1; level <= 60; level++) {
        expect(service.getLevelInfo(acumulado).level, level);
        acumulado += service.xpRequiredForLevel(level);
        expect(service.getLevelInfo(acumulado - 1).level, level);
      }
    });

    test('el progreso se queda entre 0 y 1', () {
      for (var xp = 0; xp <= 20000; xp += 313) {
        final info = service.getLevelInfo(xp);
        expect(info.progress, inInclusiveRange(0.0, 1.0));
      }
    });

    test('sin XP se empieza en el nivel 1', () {
      expect(service.getLevelInfo(0).level, 1);
    });
  });
}
