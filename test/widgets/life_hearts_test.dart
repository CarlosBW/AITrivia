import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/life_service.dart';
import 'package:trivia_ia_flutter/widgets/life_hearts.dart';

/// The hearts replaced a precise "8/10 lives", so what matters is that the
/// row still says the same thing: one heart per life, halves included —
/// a wrong answer costs half a life, and a row that couldn't show that
/// would sit unchanged through one and read as a bug.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int units,
    required int max,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeHearts(
            lifeUnits: units,
            maxLifeUnits: max,
            color: const Color(0xFFFF6B5B),
          ),
        ),
      ),
    );
  }

  // Un icono lleno por corazon con algo de relleno, y el contorno siempre.
  int filled(WidgetTester tester) =>
      tester.widgetList(find.byIcon(Icons.favorite)).length;
  int outlines(WidgetTester tester) =>
      tester.widgetList(find.byIcon(Icons.favorite_border)).length;

  testWidgets('dibuja un corazon por vida, no por unidad', (tester) async {
    await pump(tester, units: 20, max: 20);

    expect(outlines(tester), 10);
    expect(filled(tester), 10);
  });

  testWidgets('el corazon del final queda a medias con media vida',
      (tester) async {
    // 15 unidades = 7 vidas y media.
    await pump(tester, units: 15, max: 20);

    expect(outlines(tester), 10);
    // Siete llenos mas el que esta a la mitad.
    expect(filled(tester), 8);
  });

  testWidgets('sin vidas no dibuja ningun corazon lleno', (tester) async {
    await pump(tester, units: 0, max: 20);

    expect(outlines(tester), 10);
    expect(filled(tester), 0);
  });

  testWidgets('el numero de corazones sigue al maximo, no a una constante',
      (tester) async {
    // Si el balance vuelve a moverse —ya paso de 5 a 10 vidas una vez— la
    // fila tiene que seguirlo sola.
    await pump(tester, units: 10, max: 10);

    expect(outlines(tester), 5);
  });

  testWidgets('recorta unidades fuera de rango en vez de desbordarse',
      (tester) async {
    await pump(tester, units: 99, max: 20);

    expect(filled(tester), 10);
  });

  testWidgets('conserva la cifra exacta para lectores de pantalla',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, units: 15, max: 20);

    expect(find.bySemanticsLabel('7.5/10'), findsOneWidget);

    handle.dispose();
  });

  test('la fila cubre exactamente las vidas que da el servicio', () {
    // El widget divide por `unitsPerLife`; si esa constante cambiara sin
    // que el widget se entere, la fila mostraria otra cosa que el resto de
    // la app.
    expect(LifeService.unitsPerLife, 2);
    expect(
      LifeService.instance.formatLives(LifeService.defaultMaxLifeUnits),
      '10',
    );
  });
}
