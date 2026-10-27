import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import 'async_match_play_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/category_name_builder.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../theme/app_theme.dart';
import '../../l10n/season_labels.dart';
import '../../services/player_safety_service.dart';
import '../../widgets/player_actions_sheet.dart';

class AsyncFindPlayersScreen extends StatefulWidget {
  final String categoryId;
  final int difficulty;
  final int timePerQuestionSec;
  final int totalQuestions;

  const AsyncFindPlayersScreen({
    super.key,
    required this.categoryId,
    required this.difficulty,
    required this.timePerQuestionSec,
    required this.totalQuestions,
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

  /// Players this one blocked, left out of the results.
  Set<String> _blocked = const {};
  StreamSubscription<Set<String>>? _blockedSub;

  @override
  void initState() {
    super.initState();
    _blockedSub = PlayerSafetyService.instance.watchBlocked().listen((ids) {
      if (mounted) setState(() => _blocked = ids);
    });
  }

  @override
  void dispose() {
    _blockedSub?.cancel();
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

  String _safeDisplayName(Map<String, dynamic> data) {
    final v = (data['displayName'] ?? '').toString().trim();
    return v.isEmpty ? AppLocalizations.of(context).commonPlayerFallback : v;
  }

  Future<void> _challenge({
    required String challengedUid,
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

      // 1) crear match async. Antes se creaba el doc aquí y luego se
      //    escribían los nombres en un segundo `set`; ahora lo crea
      //    createAsyncPvpMatch, que además resuelve ambos nombres desde los
      //    docs de usuario y manda la notificación del reto.
      final matchId = await _service.createAsyncFixedMatch(
        challengedUid: challengedUid,
        categoryId: widget.categoryId,
        difficulty: widget.difficulty,
        totalQuestions: widget.totalQuestions,
        timePerQuestionSec: widget.timePerQuestionSec,
      );

      // 2) navegar a jugar
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AsyncMatchPlayScreen(asyncMatchId: matchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(AppLocalizations.of(context), e));
    } finally {
      if (mounted) setState(() => _loadingUid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l10n.asyncFindPlayersTitle),
        actions: const [ProfileAvatarButton()],
      ),
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
                  CategoryNameBuilder(
                    categoryId: widget.categoryId,
                    builder: (context, name) =>
                        Text(l10n.liveMatchmakingCategoryLine(name)),
                  ),
                  Text(l10n.liveMatchmakingDifficultyLine(l10n.difficultyLabel(widget.difficulty))),
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
                  style: TextStyle(color: context.appColors.danger),
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
                  final allDocs = docs
                      .where((d) => d.id != _uid && !_blocked.contains(d.id))
                      .toList();

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
                        onTap: () => showPlayerActions(
                          context,
                          uid: doc.id,
                          name: name,
                        ),
                        title: Text(name),
                        trailing: isLoadingThis
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FilledButton(
                                onPressed: disableAll
                                    ? null
                                    : () => _challenge(challengedUid: doc.id),
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
