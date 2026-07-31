import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/life_service.dart';

void main() {
  final service = LifeService.instance;

  group('LifeService.calculateLocalLifeState', () {
    test('regenerates one unit after exactly one regen interval', () {
      // calculateLocalLifeState always measures against the real wall
      // clock (Timestamp.now()) — lastTick must be relative to
      // DateTime.now(), not a fixed date, or the elapsed time is wrong by
      // however far "now" is from that fixed date.
      final lastTick = DateTime.now().subtract(
        const Duration(seconds: LifeService.defaultRegenSeconds),
      );

      final state = service.calculateLocalLifeState({
        'lifeUnits': 6,
        'maxLifeUnits': LifeService.defaultMaxLifeUnits,
        'lifeRegenSeconds': LifeService.defaultRegenSeconds,
        'lastLifeTickAt': Timestamp.fromDate(lastTick),
      });

      expect(state['lifeUnits'], 7);
    });

    test('regenerates multiple units after multiple intervals', () {
      final lastTick = DateTime.now().subtract(
        const Duration(seconds: LifeService.defaultRegenSeconds * 2 + 10),
      );

      final state = service.calculateLocalLifeState({
        'lifeUnits': 4,
        'maxLifeUnits': LifeService.defaultMaxLifeUnits,
        'lifeRegenSeconds': LifeService.defaultRegenSeconds,
        'lastLifeTickAt': Timestamp.fromDate(lastTick),
      });

      expect(state['lifeUnits'], 6);
    });

    test('never regenerates past maxLifeUnits', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final lastTick = now.subtract(const Duration(days: 1));

      final state = service.calculateLocalLifeState({
        'lifeUnits': 9,
        'maxLifeUnits': LifeService.defaultMaxLifeUnits,
        'lifeRegenSeconds': LifeService.defaultRegenSeconds,
        'lastLifeTickAt': Timestamp.fromDate(lastTick),
      });

      expect(state['lifeUnits'], LifeService.defaultMaxLifeUnits);
    });

    test('does not touch lifeUnits when already full', () {
      final state = service.calculateLocalLifeState({
        'lifeUnits': LifeService.defaultMaxLifeUnits,
        'maxLifeUnits': LifeService.defaultMaxLifeUnits,
        'lifeRegenSeconds': LifeService.defaultRegenSeconds,
        'lastLifeTickAt': Timestamp.now(),
      });

      expect(state['lifeUnits'], LifeService.defaultMaxLifeUnits);
      expect(state['secondsToNextHalfLife'], isNull);
    });
  });

  group('LifeService.formatLives', () {
    test('formats whole and half lives', () {
      expect(service.formatLives(10), '5');
      expect(service.formatLives(9), '4.5');
      expect(service.formatLives(1), '0.5');
      expect(service.formatLives(0), '0');
    });
  });

  group('LifeService.unitsToLives', () {
    test('converts units to lives', () {
      expect(service.unitsToLives(10), 5.0);
      expect(service.unitsToLives(1), 0.5);
    });
  });

  // Regression guard: these constants define real game balance
  // (regen speed, level cost, new-player grace window). A change here is
  // a deliberate design decision, not an accidental edit — this test
  // exists so any such change shows up as an intentional diff.
  group('LifeService constants', () {
    test('match the documented game balance', () {
      expect(LifeService.defaultMaxLifeUnits, 10);
      expect(LifeService.defaultRegenSeconds, 150);
      expect(LifeService.unitsPerLife, 2);
      expect(LifeService.levelEntryCostUnits, 2);
      expect(LifeService.wrongAnswerCostUnits, 1);
      expect(LifeService.newPlayerGraceLevels, 2);
    });
  });
}
