import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/l10n/league_names.dart';

// League names came straight from the services and the server, in English,
// so a Spanish-speaking player read "Liga Silver".
void main() {
  final es = lookupAppLocalizations(const Locale('es'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('leagueName', () {
    test('traduce cada liga por su id', () {
      expect(
        ['bronze', 'silver', 'gold', 'platinum', 'diamond', 'master']
            .map(es.leagueName)
            .toList(),
        ['Bronce', 'Plata', 'Oro', 'Platino', 'Diamante', 'Maestro'],
      );
    });

    test('entiende el nombre en inglés que guarda el servidor', () {
      expect(es.leagueName('Silver'), 'Plata');
      expect(en.leagueName('Silver'), 'Silver');
    });

    test('conserva el tramo de Maestro', () {
      expect(es.leagueName('Master III'), 'Maestro III');
      expect(en.leagueName('Master II'), 'Master II');
    });

    test('deja tal cual un nombre que no conoce', () {
      expect(es.leagueName('Liga desconocida'), 'Liga desconocida');
      expect(es.leagueName(''), '');
    });
  });
}
