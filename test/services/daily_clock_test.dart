import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/daily_clock.dart';

/// El reloj del reto diario se corrige con el tiempo que informa el
/// servidor en cada respuesta: la hora del celular puede estar mal y el
/// reloj de la app se detiene mientras espera cada veredicto.
void main() {
  test('sin dato del servidor el reloj sigue como estaba', () {
    expect(
      resyncedSecondsLeft(current: 40, serverRemainingMs: null, durationSeconds: 120),
      40,
    );
  });

  test('toma el tiempo del servidor, redondeando hacia arriba', () {
    expect(
      resyncedSecondsLeft(current: 40, serverRemainingMs: 20500, durationSeconds: 120),
      21,
    );
    expect(
      resyncedSecondsLeft(current: 10, serverRemainingMs: 30000, durationSeconds: 120),
      30,
    );
  });

  test('se queda dentro de la duración del reto', () {
    expect(
      resyncedSecondsLeft(current: 40, serverRemainingMs: 0, durationSeconds: 120),
      0,
    );
    expect(
      resyncedSecondsLeft(current: 40, serverRemainingMs: 500000, durationSeconds: 120),
      120,
    );
    expect(
      resyncedSecondsLeft(current: 40, serverRemainingMs: -5, durationSeconds: 120),
      0,
    );
  });
}
