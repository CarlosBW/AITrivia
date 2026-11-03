import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/widgets/nav_tour.dart';

/// El recorrido del menú inferior: ilumina un ícono, espera a que el
/// jugador lo toque, abre esa sección y la explica; así con cada pestaña.
void main() {
  late List<int> selected;
  late int finished;
  final keys = [GlobalKey(), GlobalKey()];

  Future<void> pump(WidgetTester tester) async {
    selected = [];
    finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Stack(
          children: [
            Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    for (final key in keys)
                      Expanded(child: SizedBox.expand(key: key)),
                  ],
                ),
              ),
            ),
            NavTour(
              steps: [
                NavTourStep(
                  tabIndex: 0,
                  targetKey: keys[0],
                  tabName: 'Inicio',
                  title: 'Título inicio',
                  description: 'Texto inicio',
                ),
                NavTourStep(
                  tabIndex: 3,
                  targetKey: keys[1],
                  tabName: 'Amigos',
                  title: 'Título amigos',
                  description: 'Texto amigos',
                ),
              ],
              onSelectTab: selected.add,
              onFinished: () => finished++,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  // El recorrido tapa la barra, así que el toque le llega a él y no al
  // ícono: es él quien decide si cayó sobre el ícono iluminado.
  Future<void> tapThrough(WidgetTester tester, GlobalKey key) =>
      tester.tap(find.byKey(key), warnIfMissed: false);

  testWidgets('espera el toque en el ícono y luego explica la sección',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('Inicio'), findsOneWidget);
    expect(find.text('Texto inicio'), findsNothing);

    await tapThrough(tester, keys[0]);
    await tester.pump();

    expect(selected, [0]);
    expect(find.text('Título inicio'), findsOneWidget);
    expect(find.text('Texto inicio'), findsOneWidget);
  });

  testWidgets('un toque fuera del ícono no avanza', (tester) async {
    await pump(tester);

    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    // El otro ícono tampoco: solo cuenta el que está iluminado.
    await tapThrough(tester, keys[1]);
    await tester.pump();

    expect(selected, isEmpty);
    expect(find.text('Texto inicio'), findsNothing);
  });

  testWidgets('recorre todas las pestañas y termina', (tester) async {
    await pump(tester);

    await tapThrough(tester, keys[0]);
    await tester.pump();
    await tester.tap(find.text('Siguiente'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Amigos'), findsOneWidget);
    expect(finished, 0);

    await tapThrough(tester, keys[1]);
    await tester.pump();
    expect(find.text('Texto amigos'), findsOneWidget);

    await tester.tap(find.text('¡A jugar!'));
    await tester.pump();

    expect(selected, [0, 3]);
    expect(finished, 1);
  });

  testWidgets('se puede saltar', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Saltar tutorial'));
    await tester.pump();

    expect(selected, isEmpty);
    expect(finished, 1);
  });
}
