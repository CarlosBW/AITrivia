import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'async_match_play_screen.dart';

class ActiveMatchesScreen extends StatelessWidget {
  const ActiveMatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Matches'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AsyncMatchesSection(
            title: 'Your Turn',
            emptyText: 'No async matches waiting for you.',
            query: FirebaseFirestore.instance
                .collection('async_matches')
                .where('challengedUid', isEqualTo: uid)
                .where('challengedStatus', isEqualTo: 'pending')
                .orderBy('createdAt', descending: true),
            uid: uid,
            mode: _AsyncSectionMode.yourTurn,
          ),
          const SizedBox(height: 22),
          _AsyncMatchesSection(
            title: 'Waiting For Opponent',
            emptyText: 'No matches waiting for your opponent.',
            query: FirebaseFirestore.instance
                .collection('async_matches')
                .where('challengerUid', isEqualTo: uid)
                .where('challengerStatus', isEqualTo: 'finished')
                .where('challengedStatus', isEqualTo: 'pending')
                .orderBy('createdAt', descending: true),
            uid: uid,
            mode: _AsyncSectionMode.waitingOpponent,
          ),
          const SizedBox(height: 22),
          _AsyncMatchesSection(
            title: 'Recently Finished',
            emptyText: 'No recent finished matches.',
            query: FirebaseFirestore.instance
                .collection('async_matches')
                .where('participants', arrayContains: uid)
                .where('status', isEqualTo: 'completed')
                .orderBy('updatedAt', descending: true)
                .limit(20),
            uid: uid,
            mode: _AsyncSectionMode.finished,
          ),
        ],
      ),
    );
  }
}

enum _AsyncSectionMode {
  yourTurn,
  waitingOpponent,
  finished,
}

class _AsyncMatchesSection extends StatelessWidget {
  final String title;
  final String emptyText;
  final Query<Map<String, dynamic>> query;
  final String uid;
  final _AsyncSectionMode mode;

  const _AsyncMatchesSection({
    required this.title,
    required this.emptyText,
    required this.query,
    required this.uid,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _SectionCard(
            title: title,
            child: Text(
              'Error loading matches:\n${snap.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        if (!snap.hasData) {
          return _SectionCard(
            title: title,
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return _SectionCard(
            title: title,
            child: _EmptyLine(text: emptyText),
          );
        }

        return _SectionCard(
          title: title,
          child: Column(
            children: docs.map((doc) {
              final data = doc.data();
              return _AsyncMatchTile(
                matchId: doc.id,
                data: data,
                uid: uid,
                mode: mode,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _AsyncMatchTile extends StatelessWidget {
  final String matchId;
  final Map<String, dynamic> data;
  final String uid;
  final _AsyncSectionMode mode;

  const _AsyncMatchTile({
    required this.matchId,
    required this.data,
    required this.uid,
    required this.mode,
  });

  String _opponentName() {
    final challengerUid = (data['challengerUid'] ?? '').toString();
    final isChallenger = challengerUid == uid;

    if (isChallenger) {
      return (data['challengedDisplayName'] ?? 'Player').toString();
    }

    return (data['challengerDisplayName'] ?? 'Player').toString();
  }

  String _category() {
    return (data['categoryId'] ?? 'random').toString();
  }

  String _subtitle() {
    final challengerScore = ((data['challenger']?['score']) ?? 0) as int;
    final challengedScore = ((data['challenged']?['score']) ?? 0) as int;

    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return 'Pending • ${_category()}';
      case _AsyncSectionMode.waitingOpponent:
        return 'Waiting • Your score: $challengerScore';
      case _AsyncSectionMode.finished:
        final winnerUid = data['winnerUid'] as String?;

        if (winnerUid == null) {
          return 'Draw • $challengerScore-$challengedScore';
        }

        if (winnerUid == uid) {
          return 'Victory • $challengerScore-$challengedScore';
        }

        return 'Defeat • $challengerScore-$challengedScore';
    }
  }

  IconData _icon() {
    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return Icons.play_arrow;
      case _AsyncSectionMode.waitingOpponent:
        return Icons.hourglass_bottom;
      case _AsyncSectionMode.finished:
        return Icons.emoji_events_outlined;
    }
  }

  Color _statusColor() {
    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return Colors.green;
      case _AsyncSectionMode.waitingOpponent:
        return Colors.orange;
      case _AsyncSectionMode.finished:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final opponent = _opponentName();

    return Card(
      elevation: 0,
      color: Colors.black12,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor().withOpacity(0.18),
          child: Icon(_icon(), color: _statusColor()),
        ),
        title: Text(
          'vs $opponent',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(_subtitle()),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AsyncMatchPlayScreen(asyncMatchId: matchId),
            ),
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
      ),
    );
  }
}