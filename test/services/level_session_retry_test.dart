import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/level_session_retry.dart';

/// Preparar un nivel nuevo de un tema IA puede tardar lo que tarda la IA en
/// generarlo. Si la espera se corta porque la app pasó a segundo plano o
/// se agotó el tiempo, el servidor sigue y guarda las preguntas: se vuelve
/// a pedir solo, sin mostrar el error de conexión.
void main() {
  test('reintenta si la app pasó a segundo plano durante la espera', () {
    expect(
      shouldRetryLevelSession(
        errorCode: 'unavailable',
        wentToBackground: true,
        retriesSoFar: 0,
      ),
      isTrue,
    );
  });

  test('reintenta si se agotó el tiempo de espera', () {
    expect(
      shouldRetryLevelSession(
        errorCode: 'deadline-exceeded',
        wentToBackground: false,
        retriesSoFar: 0,
      ),
      isTrue,
    );
  });

  // Que la app pasara a segundo plano explica una conexión cortada, no que
  // el nivel esté bloqueado o se haya acabado el cupo del día: esos errores
  // vuelven igual en cada intento, y cada intento puede gastar generación.
  test('tras segundo plano, un error del servidor se muestra igual', () {
    for (final code in ['failed-precondition', 'resource-exhausted',
        'permission-denied', 'invalid-argument']) {
      expect(
        shouldRetryLevelSession(
          errorCode: code,
          wentToBackground: true,
          retriesSoFar: 0,
        ),
        isFalse,
        reason: code,
      );
    }
  });

  test('un error del servidor se muestra, no se reintenta', () {
    expect(
      shouldRetryLevelSession(
        errorCode: 'failed-precondition',
        wentToBackground: false,
        retriesSoFar: 0,
      ),
      isFalse,
    );
  });

  test('no reintenta sin fin', () {
    expect(
      shouldRetryLevelSession(
        errorCode: 'deadline-exceeded',
        wentToBackground: true,
        retriesSoFar: maxLevelSessionRetries,
      ),
      isFalse,
    );
  });
}
