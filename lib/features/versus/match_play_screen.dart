import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/match_service.dart';
import '../../services/sfx_service.dart';
import '../../services/presence_service.dart';
import '../../services/analytics_service.dart';
import 'pvp_result_card.dart';
import 'find_opponent_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_chip.dart';

class MatchPlayScreen extends StatefulWidget {
  final String matchId;

  const MatchPlayScreen({
    super.key,
    required this.matchId,
  });

  @override
  State<MatchPlayScreen> createState() => _MatchPlayScreenState();
}

class _MatchPlayScreenState extends State<MatchPlayScreen> {
  final _service = MatchService();
  final _presenceService = PresenceService.instance;

  int _index = 0;

  int _secondsLeft = 0;
  Timer? _timer;
  int _timerForIndex = -1;

  bool _locked = false;
  int? _selected;

  bool _finishedSent = false;
  bool _finishing = false;

  bool _timedOut = false;
  int? _timeoutAnswerIndex;
  bool _autoNextScheduled = false;

  String? _statusMsg;

  bool _answerSubmitting = false;

  bool _requestingRematch = false;
  bool _navigatedToRematch = false;
  bool _presenceInitialized = false;
  bool _leavingMatch = false;
  bool _resultLogged = false;

  Timer? _disconnectWatchTimer;
  DateTime? _opponentUnavailableSince;
  bool _disconnectCheckRunning = false;
  bool _disconnectFinalizing = false;

  bool _rematchPromptShowing = false;

  static const int _defaultTimePerQ = 10;
  static const Duration _revealDelay = Duration(seconds: 1);
  static const Duration _switchDuration = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();

