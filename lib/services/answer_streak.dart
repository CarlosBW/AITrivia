/// The run of right answers in a row within a level: what the play screen
/// shows as it grows, and what the server pays extra XP for.
///
/// [bonuses] mirrors `ANSWER_STREAK_BONUSES` in functions/src/rewards.ts,
/// which is what actually pays; `test/services/answer_streak_sync_test.dart`
/// keeps the two from drifting apart.
class AnswerStreak {
  AnswerStreak._();

  /// Run length to the XP it earns. Only the highest step reached pays.
  static const Map<int, int> bonuses = {3: 5, 5: 10, 7: 20, 10: 30};

  /// From here on the run is shown: one right answer isn't a run.
  static const int shownFrom = 2;

  /// Whether a run of exactly [streak] has just reached a paying step.
  static bool isMilestone(int streak) => bonuses.containsKey(streak);

  /// How far along the steps a run of [streak] is, from 0 (none reached)
  /// to the number of steps: what the badge grows hotter with.
  static int heat(int streak) =>
      bonuses.keys.where((step) => streak >= step).length;
}

/// The run the player is on: how many of the latest answered questions in
/// a row were right. [results] holds each question's verdict in the order
/// asked, null for one not answered yet.
///
/// Read from the verdicts rather than counted as answers come in, so a
/// level resumed half-way shows the run it really has.
int currentAnswerStreak(List<bool?> results) {
  var last = results.length - 1;
  while (last >= 0 && results[last] == null) {
    last--;
  }

  var streak = 0;
  for (var i = last; i >= 0 && results[i] == true; i--) {
    streak++;
  }
  return streak;
}
