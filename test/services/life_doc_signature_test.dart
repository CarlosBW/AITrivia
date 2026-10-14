import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/life_service.dart';

/// Home loaded the lives once and then only counted regeneration on its
/// own, so lives spent in a level played from another tab never reached
/// it: the play screen said 5.5 / 10 and Home, behind it, kept ten full
/// hearts. Home already listens to the user doc, where the server writes
/// every life it takes; this is what lets it tell a snapshot that moved
/// the lives from the many that only moved coins or XP.
void main() {
  final tick = Timestamp.fromMillisecondsSinceEpoch(1760000000000);

  Map<String, dynamic> userDoc({int lifeUnits = 20, Timestamp? lastTick}) => {
        'lifeUnits': lifeUnits,
        'maxLifeUnits': 20,
        'lifeRegenSeconds': 90,
        'lastLifeTickAt': lastTick ?? tick,
        'coins': 100,
        'xp': 28,
      };

  group('LifeService.lifeFieldsSignature', () {
    test('changes when the server takes a life', () {
      expect(
        LifeService.lifeFieldsSignature(userDoc(lifeUnits: 11)),
        isNot(LifeService.lifeFieldsSignature(userDoc(lifeUnits: 20))),
      );
    });

    test('changes when only the regeneration clock moves', () {
      final later = Timestamp.fromMillisecondsSinceEpoch(1760000090000);

      expect(
        LifeService.lifeFieldsSignature(userDoc(lifeUnits: 11, lastTick: later)),
        isNot(LifeService.lifeFieldsSignature(userDoc(lifeUnits: 11))),
      );
    });

    test('stays the same when something else in the doc changes', () {
      final earned = userDoc(lifeUnits: 11)
        ..['coins'] = 250
        ..['xp'] = 60;

      expect(
        LifeService.lifeFieldsSignature(earned),
        LifeService.lifeFieldsSignature(userDoc(lifeUnits: 11)),
      );
    });

    test('a doc with no life fields reads as one, not as a crash', () {
      expect(
        LifeService.lifeFieldsSignature(const {'coins': 5}),
        LifeService.lifeFieldsSignature(const {'xp': 9}),
      );
    });
  });

  test('the lives a spent doc shows are the ones the server left', () {
    // Lo que Inicio pinta al recibir el doc: 11 unidades son 5.5 vidas.
    final state = LifeService.instance.calculateLocalLifeState(
      userDoc(lifeUnits: 11, lastTick: Timestamp.now()),
    );

    expect(state['lifeUnits'], 11);
    expect(LifeService.instance.formatLives(state['lifeUnits'] as int), '5.5');
  });
}
