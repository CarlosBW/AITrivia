import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/result_share.dart';

void main() {
  test('desde Android el resultado lleva el enlace de Play', () {
    expect(
      shareLinkFor(TargetPlatform.android),
      contains('pe.massivedynamics.triviaia'),
    );
  });

  // Un enlace que no lleva a ningún lado es peor que ninguno.
  test('sin enlace configurado no se inventa uno', () {
    expect(shareLinkFor(TargetPlatform.iOS, ios: ''), isNull);
    expect(shareLinkFor(TargetPlatform.windows), isNull);
  });

  test('cada plataforma usa su propio enlace', () {
    expect(
      shareLinkFor(TargetPlatform.iOS, ios: 'https://apps.apple.com/app/id1'),
      'https://apps.apple.com/app/id1',
    );
  });

  test('el enlace va debajo del mensaje, y sin enlace queda solo', () {
    expect(shareTextWithLink('Hola', 'https://x.test'), 'Hola\nhttps://x.test');
    expect(shareTextWithLink('Hola', null), 'Hola');
  });
}
