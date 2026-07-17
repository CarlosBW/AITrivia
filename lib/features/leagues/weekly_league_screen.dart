import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/league_service.dart';
import '../../services/season_service.dart';
import '../../services/weekly_league_service.dart';
import '../../widgets/player_avatar_widget.dart';
import 'season_rewards_screen.dart';

class WeeklyLeagueScreen extends StatefulWidget {
  const WeeklyLeagueScreen({super.key});

  @override
  State<WeeklyLeagueScreen> createState() => _WeeklyLeagueScreenState();
}

class _WeeklyLeagueScreenState extends State<WeeklyLeagueScreen>
    with SingleTickerProviderStateMixin {
  final _weeklyService = WeeklyLeagueService.instance;
  final _seasonService = SeasonService.instance;

  late final TabController _tabController;

  Timer? _timer;
  Duration _timeLeft = Duration.zero;
  bool _claiming = false;

  Future<DocumentSnapshot<Map<String, dynamic>>>? _userFuture;
  Future<bool>? _hasPendingRewardsFuture;
  Future<QuerySnapshot<Map<String, dynamic>>>? _leaderboardFuture;

  String? _leaderboardKey;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _loadInitialData();
    _updateTimeLeft();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeLeft();
    });
  }

  void _loadInitialData() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    _userFuture =
        FirebaseFirestore.instance.collection('users').doc(uid).get();

    _hasPendingRewardsFuture =
        _seasonService.hasPendingSeasonRewards(uid: uid);
  }

  void _updateTimeLeft() {
    if (!mounted) return;

    setState(() {
      _timeLeft = _weeklyService.timeUntilReset();
    });
  }

  Future<void> _claimRewards(String uid) async {
    if (_claiming) return;

    setState(() => _claiming = true);

    try {
      final result =
          await _seasonService.claimAllPendingRewards(uid: uid);

      if (!mounted) return;

      _hasPendingRewardsFuture =
          _seasonService.hasPendingSeasonRewards(uid: uid);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.claimedCount == 0
                ? 'No pending weekly rewards.'
                : 'Claimed ${result.claimedCount} rewards: +${result.totalCoins} coins!',
          ),
        ),
      );

      setState(() {});
    } finally {
      if (mounted) {
        setState(() => _claiming = false);
      }
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _leaderboardFor({
    required String weekId,
    required LeagueInfo league,
  }) {
    final key = '$weekId|${league.id}';

    if (_leaderboardFuture == null || _leaderboardKey != key) {
      _leaderboardKey = key;

      _leaderboardFuture = _weeklyService
          .weeklyLeaderboardQuery(
            weekId: weekId,
            leagueId: league.id,
          )
          .get();
    }

    return _leaderboardFuture!;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    return '${days}d ${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Challenge'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.leaderboard),
              text: 'Ranking',
            ),
            Tab(
              icon: Icon(Icons.card_giftcard),
              text: 'Rewards',
            ),
          ],
        ),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _userFuture,
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (userSnap.hasError) {
            return Center(
              child: Text(
                'Error loading weekly challenge:\n${userSnap.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final userData = userSnap.data?.data() ?? {};

          final leagueScore =
              ((userData['leagueScore'] ?? 0) as num).toInt();

          final league =
              LeagueService.instance.getLeagueFromScore(leagueScore);

          final weekId = _weeklyService.currentWeekId();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: _LeagueHeader(
                  league: league,
                  leagueScore: leagueScore,
                  resetText: _formatDuration(_timeLeft),
                ),
              ),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // =====================================================
                    // RANKING TAB
                    // =====================================================

                    FutureBuilder<
                        QuerySnapshot<Map<String, dynamic>>>(
                      future: _leaderboardFor(
                        weekId: weekId,
                        league: league,
                      ),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(
                            child: Text(
                              'Error loading weekly challenge:\n${snap.error}',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        if (snap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snap.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No weekly scores yet.\nPlay a Daily Challenge to enter this weekly ranking.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          children: [
                            const Text(
                              'Weekly Ranking',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 14),

                            ...List.generate(docs.length, (index) {
                              final doc = docs[index];
                              final data = doc.data();

                              final isMe = doc.id == uid;
                              final rank = index + 1;

                              final username = isMe
                                  ? (userData['username'] ??
                                          userData['displayName'] ??
                                          data['username'] ??
                                          data['displayName'] ??
                                          'Player')
                                      .toString()
                                  : (data['username'] ??
                                          data['displayName'] ??
                                          'Player')
                                      .toString();

                              final avatarId = isMe
                                  ? (userData['avatarId'] ??
                                          data['avatarId'] ??
                                          'avatar_1')
                                      .toString()
                                  : (data['avatarId'] ?? 'avatar_1')
                                      .toString();

                              final frameId = isMe
                                  ? (userData['equippedFrame'] ??
                                          data['equippedFrame'])
                                      ?.toString()
                                  : data['equippedFrame']?.toString();

                              final bestLeagueId = isMe
                                  ? (userData['bestLeagueId'] ??
                                          data['bestLeagueId'])
                                      ?.toString()
                                  : data['bestLeagueId']?.toString();

                              final weeklyScore =
                                  ((data['weeklyScore'] ?? 0)
                                          as num)
                                      .toInt();

                              final level =
                                  ((data['level'] ?? 1) as num)
                                      .toInt();

                              final streak =
                                  ((data['streak'] ?? 0) as num)
                                      .toInt();

                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10),
                                child: _WeeklyLeagueTile(
                                  rank: rank,
                                  avatarId: avatarId,
                                  frameId: frameId,
                                  bestLeagueId: bestLeagueId,
                                  username: username,
                                  weeklyScore: weeklyScore,
                                  level: level,
                                  streak: streak,
                                  isMe: isMe,
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),

                    // =====================================================
                    // REWARDS TAB
                    // =====================================================

                    ListView(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16,
                      ),
                      children: [
                        _RewardsCard(
                          league: league,
                        ),

                        const SizedBox(height: 12),

                        FutureBuilder<bool>(
                          future: _hasPendingRewardsFuture,
                          builder: (context, rewardsSnap) {
                            if (rewardsSnap.connectionState ==
                                ConnectionState.waiting) {
                              return const _PendingRewardsLoadingCard();
                            }

                            final hasPending =
                                rewardsSnap.data == true;

                            if (!hasPending) {
                              return _RewardsHistoryButton(
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SeasonRewardsScreen(),
                                    ),
                                  );

                                  if (!context.mounted) return;

                                  setState(() {
                                    _hasPendingRewardsFuture =
                                        _seasonService
                                            .hasPendingSeasonRewards(
                                      uid: uid,
                                    );
                                  });
                                },
                              );
                            }

                            return _PendingRewardsCard(
                              claiming: _claiming,
                              onClaim: () => _claimRewards(uid),
                              onOpenRewards: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SeasonRewardsScreen(),
                                  ),
                                );

                                if (!context.mounted) return;

                                setState(() {
                                  _hasPendingRewardsFuture =
                                      _seasonService
                                          .hasPendingSeasonRewards(
                                    uid: uid,
                                  );
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// COMPONENTS
// ============================================================

class _LeagueHeader extends StatelessWidget {
  final LeagueInfo league;
  final int leagueScore;
  final String resetText;

  const _LeagueHeader({
    required this.league,
    required this.leagueScore,
    required this.resetText,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(league.colorValue);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: color.withOpacity(0.55),
        ),
      ),
      child: Column(
        children: [
          Text(
            '${league.emoji} ${league.name} Tier',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Weekly Score: $leagueScore',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Weekly reset in $resetText',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PendingRewardsLoadingCard extends StatelessWidget {
  const _PendingRewardsLoadingCard();

  @override
  Widget build(BuildContext context) {
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
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
          SizedBox(width: 12),
          Text('Checking pending weekly rewards...'),
        ],
      ),
    );
  }
}


class _RewardsHistoryButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RewardsHistoryButton({
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.workspace_premium),
        label: const Text('Reward history'),
      ),
    );
  }
}

class _PendingRewardsCard extends StatelessWidget {
  final bool claiming;
  final VoidCallback onClaim;
  final VoidCallback onOpenRewards;

  const _PendingRewardsCard({
    required this.claiming,
    required this.onClaim,
    required this.onOpenRewards,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.card_giftcard,
            size: 36,
          ),
          const SizedBox(height: 8),
          const Text(
            'Pending season rewards',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Open Weekly Rewards to see exact rank and coins.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: claiming
                      ? null
                      : onOpenRewards,
                  icon: const Icon(Icons.visibility),
                  label: const Text('View details'),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      claiming ? null : onClaim,
                  icon: claiming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.redeem),
                  label: Text(
                    claiming
                        ? 'Claiming...'
                        : 'Claim',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RewardsCard extends StatelessWidget {
  final LeagueInfo league;

  const _RewardsCard({
    required this.league,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(league.colorValue);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.card_giftcard),
              SizedBox(width: 8),
              Text(
                'Weekly Rewards',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          _RewardRow(
            medal: '🥇',
            text:
                'Top 1: ${league.top1Reward} coins + promotion bonus',
            color: color,
          ),

          const SizedBox(height: 8),

          _RewardRow(
            medal: '🥈',
            text:
                'Top 2-3: ${league.top3Reward} coins',
            color: color,
          ),

          const SizedBox(height: 8),

          _RewardRow(
            medal: '🥉',
            text:
                'Top 10: ${league.top10Reward} coins',
            color: color,
          ),

          const SizedBox(height: 12),

          const Text(
            'At the end of the week, rankings reset and rewards become claimable.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  final String medal;
  final String text;
  final Color color;

  const _RewardRow({
    required this.medal,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          medal,
          style: const TextStyle(fontSize: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontWeight:
                  FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _WeeklyLeagueTile extends StatelessWidget {
  final int rank;
  final String avatarId;
  final String? frameId;
  final String? bestLeagueId;
  final String username;
  final int weeklyScore;
  final int level;
  final int streak;
  final bool isMe;

  const _WeeklyLeagueTile({
    required this.rank,
    required this.avatarId,
    this.frameId,
    this.bestLeagueId,
    required this.username,
    required this.weeklyScore,
    required this.level,
    required this.streak,
    required this.isMe,
  });

  Color _rankColor() {
    if (rank == 1) return Colors.amber;
    if (rank == 2) return Colors.blueGrey;
    if (rank == 3) return Colors.brown;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final rankColor = _rankColor();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.deepPurple.withOpacity(0.14)
            : Colors.black12,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? Colors.deepPurple
              : Colors.transparent,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
                rankColor.withOpacity(0.18),
            child: Text(
              '#$rank',
              style: TextStyle(
                color: rankColor,
                fontWeight:
                    FontWeight.bold,
                fontSize:
                    rank <= 9 ? 13 : 11,
              ),
            ),
          ),

          const SizedBox(width: 10),

          PlayerAvatarWidget(
            avatarId: avatarId,
            frameId: frameId,
            bestLeagueId: bestLeagueId,
            radius: 20,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '$username${isMe ? '  (You)' : ''}',
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'Level $level  •  Streak $streak',
                  style:
                      const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          Column(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              const Text(
                'Weekly',
                style: TextStyle(fontSize: 12),
              ),
              Text(
                '$weeklyScore',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}