import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/weekly/weekly_round_result_dialog.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// El resultado de una ronda del tema de la semana era un aviso del
/// sistema con una línea de texto.
void main() {
  Future<void> pump(
    WidgetTester tester,
    WeeklyRoundResultDialog dialog, {
    String themeId = AppThemes.defaultId,
  }) async {
    tester.view.physicalSize = const Size(360 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final spec = AppThemes.byId(themeId);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: spec.colorScheme,
        extensions: [
          const AppTypography(heading: TextStyle()),
          spec.semanticColors,
          spec.shapes,
          spec.surfaces,
          spec.decor,
        ],
      ),
      home: Scaffold(body: dialog),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el título, los aciertos y el porcentaje',
      (tester) async {
    await pump(
      tester,
      WeeklyRoundResultDialog(correct: 7, total: 10, onContinue: () {}),
    );

    expect(find.text('Ronda completada'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('/ 10'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
  });

  testWidgets('continuar y revisar llaman a lo suyo', (tester) async {
    var continued = 0;
    var reviewed = 0;
    await pump(
      tester,
      WeeklyRoundResultDialog(
        correct: 7,
        total: 10,
        onContinue: () => continued++,
        onReview: () => reviewed++,
      ),
    );

    await tester.tap(find.text('Continuar'));
    await tester.tap(find.text('Revisar preguntas'));

    expect(continued, 1);
    expect(reviewed, 1);
  });

  testWidgets('sin nada que revisar, no ofrece revisar', (tester) async {
    await pump(
      tester,
      WeeklyRoundResultDialog(correct: 0, total: 0, onContinue: () {}),
    );

    expect(find.text('Revisar preguntas'), findsNothing);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('una ronda floja no lleva destellos', (tester) async {
    await pump(
      tester,
      WeeklyRoundResultDialog(correct: 2, total: 10, onContinue: () {}),
    );
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('cabe en todos los temas sin desbordar', (tester) async {
    for (final theme in AppThemes.all) {
      await pump(
        tester,
        WeeklyRoundResultDialog(
          correct: 10,
          total: 10,
          onContinue: () {},
          onReview: () {},
        ),
        themeId: theme.id,
      );
      expect(tester.takeException(), isNull, reason: theme.id);
    }
  });
}
