import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/pvp_league_service.dart';
import '../../services/pvp_season_service.dart';
import '../../widgets/add_friend_button.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../l10n/league_names.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../l10n/season_labels.dart';
import '../../widgets/player_actions_sheet.dart';
import 'pvp_season_widgets.dart';

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

  // Held so a tab switch doesn't re-subscribe the rating stream.
  late final _userDoc = FirebaseFirestore.instance
      .collection('users')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .snapshots();

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
    final season = _seasonService.currentSeason();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        // Avatar only: with the name beside it there is no room left for
        // "Temporada PvP" on a phone, and the title was cut to "Temporada…".
        actions: const [ProfileAvatarButton(showName: false)],
        title: AppBarTitle(l10n.pvpSeasonTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.shield), text: l10n.pvpSeasonTabSeason),
            Tab(icon: const Icon(Icons.leaderboard), text: l10n.pvpSeasonTabLeaderboard),
            Tab(icon: const Icon(Icons.card_giftcard), text: l10n.pvpSeasonTabRewards),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userDoc,
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() ?? {};
          final rating =
              ((userData['pvpRating'] ?? PvpLeagueService.defaultRating) as num)
                  .toInt();
          final ratingDelta =
              ((userData['pvpRatingDelta'] ?? 0) as num).toInt();
          final league = _leagueService.leagueForRating(rating);
          final reward = _seasonService.rewardForRating(rating);

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
                rating: rating,
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
    final l10n = AppLocalizations.of(context);
    const leagues = PvpLeagueService.leagues;
    final index = leagues.indexWhere((l) => l.id == league.id);
    final next =
        index >= 0 && index + 1 < leagues.length ? leagues[index + 1] : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SeasonHeroCard(
          seasonLabel: l10n.pvpSeasonLabel(l10n.pvpSeasonName(season.id)),
          leagueEmoji: league.emoji,
          leagueTitle: l10n.liveMenuLeagueTitle(
            l10n.leagueName(
              PvpLeagueService.instance.displayNameForRating(rating),
            ),
          ),
          leagueColor: Color(league.colorValue),
          rating: rating,
          deltaText: ratingDelta == 0
              ? null
              : PvpLeagueService.instance.formatDelta(ratingDelta),
          deltaPositive: ratingDelta > 0,
          progress: league.progressFor(rating),
          progressLabel: pointsToNextLeague(rating, next) == null
              ? l10n.pvpSeasonTopLeague
              : l10n.pvpSeasonToNextLeague(
                  pointsToNextLeague(rating, next)!,
                  l10n.leagueName(next!.id),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SeasonFactTile(
                icon: Icons.timer_outlined,
                label: l10n.pvpSeasonEndsLabel,
                value: seasonService.formatTimeLeft(season.timeLeft),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SeasonFactTile(
                illustration: 'assets/illustrations/coins.png',
                label: l10n.pvpSeasonRewardLabel,
                value: '+${reward.coins}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SeasonStepsCard(
          title: l10n.pvpSeasonHowItWorksTitle,
          steps: [
            (Icons.sports_esports_rounded, l10n.pvpSeasonHowItWorksBullet1),
            (Icons.shield_rounded, l10n.pvpSeasonHowItWorksBullet2),
            (Icons.leaderboard_rounded, l10n.pvpSeasonHowItWorksBullet3),
            (Icons.card_giftcard_rounded, l10n.pvpSeasonHowItWorksBullet4),
          ],
          footnote: l10n.pvpSeasonRankedHint,
        ),
      ],
    );
  }
}

