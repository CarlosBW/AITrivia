import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/widgets/segmented_progress.dart';

/// Un segmento por pregunta: verde si se acertó, rojo si no, el actual en
/// el color de marca y los que faltan en gris.
void main() {
  Future<List<Color?>> segmentColors(
    WidgetTester tester, {
    required List<bool?> results,
    required int current,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SegmentedProgress(results: results, current: current),
        ),
      ),
    );
    return [
      for (var i = 0; i < results.length; i++)
        ((tester.widget<AnimatedContainer>(
          find.byKey(ValueKey('segment_$i')),
        ).decoration) as BoxDecoration)
            .color,
    ];
  }

  testWidgets('pinta cada segmento según su resultado', (tester) async {
    final colors = await segmentColors(
      tester,
      results: [true, false, null, null],
      current: 2,
    );
    final context = tester.element(find.byType(SegmentedProgress));
    final scheme = Theme.of(context).colorScheme;

    expect(colors[0], context.appColors.success);
    expect(colors[1], context.appColors.danger);
    expect(colors[2], scheme.primary);
    expect(colors[3], scheme.surfaceContainerHighest);
  });

  testWidgets('sin preguntas no dibuja nada', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SegmentedProgress(results: [], current: 0)),
      ),
    );
    expect(find.byType(AnimatedContainer), findsNothing);
  });
}
