import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/season_service.dart';
import '../../services/league_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_avatar_button.dart';

class SeasonRewardsScreen extends StatefulWidget {
  const SeasonRewardsScreen({super.key});

  @override
  State<SeasonRewardsScreen> createState() => _SeasonRewardsScreenState();
}

class _SeasonRewardsScreenState extends State<SeasonRewardsScreen> {
  final _seasonService = SeasonService.instance;
  bool _claiming = false;

  Future<List<PendingSeasonReward>>? _pendingFuture;
  Future<QuerySnapshot<Map<String, dynamic>>>? _historyFuture;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _reload(uid);
  }

  void _reload(String uid) {
    _pendingFuture = _seasonService.getPendingSeasonRewards(uid: uid);
    _historyFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('season_history')
        .orderBy('seasonId', descending: true)
        .get();
  }

  Future<void> _claimAll(String uid) async {
    if (_claiming) return;

    setState(() => _claiming = true);

    try {
      final result = await _seasonService.claimAllPendingRewards(uid: uid);

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.claimedCount == 0
                ? l10n.weeklyRewardsNoPending
                : l10n.weeklyRewardsClaimed(result.claimedCount, result.totalCoins),
          ),
        ),
      );

      setState(() {
        _reload(uid);
      });
    } finally {
      if (mounted) {
        setState(() => _claiming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: Text(l10n.weeklyRewardsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<List<PendingSeasonReward>>(
            future: _pendingFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _LoadingCard();
              }

              final pending = snap.data ?? [];

              if (pending.isEmpty) {
                return const _NoPendingRewardsCard();
              }

              final totalCoins = pending.fold<int>(
                0,
                (total, reward) => total + reward.rewardCoins,
              );

              return _PendingRewardsCard(
                pending: pending,
                totalCoins: totalCoins,
                claiming: _claiming,
                onClaim: () => _claimAll(uid),
              );
            },
          ),

          const SizedBox(height: 22),

          Text(
            l10n.weeklyRewardsHistoryTitle,
            style: context.heading(20),
          ),

          const SizedBox(height: 12),

          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: _historyFuture,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  l10n.weeklyRewardsErrorLoadingHistory(snap.error.toString()),
                  textAlign: TextAlign.center,
                );
              }

              if (!snap.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final docs = snap.data!.docs;

              if (docs.isEmpty) {
                return const _EmptyHistoryCard();
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data();

                  final seasonId = (data['seasonId'] ?? doc.id).toString();
                  final leagueId = (data['leagueId'] ?? '').toString();
                  final leagueName = (data['leagueName'] ??
                          l10n.weeklyRewardsLeagueFallback)
                      .toString();
                  final rank = ((data['rank'] ?? 0) as num).toInt();
                  final weeklyScore =
                      ((data['weeklyScore'] ?? 0) as num).toInt();
                  final rewardCoins =
                      ((data['rewardCoins'] ?? 0) as num).toInt();
                  final rewardMessage = (data['rewardMessage'] ??
                          l10n.weeklyRewardsMessageFallback)
                      .toString();

                  return _HistoryTile(
                    seasonId: seasonId,
                    leagueId: leagueId,
                    leagueName: leagueName,
                    rank: rank,
                    weeklyScore: weeklyScore,
                    rewardCoins: rewardCoins,
                    rewardMessage: rewardMessage,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(AppLocalizations.of(context).weeklyRewardsChecking),
        ],
      ),
    );
  }
}

class _NoPendingRewardsCard extends StatelessWidget {
  const _NoPendingRewardsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_outlined, size: 38),
          const SizedBox(height: 10),
          Text(
            l10n.weeklyRewardsNoPendingTitle,
            style: context.heading(18),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.weeklyRewardsKeepPlayingHint,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PendingRewardsCard extends StatelessWidget {
  final List<PendingSeasonReward> pending;
  final int totalCoins;
  final bool claiming;
  final VoidCallback onClaim;

  const _PendingRewardsCard({
    required this.pending,
    required this.totalCoins,
    required this.claiming,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.appColors.rewardBg,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: context.appColors.reward),
      ),
      child: Column(
        children: [
          Icon(
            Icons.card_giftcard_outlined,
            color: context.appColors.reward,
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            pending.length == 1
                ? l10n.weeklyRewardsPendingSingle(pending.length)
                : l10n.weeklyRewardsPendingMultiple(pending.length),
            style: context.heading(20),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.weeklyRewardsTotalAvailable(totalCoins),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),

          ...pending.map(
            (reward) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PendingRewardMiniTile(reward: reward),
            ),
          ),

          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: claiming ? null : onClaim,
              icon: claiming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.redeem),
              label: Text(claiming ? l10n.pvpSeasonClaiming : l10n.pvpSeasonClaimAllButton),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRewardMiniTile extends StatelessWidget {
  final PendingSeasonReward reward;

  const _PendingRewardMiniTile({
    required this.reward,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).weeklyRewardsMiniTile(
                reward.seasonId,
                reward.leagueName,
                reward.rank,
                seasonRewardMessageFor(
                  AppLocalizations.of(context),
                  reward.rewardTier,
                ),
              ),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '+${reward.rewardCoins}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Text(
        AppLocalizations.of(context).weeklyRewardsNoHistory,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final String seasonId;
  final String leagueId;
  final String leagueName;
  final int rank;
  final int weeklyScore;
  final int rewardCoins;
  final String rewardMessage;

  const _HistoryTile({
    required this.seasonId,
    required this.leagueId,
    required this.leagueName,
    required this.rank,
    required this.weeklyScore,
    required this.rewardCoins,
    required this.rewardMessage,
  });

  LeagueInfo? get _league {
    for (final l in LeagueService.leagues) {
      if (l.id == leagueId) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _league != null
        ? Color(_league!.colorValue)
        : Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.workspace_premium_outlined, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.weeklyRewardsHistoryTitleLine(seasonId, leagueName),
                  style: context.headingFace,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.weeklyRewardsHistorySubtitle(rank, weeklyScore, rewardMessage),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+$rewardCoins',
            style: context.heading(17, color: Color.lerp(color, Colors.black, 0.35)),
          ),
        ],
      ),
    );
  }
}