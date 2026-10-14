import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// El nombre del marco equipado se escribe en el color del marco, sobre una
/// pastilla tenida de ese mismo color. Con la plata eso es gris claro sobre
/// casi blanco: "Marco de Plata" no se leia en ningun tema claro. Oro,
/// platino y diamante estaban casi igual.
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  // Los seis marcos de FrameService: bronce, plata, oro, platino, diamante
  // y master.
  const frames = {
    'bronze': Color(0xFFCD7F32),
    'silver': Color(0xFFC0C0C0),
    'gold': Color(0xFFFFD700),
    'platinum': Color(0xFF4DB6AC),
    'diamond': Color(0xFF6EC6FF),
    'master': Color(0xFF9C27B0),
  };

  group('readableInk', () {
    test('la plata se lee sobre una pastilla clara', () {
      const silver = Color(0xFFC0C0C0);
      const paleChip = Color(0xFFF7F7F7);

      // El fallo: tal cual, no llega ni a 2:1.
      expect(contrast(silver, paleChip), lessThan(2));
      expect(
        contrast(readableInk(silver, paleChip), paleChip),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('cada marco se lee en cada tema', () {
      for (final spec in AppThemes.all) {
        for (final entry in frames.entries) {
          // La pastilla: el color del marco al 12% sobre la tarjeta.
          final chip = Color.alphaBlend(
            entry.value.withValues(alpha: 0.12),
            spec.colorScheme.surface,
          );

          expect(
            contrast(readableInk(entry.value, chip), chip),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} en ${spec.id}',
          );
        }
      }
    });

    test('un color que ya se lee no se toca', () {
      const master = Color(0xFF9C27B0);

      expect(readableInk(master, Colors.white), master);
    });

    test('conserva el tono: oscurece o aclara, no cambia de color', () {
      const gold = Color(0xFFFFD700);
      final onLight = HSLColor.fromColor(readableInk(gold, Colors.white));
      final onDark = HSLColor.fromColor(
        readableInk(const Color(0xFF9C27B0), const Color(0xFF211A33)),
      );

      expect(onLight.hue, closeTo(HSLColor.fromColor(gold).hue, 2));
      expect(onLight.lightness, lessThan(HSLColor.fromColor(gold).lightness));
      expect(
        onDark.lightness,
        greaterThan(HSLColor.fromColor(const Color(0xFF9C27B0)).lightness),
      );
    });
  });
}
