import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/theme/paper_backdrop.dart';
import 'package:trivia_ia_flutter/theme/starfield_backdrop.dart';
import 'package:trivia_ia_flutter/theme/wasteland_backdrop.dart';

/// Apocalipsis trae de todo a la vez: fondo, letra e iconos propios, sobre
/// un tema oscuro. Lo que puede salir mal es lo de siempre — que no se lea —
/// y que algo de eso se cuele en los temas que no lo compraron.
void main() {
  final apocalypse = AppThemes.byId(AppThemes.apocalypseId);
  final scheme = apocalypse.colorScheme;
  final semantic = apocalypse.semanticColors;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('el tema apocalipsis', () {
    test('esta en el catalogo, cuesta 400 y es oscuro', () {
      expect(apocalypse.id, AppThemes.apocalypseId);
      expect(apocalypse.price, 400);
      expect(scheme.brightness, Brightness.dark);
    });

    test('el texto se lee sobre la pagina y sobre las tarjetas', () {
      for (final bg in [
        apocalypse.scaffoldBackground,
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
        contrast(scheme.primary, apocalypse.scaffoldBackground),
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

    // Lo que se compra: letra de esténcil, concreto agrietado e iconos de
    // sobreviviente.
    test('trae titulares de esténcil, fondo de concreto e iconos propios', () {
      expect(apocalypse.headingFace, AppHeadingFace.stencil);
      expect(apocalypse.decor.backdrop, AppBackdrop.wasteland);
      expect(apocalypse.decor.navIcons, AppNavIcons.apocalypse);
      expect(apocalypse.decor.pageColor, apocalypse.scaffoldBackground);
    });

    test('placas de metal: borde, sombra dura y esquinas casi rectas', () {
      final surfaces = apocalypse.surfaces;

      expect(surfaces.overridesSurfaces, isTrue);
      expect(surfaces.hasBorder, isTrue);
      expect(surfaces.shadowBlur, 0);
      expect(surfaces.shadowOffset, isNot(Offset.zero));
      expect(apocalypse.shapes.md, lessThan(AppShapes.standard.md));
      // Un boton redondo sigue siendo redondo.
      expect(apocalypse.shapes.pill, AppShapes.standard.pill);
    });

    test('tiene nombre y descripcion en los dos idiomas', () {
      final es = lookupAppLocalizations(const Locale('es'));
      final en = lookupAppLocalizations(const Locale('en'));

      expect(es.themeNameApocalypse, 'Apocalipsis');
      expect(en.themeNameApocalypse, 'Apocalypse');
      expect(es.themeDescriptionApocalypse, isNotEmpty);
      expect(
        en.themeDescriptionApocalypse,
        isNot(es.themeDescriptionApocalypse),
      );
    });
  });

  // La letra de esténcil es solo de este tema.
  test('ningun otro tema usa la letra de esténcil', () {
    for (final spec in AppThemes.all.where(
      (s) => s.id != AppThemes.apocalypseId,
    )) {
      expect(spec.headingFace, isNot(AppHeadingFace.stencil), reason: spec.id);
    }
  });

  group('el fondo de concreto', () {
    test('el polvo y las grietas caen dentro del lienzo', () {
      const size = Size(390, 844);
      final dust = WastelandPainter.dustFor(size);
      final cracks = WastelandPainter.cracksFor(size);

      expect(dust, isNotEmpty);
      expect(cracks, isNotEmpty);
      for (final mote in dust) {
        expect(mote.center.dx, inInclusiveRange(0, size.width));
        expect(mote.center.dy, inInclusiveRange(0, size.height));
        expect(mote.radius, greaterThan(0));
      }
      for (final crack in cracks) {
        expect(crack.length, greaterThanOrEqualTo(2));
        for (final point in crack) {
          expect(point.dx, inInclusiveRange(0, size.width));
          expect(point.dy, inInclusiveRange(0, size.height));
        }
      }
    });

    // Como en Vintage: la franja de arriba, donde va la barra de titulo en
    // color liso, no lleva grietas que terminen cortadas contra ella.
    test('ninguna grieta sube a la franja de la barra de titulo', () {
      const size = Size(390, 844);
      for (final crack in WastelandPainter.cracksFor(size)) {
        for (final point in crack) {
          expect(point.dy, greaterThanOrEqualTo(size.height * 0.15));
        }
      }
    });

    test('el concreto es el mismo cada vez', () {
      const size = Size(390, 844);

      expect(
        WastelandPainter.dustFor(size).map((m) => m.center),
        WastelandPainter.dustFor(size).map((m) => m.center),
      );
      expect(
        WastelandPainter.cracksFor(size),
        WastelandPainter.cracksFor(size),
      );
    });

    test('se pinta sin errores y no repinta si nada cambio', () {
      const painter = WastelandPainter(base: Color(0xFF1A1714));
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(390, 844));
      recorder.endRecording();

      expect(
        painter.shouldRepaint(const WastelandPainter(base: Color(0xFF1A1714))),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const WastelandPainter(base: Color(0xFF000000))),
        isTrue,
      );
    });

    testWidgets('cada pantalla se monta sobre el concreto, y nada mas',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: backdropPageTransitionsTheme,
            extensions: [apocalypse.decor],
          ),
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      void expectOnConcrete(String page) {
        Finder above(Type type) => find.ancestor(
              of: find.text(page),
              matching: find.byType(type),
            );
        expect(above(WastelandBackdrop), findsOneWidget, reason: page);
        expect(above(StarfieldBackdrop), findsNothing, reason: page);
        expect(above(PaperBackdrop), findsNothing, reason: page);
      }

      expectOnConcrete('inicio');

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('segunda')),
        ),
      );
      await tester.pumpAndSettle();

      expectOnConcrete('segunda');
    });
  });
}
