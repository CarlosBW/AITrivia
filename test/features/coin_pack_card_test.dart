import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/shop/coin_pack_card.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/economy_service.dart';

void main() {
  group('coinPackBonusPercent', () {
    test('el paquete base no trae extra', () {
      expect(
        coinPackBonusPercent(
          coins: 100,
          price: 0.99,
          baseCoins: 100,
          basePrice: 0.99,
        ),
        0,
      );
    });

    test('redondea hacia abajo: no promete más de lo que da', () {
      // 600 por 4,99 contra 100 por 0,99: 19,04 % más monedas por dólar.
      expect(
        coinPackBonusPercent(
          coins: 600,
          price: 4.99,
          baseCoins: 100,
          basePrice: 0.99,
        ),
        19,
      );
    });

    test('un 20 % exacto se muestra como 20, no como 19', () {
      expect(
        coinPackBonusPercent(
          coins: 120,
          price: 1,
          baseCoins: 100,
          basePrice: 1,
        ),
        20,
      );
    });

    test('un paquete peor que el base no muestra un extra negativo', () {
      expect(
        coinPackBonusPercent(
          coins: 100,
          price: 2,
          baseCoins: 100,
          basePrice: 1,
        ),
        0,
      );
    });

    test('con un precio que no sirve no hay extra que calcular', () {
      expect(
        coinPackBonusPercent(
          coins: 600,
          price: 0,
          baseCoins: 100,
          basePrice: 0.99,
        ),
        0,
      );
      expect(
        coinPackBonusPercent(
          coins: 600,
          price: 4.99,
          baseCoins: 100,
          basePrice: 0,
        ),
        0,
      );
    });

    test('con los precios de lista, cada paquete rinde más que el anterior',
        () {
      const packs = EconomyService.coinPacks;
      final bonuses = [
        for (final pack in packs)
          coinPackBonusPercent(
            coins: pack.coins,
            price: pack.usd,
            baseCoins: packs.first.coins,
            basePrice: packs.first.usd,
          ),
      ];
      for (var i = 1; i < bonuses.length; i++) {
        expect(bonuses[i], greaterThan(bonuses[i - 1]));
      }
    });
  });

  group('coinPackIllustration', () {
    test('cada paquete de la tienda tiene su ilustración, y el archivo existe',
        () {
      final seen = <String>{};
      for (final pack in EconomyService.coinPacks) {
        final asset = coinPackIllustration(pack.id);
        expect(File(asset).existsSync(), isTrue, reason: asset);
        expect(seen.add(asset), isTrue, reason: 'repetida: $asset');
      }
    });

    test('un paquete desconocido cae en las monedas genéricas', () {
      expect(
        coinPackIllustration('coins_pack_nuevo'),
        'assets/illustrations/coins.png',
      );
    });

    test('la del paquete de inicio existe', () {
      expect(
        File('assets/illustrations/starter_pack.png').existsSync(),
        isTrue,
      );
    });
  });

  group('CoinPackCard', () {
    late int bought;

    Future<void> pump(
      WidgetTester tester, {
      int bonusPercent = 0,
      bool bestValue = false,
      int aiTopics = 0,
      bool buying = false,
    }) {
      bought = 0;
      return tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: CoinPackCard(
                  illustration: 'assets/illustrations/chest.png',
                  coins: 1500,
                  price: 'S/ 37.90',
                  bonusPercent: bonusPercent,
                  bestValue: bestValue,
                  aiTopics: aiTopics,
                  buying: buying,
                  onBuy: () => bought++,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('muestra las monedas y vende al precio de la tienda',
        (tester) async {
      await pump(tester);

      expect(find.text('1500 monedas'), findsOneWidget);
      await tester.tap(find.text('S/ 37.90'));
      expect(bought, 1);
    });

    testWidgets('sin extra ni mejor valor no pone etiquetas', (tester) async {
      await pump(tester);

      expect(find.textContaining('%'), findsNothing);
      expect(find.text('MEJOR VALOR'), findsNothing);
      expect(find.textContaining('tema'), findsNothing);
    });

    testWidgets('dice el extra, el mejor valor y para cuántos temas alcanza',
        (tester) async {
      await pump(tester, bonusPercent: 48, bestValue: true, aiTopics: 2);

      expect(find.text('+48%'), findsOneWidget);
      expect(find.text('MEJOR VALOR'), findsOneWidget);
      expect(find.text('Alcanza para 2 temas con IA'), findsOneWidget);
    });

    testWidgets('un solo tema va en singular', (tester) async {
      await pump(tester, aiTopics: 1);

      expect(find.text('Alcanza para 1 tema con IA'), findsOneWidget);
    });

    testWidgets('mientras compra no se puede volver a tocar', (tester) async {
      await pump(tester, buying: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(bought, 0);
    });

    testWidgets('con letra grande no se desborda', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 150,
                  child: CoinPackCard(
                    illustration: 'assets/illustrations/chest_big.png',
                    coins: 4000,
                    price: 'S/ 74.90',
                    bonusPercent: 98,
                    bestValue: true,
                    aiTopics: 6,
                    buying: false,
                    onBuy: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
