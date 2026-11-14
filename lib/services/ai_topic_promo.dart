import 'package:shared_preferences/shared_preferences.dart';

/// How often Home reminds the player that they can create their own topics.
const Duration aiTopicPromoInterval = Duration(days: 4);

const String _anchorKey = 'ai_topic_promo_anchor_ms';

/// Whether the reminder is due, [interval] after [anchorMs] — the last time
/// it was shown, or the first time the app was opened.
///
/// A clock set back (the anchor in the future) doesn't count as due: it
/// would otherwise show on every launch until the clock caught up.
bool aiTopicPromoDue({
  required int anchorMs,
  required int nowMs,
  Duration interval = aiTopicPromoInterval,
}) {
  return nowMs - anchorMs >= interval.inMilliseconds;
}

/// Whether Home should show the reminder now. Saying yes starts the wait
/// for the next one.
///
/// The first time the app is opened only starts the clock: a new player
/// has the tour and the first levels in front of them, and the reminder is
/// for the days after that.
Future<bool> takeAiTopicPromoTurn({DateTime? now}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final anchorMs = prefs.getInt(_anchorKey);

    if (anchorMs == null) {
      await prefs.setInt(_anchorKey, nowMs);
      return false;
    }
    if (!aiTopicPromoDue(anchorMs: anchorMs, nowMs: nowMs)) return false;

    await prefs.setInt(_anchorKey, nowMs);
    return true;
  } catch (_) {
    // No storage, no reminder: better than one on every launch.
    return false;
  }
}
