import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// El tema Juguetón dibuja los botones sobre un bloque sólido. Un botón
/// estirado a lo ancho dentro de una lista (como "Continuar en nivel 1" o
/// los de la tienda) recibe altura sin límite, y el bloque no sabía de qué
/// alto ser: la pantalla entera se quedaba en blanco.
void main() {
  Widget buttons() => ListView(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow),
                label: const Text('Jugar'),
              ),
              OutlinedButton(onPressed: () {}, child: const Text('Ampliar')),
              ElevatedButton(onPressed: () {}, child: const Text('Comprar')),
              TextButton(onPressed: () {}, child: const Text('Saltar')),
            ],
          ),
        ],
      );

  for (final spec in AppThemes.all) {
    testWidgets('en ${spec.id} un botón estirado en una lista se dibuja',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(spec), home: Scaffold(body: buttons())),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Jugar'), findsOneWidget);
      // Del alto de un botón, no de la pantalla.
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Jugar')).height,
        lessThan(80),
      );
    });
  }

  testWidgets('en Juguetón el bloque oscuro asoma solo bajo el botón',
      (tester) async {
    final playful = AppThemes.byId(AppThemes.playfulId);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(playful),
        home: Scaffold(body: buttons()),
      ),
    );
    final button = find.widgetWithText(FilledButton, 'Jugar');
    // El bloque es el DecoratedBox pintado con el color de la sombra; si
    // ocupa todo el botón, tapa el morado y el botón se ve negro.
    final block = find.descendant(
      of: button,
      matching: find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color ==
              playful.surfaces.shadowColor),
    );

    expect(block, findsOneWidget);
    expect(tester.getSize(block).height, playful.surfaces.buttonLip);
  });

  testWidgets('en Juguetón el botón se hunde al presionarlo sin cambiar de alto',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemes.byId(AppThemes.playfulId)),
        home: Scaffold(body: buttons()),
      ),
    );
    final button = find.widgetWithText(FilledButton, 'Jugar');
    final before = tester.getSize(button);

    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(button), before);
    await gesture.up();
  });

  // El texto quedaba pegado a la esquina superior izquierda de los botones
  // anchos: el bloque del labio dejaba al contenido tomar solo su ancho.
  testWidgets('en Juguetón el texto de un botón ancho queda centrado',
      (tester) async {
    final playful = AppThemes.byId(AppThemes.playfulId);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(playful),
        home: Scaffold(body: buttons()),
      ),
    );
    final button = find.widgetWithText(FilledButton, 'Jugar');
    final label = find.text('Jugar');
    final lip = playful.surfaces.buttonLip;

    final face = tester.getRect(button);
    final text = tester.getRect(label);
    expect(text.center.dx, closeTo(face.center.dx, 20));
    // Centrado en la cara, que es todo el botón menos el labio de abajo.
    expect(text.center.dy, closeTo(face.top + (face.height - lip) / 2, 2));
  });

  testWidgets('en Juguetón el texto baja exactamente el labio al presionar',
      (tester) async {
    final playful = AppThemes.byId(AppThemes.playfulId);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(playful),
        home: Scaffold(body: buttons()),
      ),
    );
    final label = find.text('Jugar');
    final resting = tester.getRect(label).top;

    final gesture = await tester.startGesture(tester.getCenter(label));
    await tester.pumpAndSettle();
    final pressed = tester.getRect(label).top;
    await gesture.up();

    expect(pressed - resting, playful.surfaces.buttonLip);
  });
}
