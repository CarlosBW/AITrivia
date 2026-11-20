import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/practice/offline_gate.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/answer_reveal.dart';

const _body = 'Hasta que vuelvas a conectarte solo puedes jugar rondas de '
    'práctica. No gastan vidas y no dan monedas, experiencia ni avance en '
    'los niveles.';

List<Map<String, dynamic>> _round() => [
      for (var i = 0; i < 2; i++)
        {
          'categoryId': 'geo',
          'q': 'Pregunta $i',
          'options': ['Buena $i', 'Mala $i'],
          'answerIndex': 0,
        },
    ];

void main() {
  test('offlineGateShown: sin conexión, o con una ronda aún abierta', () {
    expect(offlineGateShown(offline: true, practising: false), isTrue);
    expect(offlineGateShown(offline: false, practising: true), isTrue);
    expect(offlineGateShown(offline: false, practising: false), isFalse);
  });

  late ValueNotifier<bool> offline;

  Widget app({bool hasPack = true}) => MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => OfflineGate(
          offline: offline,
          hasPack: () async => hasPack,
          loadRound: () async => _round(),
          child: child!,
        ),
        home: const Scaffold(body: Text('el juego')),
      );

  setUp(() => offline = ValueNotifier<bool>(false));
  tearDown(() => offline.dispose());

  /// Lets a judged answer's pause run out.
  Future<void> afterReveal(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(
      const Duration(milliseconds: 700) + wrongAnswerExtraReveal,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('con conexión no se ve', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('el juego'), findsOneWidget);
    expect(find.text('Sin conexión'), findsNothing);
  });

  testWidgets('sin conexión avisa que solo hay práctica hasta reconectar',
      (tester) async {
    await tester.pumpWidget(app());
    offline.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión'), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
    expect(find.text('Jugar una ronda de práctica'), findsOneWidget);
  });

  testWidgets('al volver la conexión, vuelve el juego', (tester) async {
    await tester.pumpWidget(app());
    offline.value = true;
    await tester.pumpAndSettle();
    offline.value = false;
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión'), findsNothing);
    expect(find.text('el juego'), findsOneWidget);
  });

  testWidgets('sin preguntas descargadas lo dice y no ofrece jugar',
      (tester) async {
    await tester.pumpWidget(app(hasPack: false));
    offline.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Jugar una ronda de práctica'), findsNothing);
    expect(
      find.textContaining('Todavía no hay preguntas de práctica'),
      findsOneWidget,
    );
  });

  testWidgets('una ronda se juega entera sin conexión y da su resultado',
      (tester) async {
    await tester.pumpWidget(app());
    offline.value = true;
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jugar una ronda de práctica'));
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 0'), findsOneWidget);

    await tester.tap(find.text('Buena 0'));
    await afterReveal(tester);
    expect(find.text('Pregunta 1'), findsOneWidget);

    await tester.tap(find.text('Mala 1'));
    await afterReveal(tester);

    expect(find.text('Ronda terminada'), findsOneWidget);
    expect(find.text('1 de 2 correctas'), findsOneWidget);
    expect(
      find.text('La práctica no da monedas, experiencia ni avance.'),
      findsOneWidget,
    );
    expect(find.text('Otra ronda'), findsOneWidget);
  });

  testWidgets('una respuesta incorrecta se queda más que una correcta',
      (tester) async {
    await tester.pumpWidget(app());
    offline.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jugar una ronda de práctica'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mala 0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Pregunta 0'), findsOneWidget);

    await tester.pump(wrongAnswerExtraReveal);
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 1'), findsOneWidget);
  });

  testWidgets(
      'si la conexión vuelve a mitad de ronda, la ronda sigue y al salir '
      'vuelve el juego', (tester) async {
    await tester.pumpWidget(app());
    offline.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jugar una ronda de práctica'));
    await tester.pumpAndSettle();

    offline.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Pregunta 0'), findsOneWidget);

    await tester.tap(find.text('Buena 0'));
    await afterReveal(tester);
    await tester.tap(find.text('Buena 1'));
    await afterReveal(tester);

    expect(find.text('Ya tienes conexión.'), findsOneWidget);
    await tester.tap(find.text('Volver al juego'));
    await tester.pumpAndSettle();

    expect(find.text('Ronda terminada'), findsNothing);
    expect(find.text('Sin conexión'), findsNothing);
    expect(find.text('el juego'), findsOneWidget);
  });

  testWidgets('cabe en un teléfono estrecho con letra grande', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 568),
        textScaler: TextScaler.linear(1.5),
      ),
      child: app(),
    ));
    offline.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Jugar una ronda de práctica'));
    await tester.tap(find.text('Jugar una ronda de práctica'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
