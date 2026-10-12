import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/life_service.dart';
import 'package:trivia_ia_flutter/widgets/life_hearts.dart';
import 'package:trivia_ia_flutter/widgets/lives_card.dart';

/// Ten hearts and "Vidas al máximo" do not fit side by side on a phone:
/// the card on Home overflowed by 25 px at 375 wide, and by more on the
/// 360-wide phones that are most of Android.
void main() {
  Future<void> pump(WidgetTester tester, {required double width}) {
    const max = LifeService.defaultMaxLifeUnits;

    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: const LivesCard(
                lifeUnits: max,
                maxLifeUnits: max,
                isFull: true,
                countdownText: '',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('cabe en el ancho que le deja Inicio en un telefono de 360',
      (tester) async {
    // Lo que queda de 360 tras los margenes de Inicio y de la tarjeta.
    await pump(tester, width: 270);

    expect(tester.takeException(), isNull);
    expect(find.text('Vidas al máximo'), findsOneWidget);
  });

  testWidgets('con espacio de sobra los corazones no se agrandan',
      (tester) async {
    await pump(tester, width: 600);

    expect(tester.takeException(), isNull);
    // 10 corazones de 18 con 2 de separacion.
    expect(tester.getSize(find.byType(LifeHearts)).width, 198);
  });
}
