/// Bank content in the player's language.
///
/// The fixed bank is written in Spanish (`q`, `options`, `name`) and
/// carries an English version alongside (`q_en`, `options_en`, `name_en`).
/// The English options are in the same order as the Spanish ones, so
/// `answerIndex` — and the server's judging — is the same in both.
library;

/// The question text and options of [question] in [languageCode].
///
/// Falls back to Spanish when there is no usable English version: one
/// with a different number of options could put the right answer under
/// the wrong text.
({String text, List<String> options}) localizedQuestion(
  Map<String, dynamic> question,
  String languageCode,
) {
  final text = (question['q'] ?? question['question'] ?? '').toString();
  final options = ((question['options'] ?? question['answers']) as List? ??
          const [])
      .map((o) => o.toString())
      .toList();

  if (languageCode == 'en') {
    final textEn = (question['q_en'] ?? '').toString().trim();
    final optionsEn = (question['options_en'] as List? ?? const [])
        .map((o) => o.toString())
        .toList();
    if (textEn.isNotEmpty &&
        optionsEn.length == options.length &&
        optionsEn.every((o) => o.trim().isNotEmpty)) {
      return (text: textEn, options: optionsEn);
    }
  }

  return (text: text, options: options);
}

/// A fixed category's display name in [languageCode], or null if the doc
/// has none.
String? localizedCategoryName(
  Map<String, dynamic>? category,
  String languageCode,
) {
  if (category == null) return null;
  final localized = category['name_$languageCode'];
  if (localized is String && localized.trim().isNotEmpty) return localized;
  final name = category['name'];
  if (name is String && name.trim().isNotEmpty) return name;
  return null;
}
