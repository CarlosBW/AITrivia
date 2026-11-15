import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/widgets/coins_earned_celebration.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    int coins, {
    bool lives = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => lives
                  ? showLivesEarned(context, coins)
                  : showCoinsEarned(context, coins),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    // Past the pop-in, short of the moment it closes by itself.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('dice cuántas monedas se ganaron', (tester) async {
    await open(tester, 15);

    expect(find.text('¡Ganaste!'), findsOneWidget);
    expect(find.text('+15 monedas'), findsOneWidget);

    await tester.pump(coinsEarnedCelebrationTime);
    await tester.pumpAndSettle();
  });

  testWidgets('se cierra sola, sin que el jugador tenga que tocar nada',
      (tester) async {
    await open(tester, 15);

    await tester.pump(coinsEarnedCelebrationTime);
    await tester.pumpAndSettle();

    expect(find.text('+15 monedas'), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('un toque la cierra antes', (tester) async {
    await open(tester, 30);

    await tester.tap(find.text('+30 monedas'));
    await tester.pumpAndSettle();

    expect(find.text('+30 monedas'), findsNothing);
    // Its timer went with it: nothing left to fire on a closed dialog.
    await tester.pump(coinsEarnedCelebrationTime);
    expect(tester.takeException(), isNull);
  });

  // Las vidas se cuentan en medias vidas: seis unidades son tres vidas.
  testWidgets('las vidas de un anuncio se dicen en vidas, no en unidades',
      (tester) async {
    await open(tester, 6, lives: true);

    expect(find.text('+3 vidas'), findsOneWidget);

    await tester.pump(coinsEarnedCelebrationTime);
    await tester.pumpAndSettle();
  });

  testWidgets('si solo cabía una vida, dice una', (tester) async {
    await open(tester, 2, lives: true);

    expect(find.text('+1 vida'), findsOneWidget);

    await tester.pump(coinsEarnedCelebrationTime);
    await tester.pumpAndSettle();
  });

  test('la ilustración de las vidas existe', () {
    expect(File('assets/illustrations/hearts.png').existsSync(), isTrue);
  });
}
