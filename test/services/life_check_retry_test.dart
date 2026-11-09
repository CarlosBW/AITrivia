import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/life_check_retry.dart';

/// Al entrar a un nivel se comprueban las vidas en el servidor. Un corte de
/// conexion no es "no tienes vidas": se reintenta solo una vez y, si sigue
/// fallando, se muestra como error de conexion con su boton de reintentar.
void main() {
  FirebaseFunctionsException fnError(String code) =>
      FirebaseFunctionsException(code: code, message: code);

  group('isConnectionFailure', () {
    test('un corte o un tiempo agotado es de conexion', () {
      expect(isConnectionFailure(fnError('unavailable')), isTrue);
      expect(isConnectionFailure(fnError('deadline-exceeded')), isTrue);
      expect(isConnectionFailure(fnError('internal')), isTrue);
      expect(isConnectionFailure(TimeoutException('x')), isTrue);
    });

    test('una respuesta real del servidor no lo es', () {
      expect(isConnectionFailure(fnError('failed-precondition')), isFalse);
      expect(isConnectionFailure(fnError('permission-denied')), isFalse);
    });
  });

  group('withConnectionRetry', () {
    test('si el primer intento se corta, el segundo vale', () async {
      var calls = 0;
      final result = await withConnectionRetry(() async {
        calls++;
        if (calls == 1) throw fnError('unavailable');
        return 'ok';
      }, delay: Duration.zero);
      expect(result, 'ok');
      expect(calls, 2);
    });

    test('si vuelve a cortarse, el error sale', () async {
      var calls = 0;
      await expectLater(
        withConnectionRetry<String>(() async {
          calls++;
          throw fnError('unavailable');
        }, delay: Duration.zero),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(calls, 2);
    });

    test('una respuesta real del servidor no se reintenta', () async {
      var calls = 0;
      await expectLater(
        withConnectionRetry<String>(() async {
          calls++;
          throw fnError('failed-precondition');
        }, delay: Duration.zero),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(calls, 1);
    });
  });
}
