import 'package:cloud_firestore/cloud_firestore.dart';

import 'league_service.dart';
import 'weekly_league_service.dart';
import 'notification_service.dart';

class SeasonReward {
  final int coins;
  final String message;

  const SeasonReward({
    required this.coins,
    required this.message,
  });
}

class PendingSeasonReward {
  final String seasonId;
  final String leagueId;
  final String leagueName;
  final int rank;
  final int weeklyScore;
  final int rewardCoins;
  final String rewardMessage;

  const PendingSeasonReward({
    required this.seasonId,
    required this.leagueId,
    required this.leagueName,
    required this.rank,
    required this.weeklyScore,
    required this.rewardCoins,
    required this.rewardMessage,
  });
}

class ClaimSeasonRewardsResult {
  final int claimedCount;
  final int totalCoins;

  const ClaimSeasonRewardsResult({
    required this.claimedCount,
    required this.totalCoins,
  });
}

class SeasonService {
  SeasonService._();

  static final instance = SeasonService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final _notificationService = NotificationService.instance;

  String currentSeasonId([DateTime? now]) {
    return WeeklyLeagueService.instance.currentWeekId(now);
  }

  SeasonReward rewardForLeague(LeagueInfo league, int rank) {
    final baseCoins = switch (league.id) {
      'bronze' => 20,
      'silver' => 40,
      'gold' => 80,
      'diamond' => 150,
      'master' => 300,
      _ => 20,
    };

    int bonus = 0;

    if (rank == 1) {
      bonus = baseCoins;
    } else if (rank <= 3) {
      bonus = (baseCoins * 0.5).round();
    } else if (rank <= 10) {
      bonus = (baseCoins * 0.25).round();
    }

    final total = baseCoins + bonus;

    return SeasonReward(
      coins: total,
      message: rank == 1
          ? 'Champion bonus!'
          : rank <= 3
              ? 'Top 3 bonus!'
              : rank <= 10
                  ? 'Top 10 bonus!'
                  : 'Weekly league reward',
    );
  }

