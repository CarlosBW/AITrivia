import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/ad_rewards.dart';
import 'package:trivia_ia_flutter/services/life_service.dart';

/// Lo que paga un anuncio existe dos veces: aquí, para lo que la app
/// anuncia, y en `AD_REWARDS` de `ad_rewards.ts`, que es lo que de verdad
/// se acredita. Si se separan, la app promete una cosa y el servidor da
/// otra.
void main() {
  final source = File('functions/src/ad_rewards.ts').readAsStringSync();

  int serverValue(String kind, String field) {
    final match = RegExp(kind + r': \{[^}]*\b' + field + r': (\d+)')
        .firstMatch(source);
    expect(
      match,
      isNotNull,
      reason: 'ad_rewards.ts ya no declara `$kind.$field` en AD_REWARDS. '
          'Si cambió de forma, actualiza este test.',
    );
    return int.parse(match!.group(1)!);
  }

  test('las vidas por anuncio cuadran con el servidor', () {
    expect(
      AdRewards.livesPerAd * LifeService.unitsPerLife,
      serverValue('lives', 'lifeUnits'),
    );
    expect(AdRewards.livesDailyCap, serverValue('lives', 'dailyCap'));
  });

  test('las monedas por anuncio cuadran con el servidor', () {
    expect(AdRewards.coinsPerAd, serverValue('coins', 'coins'));
    expect(AdRewards.coinsDailyCap, serverValue('coins', 'dailyCap'));
  });

  test('cada recompensa se llama igual que en el servidor', () {
    for (final kind in AdRewardKind.values) {
      expect(source, contains('"${kind.name}"'));
    }
  });
}
