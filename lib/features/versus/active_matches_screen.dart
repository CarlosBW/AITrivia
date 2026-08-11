import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'async_match_play_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_avatar_button.dart';

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

      // Two separate queries per "finished"/"waiting" bucket below because
      // Firestore can't OR across two different fields (challengerUid vs
      // challengedUid) in one query — merged and re-sorted client-side.
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
        // The mirror of the query above — I already finished my side as
        // the *challenged* player, still waiting on the challenger. This
        // bucket was previously missing entirely, so a match in this state
        // was invisible here until the challenger acted.
        _safeGet(
          db
              .where('challengedUid', isEqualTo: uid)
              .where('challengedStatus', isEqualTo: 'finished')
              .where('challengerStatus', isEqualTo: 'pending')
              .orderBy('createdAt', descending: true),
        ),
        // `participants`/`updatedAt` are never actually written to an
        // async_matches doc — this query could never return anything.
        // `challengerUid`/`challengedUid`/`status`/`endedAt` are real
        // fields (finalizeAsyncPvpMatch and expireStaleAsyncMatches both
        // set them).
        _safeGet(
          db
              .where('challengerUid', isEqualTo: uid)
              .where('status', isEqualTo: 'completed')
              .orderBy('endedAt', descending: true)
              .limit(20),
        ),
        _safeGet(
          db
              .where('challengedUid', isEqualTo: uid)
              .where('status', isEqualTo: 'completed')
              .orderBy('endedAt', descending: true)
              .limit(20),
        ),
      ]);

      if (!mounted) return;

      final finished = [...results[3].docs, ...results[4].docs]
        ..sort((a, b) {
          final aTime = a.data()['endedAt'] as Timestamp?;
          final bTime = b.data()['endedAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });

      setState(() {
        _yourTurn = results[0].docs;
        _waitingOpponent = [...results[1].docs, ...results[2].docs];
        _finished = finished;
        _loading = false;
        _softError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _softError = AppLocalizations.of(context).activeMatchesReconnecting;
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
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: Text(l10n.activeMatchesTitle),
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
              title: l10n.activeMatchesYourTurn,
              emptyText: _loading
                  ? l10n.activeMatchesLoadingYourMatches
                  : l10n.activeMatchesNoneWaitingForYou,
              docs: _yourTurn,
              uid: uid,
              mode: _AsyncSectionMode.yourTurn,
              loading: _loading,
            ),

            const SizedBox(height: 22),

            _AsyncMatchesSection(
              title: l10n.activeMatchesWaitingForOpponent,
              emptyText: _loading
                  ? l10n.activeMatchesLoadingMatches
                  : l10n.activeMatchesNoneWaitingForOpponent,
              docs: _waitingOpponent,
              uid: uid,
              mode: _AsyncSectionMode.waitingOpponent,
              loading: _loading,
            ),

            const SizedBox(height: 22),

            _AsyncMatchesSection(
              title: l10n.activeMatchesRecentlyFinished,
              emptyText: _loading
                  ? l10n.activeMatchesLoadingResults
                  : l10n.activeMatchesNoneFinished,
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

  String _subtitle(AppLocalizations l10n) {
    final challengerScore = _challengerScore();
    final challengedScore = _challengedScore();

    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return l10n.activeMatchesYourTurnSubtitle(_category());
      case _AsyncSectionMode.waitingOpponent:
        return l10n.activeMatchesWaitingSubtitle(challengerScore);
      case _AsyncSectionMode.finished:
        final winnerUid = data['winnerUid'] as String?;

        if (winnerUid == null) {
          return l10n.activeMatchesDrawSubtitle(challengerScore, challengedScore);
        }

        if (winnerUid == uid) {
          return l10n.activeMatchesVictorySubtitle(challengerScore, challengedScore);
        }

        return l10n.activeMatchesDefeatSubtitle(challengerScore, challengedScore);
    }
  }

  String _buttonText(AppLocalizations l10n) {
    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return l10n.activeMatchesPlay;
      case _AsyncSectionMode.waitingOpponent:
        return l10n.activeMatchesView;
      case _AsyncSectionMode.finished:
        return l10n.activeMatchesResult;
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

  Color _statusColor(BuildContext context) {
    switch (mode) {
      case _AsyncSectionMode.yourTurn:
        return context.appColors.success;
      case _AsyncSectionMode.waitingOpponent:
        return context.appColors.reward;
      case _AsyncSectionMode.finished:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final opponent = _opponentName();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(context).withValues(alpha: 0.18),
          child: Icon(_icon(), color: _statusColor(context)),
        ),
        title: Text(
          l10n.profileVsOpponent(opponent),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(_subtitle(l10n)),
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
          child: Text(_buttonText(l10n)),
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
          style: context.heading(21),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(AppLocalizations.of(context).commonLoading),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
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
        color: context.appColors.reward.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(
          color: context.appColors.reward.withValues(alpha: 0.35),
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