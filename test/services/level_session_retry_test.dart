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
