import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';

void main() {
  // The streak on the daily result is 1 for every player on their first
  // day, so the singular is the case most people see first — and the one
  // that read "1 días".
  group('dailyResultDaysValue', () {
    final es = lookupAppLocalizations(const Locale('es'));
    final en = lookupAppLocalizations(const Locale('en'));

    test('uses the singular for a one-day streak', () {
      expect(es.dailyResultDaysValue(1), '1 día');
      expect(en.dailyResultDaysValue(1), '1 day');
    });

    test('uses the plural for every other streak', () {
      expect(es.dailyResultDaysValue(0), '0 días');
      expect(es.dailyResultDaysValue(2), '2 días');
      expect(es.dailyResultDaysValue(21), '21 días');
      expect(en.dailyResultDaysValue(0), '0 days');
      expect(en.dailyResultDaysValue(2), '2 days');
      expect(en.dailyResultDaysValue(21), '21 days');
    });
  });
}
