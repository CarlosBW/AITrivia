import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/neon_city_backdrop.dart';
import 'package:trivia_ia_flutter/theme/paper_backdrop.dart';
import 'package:trivia_ia_flutter/theme/starfield_backdrop.dart';
import 'package:trivia_ia_flutter/theme/wasteland_backdrop.dart';

/// Cyberpunk: neón sobre una ciudad de noche, con fondo, letra e iconos
/// propios. Lo que puede salir mal es que el neón no se lea sobre lo oscuro,
/// y que algo de eso se cuele en los temas que no lo compraron.
void main() {
  final cyberpunk = AppThemes.byId(AppThemes.cyberpunkId);
  final scheme = cyberpunk.colorScheme;
  final semantic = cyberpunk.semanticColors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('el tema cyberpunk', () {
    test('esta en el catalogo, cuesta 400 y es oscuro', () {
      expect(cyberpunk.id, AppThemes.cyberpunkId);
      expect(cyberpunk.price, 400);
      expect(scheme.brightness, Brightness.dark);
    });

    test('el texto se lee sobre la pagina y sobre las tarjetas', () {
      for (final bg in [
        cyberpunk.scaffoldBackground,
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
        contrast(scheme.primary, cyberpunk.scaffoldBackground),
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

    // Lo que se compra: letra tecnica, ciudad de neon e iconos propios.
    test('trae titulares tecnicos, fondo de ciudad e iconos propios', () {
      expect(cyberpunk.headingFace, AppHeadingFace.tech);
      expect(cyberpunk.decor.backdrop, AppBackdrop.neonCity);
      expect(cyberpunk.decor.navIcons, AppNavIcons.cyberpunk);
      expect(cyberpunk.decor.pageColor, cyberpunk.scaffoldBackground);
    });

    // El borde de neon y una sombra de otro color corrida, como una imagen
    // con fallo de señal.
    test('borde de neon y sombra corrida de otro color, sin difuminar', () {
      final surfaces = cyberpunk.surfaces;

      expect(surfaces.overridesSurfaces, isTrue);
      expect(surfaces.hasBorder, isTrue);
      expect(surfaces.shadowBlur, 0);
      expect(surfaces.shadowOffset.dx, isNot(0));
      expect(
        surfaces.shadowColor.withValues(alpha: 1),
        isNot(surfaces.borderColor.withValues(alpha: 1)),
      );
      expect(cyberpunk.shapes.md, lessThan(AppShapes.standard.md));
      // Un boton redondo sigue siendo redondo.
      expect(cyberpunk.shapes.pill, AppShapes.standard.pill);
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameCyberpunk, 'Cyberpunk');
      expect(en.themeNameCyberpunk, 'Cyberpunk');
      expect(es.themeDescriptionCyberpunk, isNotEmpty);
      expect(
        en.themeDescriptionCyberpunk,
        isNot(es.themeDescriptionCyberpunk),
      );
    });
  });

  test('ningun otro tema usa la letra tecnica', () {
    for (final spec in AppThemes.all.where(
      (s) => s.id != AppThemes.cyberpunkId,
    )) {
      expect(spec.headingFace, isNot(AppHeadingFace.tech), reason: spec.id);
    }
  });

  // Chakra Petch llega hasta 700. Pedirle mas solo daria una negrita falsa.
  test('la letra tecnica nunca pide mas peso del que tiene', () {
    // Sin pasar por google_fonts, que en los tests intenta bajar la letra.
    for (final weight in [FontWeight.w700, FontWeight.w800, FontWeight.w900]) {
      expect(headingWeight(AppHeadingFace.tech, weight), FontWeight.w700,
          reason: '$weight');
    }
    expect(
        headingWeight(AppHeadingFace.tech, FontWeight.w500), FontWeight.w500);
  });

  group('el fondo de ciudad', () {
    const size = Size(390, 844);

    test('los edificios caen dentro del lienzo y abajo', () {
      final buildings = NeonCityPainter.buildingsFor(size);

      expect(buildings, isNotEmpty);
      for (final b in buildings) {
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(size.width));
        expect(b.bottom, size.height);
        // Como en Vintage y Apocalipsis: nada sube a la franja de la barra
        // de titulo, que va en color liso.
        expect(b.top, greaterThanOrEqualTo(size.height * 0.15));
      }
    });

    test('cada ventana esta dentro de un edificio', () {
      final buildings = NeonCityPainter.buildingsFor(size);
      final windows = NeonCityPainter.windowsFor(size);

      expect(windows, isNotEmpty);
      for (final w in windows) {
        expect(
          buildings.any((b) => b.contains(w.topLeft) && b.contains(w.center)),
          isTrue,
          reason: '$w',
        );
      }
    });

    test('la ciudad es la misma cada vez', () {
      expect(
        NeonCityPainter.buildingsFor(size),
        NeonCityPainter.buildingsFor(size),
      );
      expect(
        NeonCityPainter.windowsFor(size),
        NeonCityPainter.windowsFor(size),
      );
    });

    test('se pinta sin errores y no repinta si nada cambio', () {
      const painter = NeonCityPainter(base: Color(0xFF0D0A1A));
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      recorder.endRecording();

      expect(
        painter.shouldRepaint(const NeonCityPainter(base: Color(0xFF0D0A1A))),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const NeonCityPainter(base: Color(0xFF000000))),
        isTrue,
      );
    });

    testWidgets('cada pantalla se monta sobre la ciudad, y nada mas',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: backdropPageTransitionsTheme,
            extensions: [cyberpunk.decor],
          ),
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      void expectOnCity(String page) {
        Finder above(Type type) => find.ancestor(
              of: find.text(page),
              matching: find.byType(type),
            );
        expect(above(NeonCityBackdrop), findsOneWidget, reason: page);
        expect(above(StarfieldBackdrop), findsNothing, reason: page);
        expect(above(PaperBackdrop), findsNothing, reason: page);
        expect(above(WastelandBackdrop), findsNothing, reason: page);
      }

      expectOnCity('inicio');

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await tester.pumpAndSettle();

      expectOnCity('segunda');
    });
  });
}
