import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import 'async_match_play_screen.dart';
import '../../l10n/generated/app_localizations.dart';

class AsyncFindPlayersScreen extends StatefulWidget {
  final String categoryId;
  final int difficulty;
  final int timePerQuestionSec;
  final int totalQuestions;
  final int winReward;

  const AsyncFindPlayersScreen({
    super.key,
    required this.categoryId,
    required this.difficulty,
    required this.timePerQuestionSec,
    required this.totalQuestions,
    required this.winReward,
  });

  @override
  State<AsyncFindPlayersScreen> createState() => _AsyncFindPlayersScreenState();
}

/// ✅ Modelo simple para evitar records
class _UserItem {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String name;

  _UserItem({
    required this.doc,
    required this.name,
  });
}

class _AsyncFindPlayersScreenState extends State<AsyncFindPlayersScreen> {
  final _db = FirebaseFirestore.instance;
  final _service = MatchService();
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  final _searchCtrl = TextEditingController();
  Future<QuerySnapshot<Map<String, dynamic>>>? _searchFuture;

  String? _error;
  String? _loadingUid;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Search-by-username instead of browsing every user — the old
  // `.collection('users').limit(50).snapshots()` + client-side filter only
  // ever showed the first 50 users in arbitrary Firestore order, making
  // most players unreachable once the userbase grew past that. Mirrors
  // FriendService.searchUsersByUsername's prefix-search pattern.
  void _onSearchChanged(String value) {
    final q = value.trim().toLowerCase();

    setState(() {
      _searchFuture = q.isEmpty
          ? null
          : _db
              .collection('users')
              .where('usernameLower', isGreaterThanOrEqualTo: q)
              .where('usernameLower', isLessThan: '$q')
              .limit(20)
              .get();
    });
  }

  Future<String> _getMyDisplayName() async {
    try {
      final me = await _db.collection('users').doc(_uid).get();
      final data = me.data();
      final name = (data?['displayName'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'Player';
  }

  String _safeDisplayName(Map<String, dynamic> data) {
    final v = (data['displayName'] ?? '').toString().trim();
    return v.isEmpty ? 'Player' : v;
  }

  Future<void> _challenge({
    required String challengedUid,
    required String challengedName,
  }) async {
    if (_loadingUid != null) return;

    setState(() {
      _loadingUid = challengedUid;
      _error = null;
    });

    try {
      if (challengedUid == _uid) {
        throw Exception(
          AppLocalizations.of(context).asyncFindPlayersCannotChallengeSelf,
        );
      }

      // 1) crear match async
      final matchId = await _service.createAsyncFixedMatch(
        challengedUid: challengedUid,
        categoryId: widget.categoryId,
        difficulty: widget.difficulty,
        totalQuestions: widget.totalQuestions,
        timePerQuestionSec: widget.timePerQuestionSec,
        winReward: widget.winReward,
      );

      // 2) guardar display names
      final myName = await _getMyDisplayName();

      await _db.collection('async_matches').doc(matchId).set({
        'challengerDisplayName': myName,
        'challengedDisplayName': challengedName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3) navegar a jugar
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AsyncMatchPlayScreen(asyncMatchId: matchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingUid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.asyncFindPlayersTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Config actual
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.liveMatchmakingCategoryLine(widget.categoryId)),
                  Text(l10n.liveMatchmakingDifficultyLine(widget.difficulty)),
                  Text(l10n.liveMatchmakingQuestionsLine(widget.totalQuestions)),
                  Text(l10n.liveMatchmakingTimePerQuestionLine(widget.timePerQuestionSec)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: l10n.asyncFindPlayersSearchLabel,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),

            if (_error != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 8),
            ],

            Expanded(
              child: _searchFuture == null
                  ? Center(child: Text(l10n.asyncFindPlayersSearchPrompt))
                  : FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _searchFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data?.docs ?? [];
                  final allDocs = docs.where((d) => d.id != _uid).toList();

                  final filtered = allDocs.map((d) {
                    final name = _safeDisplayName(d.data());
                    return _UserItem(doc: d, name: name);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(l10n.asyncFindPlayersNoneToShow),
                    );
                  }

                  // Ordenar por nombre
                  filtered.sort(
                    (a, b) => a.name.toLowerCase().compareTo(
                          b.name.toLowerCase(),
                        ),
                  );

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      final doc = item.doc;
                      final name = item.name;

                      final isLoadingThis = _loadingUid == doc.id;
                      final disableAll =
                          _loadingUid != null && !isLoadingThis;

                      return ListTile(
                        title: Text(name),
                        subtitle: Text(doc.id),
                        trailing: isLoadingThis
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FilledButton(
                                onPressed: disableAll
                                    ? null
                                    : () => _challenge(
                                          challengedUid: doc.id,
                                          challengedName: name,
                                        ),
                                child: Text(l10n.asyncFindPlayersChallengeButton),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
