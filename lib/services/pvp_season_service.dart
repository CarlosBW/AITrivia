import 'package:cloud_firestore/cloud_firestore.dart';

import 'pvp_league_service.dart';

class PvpSeasonRewardInfo {
  final int coins;
  final String label;
  final String description;

  const PvpSeasonRewardInfo({
    required this.coins,
    required this.label,
    required this.description,
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

  /// Monthly season id. Example: pvp_2026_05.
  /// This version is client-side so it works without Cloud Functions.
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
          label: 'Master reward',
          description: 'Top-tier ranked season reward.',
        );
      case 'diamond':
        return const PvpSeasonRewardInfo(
          coins: 1200,
          label: 'Diamond reward',
          description: 'High competitive season reward.',
        );
      case 'platinum':
        return const PvpSeasonRewardInfo(
          coins: 750,
          label: 'Platinum reward',
          description: 'Advanced ranked season reward.',
        );
      case 'gold':
        return const PvpSeasonRewardInfo(
          coins: 450,
          label: 'Gold reward',
          description: 'Strong ranked season reward.',
        );
      case 'silver':
        return const PvpSeasonRewardInfo(
          coins: 250,
          label: 'Silver reward',
          description: 'Progression ranked season reward.',
        );
      case 'bronze':
      default:
        return const PvpSeasonRewardInfo(
          coins: 100,
          label: 'Bronze reward',
          description: 'Entry ranked season reward.',
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
