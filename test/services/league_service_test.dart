import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/league_service.dart';

void main() {
  final service = LeagueService.instance;

  group('LeagueService.getLeagueFromScore', () {
    test('returns bronze for a fresh player', () {
      expect(service.getLeagueFromScore(0).id, 'bronze');
    });

    test('returns the correct league at each boundary', () {
      expect(service.getLeagueFromScore(299).id, 'bronze');
      expect(service.getLeagueFromScore(300).id, 'silver');
      expect(service.getLeagueFromScore(699).id, 'silver');
      expect(service.getLeagueFromScore(700).id, 'gold');
      expect(service.getLeagueFromScore(1199).id, 'gold');
      expect(service.getLeagueFromScore(1200).id, 'diamond');
      expect(service.getLeagueFromScore(1999).id, 'diamond');
      expect(service.getLeagueFromScore(2000).id, 'master');
    });

    test('never returns a league higher than the score supports', () {
      // A very high score should still resolve to the top league, not
      // throw or fall through to a default.
      expect(service.getLeagueFromScore(999999).id, 'master');
    });
  });
}
