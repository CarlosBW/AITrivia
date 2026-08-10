import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/economy_service.dart';
import '../../services/locale_controller.dart';
import '../../services/match_service.dart';
import '../../services/presence_service.dart';
import '../../services/pvp_league_service.dart';
import 'match_lobby_screen.dart';
import 'async_menu_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_for.dart';
import '../../widgets/profile_avatar_button.dart';

class LiveMatchmakingScreen extends StatefulWidget {
  final String categoryId;
  final int difficulty;
  final int timePerQuestionSec;
  final int totalQuestions;
  final int winReward;
  final String displayName;
  final bool ranked;

  const LiveMatchmakingScreen({
    super.key,
    required this.categoryId,
    this.difficulty = 1,
    this.timePerQuestionSec = 15,
    this.totalQuestions = 10,
    this.winReward = EconomyService.defaultPvpWinReward,
    this.displayName = 'Player',
    this.ranked = false,
  });

  @override
  State<LiveMatchmakingScreen> createState() => _LiveMatchmakingScreenState();
}

class _LiveMatchmakingScreenState extends State<LiveMatchmakingScreen>
    with WidgetsBindingObserver {
  final _service = MatchService();
  final _presenceService = PresenceService.instance;

  // Held rather than rebuilt in `build()`: the search poll ticks every five
  // seconds and rebuilds this screen each time.
  late final _queueStream = _service.watchMyLiveQueue();

  static const Duration _pollInterval = Duration(seconds: 5);
  static const Duration _searchTimeout = Duration(seconds: 90);

  bool _searching = false;
  bool _starting = false;
  bool _matchAttemptRunning = false;
  bool _navigatingToLobby = false;

  Timer? _pollTimer;
  Timer? _timeoutTimer;
  String? _error;
  bool _timedOut = false;

  late final Future<String> _categoryDisplayNameFuture =
      _resolveCategoryDisplayName();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  // Shows the real fixed_categories name (e.g. "Música") instead of the
  // raw doc id (e.g. "musica") the widget is constructed with.
  Future<String> _resolveCategoryDisplayName() async {
    if (widget.categoryId == 'random') {
      return l10nFor(LocaleController.instance.locale.value.languageCode)
          .friendChallengeCategoryRandom;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('fixed_categories')
          .doc(widget.categoryId)
          .get();
      final name = snap.data()?['name'];
      if (name is String && name.isNotEmpty) return name;
    } catch (_) {}

    if (widget.categoryId.isEmpty) return widget.categoryId;
    return widget.categoryId[0].toUpperCase() + widget.categoryId.substring(1);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cancel(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();

    // No se espera el Future para evitar bloquear dispose.
    // Si ya navegamos al lobby, cleanupMyLiveQueueAfterMatch se encarga del reset.
    if (_searching && !_navigatingToLobby) {
      _service.stopLiveSearch();
      _presenceService.setAvailable();
    }

    super.dispose();
  }


  int _searchAgeSeconds(Map<String, dynamic>? data) {
    final raw = data?['searchStartedAt'] ?? data?['createdAt'];
    if (raw is! Timestamp) return 0;

    final age = DateTime.now().difference(raw.toDate()).inSeconds;
    return age < 0 ? 0 : age;
  }

  Widget _rankedSearchWindowCard(Map<String, dynamic>? data) {
    final l10n = AppLocalizations.of(context);
    final rating = ((data?['pvpRating'] ?? PvpLeagueService.defaultRating) as num).toInt();
    final league = PvpLeagueService.instance.leagueForRating(rating);
    final seconds = _searchAgeSeconds(data);
    final windowLabel = PvpLeagueService.instance.matchmakingLabelFor(l10n, seconds);
    final windowDescription =
        PvpLeagueService.instance.matchmakingDescriptionFor(l10n, seconds);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color(league.colorValue).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(league.colorValue).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${league.emoji} ${league.name} • $rating MMR',
            style: TextStyle(
              color: Color(league.colorValue),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            windowLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            windowDescription,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    if (_starting || _searching) return;

    setState(() {
      _starting = true;
      _searching = true;
      _error = null;
      _timedOut = false;
    });

    try {
      await _presenceService.setSearchingMatch();
      await _service.startLiveSearch(
        categoryId: widget.categoryId,
        difficulty: widget.difficulty,
        totalQuestions: widget.totalQuestions,
        timePerQuestionSec: widget.timePerQuestionSec,
        winReward: widget.winReward,
        displayName: widget.displayName,
        ranked: widget.ranked,
      );

      await _tryFindOpponentOnce();

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        _tryFindOpponentOnce();
      });

      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(_searchTimeout, () async {
        if (!mounted || !_searching || _navigatingToLobby) return;

        await _cancel(silent: true);

        if (!mounted) return;
        setState(() {
          _error = AppLocalizations.of(context).liveMatchmakingNoOpponentFound;
          _timedOut = true;
        });
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _searching = false;
      });

      try {
        await _service.stopLiveSearch();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _tryFindOpponentOnce() async {
    if (!mounted) return;
    if (!_searching) return;
    if (_matchAttemptRunning) return;
    if (_navigatingToLobby) return;

    _matchAttemptRunning = true;

    try {
      // Keeps lastHeartbeatAt fresh — without this, _isLiveQueueEntryValid
      // (both here and in the opponent's own pairing attempt) starts
      // rejecting this session as stale after the first 30s, silently
      // making it unmatchable for the rest of the search.
      await _service.updateLiveSearchHeartbeat();

      // Pairing (category/difficulty/ranked/reward, etc.) is now entirely
      // server-side — the Cloud Function reads it all from this session's
      // own live_search doc (already written by startLiveSearch), so no
      // arguments are needed here anymore.
      await _service.tryFindLiveOpponent();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      _matchAttemptRunning = false;
    }
  }

  Future<void> _cancel({bool silent = false}) async {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();

    if (mounted) {
      setState(() {
        _searching = false;
        _starting = false;
      });
    }

    try {
      await _service.stopLiveSearch();
      await _presenceService.setAvailable();
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _goToLobby(String matchId) async {
    if (_navigatingToLobby) return;

    _navigatingToLobby = true;
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();

    if (mounted) {
      setState(() => _searching = false);
    }

    try {
      await _service.cleanupMyLiveQueueAfterMatch();
      await _presenceService.setInMatch();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchLobbyScreen(matchId: matchId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: Text(
          widget.ranked
              ? l10n.liveMatchmakingRankedTitle
              : l10n.liveMatchmakingCasualTitle,
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _queueStream,
        builder: (context, snap) {
          final data = snap.data?.data();
          final status = (data?['status'] ?? '').toString();
          final matchId = data?['matchId'] as String?;

          if (matchId != null && !_navigatingToLobby) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _goToLobby(matchId);
            });
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.liveMatchmakingTypeLine(
                  widget.ranked ? l10n.profileRanked : l10n.profileCasual,
                )),
                FutureBuilder<String>(
                  future: _categoryDisplayNameFuture,
                  builder: (context, snap) {
                    return Text(
                      l10n.liveMatchmakingCategoryLine(
                        snap.data ?? widget.categoryId,
                      ),
                    );
                  },
                ),
                Text(l10n.liveMatchmakingDifficultyLine(widget.difficulty)),
                Text(l10n.liveMatchmakingQuestionsLine(widget.totalQuestions)),
                Text(l10n.liveMatchmakingTimePerQuestionLine(widget.timePerQuestionSec)),
                // Matchmaking pairs on category/difficulty/ranked only, and
                // the match takes whichever side claimed it first — so the
                // two lines above are a preference, not a promise. Ranked
                // says nothing because both sides are on the same defaults
                // there and the player picked none of it.
                if (!widget.ranked) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.liveMatchmakingSettingsMayVary,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (widget.ranked) ...[
                  _rankedSearchWindowCard(data),
                  const SizedBox(height: 16),
                ],
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_timedOut) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AsyncMenuScreen(
                              difficulty: widget.difficulty,
                              timePerQuestionSec: widget.timePerQuestionSec,
                              totalQuestions: widget.totalQuestions,
                              winReward: widget.winReward,
                            ),
                          ),
                        );
                      },
                      child: Text(l10n.liveMatchmakingTryAsyncInstead),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_searching) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _starting ? null : _start,
                      child: _starting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.liveMatchmakingSearchButton),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status.isEmpty
                              ? l10n.liveMatchmakingSearching
                              : status == 'searching'
                                  ? l10n.liveMatchmakingSearchingOpponent
                                  : l10n.liveMatchmakingQueueStatus(status),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.ranked
                        ? l10n.liveMatchmakingRankedHint
                        : l10n.liveMatchmakingCasualHint,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _cancel(),
                      child: Text(l10n.liveMatchmakingCancelSearch),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
