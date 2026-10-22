import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/l10n/user_facing_error.dart';

// Screens used to print `e.toString()`, so a player could read
// "[firebase_functions/failed-precondition] Round already closed." or a
// raw Firestore error, in English whatever their language.
void main() {
  final es = lookupAppLocalizations(const Locale('es'));

  FirebaseFunctionsException callableError(
    String code,
    String message, {
    Object? details,
  }) {
    return FirebaseFunctionsException(
      code: code,
      message: message,
      details: details,
    );
  }

  group('userFacingError', () {
    test('muestra el mensaje que el servidor ya tradujo', () {
      final e = callableError(
        'failed-precondition',
        'No tienes suficientes monedas.',
        details: {'localized': true},
      );
      expect(userFacingError(es, e), 'No tienes suficientes monedas.');
    });

    test('no muestra un mensaje técnico del servidor', () {
      final e = callableError('failed-precondition', 'Round already closed.');
      expect(userFacingError(es, e), es.commonGenericError);
    });

    test('usa el texto propio de la acción cuando se le da', () {
      final e = callableError('not-found', 'Code not found.');
      expect(
        userFacingError(es, e, fallback: es.serviceRoomNotFound),
        es.serviceRoomNotFound,
      );
    });

    test('un servidor que no responde es un problema de conexión', () {
      expect(
        userFacingError(es, callableError('unavailable', 'unavailable')),
        es.commonConnectionError,
      );
      expect(
        userFacingError(es, TimeoutException('slow')),
        es.commonConnectionError,
      );
      expect(
        userFacingError(
          es,
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        es.commonConnectionError,
      );
    });

    test('muestra sin el prefijo el mensaje que ya tradujo un servicio', () {
      expect(
        userFacingError(es, Exception(es.serviceAlreadyFriends)),
        es.serviceAlreadyFriends,
      );
    });

    test('cualquier otro error es genérico', () {
      expect(userFacingError(es, StateError('boom')), es.commonGenericError);
      expect(
        userFacingError(
          es,
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        es.commonGenericError,
      );
    });
  });
}
