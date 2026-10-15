import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/paper_backdrop.dart';
import 'package:trivia_ia_flutter/theme/starfield_backdrop.dart';

/// Vintage es el primer tema que cambia la letra: titulares de imprenta
/// sobre papel envejecido. Lo que puede salir mal es lo de siempre — que no
/// se lea — y ademas que la letra o el papel se cuelen en los temas que no
/// los compraron.
void main() {
  final vintage = AppThemes.byId(AppThemes.vintageId);
  final scheme = vintage.colorScheme;
  final semantic = vintage.semanticColors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('el tema vintage', () {
    test('esta en el catalogo, cuesta 400 y es claro', () {
      expect(vintage.id, AppThemes.vintageId);
      expect(vintage.price, 400);
      expect(scheme.brightness, Brightness.light);
    });

    test('la tinta se lee sobre el papel y sobre las tarjetas', () {
      for (final bg in [
        vintage.scaffoldBackground,
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
        contrast(scheme.primary, vintage.scaffoldBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('acierto y error se leen sobre su tinte y sobre tarjeta', () {
      final pairs = {
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

    // Lo que se compra: letra de imprenta, papel, filete de tinta y
    // esquinas de tarjeta antigua.
    test('trae titulares serif y fondo de papel', () {
      expect(vintage.headingFace, AppHeadingFace.serif);
      expect(vintage.decor.backdrop, AppBackdrop.paper);
      expect(vintage.decor.pageColor, vintage.scaffoldBackground);
      // Y su propio juego de iconos en la barra.
      expect(vintage.decor.navIcons, AppNavIcons.vintage);
    });

    test('dibuja un filete de tinta, sin labio, y esquinas mas rectas', () {
      final surfaces = vintage.surfaces;

      expect(surfaces.overridesSurfaces, isTrue);
      expect(surfaces.hasBorder, isTrue);
      expect(surfaces.borderWidth, lessThanOrEqualTo(1.5));
      expect(surfaces.buttonLip, 0);
      expect(vintage.shapes.md, lessThan(AppShapes.standard.md));
      // Un boton redondo sigue siendo redondo.
      expect(vintage.shapes.pill, AppShapes.standard.pill);
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameVintage, 'Vintage');
      expect(en.themeNameVintage, 'Vintage');
      expect(es.themeDescriptionVintage, isNotEmpty);
      expect(en.themeDescriptionVintage, isNot(es.themeDescriptionVintage));
    });
  });

  // La letra es nueva en el sistema de temas: ningun tema que ya estaba a
  // la venta debe cambiarla sin que nadie lo haya pedido. Apocalipsis trae
  // la suya; apocalypse_theme_test.dart la revisa.
  test('los demas temas conservan los titulares redondeados', () {
    for (final spec in AppThemes.all.where(
      (s) => s.id != AppThemes.vintageId && s.id != AppThemes.apocalypseId,
    )) {
      expect(spec.headingFace, AppHeadingFace.rounded, reason: spec.id);
    }
  });

  group('el fondo de papel', () {
    test('las motas caen dentro del lienzo', () {
      const size = Size(390, 844);
      final specks = PaperPainter.specksFor(size);

      expect(specks, isNotEmpty);
      for (final speck in specks) {
        expect(speck.center.dx, inInclusiveRange(0, size.width));
        expect(speck.center.dy, inInclusiveRange(0, size.height));
        expect(speck.radius, greaterThan(0));
      }
    });

    // Fijo: el mismo papel en cada pantalla y en cada arranque.
    test('el papel es el mismo cada vez', () {
      const size = Size(390, 844);

      expect(
        PaperPainter.specksFor(size).map((s) => s.center),
        PaperPainter.specksFor(size).map((s) => s.center),
      );
    });

    test('se pinta sin errores y no repinta si nada cambio', () {
      const painter = PaperPainter(base: Color(0xFFF2E6CC));
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(390, 844));
      recorder.endRecording();

      expect(
        painter.shouldRepaint(const PaperPainter(base: Color(0xFFF2E6CC))),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const PaperPainter(base: Color(0xFFFFFFFF))),
        isTrue,
      );
    });

    // Como el cielo de Espacio: cada pantalla trae su propio papel debajo,
    // y no el de otro tema.
    testWidgets('cada pantalla se monta sobre el papel, no sobre estrellas',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: backdropPageTransitionsTheme,
            extensions: [vintage.decor],
          ),
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      void expectOnPaper(String page) {
        expect(
          find.ancestor(
            of: find.text(page),
            matching: find.byType(PaperBackdrop),
          ),
          findsOneWidget,
          reason: page,
        );
        expect(
          find.ancestor(
            of: find.text(page),
            matching: find.byType(StarfieldBackdrop),
          ),
          findsNothing,
          reason: page,
        );
      }

      expectOnPaper('inicio');

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await tester.pumpAndSettle();

      expectOnPaper('segunda');
    });
  });
}