    _disconnectWatchTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // La validación se ejecuta desde build con el último snapshot del match.
    });

    Future.microtask(() async {
      if (_presenceInitialized) return;

      _presenceInitialized = true;

      try {
        await _presenceService.setInMatch();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disconnectWatchTimer?.cancel();

    if (!_navigatedToRematch && !_leavingMatch) {
      _presenceService.setAvailable();
    }

    super.dispose();
  }

  void _resetPerQuestion() {
    _locked = false;
    _selected = null;
    _timedOut = false;
    _timeoutAnswerIndex = null;
    _autoNextScheduled = false;
    _statusMsg = null;
    _answerSubmitting = false;
  }

  void _startTimerForQuestion(int seconds, int questionIndex, int answerIndex) {
    _timer?.cancel();

    _timerForIndex = questionIndex;
    _secondsLeft = seconds;

    _resetPerQuestion();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        if (_locked) {
          t.cancel();
          return;
        }

        final next = _secondsLeft - 1;

        if (next <= 0) {
          _secondsLeft = 0;
          t.cancel();

          _locked = true;
          _timedOut = true;
          _timeoutAnswerIndex = answerIndex;
          _statusMsg = AppLocalizations.of(context).levelPlayTimeUp;

          SfxService.instance.playTimeout();

          if (!_autoNextScheduled) {
            _autoNextScheduled = true;
            Future.delayed(_revealDelay, () {
              if (!mounted) return;
              if (_index == questionIndex) _goNextQuestion();
            });
          }
        } else {
          _secondsLeft = next;
        }
      });
    });
  }

  void _goNextQuestion() {
    if (!mounted) return;

    setState(() {
      _index++;
      _timerForIndex = -1;
      _timer = null;
      _resetPerQuestion();
    });
  }

  Future<void> _exitToPvpMenu(BuildContext context) async {
    _leavingMatch = true;

    try {
      await _presenceService.setAvailable();
    } catch (_) {}

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const FindOpponentScreen(),
      ),
      (route) => route.isFirst,
    );
  }

  Future<void> _maybeShowIncomingRematchDialog({
    required BuildContext context,
    required Map<String, dynamic> match,
    required String uid,
    required String opponentUid,
    required String opponentName,
    required bool myRematchAccepted,
    required bool opponentRematchAccepted,
  }) async {
    if (_rematchPromptShowing) return;
    if (myRematchAccepted) return;
    if (!opponentRematchAccepted) return;

    _rematchPromptShowing = true;
    final l10n = AppLocalizations.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.matchPlayRematchRequestTitle),
          content: Text(l10n.matchPlayRematchRequestBody(opponentName)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: Text(l10n.navLater),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _requestRematch(match);
              },
              child: Text(l10n.realtimeInvitesAccept),
            ),
          ],
        );
      },
    );

    _rematchPromptShowing = false;
  }

  Future<void> _onTapAnswer({
    required int tappedIndex,
    required int answerIndex,
  }) async {
    if (_answerSubmitting) return;
    if (_locked) return;
    if (_secondsLeft <= 0) return;

    setState(() {
      _answerSubmitting = true;
      _selected = tappedIndex;
      _locked = true;

      _timedOut = false;
      _timeoutAnswerIndex = null;
      _statusMsg = null;
    });

    _timer?.cancel();

    final correct = tappedIndex == answerIndex;

    if (correct) {
      SfxService.instance.playCorrect();
    } else {
      SfxService.instance.playWrong();
    }

    await _service.submitAnswer(
      matchId: widget.matchId,
      questionIndex: _index,
      selectedAnswerIndex: tappedIndex,
      deltaScore: correct ? 1 : 0,
    );

    if (!_autoNextScheduled) {
      _autoNextScheduled = true;
      Future.delayed(_revealDelay, () {
        if (!mounted) return;
        _goNextQuestion();
      });
    }
  }

  Future<void> _checkOpponentDisconnect({
    required Map<String, dynamic> matchData,
    required String myUid,
  }) async {
    if (_disconnectCheckRunning || _disconnectFinalizing) return;

    final status = (matchData['status'] ?? '').toString();
    if (status != 'playing') {
      _opponentUnavailableSince = null;
      return;
    }

    final hostUid = (matchData['hostUid'] ?? '').toString();
    final guestUid = (matchData['guestUid'] ?? '').toString();
    final opponentUid = myUid == hostUid ? guestUid : hostUid;
    if (opponentUid.isEmpty || opponentUid == myUid) return;

    _disconnectCheckRunning = true;

    try {
      final opponentSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(opponentUid)
          .get();

      final opponentData = opponentSnap.data();
      final presence = Map<String, dynamic>.from(
        opponentData?['presence'] as Map? ?? {},
      );

      final presenceStatus = (presence['status'] ?? 'offline').toString();
      final inMatch = presence['inMatch'] == true;
      final isFresh = _presenceService.isProbablyOnline(presence);
      final opponentOk = isFresh && presenceStatus == 'in_match' && inMatch;

      if (opponentOk) {
        _opponentUnavailableSince = null;
        return;
      }

      _opponentUnavailableSince ??= DateTime.now();

      final unavailableFor = DateTime.now().difference(
        _opponentUnavailableSince!,
      );

      if (unavailableFor < const Duration(seconds: 30)) return;

      _disconnectFinalizing = true;
      await _service.forceFinishMatchByDisconnect(
        matchId: widget.matchId,
        winnerUid: myUid,
      );
    } catch (_) {
      // No romper UX si la lectura falla momentáneamente.
    } finally {
      _disconnectCheckRunning = false;
    }
  }

  Future<void> _finishMatch() async {
    if (_finishedSent || _finishing) return;

    _finishing = true;
    _timer?.cancel();

    try {
      await _service.setFinished(widget.matchId);

      if (!mounted) return;

      setState(() {
        _finishedSent = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _finishedSent = false;
        _statusMsg = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _finishing = false;
    }
  }

  Future<void> _requestRematch(Map<String, dynamic> match) async {
    if (_requestingRematch) return;

    final existingRematchId = (match['rematchMatchId'] ?? '').toString();

    // ✅ Si ya existe revancha, navegar directamente
    if (existingRematchId.isNotEmpty) {
      _goToRematch(existingRematchId);
      return;
    }

    setState(() {
      _requestingRematch = true;
    });

    try {
      await _service.requestRematch(widget.matchId);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _requestingRematch = false;
        });
      }
    }
  }

  void _goToRematch(String rematchMatchId) {
    if (_navigatedToRematch) return;

    _navigatedToRematch = true;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchPlayScreen(
          matchId: rematchMatchId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final l10n = AppLocalizations.of(context);

    final ref =
        FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.matchPlayTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            _leavingMatch = true;

            try {
              await _presenceService.setAvailable();
            } catch (_) {}

            if (!context.mounted) return;

            Navigator.popUntil(context, (route) => route.isFirst);
          },
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();

          if (data == null) {
            return Center(child: Text(l10n.matchPlayNotFound));
          }

          final status = (data['status'] ?? 'waiting').toString();

          if (status != 'playing' && status != 'finished') {
            return Center(child: Text(l10n.matchPlayWaitingToStart));
          }

          if (status == 'playing') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _checkOpponentDisconnect(matchData: data, myUid: uid);
            });
          }

          final timePerQ =
              ((data['timePerQuestionSec'] ?? _defaultTimePerQ) as num).toInt();

          final questions = data['questions'] as List<dynamic>? ?? [];

          if (questions.isEmpty) {
            return Center(
              child: Text(l10n.matchPlayNoQuestions),
            );
          }

          final players = Map<String, dynamic>.from(data['players'] ?? {});
          final me = Map<String, dynamic>.from(players[uid] ?? {});
          final myScore = ((me['score'] ?? 0) as num).toInt();
          final hostUid = (data['hostUid'] ?? '').toString();
          final guestUid = (data['guestUid'] ?? '').toString();

          final hostData = Map<String, dynamic>.from(players[hostUid] ?? {});
          final guestData = Map<String, dynamic>.from(players[guestUid] ?? {});

          final bothFinished =
              hostData['finished'] == true && guestData['finished'] == true;

          if (status == 'playing' && bothFinished && !_finishing) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (_finishing) return;

              _finishing = true;

              try {
                await _service.forceFinalizeMatch(widget.matchId);
              } finally {
                _finishing = false;
              }
            });
          }

          if (status == 'finished') {
            _timer?.cancel();
            return _buildEnd(context, data, uid);
          }

          if (_index >= questions.length) {
            if (!_finishedSent && !_finishing) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _finishMatch();
              });
            }

            return _buildWaitingFinish(
              context,
              data,
              uid,
              myScore,
            );
          }

          final qMap = Map<String, dynamic>.from(
            questions[_index] as Map,
          );

          final qText = (qMap['q'] ?? '').toString();

          final options = (qMap['options'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();

          final answerIndex = ((qMap['answerIndex'] ?? 0) as num).toInt();

          if (_timerForIndex != _index) {
            _startTimerForQuestion(
              timePerQ,
              _index,
              answerIndex,
            );
          }

          return AnimatedSwitcher(
            duration: _switchDuration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) {
              final slide = Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(anim);

              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: slide,
                  child: child,
                ),
              );
            },
            child: _buildQuestionView(
              key: ValueKey('match_q_$_index'),
              qText: qText,
              options: options,
              answerIndex: answerIndex,
              total: questions.length,
              myScore: myScore,
              timePerQ: timePerQ,
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionView({
    required Key key,
    required String qText,
    required List<String> options,
    required int answerIndex,
    required int total,
    required int myScore,
    required int timePerQ,
  }) {
    final l10n = AppLocalizations.of(context);
    final absorbing = _locked || _answerSubmitting;
    final colorScheme = Theme.of(context).colorScheme;

    final progress = total == 0 ? 0.0 : (_index / total).clamp(0.0, 1.0);

    final timeFraction =
        timePerQ == 0 ? 0.0 : (_secondsLeft / timePerQ).clamp(0.0, 1.0);

    final timerColor = timeFraction > 0.5
        ? AppColors.success
        : timeFraction > 0.2
            ? AppColors.reward
            : AppColors.danger;

    return AbsorbPointer(
      key: key,
      absorbing: absorbing,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.levelPlayQuestionOfTotal(_index + 1, total),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation(colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: timerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: timerColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: timerColor),
                      const SizedBox(width: 5),
                      Text(
                        '${_secondsLeft}s',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: timerColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StatChip(
              icon: Icons.emoji_events_outlined,
              label: l10n.matchPlayYourScoreLabel,
              value: '$myScore',
              fullWidth: true,
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                qText,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ...List.generate(options.length, (i) {
              final isSelected = _selected == i;
              final isCorrect = i == answerIndex;
              final letter = String.fromCharCode(65 + i);

              Color? fillColor;

              if (_locked && !_timedOut) {
                if (isCorrect) {
                  fillColor = AppColors.success.withValues(alpha: 0.16);
                }

                if (isSelected && !isCorrect) {
                  fillColor = AppColors.danger.withValues(alpha: 0.16);
                }
              } else if (!_locked && isSelected) {
                fillColor = colorScheme.surfaceContainerHighest;
              }

              Color borderColor = colorScheme.outline;
              double borderWidth = 1;

              if (_timedOut && _timeoutAnswerIndex != null) {
                if (i == _timeoutAnswerIndex) {
                  borderColor = AppColors.reward;
                  borderWidth = 3;
                }
              } else if (_locked) {
                if (isCorrect) {
                  borderColor = AppColors.success;
                  borderWidth = 2;
                }

                if (isSelected && !isCorrect) {
                  borderColor = AppColors.danger;
                  borderWidth = 2;
                }
              } else if (isSelected) {
                borderColor = colorScheme.primary;
                borderWidth = 2;
              }

              final badgeColor = (_locked && isCorrect)
                  ? AppColors.success
                  : (_locked && isSelected && !isCorrect)
                      ? AppColors.danger
                      : (!_locked && isSelected)
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest;

              final badgeTextColor =
                  badgeColor == colorScheme.surfaceContainerHighest
                      ? colorScheme.onSurfaceVariant
                      : Colors.white;

              IconData? trailingIcon;
              Color? trailingIconColor;
              if (_locked && !_timedOut) {
                if (isCorrect) {
                  trailingIcon = Icons.check_circle;
                  trailingIconColor = AppColors.success;
                } else if (isSelected) {
                  trailingIcon = Icons.cancel;
                  trailingIconColor = AppColors.danger;
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _onTapAnswer(
                    tappedIndex: i,
                    answerIndex: answerIndex,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: fillColor ?? colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            letter,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: badgeTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            options[i],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (trailingIcon != null) ...[
                          const SizedBox(width: 8),
                          Icon(trailingIcon, color: trailingIconColor),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
            SizedBox(
              height: 22,
              child: _statusMsg == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: Text(
                        _statusMsg!,
                        style: const TextStyle(
                          color: AppColors.reward,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  int? _safeIntOrNull(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _buildWaitingFinish(
    BuildContext context,
    Map<String, dynamic> match,
    String uid,
    int myScore,
  ) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                strokeWidth: 6,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.matchPlayWaitingFinalResult,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.matchPlayOpponentStillAnswering,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.matchPlayYourScoreLine(myScore),
              style: GoogleFonts.baloo2(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildEnd(
    BuildContext context,
    Map<String, dynamic> match,
    String uid,
  ) {
    final l10n = AppLocalizations.of(context);
    final players = Map<String, dynamic>.from(match['players'] ?? {});

    final hostUid = (match['hostUid'] ?? '').toString();
    final guestUid = (match['guestUid'] ?? '').toString();

    final opponentUid = uid == hostUid ? guestUid : hostUid;

    final myData = Map<String, dynamic>.from(players[uid] ?? {});
    final opponentData = Map<String, dynamic>.from(
      players[opponentUid] ?? {},
    );

    final myScore = ((myData['score'] ?? 0) as num).toInt();
    final opponentScore = ((opponentData['score'] ?? 0) as num).toInt();

    final myName = (myData['displayName'] ?? 'Tú').toString();
    final opponentName = (opponentData['displayName'] ?? 'Rival').toString();

    final myAvatarId = (myData['avatarId'] ?? 'avatar_1').toString();
    final myFrameId = myData['equippedFrame']?.toString();
    final myBestLeagueId = myData['bestLeagueId']?.toString();

    final opponentAvatarId =
        (opponentData['avatarId'] ?? 'avatar_1').toString();
    final opponentFrameId = opponentData['equippedFrame']?.toString();
    final opponentBestLeagueId = opponentData['bestLeagueId']?.toString();

    final winnerUid = match['winnerUid'] as String?;
    final winReward = ((match['winReward'] ?? 0) as num).toInt();
    final affectsPvpRating =
        match['affectsPvpRating'] == true || match['ranked'] == true;

    final ratingResults = Map<String, dynamic>.from(
      match['ratingResults'] as Map? ?? {},
    );
    final myRatingResult = Map<String, dynamic>.from(
      ratingResults[uid] as Map? ?? {},
    );

    final oldRating = _safeIntOrNull(myRatingResult['oldRating']);
    final newRating = _safeIntOrNull(myRatingResult['newRating']);
    final ratingDelta = _safeIntOrNull(myRatingResult['ratingDelta']);
    final xpEarned = _safeIntOrNull(myRatingResult['xpEarned']);
    final rankedCoinsEarned = _safeIntOrNull(myRatingResult['coinsEarned']);
    final winStreak = _safeIntOrNull(myRatingResult['winStreak']);
    final oldLeagueName =
        (myRatingResult['oldLeagueName'] ?? myRatingResult['oldLeague'] ?? '')
            .toString();
    final newLeagueName =
        (myRatingResult['newLeagueName'] ?? myRatingResult['newLeague'] ?? '')
            .toString();

    final rematchRequests =
        Map<String, dynamic>.from(match['rematchRequests'] ?? {});

    final myRematchAccepted = rematchRequests[uid] == true;
    final opponentRematchAccepted = rematchRequests[opponentUid] == true;

    if (opponentRematchAccepted && !myRematchAccepted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;

        _maybeShowIncomingRematchDialog(
          context: context,
          match: match,
          uid: uid,
          opponentUid: opponentUid,
          opponentName: opponentName,
          myRematchAccepted: myRematchAccepted,
          opponentRematchAccepted: opponentRematchAccepted,
        );
      });
    }

    final rematchMatchId = (match['rematchMatchId'] ?? '').toString();

    // ✅ Navegación automática
    if (rematchMatchId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _goToRematch(rematchMatchId);
      });
    }

    if (!_resultLogged) {
      _resultLogged = true;

      final resultLabel =
          winnerUid == null ? 'draw' : (winnerUid == uid ? 'win' : 'loss');

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await AnalyticsService.instance.logPvpMatchComplete(
            mode: 'live',
            result: resultLabel,
            ranked: affectsPvpRating,
          );
        } catch (_) {}
      });
    }

    late final PvpResultState state;
    late final String title;
    late final String subtitle;

    int coinsEarned = 0;

    if (winnerUid == null) {
      state = PvpResultState.draw;
      title = l10n.matchPlayDrawTitle;
      subtitle = l10n.matchPlayDrawSubtitle;
    } else if (winnerUid == uid) {
      state = PvpResultState.victory;
      title = l10n.matchPlayVictoryTitle;
      subtitle = affectsPvpRating
          ? l10n.matchPlayVictoryRankedSubtitle
          : l10n.matchPlayVictoryCasualSubtitle;
      coinsEarned =
          affectsPvpRating ? (rankedCoinsEarned ?? winReward) : winReward;
    } else {
      state = PvpResultState.defeat;
      title = l10n.matchPlayDefeatTitle;
      subtitle = affectsPvpRating
          ? l10n.matchPlayDefeatRankedSubtitle
          : l10n.matchPlayDefeatCasualSubtitle;
    }

    String secondaryText = l10n.matchPlayRematch;

    if (_requestingRematch) {
      secondaryText = l10n.matchPlaySendingRequest;
    } else if (myRematchAccepted && !opponentRematchAccepted) {
      secondaryText = l10n.matchPlayRequestSent;
    } else if (myRematchAccepted && opponentRematchAccepted) {
      secondaryText = l10n.matchPlayCreatingRematch;
    }

    return PvpResultCard(
      state: state,
      title: title,
      subtitle: subtitle,
      myName: myName,
      opponentName: opponentName,
      myAvatarId: myAvatarId,
      opponentAvatarId: opponentAvatarId,
      myFrameId: myFrameId,
      myBestLeagueId: myBestLeagueId,
      opponentFrameId: opponentFrameId,
      opponentBestLeagueId: opponentBestLeagueId,
      myScore: myScore,
      opponentScore: opponentScore,
      coinsEarned: coinsEarned > 0 ? coinsEarned : null,
      xpEarned: xpEarned,
      oldRating: oldRating,
      newRating: newRating,
      ratingDelta: ratingDelta,
      winStreak: winStreak,
      oldLeagueName: oldLeagueName.isEmpty ? null : oldLeagueName,
      newLeagueName: newLeagueName.isEmpty ? null : newLeagueName,
      primaryButtonText: l10n.matchPlayExit,
      onPrimaryPressed: () async {
        await _exitToPvpMenu(context);
      },
      secondaryButtonText: secondaryText,
      onSecondaryPressed: myRematchAccepted || _requestingRematch
          ? () {}
          : () => _requestRematch(match),
    );
  }
}
