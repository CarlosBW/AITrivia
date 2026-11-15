import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/ad_rewards.dart';

void main() {
  group('rewardedAdUnitId', () {
    String? unit({
      TargetPlatform platform = TargetPlatform.android,
      bool isWeb = false,
      bool debugBuild = false,
      String android = '',
      String ios = '',
    }) =>
        rewardedAdUnitId(
          platform: platform,
          isWeb: isWeb,
          debugBuild: debugBuild,
          androidAdUnitId: android,
          iosAdUnitId: ios,
        );

    // Mientras no exista la cuenta de AdMob, la app publicada no ofrece
    // anuncios: ni botones ni SDK en marcha.
    test('una build publicada sin ad unit no muestra anuncios', () {
      expect(unit(), isNull);
      expect(unit(platform: TargetPlatform.iOS), isNull);
    });

    test('una build publicada usa el ad unit de su plataforma', () {
      expect(unit(android: 'ca-app-pub-1/2', ios: 'ca-app-pub-1/3'),
          'ca-app-pub-1/2');
      expect(
        unit(
          platform: TargetPlatform.iOS,
          android: 'ca-app-pub-1/2',
          ios: 'ca-app-pub-1/3',
        ),
        'ca-app-pub-1/3',
      );
    });

    // Tocar un anuncio real mientras se desarrolla suspende la cuenta.
    test('una build de depuración usa siempre los de prueba de Google', () {
      final debug = unit(debugBuild: true, android: 'ca-app-pub-1/2');

      expect(debug, isNotNull);
      expect(debug, isNot('ca-app-pub-1/2'));
      expect(debug, startsWith('ca-app-pub-3940256099942544/'));
    });

    test('ni la web ni el escritorio tienen anuncios', () {
      expect(unit(isWeb: true, debugBuild: true, android: 'x'), isNull);
      expect(
        unit(platform: TargetPlatform.windows, debugBuild: true),
        isNull,
      );
    });
  });

  group('adRewardsLeftToday', () {
    // El día del servidor corre en UTC.
    final now = DateTime.utc(2026, 11, 14, 23, 30);

    test('sin anuncios vistos queda el tope entero', () {
      expect(
        adRewardsLeftToday(const {}, AdRewardKind.lives, now: now),
        AdRewards.livesDailyCap,
      );
    });

    test('cada recompensa descuenta de su propio tope', () {
      final user = {
        'adRewardsDate': '2026-11-14',
        'adLivesToday': 2,
        'adCoinsToday': 5,
      };

      expect(
        adRewardsLeftToday(user, AdRewardKind.lives, now: now),
        AdRewards.livesDailyCap - 2,
      );
      expect(adRewardsLeftToday(user, AdRewardKind.coins, now: now), 0);
    });

    test('la cuenta de ayer no vale hoy', () {
      final user = {
        'adRewardsDate': '2026-11-13',
        'adLivesToday': 5,
        'adCoinsToday': 5,
      };

      expect(
        adRewardsLeftToday(user, AdRewardKind.coins, now: now),
        AdRewards.coinsDailyCap,
      );
    });

    // De noche en Lima ya es el día siguiente para el servidor.
    test('el día se cuenta en UTC, no en la hora del teléfono', () {
      final limaEvening = DateTime.parse('2026-11-14T20:00:00-05:00');

      expect(adRewardsDateId(limaEvening), '2026-11-15');
    });

    test('una cuenta por encima del tope no da negativos', () {
      final user = {'adRewardsDate': '2026-11-14', 'adLivesToday': 99};

      expect(adRewardsLeftToday(user, AdRewardKind.lives, now: now), 0);
    });
  });
}
