import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';
import 'package:trivia_ia_flutter/features/onboarding/username_picker_screen.dart';

void main() {
  group('usernameFormatError', () {
    test('accepts a valid username', () {
      expect(usernameFormatError('Trivia_Fan42'), isNull);
    });

    test('accepts the minimum length (3 chars)', () {
      expect(usernameFormatError('abc'), isNull);
    });

    test('accepts the maximum length (20 chars)', () {
      expect(usernameFormatError('a' * 20), isNull);
    });

    test('rejects usernames shorter than 3 characters', () {
      expect(usernameFormatError('ab'), 'length');
    });

    test('rejects usernames longer than 20 characters', () {
      expect(usernameFormatError('a' * 21), 'length');
    });

    test('rejects spaces and symbols', () {
      expect(usernameFormatError('bad name'), 'chars');
      expect(usernameFormatError('bad-name!'), 'chars');
    });
  });

  // Quien cambia de teléfono llega a esta pantalla con su nombre de
  // siempre ya ocupado — por su propia cuenta. La salida es recuperar la
  // cuenta, y tiene que verse sin buscarla.
  group('recuperar la cuenta desde la primera pantalla', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: UsernamePickerScreen(onSubmit: (_) async {}),
          ),
        );

    testWidgets('se ofrece como un botón, con la pregunta que lo explica',
        (tester) async {
      await pump(tester);

      expect(find.text('¿Ya tienes una cuenta?'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Iniciar sesión'),
        findsOneWidget,
      );
    });

    // Con el campo enfocado desde el inicio, el teclado tapaba ese botón.
    testWidgets('el teclado no se abre solo y lo tapa', (tester) async {
      await pump(tester);
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse);
    });

    // 360 x 640 es el tamaño lógico de los Android pequeños de hoy. En
    // uno aún menor la pantalla se desplaza para llegar al botón.
    testWidgets('cabe entero en un teléfono pequeño', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester);

      expect(tester.takeException(), isNull);
      final button =
          find.widgetWithText(OutlinedButton, 'Iniciar sesión');
      expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(640));
    });
  });
}
