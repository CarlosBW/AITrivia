import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/ai_topics/ai_topic_promo_dialog.dart';
import 'package:trivia_ia_flutter/features/weekly/weekly_reward_tile.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
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
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  WeeklyRewardTile tile(WeeklyRewardState state, {VoidCallback? onClaim}) =>
      WeeklyRewardTile(
        emblem: const Icon(Icons.monetization_on_rounded),
        title: '25 respuestas correctas: +200 monedas',
        progressLabel: '12 / 25 respuestas correctas',
        progress: 12 / 25,
        state: state,
        claimLabel: 'Reclamar',
        claimedLabel: 'Reclamada',
        onClaim: onClaim,
      );

  group('weeklyRewardState', () {
    test('bloqueada hasta llegar al objetivo', () {
      expect(
        weeklyRewardState(correctAnswers: 24, threshold: 25, claimed: false),
        WeeklyRewardState.locked,
      );
    });

    test('lista al llegar', () {
      expect(
        weeklyRewardState(correctAnswers: 25, threshold: 25, claimed: false),
        WeeklyRewardState.ready,
      );
    });

    test('reclamada manda sobre todo lo demás', () {
      expect(
        weeklyRewardState(correctAnswers: 90, threshold: 25, claimed: true),
        WeeklyRewardState.claimed,
      );
    });
  });

  testWidgets('bloqueada: muestra el progreso y ningún botón', (tester) async {
    await pump(tester, tile(WeeklyRewardState.locked));

    expect(find.text('12 / 25 respuestas correctas'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('Reclamar'), findsNothing);
  });

  testWidgets('lista: el botón reclama', (tester) async {
    var claimed = 0;
    await pump(tester, tile(WeeklyRewardState.ready, onClaim: () => claimed++));

    await tester.tap(find.text('Reclamar'));
    expect(claimed, 1);
  });

  testWidgets('reclamada: lo dice y ya no ofrece reclamar', (tester) async {
    await pump(tester, tile(WeeklyRewardState.claimed));

    expect(find.text('Reclamada'), findsOneWidget);
    expect(find.text('Reclamar'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('cabe en todos los temas sin desbordar', (tester) async {
    for (final theme in AppThemes.all) {
      await pump(tester, tile(WeeklyRewardState.ready), themeId: theme.id);
      expect(tester.takeException(), isNull, reason: theme.id);
    }
  });

  // El recordatorio de temas personalizados.
  group('AiTopicPromoDialog', () {
    testWidgets('dice qué es y dónde está', (tester) async {
      await pump(
        tester,
        AiTopicPromoDialog(onCreate: () {}, onLater: () {}),
      );

      expect(find.text('Crea tu propio tema'), findsOneWidget);
      expect(find.textContaining('Inicio'), findsOneWidget);
      expect(find.textContaining('Tema personalizado'), findsOneWidget);
    });

    testWidgets('los dos botones llaman a lo suyo', (tester) async {
      var created = 0;
      var later = 0;
      await pump(
        tester,
        AiTopicPromoDialog(
          onCreate: () => created++,
          onLater: () => later++,
        ),
      );

      await tester.tap(find.text('Crear un tema'));
      await tester.tap(find.text('Ahora no'));
      expect(created, 1);
      expect(later, 1);
    });

    testWidgets('con un tema gratis, lo anuncia', (tester) async {
      await pump(
        tester,
        AiTopicPromoDialog(onCreate: () {}, onLater: () {}, freePasses: 1),
      );
      expect(find.text('1 tema gratis'), findsOneWidget);
    });

    testWidgets('sin temas gratis, no promete ninguno', (tester) async {
      await pump(
        tester,
        AiTopicPromoDialog(onCreate: () {}, onLater: () {}),
      );
      expect(find.textContaining('gratis'), findsNothing);
    });

    testWidgets('cabe en todos los temas sin desbordar', (tester) async {
      for (final theme in AppThemes.all) {
        await pump(
          tester,
          AiTopicPromoDialog(onCreate: () {}, onLater: () {}, freePasses: 2),
          themeId: theme.id,
        );
        expect(tester.takeException(), isNull, reason: theme.id);
      }
    });
  });
}
