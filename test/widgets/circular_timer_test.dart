import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/widgets/circular_timer.dart';

/// El reloj circular muestra los segundos y cambia de verde a ámbar a rojo
/// a medida que se agota, igual que la pastilla a la que reemplaza.
void main() {
  Future<CircularProgressIndicator> pump(
    WidgetTester tester,
    int secondsLeft,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CircularTimer(secondsLeft: secondsLeft, totalSeconds: 20),
        ),
      ),
    );
    return tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
  }

  testWidgets('muestra los segundos que quedan', (tester) async {
    final ring = await pump(tester, 15);
    expect(find.text('15'), findsOneWidget);
    expect(ring.value, 0.75);
  });

  testWidgets('el color sigue al tiempo restante', (tester) async {
    final full = await pump(tester, 20);
    final context = tester.element(find.byType(CircularTimer));
    final colors = context.appColors;
    expect((full.valueColor as AlwaysStoppedAnimation<Color?>).value,
        colors.success);

    final half = await pump(tester, 8);
    expect((half.valueColor as AlwaysStoppedAnimation<Color?>).value,
        colors.reward);

    final low = await pump(tester, 3);
    expect((low.valueColor as AlwaysStoppedAnimation<Color?>).value,
        colors.danger);
  });

  testWidgets('sin duración no divide entre cero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CircularTimer(secondsLeft: 0, totalSeconds: 0),
        ),
      ),
    );
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, 0);
  });
}
