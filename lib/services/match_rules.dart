/// Pure rules behind `match_service.dart`.
///
/// Kept in their own file (like `functions/src/ai_question_bank.ts` does on
/// the server) so they can be unit-tested without Firestore, auth or a
/// clock: `match_service` is the biggest service in the app and the one
/// that moves matches and ratings, and none of it had a test.
///
/// Everything here takes plain values and an explicit `now`. Converting
/// Firestore `Timestamp`s is the service's job — that boundary is what
/// keeps these functions testable.
library;

/// How long a `live_search` entry stays valid without a heartbeat.
const Duration liveQueueMaxAge = Duration(seconds: 30);

/// Rating a player starts at, mirrored from `PvpLeagueService`.
const int defaultPvpRating = 1000;

/// Reads an int out of whatever Firestore handed back.
///
/// Numbers arrive as `int` or `double` depending on how they were written,
/// and older documents sometimes hold them as strings.
int safeInt(Object? value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

/// Whether a heartbeat is fresh enough to treat its entry as alive.
///
/// A missing timestamp counts as recent on purpose: an entry written
/// before the heartbeat field existed would otherwise be read as stale and
/// silently dropped out of the queue.
bool isHeartbeatRecent({
  required DateTime? lastSeenAt,
  required DateTime now,
  Duration maxAge = liveQueueMaxAge,
}) {
  if (lastSeenAt == null) return true;
  return now.difference(lastSeenAt) <= maxAge;
}

/// Whether a `live_search` entry still represents an active search.
///
/// Three things have to hold: it says it is searching, it hasn't already
/// been paired ([matchId] unset), and its heartbeat is fresh. A player who
/// closed the app mid-search leaves an entry that passes the first two and
/// fails the third.
bool isLiveQueueEntryValid({
  required String status,
  required Object? matchId,
  required DateTime? lastSeenAt,
  required DateTime now,
  Duration maxAge = liveQueueMaxAge,
}) {
  if (status != 'searching') return false;
  if (matchId != null) return false;

  return isHeartbeatRecent(
    lastSeenAt: lastSeenAt,
    now: now,
    maxAge: maxAge,
  );
}

/// The ranked cooldown if it hasn't run out yet, otherwise null.
DateTime? activeCooldownUntil(DateTime? cooldownUntil, DateTime now) {
  if (cooldownUntil == null) return null;
  return cooldownUntil.isAfter(now) ? cooldownUntil : null;
}

/// How long is left on a cooldown, phrased for the player.
///
/// Under a minute drops the minutes entirely — "45s" reads better than
/// "0m 45s" — and seconds are zero-padded once minutes are shown so the
/// text doesn't jitter as it counts down.
String formatCooldownRemaining(Duration remaining) {
  final seconds = remaining.inSeconds.clamp(0, 999999);
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;

  if (minutes <= 0) return '${seconds}s';
  return '${minutes}m ${rest.toString().padLeft(2, '0')}s';
}

/// Turns a stored answer map (`{"0": 2, "1": 3}`) into indexed answers.
///
/// Firestore keys are always strings, and anything that doesn't parse is
/// dropped rather than guessed at — a malformed entry should cost one
/// question, not the whole match.
Map<int, int> parseAnswerMap(Object? raw) {
  if (raw is! Map) return {};

  final parsed = <int, int>{};
  raw.forEach((key, value) {
    final index = int.tryParse(key.toString());
    if (index != null && index >= 0 && value is num) {
      parsed[index] = value.toInt();
    }
  });
  return parsed;
}
