import 'package:flutter_test/flutter_test.dart';
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
}
