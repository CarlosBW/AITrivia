import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';

void main() {
  // These three were string literals in the code, so a Spanish-speaking
  // player got them in English: the daily reminder notification, the
  // three-star badge, and the pending season reward.
  group('strings that used to be hardcoded in English', () {
    final es = lookupAppLocalizations(const Locale('es'));
    final en = lookupAppLocalizations(const Locale('en'));

    test('the daily reminder is written in the player\'s language', () {
      expect(es.dailyReminderBody, 'Juega hoy y mantén tu racha.');
      expect(en.dailyReminderBody, 'Play today and keep your streak alive.');
      expect(es.dailyReminderTitle, isNot(en.dailyReminderTitle));
    });

    test('the perfect-level badge is translated', () {
      expect(es.soloPerfectBadge, '¡PERFECTO!');
      expect(en.soloPerfectBadge, 'PERFECT!');
    });

    test('the pending season reward names coins in each language', () {
      expect(es.pvpSeasonPendingCoins(250), '+250 monedas');
      expect(en.pvpSeasonPendingCoins(250), '+250 coins');
    });

    // The purchase service wrote "Purchase canceled." itself, with no
    // context to translate it from, and the shop showed it as it came.
    test('backing out of a coin purchase is said in each language', () {
      expect(es.coinShopPurchaseCanceled, 'Compra cancelada.');
      expect(en.coinShopPurchaseCanceled, 'Purchase canceled.');
    });

    // "best 1200 MMR" was written into the season screen as it stood.
    test('a pending season reward says "best" in the player\'s language', () {
      expect(
        es.pvpSeasonPendingRewardLine('pvp_2026_10', 'Silver', 1200),
        'pvp_2026_10 • Silver • mejor 1200 MMR',
      );
      expect(
        en.pvpSeasonPendingRewardLine('pvp_2026_10', 'Silver', 1200),
        'pvp_2026_10 • Silver • best 1200 MMR',
      );
    });
  });
}
