import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/sketchbook_backdrop.dart';
import 'package:trivia_ia_flutter/theme/starfield_backdrop.dart';

/// Boceto: todo el juego en blanco y negro, como dibujado a lápiz en un
/// cuaderno. Lo que puede salir mal es que se cuele un color, y que sin
/// color no se distinga lo que antes distinguía el color.
void main() {
  final sketch = AppThemes.byId(AppThemes.sketchId);
  final scheme = sketch.colorScheme;
  final semantic = sketch.semanticColors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  bool isGray(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    // Un papel apenas cálido sigue siendo blanco: hasta 6 de diferencia.
    final spread = [r, g, b].reduce((a, b) => a > b ? a : b) -
        [r, g, b].reduce((a, b) => a < b ? a : b);
    return spread <= 6;
  }

  group('el tema boceto', () {
    test('esta en el catalogo, cuesta 400 y es claro', () {
      expect(sketch.id, AppThemes.sketchId);
      expect(sketch.price, 400);
      expect(scheme.brightness, Brightness.light);
    });

    test('no tiene un solo color: todo es blanco, negro o gris', () {
      final colors = <String, Color>{
        'primary': scheme.primary,
        'onPrimary': scheme.onPrimary,
        'primaryContainer': scheme.primaryContainer,
        'secondary': scheme.secondary,
        'secondaryContainer': scheme.secondaryContainer,
        'tertiary': scheme.tertiary,
        'surface': scheme.surface,
        'onSurface': scheme.onSurface,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'onSurfaceVariant': scheme.onSurfaceVariant,
        'outline': scheme.outline,
        'error': scheme.error,
        'errorContainer': scheme.errorContainer,
        'reward': semantic.reward,
        'rewardBg': semantic.rewardBg,
        'success': semantic.success,
        'successBg': semantic.successBg,
        'danger': semantic.danger,
        'dangerBg': semantic.dangerBg,
        'brandGradientStart': semantic.brandGradientStart,
        'brandGradientEnd': semantic.brandGradientEnd,
        'heroGradientStart': semantic.heroGradientStart,
        'heroGradientEnd': semantic.heroGradientEnd,
        'page': sketch.scaffoldBackground,
        'border': sketch.surfaces.borderColor,
        for (var i = 0; i < sketch.preview.length; i++)
          'preview$i': sketch.preview[i],
      };

      colors.forEach((name, color) {
        expect(isGray(color), isTrue, reason: '$name es $color');
      });
    });

    test('el texto se lee sobre la pagina y sobre las tarjetas', () {
      for (final bg in [
        sketch.scaffoldBackground,
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

    // Sin verde ni rojo, acierto y error tienen que verse distintos por el
    // tono (además del ícono de la respuesta).
    test('acierto y error no son el mismo gris', () {
      expect(
        (semantic.success.computeLuminance() -
                semantic.danger.computeLuminance())
            .abs(),
        greaterThan(0.03),
      );
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

    test('trae letra a mano, cuaderno y trazo de tinta', () {
      expect(sketch.headingFace, AppHeadingFace.handwritten);
      expect(sketch.decor.backdrop, AppBackdrop.sketchbook);
      expect(sketch.decor.pageColor, sketch.scaffoldBackground);
      expect(sketch.surfaces.overridesSurfaces, isTrue);
      expect(sketch.surfaces.hasBorder, isTrue);
      expect(sketch.surfaces.borderColor, scheme.onSurface);
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameSketch, 'Boceto');
      expect(en.themeNameSketch, 'Sketch');
      expect(es.themeDescriptionSketch, isNotEmpty);
      expect(en.themeDescriptionSketch, isNot(es.themeDescriptionSketch));
    });
  });

  test('ningun otro tema usa la letra a mano', () {
    for (final spec in AppThemes.all.where((s) => s.id != AppThemes.sketchId)) {
      expect(
        spec.headingFace,
        isNot(AppHeadingFace.handwritten),
        reason: spec.id,
      );
    }
  });

  // Patrick Hand viene en un solo peso. Sin pasar por google_fonts, que en
  // los tests intenta bajar la letra.
  test('la letra a mano no inventa pesos', () {
    for (final weight in [FontWeight.w400, FontWeight.w700, FontWeight.w900]) {
      expect(
        headingWeight(AppHeadingFace.handwritten, weight),
        FontWeight.w400,
        reason: '$weight',
      );
    }
  });

  group('el fondo de cuaderno', () {
    const size = Size(390, 844);

    test('los trazos caen dentro del lienzo y bajo la barra de titulo', () {
      final strokes = SketchbookPainter.strokesFor(size);

      expect(strokes, isNotEmpty);
      for (final stroke in strokes) {
        for (final point in [stroke.start, stroke.end]) {
          expect(point.dx, inInclusiveRange(0, size.width));
          expect(
            point.dy,
            inInclusiveRange(size.height * 0.15, size.height),
          );
        }
      }
    });

    test('el dibujo es el mismo cada vez', () {
      expect(
        SketchbookPainter.strokesFor(size).map((s) => s.start),
        SketchbookPainter.strokesFor(size).map((s) => s.start),
      );
    });

    test('se pinta sin errores y no repinta si nada cambio', () {
      const painter = SketchbookPainter(base: Color(0xFFF6F5F1));
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      recorder.endRecording();

      expect(
        painter.shouldRepaint(const SketchbookPainter(base: Color(0xFFF6F5F1))),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const SketchbookPainter(base: Color(0xFF000000))),
        isTrue,
      );
    });

    testWidgets('cada pantalla se monta sobre el cuaderno', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: backdropPageTransitionsTheme,
            extensions: [sketch.decor],
          ),
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      expect(
        find.ancestor(
          of: find.text('inicio'),
          matching: find.byType(SketchbookBackdrop),
        ),
        findsOneWidget,
      );
    });
  });
}
