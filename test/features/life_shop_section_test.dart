import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/shop/life_shop_section.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/economy_service.dart';

/// Las vidas solo se podían comprar desde el aviso de "sin vidas", así que
/// nadie sabía que se podía. La tienda ahora las ofrece siempre.
void main() {
  late int bought;

  Future<void> pump(
    WidgetTester tester, {
    required int lifeUnits,
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
            child: LifeShopSection(
              lifeUnits: lifeUnits,
              maxLifeUnits: 20,
              coins: coins,
              countdownText: '01:30',
              buying: buying,
              onBuy: () => bought++,
            ),
          ),
        ),
      ),
    );
  }

  Finder buyButton() => find.ancestor(
        of: find.text('+1 vida'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );

  testWidgets('con vidas por llenar ofrece comprar una, con su precio',
      (tester) async {
    await pump(tester, lifeUnits: 6);

    expect(find.text('+1 vida'), findsOneWidget);
    expect(find.text('${EconomyService.buyFullLifeCost}'), findsOneWidget);

    await tester.tap(buyButton());
    expect(bought, 1);
  });

  testWidgets('con las vidas al máximo no deja comprar', (tester) async {
    await pump(tester, lifeUnits: 20);

    expect(find.text('+1 vida'), findsNothing);
    expect(find.text('Vidas al máximo'), findsWidgets);
  });

  testWidgets('sin monedas suficientes el botón sigue ahí, para avisarlo',
      (tester) async {
    await pump(tester, lifeUnits: 6, coins: 3);

    await tester.tap(buyButton());
    expect(bought, 1);
  });

  testWidgets('mientras compra no acepta otro toque', (tester) async {
    await pump(tester, lifeUnits: 6, buying: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('+1 vida'), findsNothing);
  });
}
