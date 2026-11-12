import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/weekly_topic_service.dart';

/// A Weekly Topic round left open is handed back by the server with what
/// was banked; this is how the screen picks it up where it stopped instead
/// of starting over (and paying another life for it).
void main() {
  test('a new round starts at the first question', () {
    final progress = WeeklyRoundProgress.fromBanked(const {}, const {});

    expect(progress.answered, 0);
    expect(progress.correct, 0);
    expect(progress.selected, isEmpty);
  });

  test('picks up after the answers already judged', () {
    final progress = WeeklyRoundProgress.fromBanked(
      {'0': 2, '1': 0, '2': -1},
      {
        '0': {'correct': true, 'correctIndex': 2},
        '1': {'correct': false, 'correctIndex': 3},
        '2': {'correct': false, 'correctIndex': 1},
      },
    );

    expect(progress.answered, 3);
    expect(progress.correct, 1);
    expect(progress.selected, [2, 0, -1]);
    expect(progress.correctIndexByQuestion, {0: 2, 1: 3, 2: 1});
  });

  test('reads questions in number order, not key order', () {
    final answers = {for (var i = 11; i >= 0; i--) '$i': i % 4};
    final results = {
      for (var i = 0; i < 12; i++) '$i': {'correct': i == 11, 'correctIndex': 0},
    };

    final progress = WeeklyRoundProgress.fromBanked(answers, results);

    expect(progress.answered, 12);
    expect(progress.selected.last, 11 % 4);
    expect(progress.correct, 1);
  });

  // Answers are banked in order; one past a gap can't be placed, and the
  // server returns the same verdict if the question is answered again.
  test('stops at the first question without an answer', () {
    final progress = WeeklyRoundProgress.fromBanked(
      {'0': 1, '2': 1},
      {
        '0': {'correct': true, 'correctIndex': 1},
        '2': {'correct': true, 'correctIndex': 1},
      },
    );

    expect(progress.answered, 1);
    expect(progress.correct, 1);
  });

  test('survives a response with nothing usable in it', () {
    final progress = WeeklyRoundProgress.fromBanked(null, null);

    expect(progress.answered, 0);
  });
}
