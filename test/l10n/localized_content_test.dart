import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/l10n/localized_content.dart';

// The bank is in Spanish with an English version alongside; a player in
// English must get English where it exists and never a mismatched set of
// options.
void main() {
  final question = <String, dynamic>{
    'q': '¿Capital de Perú?',
    'options': ['Lima', 'Cusco', 'Arequipa'],
    'answerIndex': 0,
    'q_en': "What is Peru's capital?",
    'options_en': ['Lima', 'Cusco', 'Arequipa'],
  };

  group('localizedQuestion', () {
    test('en inglés usa la versión en inglés', () {
      final q = localizedQuestion(question, 'en');
      expect(q.text, "What is Peru's capital?");
      expect(q.options, ['Lima', 'Cusco', 'Arequipa']);
    });

    test('en español usa el original', () {
      expect(localizedQuestion(question, 'es').text, '¿Capital de Perú?');
    });

    test('sin traducción, el inglés cae al español', () {
      final q = localizedQuestion(
        {'q': '¿Hola?', 'options': ['a', 'b'], 'answerIndex': 0},
        'en',
      );
      expect(q.text, '¿Hola?');
      expect(q.options, ['a', 'b']);
    });

    test('una traducción con otras opciones no se usa', () {
      final q = localizedQuestion({
        ...question,
        'options_en': ['Lima', 'Cusco'],
      }, 'en');
      expect(q.text, '¿Capital de Perú?',
          reason: 'la respuesta podría quedar bajo otro texto');
    });
  });

  group('localizedCategoryName', () {
    test('usa el nombre del idioma y si no, el original', () {
      final cat = {'name': 'Ciencia', 'name_en': 'Science'};
      expect(localizedCategoryName(cat, 'en'), 'Science');
      expect(localizedCategoryName(cat, 'es'), 'Ciencia');
      expect(localizedCategoryName({'name': 'Arte'}, 'en'), 'Arte');
      expect(localizedCategoryName(null, 'en'), isNull);
      expect(localizedCategoryName({'name': ''}, 'en'), isNull);
    });
  });
}
