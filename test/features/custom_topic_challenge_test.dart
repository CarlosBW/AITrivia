import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/versus/friend_challenge_setup_screen.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/services/match_service.dart';
import 'package:trivia_ia_flutter/widgets/category_name_builder.dart';

/// Un reto por turnos puede usar uno de tus temas personalizados. En el
/// selector de categoría van junto a los fijos, con su propio prefijo.
void main() {
  group('customTopicIdFrom', () {
    test('un tema personalizado da su id', () {
      expect(customTopicIdFrom(customTopicOptionValue('abc')), 'abc');
    });

    test('una categoría fija o aleatoria no es un tema personalizado', () {
      expect(customTopicIdFrom('cine'), isNull);
      expect(customTopicIdFrom('random'), isNull);
      expect(customTopicIdFrom(customTopicOptionValue('')), isNull);
    });
  });

  // El reto guarda el título del tema: no está en fixed_categories, así que
  // buscarlo ahí mostraba "custom".
  testWidgets('un reto de tema personalizado muestra su título',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CategoryNameBuilder(
            categoryId: 'custom',
            customTitle: 'Dinosaurios',
            builder: (context, name) => Text(name),
          ),
        ),
      ),
    );

    expect(find.text('Dinosaurios'), findsOneWidget);
  });

  test('la app espera mas que el servidor al preparar un reto personalizado',
      () {
    // createAsyncPvpMatch puede tardar hasta 240 s (CUSTOM_CHALLENGE_
    // TIMEOUT_SECONDS). Rendirse antes mostraba un error aunque el reto se
    // creaba y se cobraba, y reintentar creaba otro.
    expect(
      MatchService.customChallengeTimeout,
      greaterThan(const Duration(seconds: 240)),
    );
  });
}
