import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/pvp_league_service.dart';
import '../../services/pvp_season_service.dart';
import '../../widgets/tier_badge.dart';
import '../../theme/app_theme.dart';

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
          final rating =
              ((userData['pvpRating'] ?? PvpLeagueService.defaultRating) as num)
                  .toInt();
          final ratingDelta =
              ((userData['pvpRatingDelta'] ?? 0) as num).toInt();
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TierBadge(
                emoji: league.emoji,
                name: '${league.name} League',
                colorValue: league.colorValue,
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
                        color:
                            ratingDelta > 0 ? Colors.green : Colors.redAccent,
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
              Text(
                  '• Rewards are based on your final league when the season ends.'),
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
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.group), text: 'Friends'),
              Tab(icon: Icon(Icons.public), text: 'Global'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _FriendsLeaderboardList(
                  currentUid: currentUid,
                  avatarBuilder: avatarBuilder,
                ),
                _GlobalLeaderboardTab(
                  currentUid: currentUid,
                  avatarBuilder: avatarBuilder,
                  seasonService: seasonService,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalLeaderboardTab extends StatelessWidget {
  final String currentUid;
  final String Function(String avatarId) avatarBuilder;
  final PvpSeasonService seasonService;

  const _GlobalLeaderboardTab({
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
              const Tab(text: 'All'),
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

class _LeaderboardPlayer {
  final String uid;
  final String username;
  final String avatarId;
  final int rating;
  final int wins;
  final int losses;
  final int draws;

  const _LeaderboardPlayer({
    required this.uid,
    required this.username,
    required this.avatarId,
    required this.rating,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  int get matches => wins + losses + draws;
}

class _FriendsLeaderboardList extends StatelessWidget {
  final String currentUid;
  final String Function(String avatarId) avatarBuilder;

  const _FriendsLeaderboardList({
    required this.currentUid,
    required this.avatarBuilder,
  });

  Future<List<_LeaderboardPlayer>> _loadPlayers() async {
    final db = FirebaseFirestore.instance;

    final friendsSnap = await db
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .limit(100)
        .get();

    final ids = <String>{currentUid};
    for (final doc in friendsSnap.docs) {
      final data = doc.data();
      final friendUid = (data['uid'] ?? doc.id).toString();
      if (friendUid.trim().isNotEmpty) ids.add(friendUid);
    }

    final userSnaps = await Future.wait(
      ids.map((id) => db.collection('users').doc(id).get()),
    );

    final players = <_LeaderboardPlayer>[];

    for (final snap in userSnaps) {
      final data = snap.data();
      if (data == null) continue;

      final username = (data['username'] ??
              data['displayName'] ??
              (snap.id == currentUid ? 'You' : 'Player'))
          .toString();

      players.add(
        _LeaderboardPlayer(
          uid: snap.id,
          username: username,
          avatarId: (data['avatarId'] ?? 'avatar_1').toString(),
          rating: ((data['pvpRating'] ?? PvpLeagueService.defaultRating) as num)
              .toInt(),
          wins: ((data['wins1v1'] ?? 0) as num).toInt(),
          losses: ((data['losses1v1'] ?? 0) as num).toInt(),
          draws: ((data['draws1v1'] ?? 0) as num).toInt(),
        ),
      );
    }

    players.sort((a, b) {
      final ratingCompare = b.rating.compareTo(a.rating);
      if (ratingCompare != 0) return ratingCompare;
      return b.matches.compareTo(a.matches);
    });

    return players;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_LeaderboardPlayer>>(
      future: _loadPlayers(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading friends leaderboard:\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final players = snap.data ?? const <_LeaderboardPlayer>[];

        if (players.length <= 1) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.group_add, size: 44, color: Colors.black54),
                  const SizedBox(height: 12),
                  const Text(
                    'No friends in leaderboard yet',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    players.isEmpty
                        ? 'Play Ranked Matches and add friends to compare your PvP rating.'
                        : 'Add friends to compare your PvP rating with people you know.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            // Rebuilds the FutureBuilder by changing the element tree through setState
            // is not available here because this widget is stateless. Pull refresh still
            // completes after re-fetching through a new navigation/rebuild cycle.
            await _loadPlayers();
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: players.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final player = players[i];
              final isMe = player.uid == currentUid;
              final league = PvpLeagueService.instance.leagueForRating(
                player.rating,
              );
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
                      child: Text(avatarBuilder(player.avatarId)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '${player.username} (You)' : player.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${league.emoji} ${league.name} • ${player.matches} matches',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${player.wins} W / ${player.losses} L / ${player.draws} D',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${player.rating} MMR',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
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
            final rating =
                ((data['pvpRating'] ?? PvpLeagueService.defaultRating) as num)
                    .toInt();
            final league = PvpLeagueService.instance.leagueForRating(rating);
            final username =
                (data['username'] ?? data['displayName'] ?? 'Player')
                    .toString();
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
  Future<List<PendingPvpSeasonReward>>? _pendingRewardsFuture;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _reloadPendingRewards();
  }

  void _reloadPendingRewards() {
    _pendingRewardsFuture = widget.seasonService.getPendingPvpSeasonRewards(
      uid: widget.uid,
    );
  }

  Future<void> _refreshPendingRewards() async {
    setState(_reloadPendingRewards);
  }

  Future<void> _claimAllRewards() async {
    if (_claiming) return;

    setState(() => _claiming = true);

    try {
      final result = await widget.seasonService.claimAllPendingPvpSeasonRewards(
        uid: widget.uid,
      );

      if (!mounted) return;

      await _refreshPendingRewards();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.claimedCount == 0
                ? 'No pending PvP season rewards available.'
                : 'Claimed ${result.claimedCount} PvP season reward(s): +${result.totalCoins} coins!',
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
    return RefreshIndicator(
      onRefresh: _refreshPendingRewards,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _CurrentRewardSummaryCard(
            currentLeague: widget.currentLeague,
            seasonService: widget.seasonService,
          ),
          const SizedBox(height: 16),
          const Text(
            'Season Rewards',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rewards are based on your best PvP league from each finished season.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<PendingPvpSeasonReward>>(
            future: _pendingRewardsFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _PendingRewardsCard.loading();
              }

              if (snap.hasError) {
                return _PendingRewardsCard.error(
                  message: snap.error.toString(),
                  onRetry: _refreshPendingRewards,
                );
              }

              final pendingRewards =
                  snap.data ?? const <PendingPvpSeasonReward>[];

              return _PendingRewardsCard(
                pendingRewards: pendingRewards,
                claiming: _claiming,
                onClaimAll: pendingRewards.isNotEmpty && !_claiming
                    ? _claimAllRewards
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
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
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
      ),
    );
  }
}

class _CurrentRewardSummaryCard extends StatelessWidget {
  final PvpLeagueInfo currentLeague;
  final PvpSeasonService seasonService;

  const _CurrentRewardSummaryCard({
    required this.currentLeague,
    required this.seasonService,
  });

  @override
  Widget build(BuildContext context) {
    final reward = seasonService.rewardForLeague(currentLeague);
    final season = seasonService.currentSeason();
    final color = Color(currentLeague.colorValue);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Text(
            currentLeague.emoji,
            style: const TextStyle(fontSize: 38),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current projected reward',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${currentLeague.name} League',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Season ends in ${seasonService.formatTimeLeft(season.timeLeft)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '+${reward.coins}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRewardsCard extends StatelessWidget {
  final List<PendingPvpSeasonReward> pendingRewards;
  final bool claiming;
  final VoidCallback? onClaimAll;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const _PendingRewardsCard({
    required this.pendingRewards,
    required this.claiming,
    required this.onClaimAll,
  })  : loading = false,
        errorMessage = null,
        onRetry = null;

  const _PendingRewardsCard.loading()
      : pendingRewards = const [],
        claiming = false,
        onClaimAll = null,
        loading = true,
        errorMessage = null,
        onRetry = null;

  const _PendingRewardsCard.error({
    required String message,
    required VoidCallback this.onRetry,
  })  : pendingRewards = const [],
        claiming = false,
        onClaimAll = null,
        loading = false,
        errorMessage = message;

  int get _totalCoins => pendingRewards.fold<int>(
        0,
        (sum, reward) => sum + reward.rewardCoins,
      );

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
            Text('Checking pending PvP season rewards...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Could not load rewards',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (pendingRewards.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.blueGrey.withOpacity(0.35)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_clock, color: Colors.blueGrey),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No reward available yet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Play Ranked Matches this season. When the season ends, your PvP reward will appear here.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final plural = pendingRewards.length == 1 ? 'reward' : 'rewards';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${pendingRewards.length} pending season $plural',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '+$_totalCoins coins',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...pendingRewards.take(3).map(
                (reward) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reward.leagueEmoji),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${reward.seasonId} • ${reward.leagueName} • best ${reward.bestRating} MMR',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '+${reward.rewardCoins}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (pendingRewards.length > 3)
            Text(
              '+${pendingRewards.length - 3} more pending season(s)',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: claiming ? null : onClaimAll,
              icon: claiming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
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
