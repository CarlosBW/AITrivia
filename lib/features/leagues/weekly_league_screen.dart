import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/league_service.dart';
import '../../services/weekly_league_service.dart';

class WeeklyLeagueScreen extends StatefulWidget {
  const WeeklyLeagueScreen({super.key});

  @override
  State<WeeklyLeagueScreen> createState() => _WeeklyLeagueScreenState();
}

class _WeeklyLeagueScreenState extends State<WeeklyLeagueScreen> {
  final _weeklyService = WeeklyLeagueService.instance;

  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTimeLeft();
    });
  }

  void _updateTimeLeft() {
    if (!mounted) return;

    setState(() {
      _timeLeft = _weeklyService.timeUntilReset();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    return '${days}d ${hours}h ${minutes}m';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly League'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, userSnap) {
          if (!userSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnap.data!.data() ?? {};
          final leagueScore = ((userData['leagueScore'] ?? 0) as num).toInt();
          final league = LeagueService.instance.getLeagueFromScore(leagueScore);
          final weekId = _weeklyService.currentWeekId();

          final query = _weeklyService.weeklyLeaderboardQuery(
            weekId: weekId,
            leagueId: league.id,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _LeagueHeader(
                  league: league,
                  leagueScore: leagueScore,
                  resetText: _formatDuration(_timeLeft),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'Error loading weekly league:\n${snap.error}',
                          textAlign: TextAlign.center,
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
                          'No weekly scores yet.\nPlay a Daily Challenge to enter this league.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();

                        final isMe = doc.id == uid;
                        final rank = index + 1;
                        final username =
                            (data['username'] ?? data['displayName'] ?? 'Player')
                                .toString();
                        final avatarId =
                            (data['avatarId'] ?? 'avatar_1').toString();
                        final weeklyScore =
                            ((data['weeklyScore'] ?? 0) as num).toInt();
                        final level = ((data['level'] ?? 1) as num).toInt();
                        final streak = ((data['streak'] ?? 0) as num).toInt();

                        return _WeeklyLeagueTile(
                          rank: rank,
                          avatar: _avatarEmoji(avatarId),
                          username: username,
                          weeklyScore: weeklyScore,
                          level: level,
                          streak: streak,
                          isMe: isMe,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

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
            '${league.emoji} ${league.name} League',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'League Score: $leagueScore',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Season resets in $resetText',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _WeeklyLeagueTile extends StatelessWidget {
  final int rank;
  final String avatar;
  final String username;
  final int weeklyScore;
  final int level;
  final int streak;
  final bool isMe;

  const _WeeklyLeagueTile({
    required this.rank,
    required this.avatar,
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
        color: isMe ? Colors.deepPurple.withOpacity(0.14) : Colors.black12,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? Colors.deepPurple : Colors.transparent,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: rankColor.withOpacity(0.18),
            child: Text(
              '#$rank',
              style: TextStyle(
                color: rankColor,
                fontWeight: FontWeight.bold,
                fontSize: rank <= 9 ? 13 : 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.8),
            child: Text(
              avatar,
              style: const TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$username${isMe ? '  (You)' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Level $level  •  Streak $streak',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Weekly',
                style: TextStyle(fontSize: 12),
              ),
              Text(
                '$weeklyScore',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}