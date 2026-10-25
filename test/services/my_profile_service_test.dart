import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/my_profile_service.dart';

/// `withLatest` is what lets a screen opened after the profile's first
/// snapshot still show the avatar: the shared stream is a broadcast one,
/// which doesn't replay what it already emitted.
void main() {
  group('withLatest', () {
    test('un oyente tardío recibe primero el último valor', () async {
      final shared = StreamController<String>.broadcast();
      final seen = <String>[];

      final sub = withLatest(shared.stream, 'perfil v1').listen(seen.add);
      shared.add('perfil v2');
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['perfil v1', 'perfil v2']);
      await sub.cancel();
      await shared.close();
    });

    test('sin valor previo solo pasa lo que llega después', () async {
      final shared = StreamController<String>.broadcast();
      final seen = <String>[];

      final sub = withLatest<String>(shared.stream, null).listen(seen.add);
      shared.add('perfil v1');
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['perfil v1']);
      await sub.cancel();
      await shared.close();
    });

    test('cancelar deja de escuchar el stream compartido', () async {
      final shared = StreamController<String>.broadcast();

      final sub = withLatest(shared.stream, 'perfil v1').listen((_) {});
      expect(shared.hasListener, isTrue);

      await sub.cancel();
      expect(shared.hasListener, isFalse);
      await shared.close();
    });

    test('pasa los errores al oyente', () async {
      final shared = StreamController<String>.broadcast();
      final errors = <Object>[];

      final sub = withLatest<String>(shared.stream, null)
          .listen((_) {}, onError: errors.add);
      shared.addError(StateError('sin permiso'));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      await sub.cancel();
      await shared.close();
    });
  });
}
