import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  bool get hasEnded => DateTime.now().isAfter(end);
}

class PvpSeasonClaimResult {
  final String seasonId;
  final String leagueId;
  final String leagueName;
  final int finalRating;
  final int bestRating;
  final int rewardCoins;
  final bool alreadyClaimed;

  const PvpSeasonClaimResult({
    required this.seasonId,
    required this.leagueId,
    required this.leagueName,
    required this.finalRating,
    required this.bestRating,
    required this.rewardCoins,
    required this.alreadyClaimed,
  });
}

class PvpSeasonClaimStatus {
  final bool canClaim;
  final bool alreadyClaimed;
  final String seasonId;
  final String? message;

  const PvpSeasonClaimStatus({
    required this.canClaim,
    required this.alreadyClaimed,
    required this.seasonId,
    this.message,
  });
}

class PendingPvpSeasonReward {
  final String seasonId;
  final int finalRating;
  final int bestRating;
  final String leagueId;
  final String leagueName;
  final String leagueEmoji;
  final int rewardCoins;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int draws;

  const PendingPvpSeasonReward({
    required this.seasonId,
    required this.finalRating,
    required this.bestRating,
    required this.leagueId,
    required this.leagueName,
    required this.leagueEmoji,
    required this.rewardCoins,
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
  });
}

class PvpSeasonClaimAllResult {
  final int claimedCount;
  final int totalCoins;
  final List<PvpSeasonClaimResult> rewards;

  const PvpSeasonClaimAllResult({
    required this.claimedCount,
    required this.totalCoins,
    required this.rewards,
  });
}

class PvpSeasonService {
  PvpSeasonService._();

