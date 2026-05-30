import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/pvp_league_service.dart';
import '../../services/pvp_season_service.dart';

class PvpSeasonScreen extends StatefulWidget {
  const PvpSeasonScreen({super.key});

  @override
  State<PvpSeasonScreen> createState() => _PvpSeasonScreenState();
}

class _PvpSeasonScreenState extends State<PvpSeasonScreen>
    with SingleTickerProviderStateMixin {
  final _seasonService = PvpSeasonService.instance;
  final _leagueService = PvpLeagueService.instance;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _avatarEmoji(String avatarId) {
    const avatars = {
      'avatar_1': '🧠',
      'avatar_2': '🚀',
      'avatar_3': '🎮',
      'avatar_4': '🔥',
      'avatar_5': '⭐',
      'avatar_6': '🐱',
      'avatar_7': '🤖',
      'avatar_8': '🏆',
    };

    return avatars[avatarId] ?? '🙂';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final season = _seasonService.currentSeason();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PvP Season'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.shield), text: 'Season'),
            Tab(icon: Icon(Icons.leaderboard), text: 'Leaderboard'),
            Tab(icon: Icon(Icons.card_giftcard), text: 'Rewards'),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() ?? {};
          final rating = ((userData['pvpRating'] ??
                  PvpLeagueService.defaultRating) as num)
              .toInt();
          final ratingDelta = ((userData['pvpRatingDelta'] ?? 0) as num).toInt();
          final league = _leagueService.leagueForRating(rating);
          final reward = _seasonService.rewardForLeague(league);

          return TabBarView(
            controller: _tabController,
            children: [
              _SeasonOverviewTab(
                season: season,
                league: league,
                rating: rating,
                ratingDelta: ratingDelta,
                reward: reward,
                seasonService: _seasonService,
              ),
              _LeaderboardTab(
                currentUid: uid,
                avatarBuilder: _avatarEmoji,
                seasonService: _seasonService,
              ),
              _RewardsTab(
                uid: uid,
                currentLeague: league,
                seasonService: _seasonService,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SeasonOverviewTab extends StatelessWidget {
  final PvpSeasonInfo season;
  final PvpLeagueInfo league;
  final int rating;
  final int ratingDelta;
  final PvpSeasonRewardInfo reward;
  final PvpSeasonService seasonService;

  const _SeasonOverviewTab({
    required this.season,
    required this.league,
    required this.rating,
    required this.ratingDelta,
    required this.reward,
    required this.seasonService,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(league.colorValue);
    final deltaText = ratingDelta == 0
        ? null
        : PvpLeagueService.instance.formatDelta(ratingDelta);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${league.emoji} ${league.name} League',
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '$rating MMR',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  if (deltaText != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '($deltaText)',
                      style: TextStyle(
                        color: ratingDelta > 0 ? Colors.green : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: league.progressFor(rating),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 14),
              Text('Season: ${season.id}'),
              Text('Ends in: ${seasonService.formatTimeLeft(season.timeLeft)}'),
              const SizedBox(height: 12),
              Text(
                'Projected reward: +${reward.coins} coins',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ranked uses flexible matchmaking: first it looks near your league, then expands the range so players are not left waiting.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How PvP Seasons work',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text('• Play Ranked Matches to increase your MMR.'),
              Text('• Your league is calculated from your current MMR.'),
              Text('• Leaderboards rank players by MMR.'),
              Text('• Rewards are based on your final league when the season ends.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  final String currentUid;
  final String Function(String avatarId) avatarBuilder;
  final PvpSeasonService seasonService;

  const _LeaderboardTab({
    required this.currentUid,
    required this.avatarBuilder,
    required this.seasonService,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: PvpLeagueService.leagues.length + 1,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'Global'),
              ...PvpLeagueService.leagues.map(
                (league) => Tab(text: '${league.emoji} ${league.name}'),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LeaderboardList(
                  query: seasonService.globalLeaderboardQuery(limit: 100),
                  currentUid: currentUid,
                  avatarBuilder: avatarBuilder,
                ),
                ...PvpLeagueService.leagues.map(
                  (league) => _LeaderboardList(
                    query: seasonService.leagueLeaderboardQuery(
                      league: league,
                      limit: 100,
                    ),
                    currentUid: currentUid,
                    avatarBuilder: avatarBuilder,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final String currentUid;
  final String Function(String avatarId) avatarBuilder;

  const _LeaderboardList({
    required this.query,
    required this.currentUid,
    required this.avatarBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading leaderboard:\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No ranked players yet.\nPlay Ranked Match to enter this leaderboard.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final isMe = doc.id == currentUid;
            final rating = ((data['pvpRating'] ??
                    PvpLeagueService.defaultRating) as num)
                .toInt();
            final league = PvpLeagueService.instance.leagueForRating(rating);
            final username =
                (data['username'] ?? data['displayName'] ?? 'Player').toString();
            final avatarId = (data['avatarId'] ?? 'avatar_1').toString();
            final wins = ((data['wins1v1'] ?? 0) as num).toInt();
            final losses = ((data['losses1v1'] ?? 0) as num).toInt();
            final draws = ((data['draws1v1'] ?? 0) as num).toInt();
            final matches = wins + losses + draws;
            final color = Color(league.colorValue);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMe ? color.withOpacity(0.14) : Colors.black12,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isMe ? color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      '#${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: Colors.white70,
                    child: Text(avatarBuilder(avatarId)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${league.emoji} ${league.name} • $matches matches',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '$wins W / $losses L / $draws D',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$rating MMR',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RewardsTab extends StatefulWidget {
  final String uid;
  final PvpLeagueInfo currentLeague;
  final PvpSeasonService seasonService;

  const _RewardsTab({
    required this.uid,
    required this.currentLeague,
    required this.seasonService,
  });

  @override
  State<_RewardsTab> createState() => _RewardsTabState();
}

class _RewardsTabState extends State<_RewardsTab> {
  Future<PvpSeasonClaimStatus>? _claimStatusFuture;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _claimStatusFuture = widget.seasonService.getClaimStatus(uid: widget.uid);
  }

  Future<void> _reloadClaimStatus() async {
    setState(() {
      _claimStatusFuture = widget.seasonService.getClaimStatus(uid: widget.uid);
    });
  }

  Future<void> _claimReward() async {
    if (_claiming) return;

    setState(() => _claiming = true);

    try {
      final result = await widget.seasonService.claimPreviousSeasonReward(
        uid: widget.uid,
      );

      if (!mounted) return;

      await _reloadClaimStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyClaimed
                ? 'Reward already claimed for ${result.seasonId}.'
                : 'Claimed ${result.leagueName} reward: +${result.rewardCoins} coins!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previousSeason = widget.seasonService.previousSeason();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Season Rewards',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Rewards are based on your final PvP league at the end of the season.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        FutureBuilder<PvpSeasonClaimStatus>(
          future: _claimStatusFuture,
          builder: (context, snap) {
            final status = snap.data;

            if (snap.connectionState == ConnectionState.waiting) {
              return const _ClaimRewardCard.loading();
            }

            return _ClaimRewardCard(
              seasonId: previousSeason.id,
              canClaim: status?.canClaim == true,
              alreadyClaimed: status?.alreadyClaimed == true,
              claiming: _claiming,
              onClaim: status?.canClaim == true && !_claiming
                  ? _claimReward
                  : null,
            );
          },
        ),
        const SizedBox(height: 16),
        ...PvpLeagueService.leagues.reversed.map((league) {
          final reward = widget.seasonService.rewardForLeague(league);
          final color = Color(league.colorValue);
          final isCurrent = league.id == widget.currentLeague.id;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCurrent ? color.withOpacity(0.14) : Colors.black12,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isCurrent ? color : Colors.transparent,
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(league.emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${league.name} League',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${league.minRating}-${league.maxRating} MMR',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (isCurrent)
                        const Text(
                          'Current projected reward',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                    ],
                  ),
                ),
                Text(
                  '+${reward.coins} coins',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _ClaimRewardCard extends StatelessWidget {
  final String? seasonId;
  final bool canClaim;
  final bool alreadyClaimed;
  final bool claiming;
  final VoidCallback? onClaim;
  final bool loading;

  const _ClaimRewardCard({
    required this.seasonId,
    required this.canClaim,
    required this.alreadyClaimed,
    required this.claiming,
    required this.onClaim,
  }) : loading = false;

  const _ClaimRewardCard.loading()
      : seasonId = null,
        canClaim = false,
        alreadyClaimed = false,
        claiming = false,
        onClaim = null,
        loading = true;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
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
            Text('Checking previous season reward...'),
          ],
        ),
      );
    }

    IconData icon;
    String title;
    String subtitle;
    Color color;

    if (alreadyClaimed) {
      icon = Icons.verified;
      title = 'Reward already claimed';
      subtitle = 'You already claimed your reward for $seasonId.';
      color = Colors.green;
    } else if (canClaim) {
      icon = Icons.card_giftcard;
      title = 'Previous season reward available';
      subtitle = 'Claim your reward for $seasonId based on your current PvP league.';
      color = Colors.amber;
    } else {
      icon = Icons.lock_clock;
      title = 'No reward available yet';
      subtitle = 'Finish the current PvP season to claim your reward.';
      color = Colors.blueGrey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.black54),
          ),
          if (canClaim) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: claiming ? null : onClaim,
                icon: claiming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.redeem),
                label: Text(claiming ? 'Claiming...' : 'Claim Reward'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
