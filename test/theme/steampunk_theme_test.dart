import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/gears_backdrop.dart';
import 'package:trivia_ia_flutter/theme/starfield_backdrop.dart';

/// Steampunk: laton, cobre y engranajes, con fondo, letra e iconos propios.
/// Lo que puede salir mal es que el laton no se lea sobre lo oscuro, y que
/// algo de eso se cuele en los temas que no lo compraron.
void main() {
  final steampunk = AppThemes.byId(AppThemes.steampunkId);
  final scheme = steampunk.colorScheme;
  final semantic = steampunk.semanticColors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('el tema steampunk', () {
    test('esta en el catalogo, cuesta 400 y es oscuro', () {
      expect(steampunk.id, AppThemes.steampunkId);
      expect(steampunk.price, 400);
      expect(scheme.brightness, Brightness.dark);
    });

    test('el texto se lee sobre la pagina y sobre las tarjetas', () {
      for (final bg in [
        steampunk.scaffoldBackground,
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
        contrast(scheme.primary, steampunk.scaffoldBackground),
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

    test('trae titulares grabados, fondo de engranajes e iconos propios', () {
      expect(steampunk.headingFace, AppHeadingFace.engraved);
      expect(steampunk.decor.backdrop, AppBackdrop.gears);
      expect(steampunk.decor.navIcons, AppNavIcons.steampunk);
      expect(steampunk.decor.pageColor, steampunk.scaffoldBackground);
    });

    // Placas de laton: un borde grueso, mas grueso que el de cualquier otro
    // tema, y esquinas algo mas rectas que las de siempre.
    test('placas con borde grueso de laton', () {
      final surfaces = steampunk.surfaces;

      expect(surfaces.overridesSurfaces, isTrue);
      expect(surfaces.hasBorder, isTrue);
      expect(surfaces.borderWidth, greaterThanOrEqualTo(2));
      expect(steampunk.shapes.md, lessThan(AppShapes.standard.md));
      expect(steampunk.shapes.pill, AppShapes.standard.pill);
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameSteampunk, 'Steampunk');
      expect(en.themeNameSteampunk, 'Steampunk');
      expect(es.themeDescriptionSteampunk, isNotEmpty);
      expect(
        en.themeDescriptionSteampunk,
        isNot(es.themeDescriptionSteampunk),
      );
    });
  });

  test('ningun otro tema usa la letra grabada', () {
    for (final spec in AppThemes.all.where(
      (s) => s.id != AppThemes.steampunkId,
    )) {
      expect(spec.headingFace, isNot(AppHeadingFace.engraved), reason: spec.id);
    }
  });

  group('el fondo de engranajes', () {
    const size = Size(390, 844);

    test('hay engranajes, con dientes, y ninguno sube a la barra de titulo',
        () {
      final gears = GearsPainter.gearsFor(size);

      expect(gears, isNotEmpty);
      for (final gear in gears) {
        expect(gear.teeth, greaterThanOrEqualTo(6));
        expect(gear.radius, greaterThan(0));
        // Pueden salirse por los lados o por abajo, como si siguieran
        // fuera de la pantalla, pero no por la franja de arriba.
        expect(
          gear.center.dy - gear.radius,
          greaterThanOrEqualTo(size.height * 0.15),
          reason: '$gear',
        );
      }
    });

    test('los engranajes son los mismos cada vez', () {
      expect(GearsPainter.gearsFor(size), GearsPainter.gearsFor(size));
    });

    test('se pinta sin errores y no repinta si nada cambio', () {
      const painter = GearsPainter(base: Color(0xFF1C140E));
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      recorder.endRecording();

      expect(
        painter.shouldRepaint(const GearsPainter(base: Color(0xFF1C140E))),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const GearsPainter(base: Color(0xFF000000))),
        isTrue,
      );
    });

    testWidgets('cada pantalla se monta sobre los engranajes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: backdropPageTransitionsTheme,
            extensions: [steampunk.decor],
          ),
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      Finder above(String page, Type type) =>
          find.ancestor(of: find.text(page), matching: find.byType(type));

      expect(above('inicio', GearsBackdrop), findsOneWidget);
      expect(above('inicio', StarfieldBackdrop), findsNothing);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await tester.pumpAndSettle();

      expect(above('segunda', GearsBackdrop), findsOneWidget);
    });
  });
}
