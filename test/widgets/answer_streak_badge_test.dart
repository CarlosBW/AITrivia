import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/widgets/answer_streak_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, int streak, {String? themeId}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemes.byId(themeId ?? AppThemes.defaultId)),
        home: Scaffold(
          body: Center(child: AnswerStreakBadge(streak: streak)),
        ),
      ),
    );
  }

  testWidgets('con un solo acierto no ocupa lugar', (tester) async {
    await pump(tester, 1);

    expect(find.textContaining('×'), findsNothing);
    expect(tester.getSize(find.byType(AnswerStreakBadge)).height, 0);
  });

  testWidgets('desde dos aciertos seguidos muestra la racha', (tester) async {
    await pump(tester, 2);
    await tester.pumpAndSettle();

    expect(find.text('×2'), findsOneWidget);
  });

  testWidgets('crece con cada acierto y desaparece con un fallo',
      (tester) async {
    await pump(tester, 2);
    await pump(tester, 3);
    await tester.pumpAndSettle();
    expect(find.text('×3'), findsOneWidget);

    await pump(tester, 0);
    await tester.pumpAndSettle();
    expect(find.textContaining('×'), findsNothing);
  });

  for (final theme in AppThemes.all) {
    testWidgets('en ${theme.id} se dibuja sin errores en su racha máxima',
        (tester) async {
      await pump(tester, 10, themeId: theme.id);
      await tester.pumpAndSettle();

      expect(find.text('×10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
