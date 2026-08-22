import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/life_service.dart';

/// The life balance lives in three places that have to agree:
///
///  - `LifeService` (what the app shows and spends),
///  - `DEFAULT_*` in `functions/src/index.ts` (what the server enforces),
///  - `newUserEconomyFieldsValid()` in `firestore.rules` (what a brand-new
///    account is allowed to be created with).
///
/// Nothing but discipline kept them in step, and discipline already failed
/// once: raising lives from 5 to 10 moved the first two and left the rules
/// pinned to the old numbers, so every sign-up was denied in production —
/// and the error surfaced on the username screen, because the username is
/// claimed in the same transaction that creates the user document.
///
/// These tests read the other two files rather than restating their values,
/// so the only way to make them pass is to actually change all three.
void main() {
  final indexTs = File('functions/src/index.ts').readAsStringSync();
  final rules = File('firestore.rules').readAsStringSync();

  /// Reads `const NAME = 123;` out of index.ts.
  int serverConstant(String name) {
    final match = RegExp('^const $name = (-?\\d+);', multiLine: true)
        .firstMatch(indexTs);

    expect(
      match,
      isNotNull,
      reason: 'functions/src/index.ts no declara `const $name`. Si lo '
          'renombraste, actualiza este test para que siga vigilando.',
    );

    return int.parse(match!.group(1)!);
  }

  /// Reads the value `firestore.rules` pins a new account's [field] to.
  int rulesConstant(String field) {
    final match = RegExp(
      r'request\.resource\.data\.' + field + r' == (-?\d+)',
    ).firstMatch(rules);

    expect(
      match,
      isNotNull,
      reason: 'firestore.rules ya no fija `$field` al crear la cuenta. Si '
          'se quitó a propósito, actualiza este test.',
    );

    return int.parse(match!.group(1)!);
  }

  group('el balance de vidas coincide entre cliente y servidor', () {
    test('unidades máximas', () {
      expect(
        serverConstant('DEFAULT_MAX_LIFE_UNITS'),
        LifeService.defaultMaxLifeUnits,
      );
    });

    test('segundos de regeneración por unidad', () {
      expect(
        serverConstant('DEFAULT_LIFE_REGEN_SECONDS'),
        LifeService.defaultRegenSeconds,
      );
    });

    test('unidades por vida', () {
      expect(serverConstant('UNITS_PER_LIFE'), LifeService.unitsPerLife);
    });

    test('costo de entrar a un nivel', () {
      expect(
        serverConstant('LEVEL_ENTRY_COST_UNITS'),
        LifeService.levelEntryCostUnits,
      );
    });

    test('costo de una respuesta incorrecta', () {
      expect(
        serverConstant('WRONG_ANSWER_COST_UNITS'),
        LifeService.wrongAnswerCostUnits,
      );
    });

    test('niveles de gracia para jugadores nuevos', () {
      expect(
        serverConstant('NEW_PLAYER_GRACE_LEVELS'),
        LifeService.newPlayerGraceLevels,
      );
    });
  });

  group('firestore.rules deja crear la cuenta con ese balance', () {
    // Este es el que fallo en produccion: las reglas rechazan el `create`
    // entero si el valor no coincide, y con el se cae el reclamo del
    // nombre de usuario, que viaja en la misma transaccion.
    test('lifeUnits inicial', () {
      expect(rulesConstant('lifeUnits'), LifeService.defaultMaxLifeUnits);
    });

    test('maxLifeUnits inicial', () {
      expect(rulesConstant('maxLifeUnits'), LifeService.defaultMaxLifeUnits);
    });

    test('lifeRegenSeconds inicial', () {
      expect(rulesConstant('lifeRegenSeconds'), LifeService.defaultRegenSeconds);
    });
  });

  group('el balance se mantiene coherente consigo mismo', () {
    test('una vida son unidades enteras', () {
      expect(LifeService.defaultMaxLifeUnits % LifeService.unitsPerLife, 0);
    });

    test('entrar cuesta una vida completa', () {
      expect(LifeService.levelEntryCostUnits, LifeService.unitsPerLife);
    });

    test('fallar cuesta menos que entrar', () {
      expect(
        LifeService.wrongAnswerCostUnits,
        lessThan(LifeService.levelEntryCostUnits),
      );
    });
  });
}
