import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/daily_challenge_service.dart';

class DailyLeaderboardScreen extends StatelessWidget {
  const DailyLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final dateId = DailyChallengeService.instance.todayDateId();

    final leaderboardQuery = FirebaseFirestore.instance
        .collection('daily_leaderboards')
        .doc(dateId)
        .collection('players')
        .orderBy('score', descending: true)
        .limit(50);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Leaderboard'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: leaderboardQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error loading leaderboard:\n${snap.error}',
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
                'No scores yet today.\nPlay the Daily Challenge first!',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final isMe = doc.id == uid;
              final rank = index + 1;

              final displayName =
                  (data['displayName'] ?? 'Player').toString();
              final score = (data['score'] ?? 0).toString();
              final correct = (data['correct'] ?? 0).toString();
              final totalAnswered =
                  (data['totalAnswered'] ?? 0).toString();
              final streak = (data['streak'] ?? 0).toString();

              return _LeaderboardTile(
                rank: rank,
                displayName: displayName,
                score: score,
                correct: correct,
                totalAnswered: totalAnswered,
                streak: streak,
                isMe: isMe,
              );
            },
          );
        },
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final int rank;
  final String displayName;
  final String score;
  final String correct;
  final String totalAnswered;
  final String streak;
  final bool isMe;

  const _LeaderboardTile({
    required this.rank,
    required this.displayName,
    required this.score,
    required this.correct,
    required this.totalAnswered,
    required this.streak,
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
    final rankColor = _rankColor();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMe ? Colors.deepPurple.withOpacity(0.14) : Colors.black12,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? Colors.deepPurple : Colors.transparent,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: rankColor.withOpacity(0.18),
            child: Icon(
              _rankIcon(),
              color: rankColor,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$rank $displayName${isMe ? '  (You)' : ''}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Correct: $correct / $totalAnswered  •  Streak: $streak',
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
                'Score',
                style: TextStyle(fontSize: 12),
              ),
              Text(
                score,
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