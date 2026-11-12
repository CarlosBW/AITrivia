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
  // Los mismos casos que functions/src/weekly_league.test.ts: la pantalla
  // tiene que mostrar el número del que partirá el servidor.
  group('decayedLeagueScore', () {
    const w1 = '2026-11-09';
    const w2 = '2026-11-16';
    const w3 = '2026-11-23';

    test('la misma semana no quita nada', () {
      expect(LeagueService.decayedLeagueScore(2000, w1, w1), 2000);
    });

    test('cada semana que pasa quita un cuarto', () {
      expect(LeagueService.decayedLeagueScore(2000, w1, w2), 1500);
      expect(LeagueService.decayedLeagueScore(2000, w1, w3), 1125);
    });

    test('redondea hacia abajo y nunca baja de cero', () {
      expect(LeagueService.decayedLeagueScore(5, w1, w2), 3);
      expect(LeagueService.decayedLeagueScore(-40, w1, w2), 0);
    });

    test('sin semana registrada no se pierde nada', () {
      expect(LeagueService.decayedLeagueScore(2000, null, w2), 2000);
      expect(LeagueService.decayedLeagueScore(2000, '', w2), 2000);
    });

    test('una semana anterior no quita nada', () {
      expect(LeagueService.decayedLeagueScore(2000, w2, w1), 2000);
    });

    test('cruza el cambio de año', () {
      expect(
        LeagueService.decayedLeagueScore(1000, '2026-12-28', '2027-01-04'),
        750,
      );
    });
  });
}
