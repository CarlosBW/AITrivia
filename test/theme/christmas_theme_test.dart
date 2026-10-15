import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/snowfall_backdrop.dart';
import 'package:trivia_ia_flutter/theme/starfield_backdrop.dart';

/// Navidad: nieve sobre una noche de pino, rojo y dorado, con fondo, letra e
/// iconos propios. Lo que puede salir mal es que el rojo no se lea sobre el
/// verde oscuro, y que algo de eso se cuele en los temas que no lo
/// compraron.
void main() {
  final christmas = AppThemes.byId(AppThemes.christmasId);
  final scheme = christmas.colorScheme;
  final semantic = christmas.semanticColors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('el tema navidad', () {
    test('esta en el catalogo, cuesta 400 y es oscuro', () {
      expect(christmas.id, AppThemes.christmasId);
      expect(christmas.price, 400);
      expect(scheme.brightness, Brightness.dark);
    });

    test('el texto se lee sobre la pagina y sobre las tarjetas', () {
      for (final bg in [
        christmas.scaffoldBackground,
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

    test('los botones y los enlaces se leen', () {
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.primary, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.primary, christmas.scaffoldBackground),
        greaterThanOrEqualTo(4.5),
      );
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

    test('el texto blanco se lee sobre sus degradados', () {
      for (final stop in [
        semantic.brandGradientStart,
        semantic.brandGradientEnd,
        semantic.heroGradientStart,
        semantic.heroGradientEnd,
      ]) {
        expect(
          contrast(semantic.onAccent, stop),
          greaterThanOrEqualTo(4.5),
          reason: '$stop',
        );
      }
    });

    test('trae titulares festivos, nieve e iconos propios', () {
      expect(christmas.headingFace, AppHeadingFace.festive);
      expect(christmas.decor.backdrop, AppBackdrop.snowfall);
      expect(christmas.decor.navIcons, AppNavIcons.christmas);
      expect(christmas.decor.pageColor, christmas.scaffoldBackground);
    });

    // Mas redondo que el clasico, como algo acolchado, con un hilo dorado.
    test('esquinas mas redondas que las de siempre y borde dorado', () {
      expect(christmas.surfaces.overridesSurfaces, isTrue);
      expect(christmas.surfaces.hasBorder, isTrue);
      expect(christmas.shapes.md, greaterThan(AppShapes.standard.md));
      expect(christmas.shapes.pill, AppShapes.standard.pill);
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameChristmas, 'Navidad');
      expect(en.themeNameChristmas, 'Christmas');
      expect(es.themeDescriptionChristmas, isNotEmpty);
      expect(
        en.themeDescriptionChristmas,
        isNot(es.themeDescriptionChristmas),
      );
    });
  });

  test('ningun otro tema usa la letra festiva', () {
    for (final spec in AppThemes.all.where(
      (s) => s.id != AppThemes.christmasId,
    )) {
      expect(spec.headingFace, isNot(AppHeadingFace.festive), reason: spec.id);
    }
  });

  // Mountains of Christmas llega hasta 700. Sin pasar por google_fonts, que
  // en los tests intenta bajar la letra.
  test('la letra festiva nunca pide mas peso del que tiene', () {
    for (final weight in [FontWeight.w700, FontWeight.w800, FontWeight.w900]) {
      expect(
        headingWeight(AppHeadingFace.festive, weight),
        FontWeight.w700,
        reason: '$weight',
      );
    }
    // Las que tienen todos los pesos los conservan.
    expect(
      headingWeight(AppHeadingFace.engraved, FontWeight.w900),
      FontWeight.w900,
    );
  });

  group('el fondo de nieve', () {
    const size = Size(390, 844);

    test('los copos caen dentro del lienzo y bajo la barra de titulo', () {
      final flakes = SnowfallPainter.flakesFor(size);

      expect(flakes, isNotEmpty);
      for (final flake in flakes) {
        expect(flake.center.dx, inInclusiveRange(0, size.width));
        expect(
          flake.center.dy,
          inInclusiveRange(size.height * 0.15, size.height),
        );
        expect(flake.radius, greaterThan(0));
      }
    });

    test('la nieve es la misma cada vez', () {
      expect(
        SnowfallPainter.flakesFor(size).map((f) => f.center),
        SnowfallPainter.flakesFor(size).map((f) => f.center),
      );
    });

    test('se pinta sin errores y no repinta si nada cambio', () {
      const painter = SnowfallPainter(base: Color(0xFF0E2A20));
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      recorder.endRecording();

      expect(
        painter.shouldRepaint(const SnowfallPainter(base: Color(0xFF0E2A20))),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const SnowfallPainter(base: Color(0xFF000000))),
        isTrue,
      );
    });

    testWidgets('cada pantalla se monta sobre la nieve', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: backdropPageTransitionsTheme,
            extensions: [christmas.decor],
          ),
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      Finder above(String page, Type type) =>
          find.ancestor(of: find.text(page), matching: find.byType(type));

      expect(above('inicio', SnowfallBackdrop), findsOneWidget);
      expect(above('inicio', StarfieldBackdrop), findsNothing);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await tester.pumpAndSettle();

      expect(above('segunda', SnowfallBackdrop), findsOneWidget);
    });
  });
}