  DocumentReference<Map<String, dynamic>> seasonHistoryRef({
    required String uid,
    required String seasonId,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('season_history')
        .doc(seasonId);
  }

  Future<bool> hasClaimedSeasonReward({
    required String uid,
    required String seasonId,
  }) async {
    final snap = await seasonHistoryRef(
      uid: uid,
      seasonId: seasonId,
    ).get();

    return snap.exists && snap.data()?['claimed'] == true;
  }

  Future<int> _calculateRank({
    required String seasonId,
    required String leagueId,
    required int weeklyScore,
  }) async {
    final betterPlayersQuery = _db
        .collection('weekly_leagues')
        .doc(seasonId)
        .collection(leagueId)
        .where('weeklyScore', isGreaterThan: weeklyScore);

    try {
      final aggregate = await betterPlayersQuery.count().get();
      return (aggregate.count ?? 0) + 1;
    } catch (_) {
      // Fallback for older Firebase SDKs or aggregation issues.
      // Kept as a safety net, but normal builds should use count().
      final betterPlayersSnap = await betterPlayersQuery.get();
      return betterPlayersSnap.docs.length + 1;
    }
  }

  LeagueInfo _leagueById(String leagueId) {
    return LeagueService.leagues.firstWhere(
      (league) => league.id == leagueId,
      orElse: () => LeagueService.leagues.first,
    );
  }

  /// Cheap check used by Home and Weekly to show a warning badge/card.
  ///
  /// This intentionally does NOT calculate rank or reward coins.
  /// It only checks whether the user has at least one finished previous
  /// weekly participation that has not been claimed yet.
  Future<bool> hasPendingSeasonRewards({
    required String uid,
  }) async {
    final currentSeason = currentSeasonId();

    final participationSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('weekly_participation')
        .orderBy('weekId', descending: true)
        .limit(8)
        .get();

    for (final doc in participationSnap.docs) {
      final data = doc.data();
      final seasonId = (data['weekId'] ?? doc.id).toString();

      if (seasonId == currentSeason) continue;

      final weeklyScore = ((data['weeklyScore'] ?? 0) as num).toInt();
      if (weeklyScore <= 0) continue;

      final historySnap = await seasonHistoryRef(
        uid: uid,
        seasonId: seasonId,
      ).get();

      if (historySnap.exists && historySnap.data()?['claimed'] == true) {
        continue;
      }

      return true;
    }

    return false;
  }

  Future<List<PendingSeasonReward>> getPendingSeasonRewards({
    required String uid,
  }) async {
    final currentSeason = currentSeasonId();

    final participationSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('weekly_participation')
        .orderBy('weekId', descending: true)
        .limit(8)
        .get();

    final pending = <PendingSeasonReward>[];

    for (final doc in participationSnap.docs) {
      final data = doc.data();

      final seasonId = (data['weekId'] ?? doc.id).toString();

      // Current week is still active, so no reward yet.
      if (seasonId == currentSeason) continue;

      final historySnap = await seasonHistoryRef(
        uid: uid,
        seasonId: seasonId,
      ).get();

      if (historySnap.exists && historySnap.data()?['claimed'] == true) {
        continue;
      }

      final leagueId = (data['leagueId'] ?? 'bronze').toString();
      final leagueName = (data['leagueName'] ?? 'Bronze').toString();
      final weeklyScore = ((data['weeklyScore'] ?? 0) as num).toInt();

      if (weeklyScore <= 0) continue;

      final rank = await _calculateRank(
        seasonId: seasonId,
        leagueId: leagueId,
        weeklyScore: weeklyScore,
      );

      final league = _leagueById(leagueId);
      final reward = rewardForLeague(league, rank);

      pending.add(
        PendingSeasonReward(
          seasonId: seasonId,
          leagueId: leagueId,
          leagueName: leagueName,
          rank: rank,
          weeklyScore: weeklyScore,
          rewardCoins: reward.coins,
          rewardMessage: reward.message,
        ),
      );
    }

    pending.sort((a, b) => a.seasonId.compareTo(b.seasonId));

    return pending;
  }

  Future<void> saveSeasonReward({
    required String uid,
    required String seasonId,
    required LeagueInfo league,
    required int rank,
    required int weeklyScore,
  }) async {
    final historyRef = seasonHistoryRef(
      uid: uid,
      seasonId: seasonId,
    );

    final userRef = _db.collection('users').doc(uid);
    final reward = rewardForLeague(league, rank);

    await _db.runTransaction((tx) async {
      final historySnap = await tx.get(historyRef);

      if (historySnap.exists && historySnap.data()?['claimed'] == true) {
        return;
      }

      tx.set(
          historyRef,
          {
            'seasonId': seasonId,
            'leagueId': league.id,
            'leagueName': league.name,
            'rank': rank,
            'weeklyScore': weeklyScore,
            'rewardCoins': reward.coins,
            'rewardMessage': reward.message,
            'claimed': true,
            'claimedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      if (reward.coins > 0) {
        tx.set(
            userRef,
            {
              'coins': FieldValue.increment(reward.coins),
              'lastSeasonRewardClaimed': seasonId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
    });
  }

  Future<ClaimSeasonRewardsResult> claimAllPendingRewards({
    required String uid,
  }) async {
    final pendingRewards = await getPendingSeasonRewards(uid: uid);

    if (pendingRewards.isEmpty) {
      return const ClaimSeasonRewardsResult(
        claimedCount: 0,
        totalCoins: 0,
      );
    }

    final userRef = _db.collection('users').doc(uid);
    final batch = _db.batch();

    int totalCoins = 0;

    for (final reward in pendingRewards) {
      final historyRef = seasonHistoryRef(
        uid: uid,
        seasonId: reward.seasonId,
      );

      batch.set(
          historyRef,
          {
            'seasonId': reward.seasonId,
            'leagueId': reward.leagueId,
            'leagueName': reward.leagueName,
            'rank': reward.rank,
            'weeklyScore': reward.weeklyScore,
            'rewardCoins': reward.rewardCoins,
            'rewardMessage': reward.rewardMessage,
            'claimed': true,
            'claimedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      totalCoins += reward.rewardCoins;
    }

    if (totalCoins > 0) {
      batch.set(
          userRef,
          {
            'coins': FieldValue.increment(totalCoins),
            'lastSeasonRewardClaimed': pendingRewards.last.seasonId,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }

    await batch.commit();

    return ClaimSeasonRewardsResult(
      claimedCount: pendingRewards.length,
      totalCoins: totalCoins,
    );
  }

  Future<void> ensureSeasonRewardNotification({
    required String uid,
  }) async {
    try {
      final pending = await getPendingSeasonRewards(
        uid: uid,
      );

      if (pending.isEmpty) return;

      final userRef = _db.collection('users').doc(uid);

      final userSnap = await userRef.get();

      final data = userSnap.data() ?? {};

      final alreadyNotifiedSeason =
          (data['lastSeasonRewardNotification'] ?? '').toString();

      final latestSeason = pending.last.seasonId;

      // Ya notificamos esta season
      if (alreadyNotifiedSeason == latestSeason) {
        return;
      }

      await userRef.set({
        'lastSeasonRewardNotification': latestSeason,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _notificationService.createNotification(
        targetUid: uid,
        type: 'season_reward',
        title: 'Weekly reward available',
        body: 'Your weekly league reward is ready to claim.',
        data: {
          'seasonId': latestSeason,
        },
      );
    } catch (_) {}
  }
}
