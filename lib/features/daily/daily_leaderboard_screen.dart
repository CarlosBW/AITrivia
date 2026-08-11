import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/daily_challenge_service.dart';
import '../../services/league_service.dart';
import '../../widgets/player_avatar_widget.dart';
import '../../widgets/add_friend_button.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../theme/app_theme.dart';

// Stateful only to hold the leaderboard query: built inside `build()` it
// was a fresh Future on every rebuild, and this one is a 50-document read,
// not a single doc. Any ancestor repaint — or simply pushing a profile on
// top and coming back — re-ran the whole query and bounced the table back
// to a spinner.
class DailyLeaderboardScreen extends StatefulWidget {
  const DailyLeaderboardScreen({super.key});

  @override
  State<DailyLeaderboardScreen> createState() => _DailyLeaderboardScreenState();
}

class _DailyLeaderboardScreenState extends State<DailyLeaderboardScreen> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _leaderboard;

  @override
  void initState() {
    super.initState();

    // Resolved once, on open. The board is a snapshot of the day either
    // way — reopening the screen is what refreshes it.
    final dateId = DailyChallengeService.instance.todayDateId();

    _leaderboard = FirebaseFirestore.instance
        .collection('daily_leaderboards')
        .doc(dateId)
        .collection('players')
        .orderBy('score', descending: true)
        .limit(50)
        .get();
  }

  LeagueInfo _leagueFromData(Map<String, dynamic> data) {
    final leagueId = (data['leagueId'] ?? 'bronze').toString();

    return LeagueService.leagues.firstWhere(
      (l) => l.id == leagueId,
      orElse: () => LeagueService.leagues.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: Text(l10n.dailyLeaderboardTitle),
      ),
      body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _leaderboard,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                l10n.dailyLeaderboardErrorLoading(snap.error.toString()),
                textAlign: TextAlign.center,
              ),
            );
          }

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snap.hasData) {
            return Center(
              child: Text(
                l10n.dailyLeaderboardNoData,
                textAlign: TextAlign.center,
              ),
            );
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Text(
                l10n.dailyLeaderboardNoScoresYet,
                textAlign: TextAlign.center,
              ),
            );
          }

          final topThree = docs.take(3).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (topThree.isNotEmpty)
                _TopThreePodium(
                  players: topThree,
                  currentUid: uid,
                  leagueBuilder: _leagueFromData,
                ),
              const SizedBox(height: 16),
              Text(
                l10n.dailyLeaderboardRankingTitle,
                style: context.heading(20),
              ),
              const SizedBox(height: 10),
              ...List.generate(docs.length, (index) {
                final doc = docs[index];
                final data = doc.data();

                final isMe = doc.id == uid;
                final rank = index + 1;

                final displayName =
                    (data['username'] ?? data['displayName'] ?? 'Player')
                        .toString();
                final score = ((data['score'] ?? 0) as num).toInt();
                final correct = ((data['correct'] ?? 0) as num).toInt();
                final totalAnswered =
                    ((data['totalAnswered'] ?? 0) as num).toInt();
                final streak = ((data['streak'] ?? 0) as num).toInt();
                final league = _leagueFromData(data);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LeaderboardTile(
                    rank: rank,
                    targetUid: doc.id,
                    player: data,
                    displayName: displayName,
                    score: score,
                    correct: correct,
                    totalAnswered: totalAnswered,
                    streak: streak,
                    league: league,
                    isMe: isMe,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _TopThreePodium extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> players;
  final String currentUid;
  final LeagueInfo Function(Map<String, dynamic> data) leagueBuilder;

  const _TopThreePodium({
    required this.players,
    required this.currentUid,
    required this.leagueBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (players.length > 1)
            Expanded(
              child: _PodiumPlayer(
                rank: 2,
                doc: players[1],
                isMe: players[1].id == currentUid,
                leagueBuilder: leagueBuilder,
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          Expanded(
            child: _PodiumPlayer(
              rank: 1,
              doc: players[0],
              isMe: players[0].id == currentUid,
              leagueBuilder: leagueBuilder,
              large: true,
            ),
          ),
          const SizedBox(width: 8),
          if (players.length > 2)
            Expanded(
              child: _PodiumPlayer(
                rank: 3,
                doc: players[2],
                isMe: players[2].id == currentUid,
                leagueBuilder: leagueBuilder,
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }
}

class _PodiumPlayer extends StatelessWidget {
  final int rank;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isMe;
  final bool large;
  final LeagueInfo Function(Map<String, dynamic> data) leagueBuilder;

  const _PodiumPlayer({
    required this.rank,
    required this.doc,
    required this.isMe,
    required this.leagueBuilder,
    this.large = false,
  });

  String _medal() {
    if (rank == 1) return '🥇';
    if (rank == 2) return '🥈';
    return '🥉';
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final name =
        (data['username'] ?? data['displayName'] ?? 'Player').toString();
    final score = ((data['score'] ?? 0) as num).toInt();
    final league = leagueBuilder(data);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: EdgeInsets.all(large ? 14 : 10),
      decoration: BoxDecoration(
        color: isMe
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.20)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(
          color: isMe ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            _medal(),
            style: TextStyle(fontSize: large ? 30 : 24),
          ),
          const SizedBox(height: 6),
          PlayerAvatarWidget.fromPlayer(
            data,
            radius: large ? 32 : 25,
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: large ? 15 : 13,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${league.emoji} ${league.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(league.colorValue),
              fontSize: large ? 12 : 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            AppLocalizations.of(context).dailyLeaderboardPtsSuffix(score),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
              fontSize: large ? 14 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final int rank;
  final String targetUid;
  final Map<String, dynamic> player;
  final String displayName;
  final int score;
  final int correct;
  final int totalAnswered;
  final int streak;
  final LeagueInfo league;
  final bool isMe;

  const _LeaderboardTile({
    required this.rank,
    required this.targetUid,
    required this.player,
    required this.displayName,
    required this.score,
    required this.correct,
    required this.totalAnswered,
    required this.streak,
    required this.league,
    required this.isMe,
  });

  IconData _rankIcon() {
    if (rank == 1) return Icons.emoji_events;
    if (rank == 2) return Icons.military_tech;
    if (rank == 3) return Icons.workspace_premium;
    return Icons.person;
  }

  Color _rankColor() {
    if (rank == 1) return Colors.amber;
    if (rank == 2) return Colors.blueGrey;
    if (rank == 3) return Colors.brown;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rankColor = _rankColor();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMe
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: rankColor.withValues(alpha: 0.18),
            child: rank <= 3
                ? Icon(
                    _rankIcon(),
                    color: rankColor,
                  )
                : Text(
                    '$rank',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(width: 10),
          PlayerAvatarWidget.fromPlayer(
            player,
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? l10n.dailyLeaderboardNameWithYou(displayName) : displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${league.emoji} ${l10n.liveMenuLeagueTitle(league.name)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(league.colorValue),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.dailyLeaderboardCorrectStreakLine(correct, totalAnswered, streak),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                l10n.dailyLeaderboardScoreLabel,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '$score',
                style: context.heading(20),
              ),
            ],
          ),
          if (!isMe) AddFriendButton(targetUid: targetUid),
        ],
      ),
    );
  }
}