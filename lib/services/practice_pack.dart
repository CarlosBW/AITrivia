import 'dart:convert';

/// The questions kept on the phone for practising with no connection, and
/// when they were downloaded.
///
/// Unlike every other mode, these carry their answers: offline there is no
/// server to judge them. Nothing played from a pack earns or records
/// anything (see `downloadPracticePack` in functions/src/index.ts).
class PracticePack {
  const PracticePack({required this.questions, required this.fetchedAt});

  final List<Map<String, dynamic>> questions;
  final DateTime fetchedAt;
}

/// Questions in one practice round.
const int practiceRoundSize = 10;

/// How old a pack gets before a new one is asked for.
const Duration practicePackMaxAge = Duration(hours: 24);

/// The playable questions out of what the server (or the saved pack) holds:
/// text, at least two options, and an answer that is one of them.
List<Map<String, dynamic>> parsePracticeQuestions(Object? raw) {
  if (raw is! List) return const [];

  final questions = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final question = Map<String, dynamic>.from(item);

    final text = question['q'];
    final options = question['options'];
    final answer = question['answerIndex'];
    if (text is! String || text.trim().isEmpty) continue;
    if (options is! List || options.length < 2) continue;
    if (answer is! int || answer < 0 || answer >= options.length) continue;

    questions.add(question);
  }
  return questions;
}

String encodePracticePack(PracticePack pack) => jsonEncode({
      'fetchedAt': pack.fetchedAt.millisecondsSinceEpoch,
      'questions': pack.questions,
    });

/// The saved pack, or null when there is none worth having: nothing saved,
/// something unreadable, or no playable question in it.
PracticePack? decodePracticePack(String? saved) {
  if (saved == null || saved.isEmpty) return null;
  try {
    final data = jsonDecode(saved);
    if (data is! Map) return null;
    final fetchedAt = data['fetchedAt'];
    final questions = parsePracticeQuestions(data['questions']);
    if (fetchedAt is! int || questions.isEmpty) return null;
    return PracticePack(
      questions: questions,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt),
    );
  } on FormatException {
    return null;
  }
}

/// Whether to ask the server for a new pack: there is none, or it is old.
bool shouldRefreshPracticePack(DateTime? fetchedAt, DateTime now) =>
    fetchedAt == null || now.difference(fetchedAt) >= practicePackMaxAge;

/// The next round out of [questions], starting at [cursor] and wrapping
/// round to the start, so a pack is played through before anything
/// repeats. [nextCursor] is where the round after it starts.
({List<Map<String, dynamic>> questions, int nextCursor}) practiceRound(
  List<Map<String, dynamic>> questions,
  int cursor, {
  int size = practiceRoundSize,
}) {
  if (questions.isEmpty) return (questions: const [], nextCursor: 0);

  final start = cursor < 0 ? 0 : cursor % questions.length;
  final count = size < questions.length ? size : questions.length;

  return (
    questions: [
      for (var i = 0; i < count; i++) questions[(start + i) % questions.length],
    ],
    nextCursor: (start + count) % questions.length,
  );
}
