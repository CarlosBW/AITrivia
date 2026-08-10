import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/player_level_service.dart';

void main() {
  final service = PlayerLevelService.instance;

  group('PlayerLevelService.xpRequiredForLevel', () {
    test('costs 100 XP for the first level', () {
      expect(service.xpRequiredForLevel(1), 100);
    });

    test('grows with each level instead of staying flat', () {
      expect(service.xpRequiredForLevel(2), 118);
      expect(service.xpRequiredForLevel(3), 236);
      expect(service.xpRequiredForLevel(4), 354);
      expect(service.xpRequiredForLevel(5), 472);
    });
  });

  group('PlayerLevelService.getLevelInfo', () {
    test('starts a new player at level 1 with an empty bar', () {
      final info = service.getLevelInfo(0);

      expect(info.level, 1);
      expect(info.currentLevelXp, 0);
      expect(info.xpRequired, 100);
      expect(info.progress, 0);
    });

    // The level-complete screen shows this card, and it used to render it
    // before `submitSoloLevelResult` came back — so it read the total as 0
    // and told every player they were level 1 on 0/100 while the header
    // above it showed their real level.
    test('places 1150 XP at level 5, not level 1', () {
      final info = service.getLevelInfo(1150);

      expect(info.level, 5);
      expect(info.currentLevelXp, 342);
      expect(info.xpRequired, 472);
    });

    test('levels up exactly on the threshold', () {
      expect(service.getLevelInfo(99).level, 1);
      expect(service.getLevelInfo(100).level, 2);
      expect(service.getLevelInfo(217).level, 2);
      expect(service.getLevelInfo(218).level, 3);
    });

    test('reports progress as the fraction of the current level', () {
      final info = service.getLevelInfo(50);

      expect(info.level, 1);
      expect(info.progress, closeTo(0.5, 0.001));
    });

    test('never reports progress outside 0..1', () {
      for (final xp in [0, 1, 99, 100, 500, 1150, 99999]) {
        final info = service.getLevelInfo(xp);
        expect(info.progress, inInclusiveRange(0.0, 1.0), reason: 'xp $xp');
      }
    });
  });
}