  static final PvpSeasonService instance = PvpSeasonService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  PvpSeasonInfo previousSeason() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 1, 1);
    final end = DateTime(now.year, now.month, 1);
    final id = 'pvp_${start.year}_${start.month.toString().padLeft(2, '0')}';

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
          coins: 80,
          label: 'Master reward',
          description: 'Top-tier ranked season reward.',
        );
      case 'diamond':
        return const PvpSeasonRewardInfo(
          coins: 40,
          label: 'Diamond reward',
          description: 'High competitive season reward.',
        );
      case 'platinum':
        return const PvpSeasonRewardInfo(
          coins: 20,
          label: 'Platinum reward',
          description: 'Advanced ranked season reward.',
        );
      case 'gold':
        return const PvpSeasonRewardInfo(
          coins: 10,
          label: 'Gold reward',
          description: 'Strong ranked season reward.',
        );
      case 'silver':
        return const PvpSeasonRewardInfo(
          coins: 5,
          label: 'Silver reward',
          description: 'Progression ranked season reward.',
        );
      case 'bronze':
      default:
        return const PvpSeasonRewardInfo(
          coins: 2,
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

  bool _isPastSeasonId(String seasonId) {
    return seasonId.compareTo(currentSeason().id) < 0;
  }

  int _safeInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  PendingPvpSeasonReward _pendingRewardFromStats({
    required String seasonId,
    required Map<String, dynamic> statsData,
  }) {
    final finalRating = _safeInt(
      statsData['finalRating'],
      PvpLeagueService.defaultRating,
    );

    final bestRating = _safeInt(
      statsData['bestRating'],
      finalRating,
    );

    final bestLeague = PvpLeagueService.instance.leagueForRating(bestRating);
    final reward = rewardForLeague(bestLeague);

    return PendingPvpSeasonReward(
      seasonId: seasonId,
      finalRating: finalRating,
      bestRating: bestRating,
      leagueId: bestLeague.id,
      leagueName: bestLeague.name,
      leagueEmoji: bestLeague.emoji,
      rewardCoins: reward.coins,
      matchesPlayed: _safeInt(statsData['matchesPlayed'], 0),
      wins: _safeInt(statsData['wins'], 0),
      losses: _safeInt(statsData['losses'], 0),
      draws: _safeInt(statsData['draws'], 0),
    );
  }

  Future<List<PendingPvpSeasonReward>> getPendingPvpSeasonRewards({
    required String uid,
  }) async {
    final userRef = _db.collection('users').doc(uid);

    final statsSnap = await userRef.collection('pvp_season_stats').get();
    final historySnap = await userRef.collection('pvp_season_history').get();

    final claimedSeasonIds = historySnap.docs.map((doc) => doc.id).toSet();

    final pending = <PendingPvpSeasonReward>[];

    for (final doc in statsSnap.docs) {
      final seasonId = doc.id;

      if (!_isPastSeasonId(seasonId)) continue;
      if (claimedSeasonIds.contains(seasonId)) continue;

      pending.add(
        _pendingRewardFromStats(
          seasonId: seasonId,
          statsData: doc.data(),
        ),
      );
    }

    pending.sort((a, b) => b.seasonId.compareTo(a.seasonId));
    return pending;
  }

  Future<bool> hasPendingPvpSeasonRewards({required String uid}) async {
    final pending = await getPendingPvpSeasonRewards(uid: uid);
    return pending.isNotEmpty;
  }

  Future<PvpSeasonClaimStatus> getClaimStatus({required String uid}) async {
    final pending = await getPendingPvpSeasonRewards(uid: uid);

    if (pending.isNotEmpty) {
      final totalCoins = pending.fold<int>(
        0,
        (sum, item) => sum + item.rewardCoins,
      );

      return PvpSeasonClaimStatus(
        canClaim: true,
        alreadyClaimed: false,
        seasonId: pending.first.seasonId,
        message:
            '${pending.length} pending PvP season reward(s): +$totalCoins coins.',
      );
    }

    final previous = previousSeason();
    final historyRef = _db
        .collection('users')
        .doc(uid)
        .collection('pvp_season_history')
        .doc(previous.id);

    final historySnap = await historyRef.get();

    if (historySnap.exists) {
      return PvpSeasonClaimStatus(
        canClaim: false,
        alreadyClaimed: true,
        seasonId: previous.id,
        message: 'Previous PvP season reward already claimed.',
      );
    }

    return PvpSeasonClaimStatus(
      canClaim: false,
      alreadyClaimed: false,
      seasonId: previous.id,
      message: 'No pending PvP season rewards available.',
    );
  }

  Future<PvpSeasonClaimResult> claimPreviousSeasonReward({
    required String uid,
  }) async {
    final result = await claimAllPendingPvpSeasonRewards(uid: uid);

    if (result.rewards.isEmpty) {
      final previous = previousSeason();
      throw Exception(
        'No pending PvP season rewards available for ${previous.id}.',
      );
    }

    return result.rewards.first;
  }

  /// Claims all pending PvP season rewards via the `claimPvpSeasonRewards`
  /// Cloud Function. The reward source data (pvp_season_stats /
  /// pvp_season_history) is already server-only, so this only exists
  /// because writing `coins` directly from the client is no longer allowed
  /// once that field is protected in firestore.rules.
  Future<PvpSeasonClaimAllResult> claimAllPendingPvpSeasonRewards({
    required String uid,
  }) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('claimPvpSeasonRewards');
    final response = await callable.call();
    final data = Map<String, dynamic>.from(response.data as Map);

    final rewards = ((data['rewards'] as List?) ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map((r) => PvpSeasonClaimResult(
              seasonId: (r['seasonId'] ?? '').toString(),
              leagueId: (r['leagueId'] ?? '').toString(),
              leagueName: (r['leagueName'] ?? '').toString(),
              finalRating: ((r['finalRating'] ?? 0) as num).toInt(),
              bestRating: ((r['bestRating'] ?? 0) as num).toInt(),
              rewardCoins: ((r['rewardCoins'] ?? 0) as num).toInt(),
              alreadyClaimed: r['alreadyClaimed'] == true,
            ))
        .toList();

    return PvpSeasonClaimAllResult(
      claimedCount: ((data['claimedCount'] ?? 0) as num).toInt(),
      totalCoins: ((data['totalCoins'] ?? 0) as num).toInt(),
      rewards: rewards,
    );
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
