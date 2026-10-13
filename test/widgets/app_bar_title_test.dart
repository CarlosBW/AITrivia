import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/widgets/app_bar_title.dart';

/// Casi todas las pantallas llevan en la barra el nombre y el avatar del
/// jugador, y en un telefono eso deja al titulo con medio ancho: "Weekly
/// Challenge" o "Daily Challenge" salian cortados con puntos suspensivos.
/// El titulo ahora se encoge para caber, hasta un limite.
void main() {
  const titleSize = 26.0;

  // Lo que ocupan el nombre y el avatar del jugador en la barra.
  const playerPill = SizedBox(width: 140, height: 40);

  Future<void> pump(WidgetTester tester, String title, {double width = 360}) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            titleTextStyle: TextStyle(fontSize: titleSize),
          ),
        ),
        home: Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: AppBarTitle(title),
            actions: const [playerPill],
          ),
        ),
      ),
    );
  }

  RenderParagraph paragraph(WidgetTester tester, String title) =>
      tester.renderObject<RenderParagraph>(find.text(title));

  double fontSize(WidgetTester tester, String title) =>
      tester.widget<Text>(find.text(title)).style!.fontSize!;

  testWidgets('un titulo que cabe se queda a su tamano', (tester) async {
    await pump(tester, 'Solo');

    expect(fontSize(tester, 'Solo'), titleSize);
    expect(paragraph(tester, 'Solo').didExceedMaxLines, isFalse);
  });

  testWidgets('un titulo que no cabe se encoge en vez de cortarse',
      (tester) async {
    // La fuente de los tests mide un cuadrado por letra: 7 letras a 26 son
    // 182, y junto al nombre del jugador quedan unos 148 en un telefono.
    await pump(tester, 'Niveles');

    expect(fontSize(tester, 'Niveles'), lessThan(titleSize));
    expect(paragraph(tester, 'Niveles').didExceedMaxLines, isFalse);
  });

  testWidgets('no se encoge por debajo de un tamano legible', (tester) async {
    const endless = 'Un titulo de tema de IA larguisimo que nunca cabria';
    await pump(tester, endless);

    // A partir de ahi vuelve a cortarse: ilegible es peor que incompleto.
    expect(
      fontSize(tester, endless),
      closeTo(titleSize * AppBarTitle.minScale, 0.01),
    );
    expect(paragraph(tester, endless).didExceedMaxLines, isTrue);
  });

  testWidgets('con mas ancho recupera su tamano', (tester) async {
    await pump(tester, 'Niveles', width: 600);

    expect(fontSize(tester, 'Niveles'), titleSize);
  });
}
