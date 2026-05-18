import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/season_service.dart';

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.claimedCount == 0
                ? 'No pending rewards.'
                : 'Claimed ${result.claimedCount} reward(s): +${result.totalCoins} coins!',
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Season Rewards'),
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
                (sum, reward) => sum + reward.rewardCoins,
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

          const Text(
            'Season History',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: _historyFuture,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  'Error loading history:\n${snap.error}',
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
                  final leagueName =
                      (data['leagueName'] ?? 'League').toString();
                  final rank = ((data['rank'] ?? 0) as num).toInt();
                  final weeklyScore =
                      ((data['weeklyScore'] ?? 0) as num).toInt();
                  final rewardCoins =
                      ((data['rewardCoins'] ?? 0) as num).toInt();
                  final rewardMessage =
                      (data['rewardMessage'] ?? 'Reward claimed').toString();

                  return _HistoryTile(
                    seasonId: seasonId,
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
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Checking pending rewards...'),
        ],
      ),
    );
  }
}

class _NoPendingRewardsCard extends StatelessWidget {
  const _NoPendingRewardsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.verified, size: 38),
          SizedBox(height: 10),
          Text(
            'No pending rewards',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Keep playing weekly leagues to earn season rewards.',
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        children: [
          const Icon(Icons.card_giftcard, size: 42),
          const SizedBox(height: 10),
          Text(
            '${pending.length} pending reward${pending.length == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Total available: +$totalCoins coins',
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
              label: Text(claiming ? 'Claiming...' : 'Claim All Rewards'),
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
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${reward.seasonId} • ${reward.leagueName} • Rank #${reward.rank}',
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
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'No season rewards claimed yet.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final String seasonId;
  final String leagueName;
  final int rank;
  final int weeklyScore;
  final int rewardCoins;
  final String rewardMessage;

  const _HistoryTile({
    required this.seasonId,
    required this.leagueName,
    required this.rank,
    required this.weeklyScore,
    required this.rewardCoins,
    required this.rewardMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.black12,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: const Icon(Icons.workspace_premium),
        title: Text(
          '$seasonId • $leagueName',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Rank #$rank • Score $weeklyScore • $rewardMessage',
        ),
        trailing: Text(
          '+$rewardCoins',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
    );
  }
}