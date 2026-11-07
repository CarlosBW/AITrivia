import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/social/friends_screen.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';

/// La fila de un amigo en un iPhone: el puntaje del día más el botón de
/// retar no cabían en la altura fija de un ListTile y el botón se salía de
/// la tarjeta.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double width,
    bool online = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: FriendTile(
                actionsUid: 'u1',
                player: const {},
                title: 'CarlosBW1990_con_un_nombre_largo',
                subtitle: 'Visto por última vez hace 7 horas',
                statusColor: Colors.grey,
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Hoy: 265 pts'),
                    const SizedBox(height: 4),
                    FriendChallengeButton(online: online, onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // "Async only" no le decía nada a nadie: el botón dice qué hace y, si el
  // amigo no está conectado, qué va a pasar.
  testWidgets('desconectado, explica que jugará al conectarse',
      (tester) async {
    await pump(tester, width: 390);
    expect(find.text('Retar'), findsOneWidget);
    expect(find.text('Jugará cuando se conecte'), findsOneWidget);
  });

  testWidgets('conectado, el reto es en vivo y no necesita explicación',
      (tester) async {
    await pump(tester, width: 390, online: true);
    expect(find.text('Retar'), findsOneWidget);
    expect(find.text('Jugará cuando se conecte'), findsNothing);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('cabe en un teléfono de ${width.toInt()} px', (tester) async {
      await pump(tester, width: width);

      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(Card));
      final button = tester.getRect(find.byType(FilledButton));
      expect(card.contains(button.topLeft), isTrue);
      expect(card.contains(button.bottomRight - const Offset(1, 1)), isTrue);
    });
  }
}
