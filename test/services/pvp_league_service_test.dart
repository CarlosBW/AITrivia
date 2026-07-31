import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/pvp_league_service.dart';

void main() {
  final service = PvpLeagueService.instance;

  group('PvpLeagueService.leagueForRating', () {
    test('returns silver for the default starting rating', () {
      expect(service.leagueForRating(PvpLeagueService.defaultRating).id,
          'silver');
    });

    test('returns the correct league at each boundary', () {
      expect(service.leagueForRating(0).id, 'bronze');
      expect(service.leagueForRating(999).id, 'bronze');
      expect(service.leagueForRating(1000).id, 'silver');
      expect(service.leagueForRating(1199).id, 'silver');
      expect(service.leagueForRating(1200).id, 'gold');
      expect(service.leagueForRating(1399).id, 'gold');
      expect(service.leagueForRating(1400).id, 'platinum');
      expect(service.leagueForRating(1599).id, 'platinum');
      expect(service.leagueForRating(1600).id, 'diamond');
      expect(service.leagueForRating(1899).id, 'diamond');
      expect(service.leagueForRating(1900).id, 'master');
    });

    test('clamps out-of-range ratings to the nearest league', () {
      expect(service.leagueForRating(-100).id, 'bronze');
      expect(service.leagueForRating(999999).id, 'master');
    });
  });

  group('PvpLeagueService.leagueById', () {
    test('resolves every league id used elsewhere in the app', () {
      for (final id in [
        'bronze',
        'silver',
        'gold',
        'platinum',
        'diamond',
        'master',
      ]) {
        expect(service.leagueById(id).id, id);
      }
    });

    test('falls back to bronze for an unknown id', () {
      expect(service.leagueById('not_a_real_league').id, 'bronze');
    });
  });

  group('PvpLeagueInfo.contains', () {
    test('is inclusive on both ends', () {
      final league = PvpLeagueService.leagues.first; // bronze: 0-999
      expect(league.contains(0), isTrue);
      expect(league.contains(999), isTrue);
      expect(league.contains(1000), isFalse);
    });
  });
}
