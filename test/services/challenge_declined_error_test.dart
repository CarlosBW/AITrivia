import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/match_service.dart';

/// Abrir un reto que el rival ya rechazó mostraba el error de conexión con
/// un "Reintentar" que nunca podía funcionar.
void main() {
  test('reconoce el rechazo que marca el servidor', () {
    final error = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'Challenge was declined.',
      details: {'reason': 'challenge_declined'},
    );

    expect(isChallengeDeclinedError(error), isTrue);
  });

  test('otro fallo del servidor no es un rechazo', () {
    final error = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'Round already closed.',
    );

    expect(isChallengeDeclinedError(error), isFalse);
  });

  test('un fallo de conexión no es un rechazo', () {
    expect(isChallengeDeclinedError(StateError('offline')), isFalse);
  });
}
