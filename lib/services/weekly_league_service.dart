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