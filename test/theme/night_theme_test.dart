import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// El tema Noche es el primero que cambia la paleta, y el unico oscuro. Lo
/// que puede salir mal no es que se vea feo sino que no se lea: texto del
/// tema claro sobre un fondo que ya no lo es.
void main() {
  final night = AppThemes.byId(AppThemes.nightId);
  final scheme = night.colorScheme;
  final semantic = night.semanticColors;

  // Contraste WCAG entre dos colores opacos.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('el tema noche', () {
    test('esta en el catalogo, es de pago y es oscuro', () {
      expect(night.id, AppThemes.nightId);
      expect(night.isFree, isFalse);
      expect(scheme.brightness, Brightness.dark);
    });

    test('el fondo de pagina es mas oscuro que las tarjetas', () {
      // Sin sombra visible sobre un fondo oscuro, la diferencia de tono es
      // lo unico que separa una tarjeta de la pagina.
      expect(
        night.scaffoldBackground.computeLuminance(),
        lessThan(scheme.surface.computeLuminance()),
      );
    });

    test('el texto se lee sobre la pagina y sobre las tarjetas', () {
      for (final bg in [
        night.scaffoldBackground,
        scheme.surface,
        scheme.surfaceContainerHighest,
      ]) {
        expect(contrast(scheme.onSurface, bg), greaterThanOrEqualTo(4.5));
        expect(
          contrast(scheme.onSurfaceVariant, bg),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('el color de marca se distingue como texto y como boton', () {
      // 3:1 es el minimo de WCAG para controles y texto grande en negrita,
      // que es como se usa: botones, enlaces y titulos.
      expect(
        contrast(scheme.primary, night.scaffoldBackground),
        greaterThanOrEqualTo(3),
      );
      expect(contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(3));
      expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(3));
      expect(
        contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('recompensa, acierto y error se leen sobre su tinte y sobre tarjeta',
        () {
      final pairs = {
        semantic.reward: semantic.rewardBg,
        semantic.success: semantic.successBg,
        semantic.danger: semantic.dangerBg,
      };

      pairs.forEach((fg, tint) {
        expect(contrast(fg, tint), greaterThanOrEqualTo(4.5));
        expect(contrast(fg, scheme.surface), greaterThanOrEqualTo(4.5));
      });
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameNight, 'Noche');
      expect(en.themeNameNight, 'Night');
      expect(es.themeDescriptionNight, isNotEmpty);
      expect(en.themeDescriptionNight, isNot(es.themeDescriptionNight));
    });
  });

  // Las pantallas oscurecian un color de acento hacia el negro para escribir
  // sobre su propio tinte. Sobre un tinte oscuro eso lo vuelve ilegible: en
  // un tema oscuro hay que aclararlo.
  group('los tintes siguen la luminosidad del tema', () {
    Future<BuildContext> pumpWith(WidgetTester tester, AppThemeSpec spec) async {
      late BuildContext captured;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: spec.colorScheme),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      return captured;
    }

    const accent = Color(0xFFE5622C);
    const paleWash = Color(0xFFFFE8D6);

    testWidgets('en el clasico todo queda como estaba', (tester) async {
      final context = await pumpWith(
        tester,
        AppThemes.byId(AppThemes.defaultId),
      );

      expect(
        context.onTint(accent, 0.35),
        Color.lerp(accent, Colors.black, 0.35),
      );
      expect(context.tintOf(accent, paleWash), paleWash);
    });

    testWidgets('en noche el texto se aclara y el tinte se oscurece',
        (tester) async {
      final context = await pumpWith(tester, night);

      expect(
        context.onTint(accent, 0.35).computeLuminance(),
        greaterThan(accent.computeLuminance()),
      );

      // El lavado palido del tema claro no puede sobrevivir: seria una
      // tarjeta casi blanca en medio de una pantalla oscura.
      final tint = Color.alphaBlend(context.tintOf(accent, paleWash), scheme.surface);
      expect(tint.computeLuminance(), lessThan(0.1));
      expect(
        contrast(scheme.onSurface, tint),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
