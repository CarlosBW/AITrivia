import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/l10n/season_labels.dart';

// Season and week ids are storage keys ("pvp_2026_10", "2026-10-19") and
// used to be printed as they were.
void main() {
  final es = lookupAppLocalizations(const Locale('es'));
  final en = lookupAppLocalizations(const Locale('en'));

  // The app gets these from flutter_localizations; a test has to load them.
  setUpAll(() async {
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });

  group('pvpSeasonName', () {
    test('nombra el mes de la temporada', () {
      expect(es.pvpSeasonName('pvp_2026_10'), 'Octubre de 2026');
      expect(en.pvpSeasonName('pvp_2026_10'), 'October 2026');
    });

    test('deja tal cual un id que no reconoce', () {
      expect(es.pvpSeasonName('temporada_rara'), 'temporada_rara');
    });
  });

  group('weekLabel', () {
    test('nombra la semana por su lunes', () {
      expect(es.weekLabel('2026-10-19'), 'Semana del 19 oct 2026');
      expect(en.weekLabel('2026-10-19'), 'Week of Oct 19, 2026');
    });

    test('deja tal cual un id que no reconoce', () {
      expect(es.weekLabel('2026-W42'), '2026-W42');
    });
  });

  group('difficultyLabel', () {
    test('usa el nombre de la dificultad, no su número', () {
      expect(es.difficultyLabel(1), 'Fácil');
      expect(es.difficultyLabel(2), 'Media');
      expect(es.difficultyLabel(3), 'Difícil');
      expect(en.difficultyLabel(2), en.friendChallengeDiffMedium);
    });
  });
}
