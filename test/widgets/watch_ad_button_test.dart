import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/widgets/watch_ad_button.dart';

void main() {
  // "No hay anuncios" no decía por qué: sin relleno, sin consentimiento y
  // un bloque mal configurado se veían igual desde fuera.
  group('adUnavailableMessage', () {
    test('lleva el código del fallo, para poder reportarlo', () {
      expect(
        adUnavailableMessage('No hay anuncios disponibles.', '3'),
        'No hay anuncios disponibles. (3)',
      );
      expect(
        adUnavailableMessage('No hay anuncios disponibles.', 'C'),
        'No hay anuncios disponibles. (C)',
      );
    });

    test('sin código, el mensaje va solo', () {
      expect(
        adUnavailableMessage('No hay anuncios disponibles.', null),
        'No hay anuncios disponibles.',
      );
      expect(
        adUnavailableMessage('No hay anuncios disponibles.', ''),
        'No hay anuncios disponibles.',
      );
    });
  });
}
