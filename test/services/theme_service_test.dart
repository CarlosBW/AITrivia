import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/theme_service.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// What a user doc *means* about themes, which is where the awkward cases
/// live: docs created before themes existed carry neither field, and a doc
/// can name a theme this build doesn't ship.
void main() {
  group('ownedThemeIds', () {
    test('un doc sin el campo posee el tema gratis', () {
      expect(ThemeService.ownedThemeIds({}), contains(AppThemes.defaultId));
    });

    test('un doc nulo tampoco se queda sin nada', () {
      expect(ThemeService.ownedThemeIds(null), contains(AppThemes.defaultId));
    });

    test('suma lo comprado a lo gratis', () {
      final owned = ThemeService.ownedThemeIds({
        'ownedThemes': [AppThemes.playfulId],
      });

      expect(owned, containsAll([AppThemes.defaultId, AppThemes.playfulId]));
    });

    // Un id que esta build no conoce no debe colarse: nadie podría pintarlo,
    // y dejarlo pasar haría que `equip` intentara algo imposible.
    test('descarta ids que este build no conoce', () {
      final owned = ThemeService.ownedThemeIds({
        'ownedThemes': ['tema_de_una_version_futura'],
      });

      expect(owned, isNot(contains('tema_de_una_version_futura')));
      expect(owned, contains(AppThemes.defaultId));
    });

    test('tolera un campo con tipo raro', () {
      expect(
        ThemeService.ownedThemeIds({'ownedThemes': 'no es una lista'}),
        contains(AppThemes.defaultId),
      );
    });
  });

  group('equippedIdFrom', () {
    test('sin campo devuelve el tema por defecto', () {
      expect(ThemeService.equippedIdFrom({}), AppThemes.defaultId);
      expect(ThemeService.equippedIdFrom(null), AppThemes.defaultId);
    });

    test('devuelve el tema equipado', () {
      expect(
        ThemeService.equippedIdFrom({'equippedTheme': AppThemes.playfulId}),
        AppThemes.playfulId,
      );
    });

    // Desinstalar una actualización, o comprar desde otro dispositivo con una
    // versión más nueva, deja aquí un id irreconocible. Debe caer al base,
    // no dejar la app sin tema.
    test('un id desconocido cae al tema por defecto', () {
      expect(
        ThemeService.equippedIdFrom({'equippedTheme': 'tema_inventado'}),
        AppThemes.defaultId,
      );
    });

    test('una cadena vacia cae al tema por defecto', () {
      expect(
        ThemeService.equippedIdFrom({'equippedTheme': ''}),
        AppThemes.defaultId,
      );
    });
  });
}
