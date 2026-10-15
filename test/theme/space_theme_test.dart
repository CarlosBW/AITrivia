import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/starfield_backdrop.dart';
import 'package:trivia_ia_flutter/widgets/nav_glyphs.dart';

/// Espacio es el primer tema que pinta algo detras de las pantallas y que
/// cambia iconos. Lo que puede salir mal es que no se lea, como en Noche, y
/// ademas que el fondo o los iconos se cuelen en los temas que no los
/// compraron.
void main() {
  final space = AppThemes.byId(AppThemes.spaceId);
  final scheme = space.colorScheme;
  final semantic = space.semanticColors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('el tema espacio', () {
    test('esta en el catalogo, cuesta 400 y es oscuro', () {
      expect(space.id, AppThemes.spaceId);
      expect(space.price, 400);
      expect(scheme.brightness, Brightness.dark);
    });

    test('el texto se lee sobre la pagina y sobre las tarjetas', () {
      for (final bg in [
        space.scaffoldBackground,
        scheme.surface,
        scheme.surfaceContainerHighest,
      ]) {
        expect(contrast(scheme.onSurface, bg), greaterThanOrEqualTo(4.5));
        expect(
            contrast(scheme.onSurfaceVariant, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('el color de marca se distingue como texto y como boton', () {
      expect(contrast(scheme.primary, space.scaffoldBackground),
          greaterThanOrEqualTo(3));
      expect(contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(3));
      expect(
          contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(3));
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

    // Las tarjetas de degradado llevan texto blanco en todos los temas.
    test('el texto blanco se lee sobre sus degradados', () {
      for (final stop in [
        semantic.brandGradientStart,
        semantic.brandGradientEnd,
        semantic.heroGradientStart,
        semantic.heroGradientEnd,
      ]) {
        expect(contrast(semantic.onAccent, stop), greaterThanOrEqualTo(4.5),
            reason: '$stop');
      }
    });

    // Lo que se compra: brillo en vez de sombra, sin el labio de Jugueton.
    test('dibuja un borde fino luminoso y un resplandor, no una sombra', () {
      final surfaces = space.surfaces;

      expect(surfaces.overridesSurfaces, isTrue);
      expect(surfaces.hasBorder, isTrue);
      expect(surfaces.borderWidth, lessThanOrEqualTo(1.5));
      expect(surfaces.shadowOffset, Offset.zero);
      expect(surfaces.shadowBlur, greaterThan(0));
      expect(surfaces.buttonLip, 0);
    });

    test('trae fondo de estrellas e iconos espaciales', () {
      expect(space.decor.backdrop, AppBackdrop.starfield);
      expect(space.decor.navIcons, AppNavIcons.space);
      expect(space.decor.pageColor, space.scaffoldBackground);
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameSpace, 'Espacio');
      expect(en.themeNameSpace, 'Space');
      expect(es.themeDescriptionSpace, isNotEmpty);
      expect(en.themeDescriptionSpace, isNot(es.themeDescriptionSpace));
    });
  });

  // El fondo y los iconos son nuevos en el sistema de temas. Ningun tema que
  // ya estaba a la venta debe recibirlos sin que nadie los haya pedido.
  group('los demas temas siguen como estaban', () {
    for (final spec in AppThemes.all.where((s) => s.id != AppThemes.spaceId)) {
      test(spec.id, () {
        // Vintage and the themes after it sell their own backdrop
        // and icons; their own tests check them. Nobody but Space gets the
        // stars or the space icons.
        final (backdrop, icons) = switch (spec.id) {
          AppThemes.vintageId => (AppBackdrop.paper, AppNavIcons.vintage),
          AppThemes.apocalypseId => (
              AppBackdrop.wasteland,
              AppNavIcons.apocalypse,
            ),
          AppThemes.cyberpunkId => (
              AppBackdrop.neonCity,
              AppNavIcons.cyberpunk,
            ),
          AppThemes.steampunkId => (AppBackdrop.gears, AppNavIcons.steampunk),
          AppThemes.christmasId => (
              AppBackdrop.snowfall,
              AppNavIcons.christmas,
            ),
          _ => (AppBackdrop.plain, AppNavIcons.classic),
        };
        expect(spec.decor.backdrop, backdrop);
        expect(spec.decor.navIcons, icons);
        expect(spec.decor.pageColor, spec.scaffoldBackground);
      });
    }

    test('sin la extension, el contexto cae en lo clasico', () {
      expect(AppDecor.plainOf(AppColors.pageBackground).backdrop,
          AppBackdrop.plain);
    });
  });

  group('el fondo de estrellas', () {
    test('las estrellas caen dentro del lienzo', () {
      const size = Size(390, 844);
      final stars = StarfieldPainter.starsFor(size);

      expect(stars, isNotEmpty);
      for (final star in stars) {
        expect(star.center.dx, inInclusiveRange(0, size.width));
        expect(star.center.dy, inInclusiveRange(0, size.height));
        expect(star.radius, greaterThan(0));
      }
    });

    // Fijas: el mismo cielo en cada pantalla y en cada arranque, sin que
    // las estrellas salten al navegar.
    test('el cielo es el mismo cada vez', () {
      const size = Size(390, 844);
      final a = StarfieldPainter.starsFor(size);
      final b = StarfieldPainter.starsFor(size);

      expect(a.map((s) => s.center), b.map((s) => s.center));
    });

    test('se pinta sin errores y no repinta si nada cambio', () {
      const painter = StarfieldPainter(base: Color(0xFF0B1026));
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(390, 844));
      recorder.endRecording();

      expect(
        painter.shouldRepaint(const StarfieldPainter(base: Color(0xFF0B1026))),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const StarfieldPainter(base: Color(0xFF000000))),
        isTrue,
      );
    });

    // Cada pantalla trae su propio cielo debajo: asi, durante la transicion,
    // la que entra tapa a la que sale en vez de verse una encima de otra.
    testWidgets('cada pantalla nueva se monta sobre las estrellas',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: backdropPageTransitionsTheme,
            extensions: [space.decor],
          ),
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      expect(
        find.ancestor(
          of: find.text('inicio'),
          matching: find.byType(StarfieldBackdrop),
        ),
        findsOneWidget,
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('segunda'),
          matching: find.byType(StarfieldBackdrop),
        ),
        findsOneWidget,
      );
    });
  });

  group('los iconos de la barra', () {
    for (final icons in AppNavIcons.values) {
      test('${icons.name} trae los cuatro y se pintan', () {
        final painters = navGlyphPainters(icons, Colors.white);

        expect(painters, hasLength(4));
        for (final painter in painters) {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), const Size(24, 24));
          recorder.endRecording();
        }
      });
    }

    test('los espaciales no son los clasicos', () {
      final classic = navGlyphPainters(AppNavIcons.classic, Colors.white)
          .map((p) => p.runtimeType);
      final space = navGlyphPainters(AppNavIcons.space, Colors.white)
          .map((p) => p.runtimeType);

      expect(classic.toSet().intersection(space.toSet()), isEmpty);
    });

    test('cada juego tiene sus propios dibujos', () {
      final seen = <Type>{};
      for (final icons in AppNavIcons.values) {
        for (final painter in navGlyphPainters(icons, Colors.white)) {
          expect(seen.add(painter.runtimeType), isTrue,
              reason: '${icons.name}: ${painter.runtimeType}');
        }
      }
    });
  });
}
