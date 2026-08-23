import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';

/// The foreground tokens exist so a purchasable theme can move text off
/// white when it repaints the surface underneath. Their *defaults* are a
/// different matter: they replaced `Colors.white` / `Colors.black` written
/// into ~45 call sites, and that swap is only safe while the default
/// resolves to exactly what was there before.
///
/// So this pins the shipped values. A theme is free to override them; the
/// default palette drifting is what would silently restyle the whole app.
/// Lo que no cubre: que `buildAppTheme` llegue a registrar la extension.
/// Esa funcion resuelve su tipografia con google_fonts, que necesita la
/// fuente en tiempo de ejecucion —por red o empaquetada como asset— y
/// ninguna de las dos existe en un unit test. De ahi que la paleta viva en
/// `appColorScheme`, que si se puede leer sin construir el tema.
void main() {
  const colors = AppSemanticColors.standard;

  group('los tokens de primer plano conservan el valor que sustituyeron', () {
    test('onAccent sigue siendo blanco', () {
      expect(colors.onAccent, Colors.white);
    });

    test('onScrim sigue siendo blanco', () {
      expect(colors.onScrim, Colors.white);
    });

    // Negro y no blanco: se dibuja sobre `reward`, que es un dorado claro.
    test('onReward sigue siendo negro', () {
      expect(colors.onReward, Colors.black);
    });

    // Las sombras pasaron de `Colors.black.withValues(...)` a
    // `colorScheme.shadow`, y los overlays a `colorScheme.scrim`.
    test('shadow y scrim del esquema siguen siendo negros', () {
      expect(appColorScheme.shadow, Colors.black);
      expect(appColorScheme.scrim, Colors.black);
    });

    // Los fondos claros de avatar pasaron de `Colors.white` a `surface`.
    test('surface sigue siendo blanco', () {
      expect(appColorScheme.surface, Colors.white);
    });
  });

  group('la extension se comporta como ThemeExtension', () {
    test('copyWith cambia solo lo que se le pasa', () {
      final changed = colors.copyWith(onAccent: Colors.red);

      expect(changed.onAccent, Colors.red);
      expect(changed.onScrim, colors.onScrim);
      expect(changed.onReward, colors.onReward);
      expect(changed.reward, colors.reward);
    });

    // Sin esto una transicion entre temas dejaria los tokens nuevos
    // clavados en el valor de origen mientras el resto de la paleta se
    // mueve, que es justo el parpadeo que ThemeExtension.lerp evita.
    test('lerp interpola tambien los tokens nuevos', () {
      final other = colors.copyWith(
        onAccent: Colors.black,
        onScrim: Colors.black,
        onReward: Colors.white,
      );

      final mid = colors.lerp(other, 1.0);

      expect(mid.onAccent, Colors.black);
      expect(mid.onScrim, Colors.black);
      expect(mid.onReward, Colors.white);
    });
  });
}
