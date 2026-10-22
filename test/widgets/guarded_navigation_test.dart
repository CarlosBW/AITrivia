import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/widgets/guarded_navigation.dart';

/// Home opens the Daily Challenge and the Weekly League through this, and
/// waits for the screen it pushed to be closed. The 12 seconds were meant
/// for the loading before the push, but they kept counting on the screen
/// itself: every player got "the action took too long" twelve seconds into
/// a challenge that was going fine — and got it as "TimeoutLa acción tardó
/// demasiado.", the exception's own name glued to the message.
void main() {
  const message = 'La acción tardó demasiado.';

  Future<void> pumpHome(
    WidgetTester tester,
    Future<void> Function(BuildContext context) action,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        // The failure message is looked up in the player's language.
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => runGuardedNavigation(
                context,
                () => action(context),
                timeoutMessage: message,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('avisa, con el mensaje limpio, si la carga se cuelga',
      (tester) async {
    // Nunca termina y nunca abre nada: un cuelgue de verdad.
    await pumpHome(tester, (_) => Completer<void>().future);

    await tester.tap(find.text('abrir'));
    await tester.pump(const Duration(seconds: 13));
    await tester.pump();

    expect(find.text(message), findsOneWidget);
  });

  testWidgets('no avisa mientras el jugador esta en la pantalla que se abrio',
      (tester) async {
    await pumpHome(
      tester,
      (context) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('reto en curso')),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('reto en curso'), findsOneWidget);

    await tester.pump(const Duration(seconds: 13));
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('un fallo de la accion se muestra sin el prefijo de excepcion',
      (tester) async {
    await pumpHome(tester, (_) async => throw Exception('Sin conexión.'));

    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sin conexión.'), findsOneWidget);
  });
}
