import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/shop/starter_pack_card.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/economy_service.dart';

void main() {
  late int bought;

  Future<void> pump(WidgetTester tester, {bool buying = false}) {
    bought = 0;
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StarterPackCard(
              price: 'S/ 7.50',
              buying: buying,
              onBuy: () => bought++,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dice qué trae y lo vende al precio de la tienda',
      (tester) async {
    await pump(tester);

    expect(find.text('Paquete de inicio'), findsOneWidget);
    expect(
      find.text(
        '${EconomyService.starterPackCoins} monedas + '
        '${EconomyService.starterPackStreakFreezes} protectores de racha',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Comprar por S/ 7.50'));
    expect(bought, 1);
  });

  testWidgets('mientras compra no se puede volver a tocar', (tester) async {
    await pump(tester, buying: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(bought, 0);
  });

  group('starterPackOffered', () {
    test('se ofrece a una cuenta que no lo compró', () {
      expect(starterPackOffered({}), isTrue);
      expect(starterPackOffered({'starterPackBought': false}), isTrue);
    });

    test('no se ofrece a la que ya lo compró', () {
      expect(starterPackOffered({'starterPackBought': true}), isFalse);
    });
  });
}
