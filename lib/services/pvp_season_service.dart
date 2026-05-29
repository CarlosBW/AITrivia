import 'package:cloud_firestore/cloud_firestore.dart';

import 'pvp_league_service.dart';

class PvpSeasonRewardInfo {
  final int coins;
  final String label;

  const PvpSeasonRewardInfo({
    required this.coins,
    required this.label,
  });
}

class PvpSeasonInfo {
  final String id;
  final DateTime start;
  final DateTime end;

  const PvpSeasonInfo({
    required this.id,
    required this.start,
    required this.end,
  });

  Duration get timeLeft {
    final now = DateTime.now();
    if (now.isAfter(end)) return Duration.zero;
    return end.difference(now);
  }
}

class PvpSeasonService {
  PvpSeasonService._();

  static final PvpSeasonService instance = PvpSeasonService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Monthly client-side season id. Example: pvp_2026_05.
  /// This keeps the first version simple and avoids needing Cloud Functions.
  PvpSeasonInfo currentSeason() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    final id = 'pvp_${now.year}_${now.month.toString().padLeft(2, '0')}';

    return PvpSeasonInfo(
      id: id,
      start: start,
      end: end,
    );
  }

  PvpSeasonRewardInfo rewardForLeague(PvpLeagueInfo league) {
    switch (league.id) {
      case 'master':
        return const PvpSeasonRewardInfo(
          coins: 2000,
          label: 'Master season reward',
        );
      case 'diamond':
        return const PvpSeasonRewardInfo(
          coins: 1200,
          label: 'Diamond season reward',
        );
      case 'platinum':
        return const PvpSeasonRewardInfo(
          coins: 750,
          label: 'Platinum season reward',
        );
      case 'gold':
        return const PvpSeasonRewardInfo(
          coins: 450,
          label: 'Gold season reward',
        );
      case 'silver':
        return const PvpSeasonRewardInfo(
          coins: 250,
          label: 'Silver season reward',
        );
      case 'bronze':
      default:
        return const PvpSeasonRewardInfo(
          coins: 100,
          label: 'Bronze season reward',
        );
    }
  }

  Query<Map<String, dynamic>> globalLeaderboardQuery({int limit = 100}) {
    return _db
        .collection('users')
        .orderBy('pvpRating', descending: true)
        .limit(limit);
  }

  Query<Map<String, dynamic>> leagueLeaderboardQuery({
    required PvpLeagueInfo league,
    int limit = 100,
  }) {
    return _db
        .collection('users')
        .where('pvpRating', isGreaterThanOrEqualTo: league.minRating)
        .where('pvpRating', isLessThanOrEqualTo: league.maxRating)
        .orderBy('pvpRating', descending: true)
        .limit(limit);
  }

  String formatTimeLeft(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}