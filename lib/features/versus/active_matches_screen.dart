import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'async_match_play_screen.dart';

class ActiveMatchesScreen extends StatefulWidget {
  const ActiveMatchesScreen({super.key});

  @override
  State<ActiveMatchesScreen> createState() => _ActiveMatchesScreenState();
}

class _ActiveMatchesScreenState extends State<ActiveMatchesScreen> {
  static const Duration _loadTimeout = Duration(seconds: 12);
  static const Duration _autoRetryDelay = Duration(seconds: 5);

  late final String uid;

  bool _loading = true;
  String? _softError;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _yourTurn = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _waitingOpponent = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _finished = [];

  Timer? _retryTimer;
  bool _loadingNow = false;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _loadMatches();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _safeGet(
    Query<Map<String, dynamic>> query,
  ) {
    return query.get().timeout(
      _loadTimeout,
      onTimeout: () {
        throw TimeoutException('Firestore query timeout');
      },
    );
  }

  Future<void> _loadMatches({bool retry = false}) async {
    if (_loadingNow) return;

    _retryTimer?.cancel();
    _loadingNow = true;

    if (!retry && mounted) {
      setState(() {
        _loading = true;
        _softError = null;
      });
    }

    try {
      final db = FirebaseFirestore.instance.collection('async_matches');

      final results = await Future.wait([
        _safeGet(
          db
              .where('challengedUid', isEqualTo: uid)
              .where('challengedStatus', isEqualTo: 'pending')
              .orderBy('createdAt', descending: true),
        ),
        _safeGet(
          db
              .where('challengerUid', isEqualTo: uid)
              .where('challengerStatus', isEqualTo: 'finished')
              .where('challengedStatus', isEqualTo: 'pending')
              .orderBy('createdAt', descending: true),
        ),
        _safeGet(
          db
              .where('participants', arrayContains: uid)
              .where('status', isEqualTo: 'completed')
              .orderBy('updatedAt', descending: true)
              .limit(20),
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _yourTurn = results[0].docs;
        _waitingOpponent = results[1].docs;
        _finished = results[2].docs;
        _loading = false;
        _softError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _softError = 'Reconnecting...';
      });

      _retryTimer = Timer(_autoRetryDelay, () {
        if (mounted) {
          _loadMatches(retry: true);
        }
      });
    } finally {
      _loadingNow = false;
    }
  }

  Future<void> _refreshSilently() async {
    await _loadMatches(retry: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Matches'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSilently,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_softError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SoftStatusCard(text: _softError!),
              ),

            _AsyncMatchesSection(
              title: 'Your Turn',
              emptyText: _loading
                  ? 'Loading your matches...'
                  : 'No async matches waiting for you.',
              docs: _yourTurn,
              uid: uid,
              mode: _AsyncSectionMode.yourTurn,
              loading: _loading,
            ),

            const SizedBox(height: 22),

            _AsyncMatchesSection(
              title: 'Waiting For Opponent',
              emptyText: _loading
                  ? 'Loading matches...'
                  : 'No matches waiting for your opponent.',
              docs: _waitingOpponent,
              uid: uid,
              mode: _AsyncSectionMode.waitingOpponent,
              loading: _loading,
            ),

            const SizedBox(height: 22),

            _AsyncMatchesSection(
              title: 'Recently Finished',
              emptyText: _loading
                  ? 'Loading results...'
                  : 'No recent finished matches.',
              docs: _finished,
              uid: uid,
              mode: _AsyncSectionMode.finished,
              loading: _loading,
            ),
          ],
        ),
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
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String uid;
  final _AsyncSectionMode mode;
  final bool loading;

  const _AsyncMatchesSection({
    required this.title,
    required this.emptyText,
    required this.docs,
    required this.uid,
    required this.mode,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && docs.isEmpty) {
      return _SectionCard(
        title: title,
        child: const _LoadingLine(),
      );
    }

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

  int _challengerScore() {
    final raw = (data['challenger'] as Map?)?['score'] ?? 0;
    return raw is num ? raw.toInt() : 0;
  }

  int _challengedScore() {
    final raw = (data['challenged'] as Map?)?['score'] ?? 0;
    return raw is num ? raw.toInt() : 0;
  }

  String _subtitle() {
    final challengerScore = _challengerScore();
    final challengedScore = _challengedScore();

    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return 'Your turn • ${_category()}';
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

  String _buttonText() {
    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return 'Play';
      case _AsyncSectionMode.waitingOpponent:
        return 'View';
      case _AsyncSectionMode.finished:
        return 'Result';
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
        trailing: FilledButton.tonal(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AsyncMatchPlayScreen(
                  asyncMatchId: matchId,
                ),
              ),
            );
          },
          child: Text(_buttonText()),
        ),
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

class _LoadingLine extends StatelessWidget {
  const _LoadingLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
          Text('Loading...'),
        ],
      ),
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

class _SoftStatusCard extends StatelessWidget {
  final String text;

  const _SoftStatusCard({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}