import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/ad_rewards.dart';

/// El id de la app en AdMob vive en los archivos nativos, y hoy es el de
/// prueba de Google. Los ad units viven en `AdRewards`. Publicar ad units
/// reales con el id de app de prueba deja los anuncios sin cuenta a la que
/// pagar, y nada lo avisaría.
void main() {
  const googleTestPublisher = 'ca-app-pub-3940256099942544';

  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  // Sin el id, el SDK cierra la app al arrancar.
  test('los dos nativos declaran un id de app de AdMob', () {
    expect(manifest, contains('com.google.android.gms.ads.APPLICATION_ID'));
    expect(plist, contains('GADApplicationIdentifier'));
  });

  test('Android no publica ad units reales con el id de app de prueba', () {
    if (AdRewards.androidAdUnitId.isEmpty) return;
    expect(manifest, isNot(contains(googleTestPublisher)));
  });

  test('iOS no publica ad units reales con el id de app de prueba', () {
    if (AdRewards.iosAdUnitId.isEmpty) return;
    expect(plist, isNot(contains(googleTestPublisher)));
  });
}
