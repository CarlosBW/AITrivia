import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/match_rules.dart';

void main() {
  final now = DateTime(2026, 8, 22, 12, 0, 0);

  group('safeInt', () {
    test('acepta enteros y decimales', () {
      expect(safeInt(7, 0), 7);
      expect(safeInt(7.9, 0), 7);
    });

    test('rescata números guardados como texto', () {
      expect(safeInt('1200', 0), 1200);
    });

    test('cae al valor por defecto ante basura o ausencia', () {
      expect(safeInt(null, 1000), 1000);
      expect(safeInt('', 1000), 1000);
      expect(safeInt('abc', 1000), 1000);
      expect(safeInt(<String, int>{}, 1000), 1000);
    });
  });

  group('isHeartbeatRecent', () {
    test('un latido dentro de la ventana es reciente', () {
      expect(
        isHeartbeatRecent(
          lastSeenAt: now.subtract(const Duration(seconds: 29)),
          now: now,
        ),
        isTrue,
      );
    });

    test('pasada la ventana deja de serlo', () {
      expect(
        isHeartbeatRecent(
          lastSeenAt: now.subtract(const Duration(seconds: 31)),
          now: now,
        ),
        isFalse,
      );
    });

    test('el borde exacto todavía cuenta', () {
      expect(
        isHeartbeatRecent(
          lastSeenAt: now.subtract(liveQueueMaxAge),
          now: now,
        ),
        isTrue,
      );
    });

    // Deliberado: una entrada escrita antes de que existiera el latido no
    // debe leerse como caducada y desaparecer de la cola.
    test('sin latido se considera reciente', () {
      expect(isHeartbeatRecent(lastSeenAt: null, now: now), isTrue);
    });
  });

  group('isLiveQueueEntryValid', () {
    bool valid({
      String status = 'searching',
      Object? matchId,
      Duration age = const Duration(seconds: 1),
    }) {
      return isLiveQueueEntryValid(
        status: status,
        matchId: matchId,
        lastSeenAt: now.subtract(age),
        now: now,
      );
    }

    test('buscando, sin pareja y con latido fresco', () {
      expect(valid(), isTrue);
    });

    test('detenida no cuenta', () {
      expect(valid(status: 'stopped'), isFalse);
      expect(valid(status: ''), isFalse);
    });

    test('ya emparejada no cuenta', () {
      expect(valid(matchId: 'match_1'), isFalse);
    });

    // El caso que este chequeo existe para atrapar: alguien cerro la app
    // mientras buscaba y dejo la entrada diciendo que sigue en cola.
    test('buscando pero con el latido caducado no cuenta', () {
      expect(valid(age: const Duration(minutes: 5)), isFalse);
    });
  });

  group('activeCooldownUntil', () {
    test('devuelve el castigo que aún no vence', () {
      final until = now.add(const Duration(minutes: 3));
      expect(activeCooldownUntil(until, now), until);
    });

    test('descarta el ya vencido', () {
      expect(
        activeCooldownUntil(now.subtract(const Duration(seconds: 1)), now),
        isNull,
      );
    });

    test('el instante exacto ya no castiga', () {
      expect(activeCooldownUntil(now, now), isNull);
    });

    test('sin castigo no hay nada que devolver', () {
      expect(activeCooldownUntil(null, now), isNull);
    });
  });

  group('formatCooldownRemaining', () {
    test('bajo un minuto omite los minutos', () {
      expect(formatCooldownRemaining(const Duration(seconds: 45)), '45s');
    });

    test('con minutos rellena los segundos a dos dígitos', () {
      expect(
        formatCooldownRemaining(const Duration(minutes: 2, seconds: 5)),
        '2m 05s',
      );
    });

    test('un minuto exacto', () {
      expect(formatCooldownRemaining(const Duration(minutes: 1)), '1m 00s');
    });

    test('una duración negativa no se muestra en negativo', () {
      expect(formatCooldownRemaining(const Duration(seconds: -30)), '0s');
    });
  });

  group('parseAnswerMap', () {
    test('convierte las claves de texto a índices', () {
      expect(parseAnswerMap({'0': 2, '1': 3}), {0: 2, 1: 3});
    });

    test('acepta números almacenados como decimales', () {
      expect(parseAnswerMap({'0': 2.0}), {0: 2});
    });

    test('conserva el -1 con el que se marca un timeout', () {
      expect(parseAnswerMap({'4': -1}), {4: -1});
    });

    // Una entrada corrupta cuesta una pregunta, no la partida entera.
    test('descarta entradas ilegibles y deja el resto', () {
      expect(
        parseAnswerMap({'x': 1, '-2': 1, '1': 'dos', '0': 3}),
        {0: 3},
      );
    });

    test('tolera un valor que no es mapa', () {
      expect(parseAnswerMap(null), isEmpty);
      expect(parseAnswerMap('nope'), isEmpty);
      expect(parseAnswerMap(<String, dynamic>{}), isEmpty);
    });
  });
}