/// How many rating points separate [rating] from [next], the league above
/// the player's; null when there is none above, or the player is already
/// in it.
int? pointsToNextLeague(int rating, PvpLeagueInfo? next) {
  if (next == null) return null;
  final points = next.minRating - rating;
  return points > 0 ? points : null;
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
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          SeasonPillTabBar(
            tabs: [
              SeasonPillTab(
                icon: Icons.group_rounded,
                label: l10n.pvpSeasonFriendsTab,
              ),
              SeasonPillTab(
                icon: Icons.public_rounded,
                label: l10n.pvpSeasonGlobalTab,
              ),
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
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: PvpLeagueService.leagues.length + 1,
      child: Column(
        children: [
          SeasonPillTabBar(
            scrollable: true,
            tabs: [
              SeasonPillTab(label: l10n.pvpSeasonAllTab),
              ...PvpLeagueService.leagues.map(
                (league) => SeasonPillTab(
                  label: '${league.emoji} ${l10n.leagueName(league.id)}',
                ),
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

class _FriendsLeaderboardList extends StatefulWidget {
  final String currentUid;
  final String Function(String avatarId) avatarBuilder;

  const _FriendsLeaderboardList({
    required this.currentUid,
    required this.avatarBuilder,
  });

  @override
  State<_FriendsLeaderboardList> createState() =>
      _FriendsLeaderboardListState();
}

class _FriendsLeaderboardListState extends State<_FriendsLeaderboardList> {
  late Future<List<_LeaderboardPlayer>> _playersFuture;

  @override
  void initState() {
    super.initState();
    _playersFuture = _loadPlayers();
  }

  Future<void> _refresh() async {
    final future = _loadPlayers();
    setState(() => _playersFuture = future);
    await future;
  }

  Future<List<_LeaderboardPlayer>> _loadPlayers() async {
    final currentUid = widget.currentUid;
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

      // Loaded from initState, before the strings can be looked up: a
      // missing name stays empty and the row fills it in.
      final username =
          (data['username'] ?? data['displayName'] ?? '').toString();

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
    final l10n = AppLocalizations.of(context);

    return FutureBuilder<List<_LeaderboardPlayer>>(
      future: _playersFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.pvpSeasonErrorLoadingFriends(userFacingError(AppLocalizations.of(context), snap.error!)),
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
                  Icon(
                    Icons.group_add_outlined,
                    size: 44,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.pvpSeasonNoFriendsTitle,
                    style: context.heading(18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    players.isEmpty
                        ? l10n.pvpSeasonNoFriendsEmptyHint
                        : l10n.pvpSeasonNoFriendsHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: players.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final player = players[i];
              final isMe = player.uid == widget.currentUid;
              final league = PvpLeagueService.instance.leagueForRating(
                player.rating,
              );

              return SeasonRankRow(
                position: i + 1,
                avatar: widget.avatarBuilder(player.avatarId),
                name: isMe
                    ? l10n.pvpSeasonYouSuffix(
                        player.username.isEmpty
                            ? l10n.asyncMatchPlayYouFallback
                            : player.username,
                      )
                    : (player.username.isEmpty
                        ? l10n.commonPlayerFallback
                        : player.username),
                leagueLine:
                    '${league.emoji} ${l10n.leagueName(league.id)} • ${l10n.pvpSeasonMatchesCount(player.matches)}',
                recordLine: l10n.pvpSeasonWinLossDraw(
                  player.wins,
                  player.losses,
                  player.draws,
                ),
                rating: player.rating,
                leagueColor: Color(league.colorValue),
                isMe: isMe,
                // Report or block a player from the friends ranking.
                onTap: () => showPlayerActions(
                  context,
                  uid: player.uid,
                  name: player.username,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _LeaderboardList extends StatefulWidget {
  final Query<Map<String, dynamic>> query;
  final String currentUid;
  final String Function(String avatarId) avatarBuilder;

  const _LeaderboardList({
    required this.query,
    required this.currentUid,
    required this.avatarBuilder,
  });

  @override
  State<_LeaderboardList> createState() => _LeaderboardListState();
}

// Stateful only to keep the leaderboard read across rebuilds.
class _LeaderboardListState extends State<_LeaderboardList> {
  // Read once per visit, like the weekly league's: a live listener on the
  // top 100 was re-billed every time any of them played a ranked match.
  late final _results = widget.query.get();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _results,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.pvpSeasonErrorLoadingLeaderboard(userFacingError(AppLocalizations.of(context), snap.error!)),
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
          return Center(
            child: Text(
              l10n.pvpSeasonNoRankedPlayers,
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
            final isMe = doc.id == widget.currentUid;
            final rating =
                ((data['pvpRating'] ?? PvpLeagueService.defaultRating) as num)
                    .toInt();
            final league = PvpLeagueService.instance.leagueForRating(rating);
            final username =
                (data['username'] ?? data['displayName'] ?? AppLocalizations.of(context).commonPlayerFallback)
                    .toString();
            final avatarId = (data['avatarId'] ?? 'avatar_1').toString();
            final wins = ((data['wins1v1'] ?? 0) as num).toInt();
            final losses = ((data['losses1v1'] ?? 0) as num).toInt();
            final draws = ((data['draws1v1'] ?? 0) as num).toInt();
            final matches = wins + losses + draws;

            return SeasonRankRow(
              position: i + 1,
              avatar: widget.avatarBuilder(avatarId),
              name: username,
              leagueLine:
                  '${league.emoji} ${l10n.leagueName(league.id)} • ${l10n.pvpSeasonMatchesCount(matches)}',
              recordLine: l10n.pvpSeasonWinLossDraw(wins, losses, draws),
              rating: rating,
              leagueColor: Color(league.colorValue),
              isMe: isMe,
              trailing: isMe ? null : AddFriendButton(targetUid: doc.id),
              // Report or block a player from the ranking.
              onTap: () => showPlayerActions(
                context,
                uid: doc.id,
                name: username,
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
  final int rating;
  final PvpSeasonService seasonService;

  const _RewardsTab({
    required this.uid,
    required this.currentLeague,
    required this.rating,
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

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.claimedCount == 0
                ? l10n.pvpSeasonNoPendingRewards
                : l10n.pvpSeasonClaimedRewards(result.claimedCount, result.totalCoins),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(AppLocalizations.of(context), e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: _refreshPendingRewards,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _CurrentRewardSummaryCard(
            currentLeague: widget.currentLeague,
            rating: widget.rating,
            seasonService: widget.seasonService,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.pvpSeasonRewardsTitle,
            style: context.heading(22),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pvpSeasonRewardsSubtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
                  message: userFacingError(AppLocalizations.of(context), snap.error!),
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
            final isCurrent = league.id == widget.currentLeague.id;
            final reward = isCurrent
                ? widget.seasonService.rewardForRating(widget.rating)
                : widget.seasonService.rewardForLeague(league);
            final displayName = l10n.leagueName(
              isCurrent
                  ? PvpLeagueService.instance.displayNameForRating(
                      widget.rating,
                    )
                  : league.id,
            );

            return SeasonLeagueRewardRow(
              emoji: league.emoji,
              title: l10n.liveMenuLeagueTitle(displayName),
              // The top league has no real ceiling: its stored maximum
              // (5000) read as a cap nobody reaches.
              range: league == PvpLeagueService.leagues.last
                  ? l10n.pvpLeagueRatingFrom(league.minRating)
                  : '${league.minRating}-${league.maxRating} MMR',
              coinsText: l10n.pvpSeasonPendingCoins(reward.coins),
              leagueColor: Color(league.colorValue),
              currentLabel:
                  isCurrent ? l10n.pvpSeasonCurrentProjectedReward : null,
            );
          }),
        ],
      ),
    );
  }
}

class _CurrentRewardSummaryCard extends StatelessWidget {
  final PvpLeagueInfo currentLeague;
  final int rating;
  final PvpSeasonService seasonService;

  const _CurrentRewardSummaryCard({
    required this.currentLeague,
    required this.rating,
    required this.seasonService,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reward = seasonService.rewardForRating(rating);
    final season = seasonService.currentSeason();

    return SeasonRewardSummaryCard(
      label: l10n.pvpSeasonCurrentProjectedReward,
      leagueTitle: l10n.liveMenuLeagueTitle(
        l10n.leagueName(
          PvpLeagueService.instance.displayNameForRating(rating),
        ),
      ),
      endsLine: l10n.pvpSeasonEndsInLine(
        seasonService.formatTimeLeft(season.timeLeft),
      ),
      coins: reward.coins,
      leagueColor: Color(currentLeague.colorValue),
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
        (total, reward) => total + reward.rewardCoins,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(context.radii.md),
          border: context.surfaces.borderOr(null),
          boxShadow: context.surfaces.shadowsOr(null),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            // Expanded so the sentence wraps: on a phone it is about 100 px
            // wider than the card, and overflowed while this was showing.
            Expanded(child: Text(l10n.pvpSeasonCheckingRewards)),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appColors.dangerBg,
          borderRadius: BorderRadius.circular(context.radii.md),
          boxShadow: context.surfaces.shadowsOr(null),
          border: context.surfaces.borderOr(
            Border.all(color: context.appColors.danger.withValues(alpha: 0.35)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: context.appColors.danger),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.pvpSeasonCouldNotLoad,
                    style: context.heading(16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.commonRetry),
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
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(context.radii.md),
          boxShadow: context.surfaces.shadowsOr(null),
          border: context.surfaces.borderOr(
            Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_clock,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pvpSeasonNoRewardYetTitle,
                    style: context.heading(16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.pvpSeasonNoRewardYetHint,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final pendingText = pendingRewards.length == 1
        ? l10n.pvpSeasonPendingSingle(pendingRewards.length)
        : l10n.pvpSeasonPendingMultiple(pendingRewards.length);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.rewardBg,
        borderRadius: BorderRadius.circular(context.radii.md),
        boxShadow: context.surfaces.shadowsOr(null),
        border: context.surfaces.borderOr(
          Border.all(color: context.appColors.reward.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/illustrations/chest.png',
                width: 44,
                height: 44,
                cacheWidth:
                    (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pendingText,
                  style: context.heading(16),
                ),
              ),
              Text(
                l10n.pvpSeasonPendingCoins(_totalCoins),
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
                          l10n.pvpSeasonPendingRewardLine(
                            l10n.pvpSeasonName(reward.seasonId),
                            l10n.leagueName(reward.leagueName),
                            reward.bestRating,
                          ),
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
              l10n.pvpSeasonMorePending(pendingRewards.length - 3),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
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
              label: Text(claiming ? l10n.pvpSeasonClaiming : l10n.pvpSeasonClaimAllButton),
            ),
          ),
        ],
      ),
    );
  }
}
