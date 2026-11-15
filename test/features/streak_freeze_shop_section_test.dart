import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/shop/streak_freeze_shop_section.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/economy_service.dart';

void main() {
  late int bought;

  Future<void> pump(
    WidgetTester tester, {
    required int held,
    int coins = 100,
    bool buying = false,
  }) {
    bought = 0;
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StreakFreezeShopSection(
              held: held,
              coins: coins,
              buying: buying,
              onBuy: () => bought++,
            ),
          ),
        ),
      ),
    );
  }

  Finder buyButton() => find.ancestor(
        of: find.text('${EconomyService.streakFreezeCost}'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );

  testWidgets('dice cuántos tiene y ofrece comprar otro, con su precio',
      (tester) async {
    await pump(tester, held: 1);

    expect(
      find.text('Tienes 1 de ${EconomyService.maxStreakFreezes}'),
      findsOneWidget,
    );
    await tester.tap(buyButton());
    expect(bought, 1);
  });

  testWidgets('con el máximo ya no deja comprar', (tester) async {
    await pump(tester, held: EconomyService.maxStreakFreezes);

    expect(buyButton(), findsNothing);
    expect(find.textContaining('Ya tienes el máximo'), findsOneWidget);
  });

  testWidgets('por encima del máximo no dice "4 de 2"', (tester) async {
    await pump(tester, held: 4);

    expect(find.text('Tienes 4 de 4'), findsOneWidget);
    expect(buyButton(), findsNothing);
  });

  testWidgets('sin monedas suficientes el botón sigue ahí, para avisarlo',
      (tester) async {
    await pump(tester, held: 0, coins: 3);

    await tester.tap(buyButton());
    expect(bought, 1);
  });

  testWidgets('mientras compra no hay botón que volver a tocar',
      (tester) async {
    await pump(tester, held: 0, buying: true);

    expect(buyButton(), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
