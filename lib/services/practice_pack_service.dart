import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'practice_pack.dart';

/// Keeps a pack of practice questions on the phone, for when there is no
/// connection, and deals rounds out of it.
class PracticePackService {
  PracticePackService._();

  static final PracticePackService instance = PracticePackService._();

  static const String _packKey = 'practice_pack_v1';
  static const String _cursorKey = 'practice_pack_cursor_v1';

  bool _refreshing = false;

  /// Downloads a new pack if the phone has none or its own is old. Called
  /// while online, from Home; fire and forget — a failure only means the
  /// pack on the phone stays as it is.
  Future<void> refreshIfDue() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = decodePracticePack(prefs.getString(_packKey));
      if (!shouldRefreshPracticePack(current?.fetchedAt, DateTime.now())) {
        return;
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('downloadPracticePack')
          .call<Map<Object?, Object?>>();
      // Empty when the server handed one out too recently: keep ours.
      final questions = parsePracticeQuestions(result.data['questions']);
      if (questions.isEmpty) return;

      await prefs.setString(
        _packKey,
        encodePracticePack(
          PracticePack(questions: questions, fetchedAt: DateTime.now()),
        ),
      );
      await prefs.setInt(_cursorKey, 0);
    } catch (_) {
      // Offline, or a server without the function yet.
    } finally {
      _refreshing = false;
    }
  }

  /// Whether there is anything to practise with.
  Future<bool> hasPack() async {
    final prefs = await SharedPreferences.getInstance();
    return decodePracticePack(prefs.getString(_packKey)) != null;
  }

  /// The next round, empty when the phone has no pack. Moves on through
  /// the pack, so the round after it brings other questions.
  Future<List<Map<String, dynamic>>> nextRound() async {
    final prefs = await SharedPreferences.getInstance();
    final pack = decodePracticePack(prefs.getString(_packKey));
    if (pack == null) return const [];

    final round = practiceRound(pack.questions, prefs.getInt(_cursorKey) ?? 0);
    await prefs.setInt(_cursorKey, round.nextCursor);
    return round.questions;
  }
}
