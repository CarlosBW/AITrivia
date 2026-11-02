import 'package:cloud_functions/cloud_functions.dart';

import 'life_service.dart';

/// The server's verdict on one answer.
class AnswerVerdict {
  final bool correct;

  /// The right option, in the question's stored order.
  final int correctIndex;

  /// A wrong answer took life.
  final bool lifeLost;

  /// The life balance after this answer, when the mode spends lives.
  final Map<String, dynamic>? lifeState;

  /// What is left of a timed run by the server's clock, when the mode has
  /// one (the Daily Challenge).
  final int? remainingMs;

  const AnswerVerdict({
    required this.correct,
    required this.correctIndex,
    this.lifeLost = false,
    this.lifeState,
    this.remainingMs,
  });
}

/// The Daily Challenge run is over on the server — its clock ran out, or it
/// was already saved — so the answer can't count. The run should be
/// closed and saved rather than retried.
class DailyClosedException implements Exception {
  const DailyClosedException();
}

/// The player can't afford to answer: out of lives, or not enough for a
/// level's entry.
class NoLivesException implements Exception {
  final Map<String, dynamic>? lifeState;

  const NoLivesException([this.lifeState]);
}

/// Sends each answer to the server as it is given.
///
/// Solo, Daily Challenge and Weekly Topic questions reach the app without
/// their answers; the server judges each one, banks it (the first answer
/// is final) and, where the mode costs lives, charges for it.
class AnswerService {
  AnswerService._();

  static final AnswerService instance = AnswerService._();

  static const Duration _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(name, options: HttpsCallableOptions(timeout: _timeout))
          .call(data);
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is Map && details['reason'] == 'no_lives') {
        throw const NoLivesException();
      }
      if (details is Map &&
          (details['reason'] == 'daily_time_up' ||
              details['reason'] == 'daily_closed')) {
        throw const DailyClosedException();
      }
      rethrow;
    }
  }

  /// Codes that mean the call may never have reached the server, or its
  /// reply never came back.
  static const _retryableCodes = {'unavailable', 'deadline-exceeded', 'internal'};

  AnswerVerdict _verdict(Map<String, dynamic> data, {bool withLives = true}) {
    return AnswerVerdict(
      correct: data['correct'] == true,
      correctIndex: ((data['correctIndex'] ?? -1) as num).toInt(),
      lifeLost: data['lifeLost'] == true,
      lifeState: withLives && data.containsKey('lifeUnits')
          ? LifeService.instance.stateFromCallableResponse(data)
          : null,
      remainingMs: (data['remainingMs'] as num?)?.toInt(),
    );
  }

  /// A Solo or AI-topic level. -1 is a question the clock ran out on.
  Future<AnswerVerdict> answerSolo({
    required bool isAiTopic,
    required String categoryId,
    required String? aiTopicId,
    required int levelNumber,
    required int questionIndex,
    required int selectedIndex,
  }) async {
    return _verdict(await _call('answerSoloQuestion', {
      'isAiTopic': isAiTopic,
      'categoryId': categoryId,
      'aiTopicId': aiTopicId,
      'levelNumber': levelNumber,
      'questionIndex': questionIndex,
      'selectedIndex': selectedIndex,
    }));
  }

  /// The Daily Challenge, which costs no lives.
  ///
  /// A call lost on the way is sent once more before giving up: the clock
  /// is running, and the server answers a repeat with the verdict it
  /// already banked, so a second try can't count an answer twice.
  Future<AnswerVerdict> answerDaily({
    required String dateId,
    required int questionIndex,
    required int selectedIndex,
  }) async {
    final data = {
      'dateId': dateId,
      'questionIndex': questionIndex,
      'selectedIndex': selectedIndex,
    };
    Map<String, dynamic> response;
    try {
      response = await _call('answerDailyQuestion', data);
    } on FirebaseFunctionsException catch (e) {
      if (!_retryableCodes.contains(e.code)) rethrow;
      response = await _call('answerDailyQuestion', data);
    }
    return _verdict(response, withLives: false);
  }

  /// The Weekly Topic round drawn by `drawWeeklyTopicRound`.
  Future<AnswerVerdict> answerWeekly({
    required int questionIndex,
    required int selectedIndex,
  }) async {
    return _verdict(await _call('answerWeeklyQuestion', {
      'questionIndex': questionIndex,
      'selectedIndex': selectedIndex,
    }));
  }
}
