import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'league_service.dart';
import 'weekly_league_service.dart';
import 'notification_service.dart';
import '../l10n/generated/app_localizations.dart';

/// Which rank-based bonus tier a weekly-league reward falls into. Kept as
/// an enum (rather than a pre-localized string) so the display text can be
/// resolved lazily from a widget's own `AppLocalizations.of(context)` —
/// `getPendingSeasonRewards` below runs from `initState`, where a
/// context-derived locale isn't safely available yet.
enum SeasonRewardTier { champion, top3, top10, generic }

String seasonRewardMessageFor(AppLocalizations l10n, SeasonRewardTier tier) {
  switch (tier) {
    case SeasonRewardTier.champion:
      return l10n.weeklyRewardChampionBonus;
    case SeasonRewardTier.top3:
      return l10n.weeklyRewardTop3Bonus;
    case SeasonRewardTier.top10:
      return l10n.weeklyRewardTop10Bonus;
    case SeasonRewardTier.generic:
      return l10n.weeklyRewardGenericBonus;
  }
}

class SeasonReward {
  final int coins;
  final SeasonRewardTier tier;

  const SeasonReward({
    required this.coins,
    required this.tier,
  });
}

class PendingSeasonReward {
  final String seasonId;
  final String leagueId;
  final String leagueName;
  final int rank;
  final int weeklyScore;
  final int rewardCoins;
  final SeasonRewardTier rewardTier;

  const PendingSeasonReward({
    required this.seasonId,
    required this.leagueId,
    required this.leagueName,
    required this.rank,
    required this.weeklyScore,
    required this.rewardCoins,
    required this.rewardTier,
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

    final tier = rank == 1
        ? SeasonRewardTier.champion
        : rank <= 3
            ? SeasonRewardTier.top3
            : rank <= 10
                ? SeasonRewardTier.top10
                : SeasonRewardTier.generic;

    return SeasonReward(coins: total, tier: tier);
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
          rewardTier: reward.tier,
        ),
      );
    }

    pending.sort((a, b) => a.seasonId.compareTo(b.seasonId));

    return pending;
  }

  /// Claims all pending weekly-league season rewards via the
  /// `claimWeeklySeasonRewards` Cloud Function. The rank/score source data
  /// (weekly_leagues / weekly_participation) is now Cloud-Function-only
  /// writable, so this only exists because the `coins` grant itself must
  /// move server-side once that field is protected in firestore.rules.
  Future<ClaimSeasonRewardsResult> claimAllPendingRewards({
    required String uid,
  }) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('claimWeeklySeasonRewards');
    final response = await callable.call();
    final data = Map<String, dynamic>.from(response.data as Map);

    return ClaimSeasonRewardsResult(
      claimedCount: ((data['claimedCount'] ?? 0) as num).toInt(),
      totalCoins: ((data['totalCoins'] ?? 0) as num).toInt(),
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
