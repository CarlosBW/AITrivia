import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyLeagueService {
  WeeklyLeagueService._();

  static final instance = WeeklyLeagueService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String currentWeekId([DateTime? now]) {
    final date = now ?? DateTime.now();
    final monday = date.subtract(Duration(days: date.weekday - 1));

    final y = monday.year.toString().padLeft(4, '0');
    final m = monday.month.toString().padLeft(2, '0');
    final d = monday.day.toString().padLeft(2, '0');

    return '$y-$m-$d';
  }

  DateTime nextResetDate([DateTime? now]) {
    final date = now ?? DateTime.now();
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day).add(
      const Duration(days: 7),
    );
  }

  Duration timeUntilReset([DateTime? now]) {
    final date = now ?? DateTime.now();
    return nextResetDate(date).difference(date);
  }

  DocumentReference<Map<String, dynamic>> weeklyPlayerRef({
    required String uid,
    required String weekId,
    required String leagueId,
  }) {
    return _db
        .collection('weekly_leagues')
        .doc(weekId)
        .collection(leagueId)
        .doc(uid);
  }

  /// The league [uid] is playing [weekId] in, or null before their first
  /// game of the week. Fixed for the whole week: a promotion takes effect
  /// from the next one, so the board to show is this one, not the league
  /// the player's total score now reaches.
  Future<String?> weekLeagueId({
    required String uid,
    required String weekId,
  }) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('weekly_participation')
        .doc(weekId)
        .get();
    return snap.data()?['leagueId'] as String?;
  }

  Query<Map<String, dynamic>> weeklyLeaderboardQuery({
    required String weekId,
    required String leagueId,
    int limit = 50,
  }) {
    return _db
        .collection('weekly_leagues')
        .doc(weekId)
        .collection(leagueId)
        .orderBy('weeklyScore', descending: true)
        .limit(limit);
  }
}