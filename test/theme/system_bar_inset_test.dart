import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// En Android la barra del sistema (atrás, inicio, recientes) quedaba
/// encima de lo último de las pantallas largas, botones incluidos.
void main() {
  const barHeight = 48.0;
  const screen = Size(360, 760);

  /// Una pantalla cuyo contenido llega hasta el final, como una lista
  /// larga con su propio padding.
  Widget page(String label) => Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox()),
            SizedBox(height: 40, child: Text(label)),
          ],
        ),
      );

  Future<void> pumpApp(WidgetTester tester, String themeId) async {
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: barHeight * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: barHeight * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(AppThemes.byId(themeId)),
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => page('fin de la lista')),
                ),
                child: const Text('abrir'),
              ),
              const Expanded(child: SizedBox()),
              const SizedBox(height: 40, child: Text('fin del inicio')),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final theme in AppThemes.all) {
    testWidgets(
        'en ${theme.id} una pantalla abierta termina encima de la barra',
        (tester) async {
      await pumpApp(tester, theme.id);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(find.text('fin de la lista')).dy,
        lessThanOrEqualTo(screen.height - barHeight),
      );
      expect(tester.takeException(), isNull);
    });
  }

  // La primera ruta es el contenedor de pestañas: su barra inferior ya se
  // extiende bajo la del sistema, con su propio color.
  testWidgets('la primera pantalla sigue llegando hasta el borde',
      (tester) async {
    await pumpApp(tester, AppThemes.defaultId);

    expect(
      tester.getBottomLeft(find.text('fin del inicio')).dy,
      screen.height,
    );
  });
}
