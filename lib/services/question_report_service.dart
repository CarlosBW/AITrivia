import 'package:cloud_functions/cloud_functions.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';
import '../l10n/localized_content.dart';
import '../l10n/user_facing_error.dart';
import 'locale_controller.dart';

/// One question as the end-of-level review shows it.
class ReviewedQuestion {
  final String text;
  final List<String> options;
  final int correctIndex;

  /// The option the player picked, or null if the time ran out.
  final int? selectedIndex;

  /// What `reportQuestion` needs to find this question on the server.
  final Map<String, dynamic> reportTarget;

  const ReviewedQuestion({
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.selectedIndex,
    required this.reportTarget,
  });
}

/// Builds the review list from a run's questions and the answers given.
///
/// [answers] holds `{questionIndex, selectedIndex}` maps, in the stored
/// option order. With [onlyAnswered] (the Daily Challenge, where a player
/// sees only some of the questions) the ones never answered are left out;
/// otherwise they show as unanswered. Malformed questions are skipped.
List<ReviewedQuestion> reviewedQuestions({
  required List<dynamic> questions,
  required List<Map<String, dynamic>> answers,
  required Map<String, dynamic> Function(int index, Map<String, dynamic> q)
      targetFor,
  bool onlyAnswered = false,
  String languageCode = 'es',
}) {
  final selectedByIndex = <int, int>{
    for (final answer in answers)
      if (answer['questionIndex'] is int && answer['selectedIndex'] is int)
        answer['questionIndex'] as int: answer['selectedIndex'] as int,
  };

  final result = <ReviewedQuestion>[];
  for (var i = 0; i < questions.length; i++) {
    final raw = questions[i];
    if (raw is! Map) continue;
    final q = Map<String, dynamic>.from(raw);

    final localized = localizedQuestion(q, languageCode);
    final text = localized.text;
    final options = localized.options;
    final correct = q['answerIndex'] ?? q['correctIndex'];
    if (text.isEmpty || options.isEmpty || correct is! num) continue;

    final selected = selectedByIndex[i];
    if (onlyAnswered && selected == null) continue;

    result.add(ReviewedQuestion(
      text: text,
      options: options,
      correctIndex: correct.toInt(),
      // A timeout is banked as -1: shown as unanswered, not as an option.
      selectedIndex:
          selected != null && selected >= 0 && selected < options.length
              ? selected
              : null,
      reportTarget: targetFor(i, q),
    ));
  }
  return result;
}

/// Sends a player's report of a bad question (Cloud Function
/// `reportQuestion`).
class QuestionReportService {
  QuestionReportService._();

  static final QuestionReportService instance = QuestionReportService._();

  /// The reasons the report sheet offers, in its order.
  static const List<String> reasons = [
    'wrong_answer',
    'confusing',
    'typo',
    'inappropriate',
    'other',
  ];

  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  Future<void> report({
    required Map<String, dynamic> target,
    required String reason,
    String details = '',
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'reportQuestion',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({
        ...target,
        'reason': reason,
        if (details.trim().isNotEmpty) 'details': details.trim(),
      });
    } catch (e) {
      throw Exception(
        userFacingError(_l10n, e, fallback: _l10n.questionReportFailed),
      );
    }
  }
}
