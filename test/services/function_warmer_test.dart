import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/function_warmer.dart';

void main() {
  final now = DateTime(2026, 11, 15, 12);

  group('shouldWarm', () {
    test('una función que nunca se calentó, se calienta', () {
      expect(shouldWarm(null, now), isTrue);
    });

    test('una recién calentada no se vuelve a pedir', () {
      expect(
        shouldWarm(now.subtract(const Duration(seconds: 30)), now),
        isFalse,
      );
    });

    test('pasado el plazo, la instancia puede haberse ido: se pide otra vez',
        () {
      expect(
        shouldWarm(now.subtract(FunctionWarmer.rewarmAfter), now),
        isTrue,
      );
      expect(
        shouldWarm(now.subtract(const Duration(minutes: 30)), now),
        isTrue,
      );
    });
  });

  test('sin Firebase no lanza: calentar nunca rompe una pantalla', () {
    expect(
      () => FunctionWarmer.instance.warm(['answerDailyQuestion']),
      returnsNormally,
    );
  });

  // El aviso solo es seguro en funciones que lo reconocen. Una que no lo
  // hiciera ejecutaría su trabajo de verdad con datos vacíos:
  // consumeLevelEntryLife, por ejemplo, cobraría una vida.
  group('cada función que la app calienta reconoce el aviso en el servidor',
      () {
    final server = File('functions/src/index.ts').readAsStringSync();
    final warmed = <String>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final call
          in RegExp(r'FunctionWarmer\.instance\.warm\(\s*(?:const\s*)?\[([^\]]*)\]')
              .allMatches(source)) {
        warmed.addAll(
          RegExp(r"'(\w+)'").allMatches(call.group(1)!).map((m) => m.group(1)!),
        );
      }
    }

    test('la app calienta al menos las de responder', () {
      expect(
        warmed,
        containsAll(['answerDailyQuestion', 'answerSoloQuestion']),
      );
    });

    for (final name in warmed) {
      test(name, () {
        final start = server.indexOf('export const $name = onCall(');
        expect(start, isNonNegative, reason: 'no existe en index.ts');
        final head = server.substring(start, start + 700);
        expect(
          head,
          contains('if (await warmedUp(request.data, uid)) return'),
          reason: '$name no responde al aviso de calentamiento',
        );
      });
    }
  });
}
