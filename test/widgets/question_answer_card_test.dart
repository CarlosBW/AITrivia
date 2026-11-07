import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/widgets/question_answer_card.dart';

/// Mientras el servidor juzga la respuesta, la opción tocada lo muestra:
/// sin esa señal, una respuesta lenta parecía un toque perdido y el jugador
/// tocaba una y otra vez.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    int? selectedIndex,
    bool locked = false,
    bool pending = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionAnswerCard(
              qText: '¿Pregunta?',
              options: const ['Uno', 'Dos', 'Tres', 'Cuatro'],
              answerIndex: locked ? 2 : -1,
              selectedIndex: selectedIndex,
              locked: locked,
              pending: pending,
              onTapAnswer: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  Finder spinnerIn(String option) => find.descendant(
        of: find.ancestor(
          of: find.text(option),
          matching: find.byType(InkWell),
        ),
        matching: find.byType(CircularProgressIndicator),
      );

  testWidgets('la opción tocada muestra que espera el veredicto',
      (tester) async {
    await pump(tester, selectedIndex: 1, pending: true);

    expect(spinnerIn('Dos'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('sin respuesta pendiente no hay indicador', (tester) async {
    await pump(tester, selectedIndex: 1);

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('con el veredicto el indicador da paso al resultado',
      (tester) async {
    await pump(tester, selectedIndex: 1, locked: true, pending: true);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  // En los temas con sombra sólida, como Juguetón, el tinte de acierto y
  // de error era semitransparente y dejaba ver la sombra de tinta de debajo:
  // la opción quedaba casi negra y su texto no se leía.
  testWidgets('acierto y error se pintan opacos sobre una sombra solida',
      (tester) async {
    final playful = AppThemes.byId(AppThemes.playfulId);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: playful.colorScheme,
          extensions: [
            playful.semanticColors,
            playful.shapes,
            playful.surfaces,
          ],
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionAnswerCard(
              qText: '¿Pregunta?',
              options: const ['Uno', 'Dos', 'Tres', 'Cuatro'],
              answerIndex: 1,
              selectedIndex: 0,
              locked: true,
              onTapAnswer: (_) {},
            ),
          ),
        ),
      ),
    );

    for (final option in ['Uno', 'Dos']) {
      final box = tester.widget<AnimatedContainer>(find.ancestor(
        of: find.text(option),
        matching: find.byType(AnimatedContainer),
      ));
      final fill = (box.decoration! as BoxDecoration).color!;
      expect(fill.a, 1.0, reason: option);
    }
  });
}
