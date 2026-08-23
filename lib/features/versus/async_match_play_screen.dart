import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import '../../services/sfx_service.dart';
import '../../services/presence_service.dart';
import 'pvp_result_card.dart';
import '../../services/notification_service.dart';
import '../../services/analytics_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_chip.dart';
import '../../widgets/profile_avatar_button.dart';

class AsyncMatchPlayScreen extends StatefulWidget {
  final String asyncMatchId;

  const AsyncMatchPlayScreen({
    super.key,
    required this.asyncMatchId,
  });

  @override
  State<AsyncMatchPlayScreen> createState() => _AsyncMatchPlayScreenState();
}

class _AsyncMatchPlayScreenState extends State<AsyncMatchPlayScreen> {
  final _service = MatchService();
  final _presenceService = PresenceService.instance;

  // Held rather than rebuilt in `build()`: the per-question countdown calls
  // setState once a second, and each of those used to re-subscribe this.
  late final _matchDoc = FirebaseFirestore.instance
      .collection('async_matches')
      .doc(widget.asyncMatchId)
      .snapshots();

  int _index = 0;
  int _correct = 0;
  final Map<int, int> _answers = {};

  bool _locked = false;
  int? _selected;

  int _secondsLeft = 0;
  Timer? _timer;
  int _timerForIndex = -1;

  /// The server's clock for the question on screen. Null means we don't
  /// know where the run is and have to ask.
  _TurnAnchor? _anchor;

  bool _timedOut = false;
  int? _timeoutAnswerIndex;
  bool _autoNextScheduled = false;
  String? _statusMsg;

  bool _answerSubmitting = false;
  bool _answerInFlight = false;
  bool _openingTurn = false;
  bool _turnError = false;
  bool _submittedFinal = false;
  bool _presenceInitialized = false;
  bool _leavingScreen = false;
  bool _resultLogged = false;
  bool _requestingRematch = false;

  /// Whether leaving right now costs the player the question on screen.
  /// Written by `build`, read when they try to back out.
  bool _questionInProgress = false;

  static const Duration _revealDelay = Duration(seconds: 1);
  static const Duration _switchDuration = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();

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

    if (!_leavingScreen) {
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

  /// Seconds left on the question on screen, per the server's anchor.
  int _secondsLeftFromAnchor() {
    final anchor = _anchor;
    if (anchor == null || anchor.index != _index) return 0;

    return (anchor.leftMs / 1000).ceil().clamp(0, 999);
  }

  /// Runs the countdown off the server's anchor rather than a local
  /// per-question budget, so the clock a modified client shows itself has
  /// no bearing on what the server accepts. Ticks faster than once a second
  /// because it reads a deadline instead of decrementing a counter.
  void _startTimerForQuestion(int questionIndex, int answerIndex) {
    _timer?.cancel();

    _timerForIndex = questionIndex;

    _resetPerQuestion();

    _secondsLeft = _secondsLeftFromAnchor();

    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted) return;

      if (_locked) {
        t.cancel();
        return;
      }

      final left = _secondsLeftFromAnchor();

      if (left > 0) {
        if (left != _secondsLeft) setState(() => _secondsLeft = left);
        return;
      }

      t.cancel();

      setState(() {
        _secondsLeft = 0;
        _locked = true;
        _timedOut = true;
        _timeoutAnswerIndex = answerIndex;
        _statusMsg = AppLocalizations.of(context).levelPlayTimeUp;
      });

      SfxService.instance.playTimeout();

      // Banked as -1 (no answer) rather than left unrecorded: an
      // unrecorded question is one the player can come back and answer
      // after looking it up, which would make running the clock out the
      // cheapest way to buy time.
      _answers[questionIndex] = -1;
      unawaited(_persistAnswer(questionIndex, -1, answerIndex));

      if (!_autoNextScheduled) {
        _autoNextScheduled = true;
        Future.delayed(_revealDelay, () {
          if (!mounted) return;
          if (_index == questionIndex) _goNextQuestion();
        });
      }
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

  void _onTapAnswer({
    required int tappedIndex,
    required int answerIndex,
  }) {
    if (_answerSubmitting) return;
    if (_locked) return;
    if (_secondsLeft <= 0) return;

    final questionIndex = _index;

    setState(() {
      _answerSubmitting = true;
      _selected = tappedIndex;
      _locked = true;
      _timedOut = false;
      _timeoutAnswerIndex = null;
      _statusMsg = null;
    });

    _timer?.cancel();

    if (tappedIndex == answerIndex) {
      SfxService.instance.playCorrect();
    } else {
      SfxService.instance.playWrong();
    }

    // Banked alongside the reveal rather than before it: the round trip
    // fits inside the pause, and the running score follows what the server
    // actually stored (see [_persistAnswer]) instead of the tap.
    _answers[questionIndex] = tappedIndex;
    unawaited(_persistAnswer(questionIndex, tappedIndex, answerIndex));

    if (!_autoNextScheduled) {
      _autoNextScheduled = true;
      Future.delayed(_revealDelay, () {
        if (!mounted) return;
        _goNextQuestion();
      });
    }
  }

  /// Banks one answer server-side and picks up the next question's clock
  /// from the response, so advancing costs no extra round trip.
  ///
  /// A failure drops the anchor instead of being swallowed: the server owns
  /// both the answers and the clock now, so carrying on with a local
  /// countdown would only show the player a run the server doesn't have.
  /// The rebuild that follows re-opens the turn and takes its word for it.
  Future<void> _persistAnswer(
    int questionIndex,
    int selectedAnswerIndex,
    int answerIndex,
  ) async {
    _answerInFlight = true;

    try {
      final result = await _service.submitAsyncAnswer(
        matchId: widget.asyncMatchId,
        questionIndex: questionIndex,
        selectedAnswerIndex: selectedAnswerIndex,
      );

      if (!mounted) return;

      setState(() {
        _answers[questionIndex] = result.storedIndex;
        if (result.storedIndex == answerIndex) _correct++;

        _anchor = result.finished
            ? null
            : _TurnAnchor(
                index: result.nextIndex,
                remainingMs: result.nextRemainingMs,
              );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _anchor = null);
    } finally {
      _answerInFlight = false;
    }
  }

  /// Asks the server which question to show and how long is left on it.
  ///
  /// This is the only way in: the screen used to start at question 1 and
  /// run its own clock, so a player could back out, look the answers up,
  /// and come back to a clean run. A question's deadline is stamped once
  /// server-side and never refreshed, so coming back after it passed banks
  /// that question as a timeout and moves on.
  Future<void> _openTurn(List<dynamic> questions) async {
    if (_openingTurn) return;
    _openingTurn = true;

    try {
      final turn = await _service.openAsyncTurn(matchId: widget.asyncMatchId);

      if (!mounted) return;

      var correct = 0;

      turn.answers.forEach((index, selected) {
        if (index < 0 || index >= questions.length) return;

        final question = Map<String, dynamic>.from(questions[index] as Map);
        final answerIndex = ((question['answerIndex'] ?? -1) as num).toInt();

        if (selected == answerIndex) correct++;
      });

      setState(() {
        _answers
          ..clear()
          ..addAll(turn.answers);
        _correct = correct;
        _index = turn.finished ? questions.length : turn.index;
        _anchor = turn.finished
            ? null
            : _TurnAnchor(index: turn.index, remainingMs: turn.remainingMs);
        _timerForIndex = -1;
        _turnError = false;
        _resetPerQuestion();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _turnError = true);
    } finally {
      _openingTurn = false;
    }
  }

  Future<void> _submitFinalScoreIfNeeded() async {
    if (_submittedFinal) return;

    _submittedFinal = true;

    try {
      await NotificationService.instance.markMatchNotificationsAsRead(
        matchId: widget.asyncMatchId,
      );

      // The server scores the round from the answers it banked; showing its
      // number here keeps the waiting card from disagreeing with the result
      // the match is settled on.
      final score = await _service.finishAsyncMatch(
        matchId: widget.asyncMatchId,
      );

      if (mounted) setState(() => _correct = score);

      try {
        await _presenceService.setAvailable();
      } catch (_) {}
    } catch (_) {
      // Closing the round is what triggers finalization, so a failure here
      // can't be swallowed — it would leave the match open with the player
      // believing they had finished it.
      //
      // Rewinding to the turn-open path is what makes the retry work: the
      // server refuses to close a round with a question still open, so if
      // the last answer never landed, only re-opening the turn resolves it
      // — either the question is still playable or its clock has run out.
      // `_index` is a placeholder here; `_openTurn` overwrites it with
      // whatever the server says.
      _submittedFinal = false;

      if (!mounted) return;

      setState(() {
        _turnError = true;
        _anchor = null;
        _index = 0;
      });
    }
  }

  /// Confirms backing out of a question that is still on the clock.
  ///
  /// The clock is server-anchored and keeps running, so leaving is not the
  /// free pause it used to be — the player is told before it costs them.
  Future<void> _leaveScreen() async {
    if (_questionInProgress) {
      final l10n = AppLocalizations.of(context);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.asyncMatchPlayLeaveTitle),
          content: Text(l10n.asyncMatchPlayLeaveBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.asyncMatchPlayLeaveStay),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.asyncMatchPlayLeaveConfirm),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    if (!mounted) return;

    _leavingScreen = true;

    try {
      await _presenceService.setAvailable();
    } catch (_) {}

    if (!mounted) return;

    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _requestRematch({
    required BuildContext context,
    required String opponentUid,
    required String categoryId,
    required int difficulty,
    required int totalQuestions,
    required int timePerQuestionSec,
  }) async {
    if (_requestingRematch) return;

    setState(() => _requestingRematch = true);

    try {
      final newMatchId = await _service.createAsyncFixedMatch(
        challengedUid: opponentUid,
        categoryId: categoryId,
        difficulty: difficulty,
        totalQuestions: totalQuestions,
        timePerQuestionSec: timePerQuestionSec,
      );

      if (!context.mounted) return;

      _leavingScreen = true;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AsyncMatchPlayScreen(asyncMatchId: newMatchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _requestingRematch = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final l10n = AppLocalizations.of(context);


    final scaffold = Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton(openProfileOnTap: false)],
        title: Text(l10n.asyncMatchPlayTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leaveScreen,
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _matchDoc,
        builder: (context, snap) {
          _questionInProgress = false;

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();

          if (data == null) {
            return Center(child: Text(l10n.asyncMatchPlayNotFound));
          }

          final timePerQ = ((data['timePerQuestionSec'] ?? 15) as num).toInt();

          final questions = data['questions'] as List<dynamic>? ?? [];

          if (questions.isEmpty) {
            return Center(
              child: Text(l10n.asyncMatchPlayNoQuestions),
            );
          }

          final challengerUid = (data['challengerUid'] ?? '').toString();
          final challengedUid = (data['challengedUid'] ?? '').toString();

          final myRole = uid == challengerUid ? 'challenger' : 'challenged';
          final opponentRole =
              myRole == 'challenger' ? 'challenged' : 'challenger';

          final myStatusKey =
              myRole == 'challenger' ? 'challengerStatus' : 'challengedStatus';

          final opponentStatusKey = opponentRole == 'challenger'
              ? 'challengerStatus'
              : 'challengedStatus';

          final myStatus = (data[myStatusKey] ?? 'pending').toString();
          final opponentStatus =
              (data[opponentStatusKey] ?? 'pending').toString();

          final challengerScore = ((data['challenger']?['score']) ?? 0) as int;
          final challengedScore = ((data['challenged']?['score']) ?? 0) as int;

          final mySavedScore =
              myRole == 'challenger' ? challengerScore : challengedScore;

          final opponentSavedScore =
              myRole == 'challenger' ? challengedScore : challengerScore;

          final status = (data['status'] ?? '').toString();
          final winnerUid = data['winnerUid'] as String?;

          final myName = _nameForRole(
            data: data,
            role: myRole,
            fallback: l10n.asyncMatchPlayYouFallback,
          );

          final opponentName = _nameForRole(
            data: data,
            role: opponentRole,
            fallback: l10n.asyncMatchPlayOpponentFallback,
          );

          if (myStatus == 'finished') {
            _timer?.cancel();

            final opponentUid =
                myRole == 'challenger' ? challengedUid : challengerUid;

            return _buildResultCard(
              context,
              uid: uid,
              opponentUid: opponentUid,
              status: status,
              winnerUid: winnerUid,
              myName: myName,
              opponentName: opponentName,
              myScore: mySavedScore,
              opponentScore: opponentSavedScore,
              opponentFinished: opponentStatus == 'finished',
              categoryId: (data['categoryId'] ?? 'random').toString(),
              difficulty: ((data['difficulty'] ?? 1) as num).toInt(),
              totalQuestions: ((data['totalQuestions'] ?? 10) as num).toInt(),
              timePerQuestionSec: timePerQ,
            );
          }

          // The server owns the answers and the clock, so a call that
          // failed leaves nothing safe to show — better a retry than a run
          // that only exists on this device.
          if (_turnError) {
            _timer?.cancel();
            return _buildTurnErrorCard(context);
          }

          if (_index >= questions.length) {
            _timer?.cancel();

            if (!_submittedFinal) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _submitFinalScoreIfNeeded();
              });
            }

            return _buildWaitingSubmitCard(
              context,
              myName: myName,
              opponentName: opponentName,
              myScore: _correct,
            );
          }

          // Gated before any question renders: only the server knows which
          // question is next and how long is left on it, and showing one
          // without its clock would start it at zero. Mid-reveal the anchor
          // already points at the *next* question and no clock is running,
          // so the revealed answer stays on screen.
          //
          // A pending answer carries the next question's clock in its
          // response, so waiting for that is enough — asking again while it
          // is in flight would just race it.
          final anchored = _anchor?.index == _index;

          if (!anchored && !_locked) {
            if (!_answerInFlight) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _openTurn(questions);
              });
            }
            return const Center(child: CircularProgressIndicator());
          }

          final qMap = Map<String, dynamic>.from(questions[_index] as Map);
          final qText = (qMap['q'] ?? '').toString();

          final options = (qMap['options'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();

          final answerIndex = ((qMap['answerIndex'] ?? 0) as num).toInt();

          if (_timerForIndex != _index) {
            _startTimerForQuestion(_index, answerIndex);
          }

          _questionInProgress = !_locked;

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
              key: ValueKey('async_q_$_index'),
              qText: qText,
              options: options,
              answerIndex: answerIndex,
              total: questions.length,
              timePerQ: timePerQ,
            ),
          );
        },
      ),
    );

    // Every exit goes through `_leaveScreen`, which warns first when a
    // question is still on the clock — the clock is anchored server-side
    // now, so backing out is no longer the free pause it used to be.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _leaveScreen();
      },
      child: scaffold,
    );
  }

  String _nameForRole({
    required Map<String, dynamic> data,
    required String role,
    required String fallback,
  }) {
    if (role == 'challenger') {
      final name = (data['challengerDisplayName'] ?? '').toString().trim();
      return name.isEmpty ? fallback : name;
    }

    final name = (data['challengedDisplayName'] ?? '').toString().trim();
    return name.isEmpty ? fallback : name;
  }

  Widget _buildQuestionView({
    required Key key,
    required String qText,
    required List<String> options,
    required int answerIndex,
    required int total,
    required int timePerQ,
  }) {
    final l10n = AppLocalizations.of(context);
    final absorbing = _locked || _answerSubmitting;
    final colorScheme = Theme.of(context).colorScheme;

    final progress = total == 0 ? 0.0 : (_index / total).clamp(0.0, 1.0);

    final timeFraction =
        timePerQ == 0 ? 0.0 : (_secondsLeft / timePerQ).clamp(0.0, 1.0);

    final timerColor = timeFraction > 0.5
        ? context.appColors.success
        : timeFraction > 0.2
            ? context.appColors.reward
            : context.appColors.danger;

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
                        borderRadius: BorderRadius.circular(context.radii.pill),
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
                    borderRadius: BorderRadius.circular(context.radii.pill),
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
              icon: Icons.check_circle_outline,
              label: l10n.asyncMatchPlayCorrectLabel,
              value: '$_correct',
              fullWidth: true,
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(context.radii.md),
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
                  fillColor = context.appColors.success.withValues(alpha: 0.16);
                }

                if (isSelected && !isCorrect) {
                  fillColor = context.appColors.danger.withValues(alpha: 0.16);
                }
              } else if (!_locked && isSelected) {
                fillColor = colorScheme.surfaceContainerHighest;
              }

              Color borderColor = colorScheme.outline;
              double borderWidth = 1;

              if (_timedOut && _timeoutAnswerIndex != null) {
                if (i == _timeoutAnswerIndex) {
                  borderColor = context.appColors.reward;
                  borderWidth = 3;
                }
              } else if (_locked) {
                if (isCorrect) {
                  borderColor = context.appColors.success;
                  borderWidth = 2;
                }

                if (isSelected && !isCorrect) {
                  borderColor = context.appColors.danger;
                  borderWidth = 2;
                }
              } else if (isSelected) {
                borderColor = colorScheme.primary;
                borderWidth = 2;
              }

              final badgeColor = (_locked && isCorrect)
                  ? context.appColors.success
                  : (_locked && isSelected && !isCorrect)
                      ? context.appColors.danger
                      : (!_locked && isSelected)
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest;

              final badgeTextColor =
                  badgeColor == colorScheme.surfaceContainerHighest
                      ? colorScheme.onSurfaceVariant
                      : context.appColors.onAccent;

              IconData? trailingIcon;
              Color? trailingIconColor;
              if (_locked && !_timedOut) {
                if (isCorrect) {
                  trailingIcon = Icons.check_circle;
                  trailingIconColor = context.appColors.success;
                } else if (isSelected) {
                  trailingIcon = Icons.cancel;
                  trailingIconColor = context.appColors.danger;
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radii.md),
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
                      borderRadius: BorderRadius.circular(context.radii.md),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
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
                        style: TextStyle(
                          color: context.appColors.reward,
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

  /// Shown when a turn call fails. Clearing the flag is enough to retry:
  /// the next build re-runs whichever step was pending, opening the turn or
  /// closing the round.
  Widget _buildTurnErrorCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.asyncMatchPlayConnectionError,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => setState(() => _turnError = false),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingSubmitCard(
    BuildContext context, {
    required String myName,
    required String opponentName,
    required int myScore,
  }) {
    final l10n = AppLocalizations.of(context);

    return PvpResultCard(
      state: PvpResultState.waiting,
      title: l10n.asyncMatchPlayChallengeCompletedTitle,
      subtitle: l10n.asyncMatchPlaySendingResultSubtitle,
      myName: myName,
      opponentName: opponentName,
      myScore: myScore,
      opponentScore: null,
      primaryButtonText: l10n.matchPlayExit,
      onPrimaryPressed: _leaveScreen,
    );
  }

  Widget _buildResultCard(
    BuildContext context, {
    required String uid,
    required String opponentUid,
    required String status,
    required String? winnerUid,
    required String myName,
    required String opponentName,
    required int myScore,
    required int opponentScore,
    required bool opponentFinished,
    required String categoryId,
    required int difficulty,
    required int totalQuestions,
    required int timePerQuestionSec,
  }) {
    final l10n = AppLocalizations.of(context);

    if (status != 'completed') {
      return PvpResultCard(
        state: PvpResultState.waiting,
        title: l10n.asyncMatchPlayAlreadyPlayedTitle,
        subtitle: opponentFinished
            ? l10n.asyncMatchPlayCalculatingFinal
            : l10n.asyncMatchPlayWaitingOpponentPlay,
        myName: myName,
        opponentName: opponentName,
        myScore: myScore,
        opponentScore: opponentFinished ? opponentScore : null,
        primaryButtonText: l10n.matchPlayExit,
        onPrimaryPressed: _leaveScreen,
      );
    }

    late final PvpResultState state;
    late final String title;
    late final String subtitle;

    if (winnerUid == null) {
      state = PvpResultState.draw;
      title = l10n.matchPlayDrawTitle;
      subtitle = l10n.matchPlayDrawSubtitle;
    } else if (winnerUid == uid) {
      if (!_resultLogged) SfxService.instance.playReward();
      state = PvpResultState.victory;
      title = l10n.matchPlayVictoryTitle;
      subtitle = l10n.matchPlayVictoryCasualSubtitle;
    } else {
      state = PvpResultState.defeat;
      title = l10n.matchPlayDefeatTitle;
      subtitle = l10n.matchPlayDefeatCasualSubtitle;
    }

    if (!_resultLogged) {
      _resultLogged = true;

      final resultLabel =
          winnerUid == null ? 'draw' : (winnerUid == uid ? 'win' : 'loss');

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await AnalyticsService.instance.logPvpMatchComplete(
            mode: 'async',
            result: resultLabel,
            ranked: false,
          );
        } catch (_) {}
      });
    }

    return PvpResultCard(
      state: state,
      title: title,
      subtitle: subtitle,
      myName: myName,
      opponentName: opponentName,
      myScore: myScore,
      opponentScore: opponentScore,
      primaryButtonText: l10n.matchPlayExit,
      onPrimaryPressed: _leaveScreen,
      secondaryButtonText: _requestingRematch
          ? l10n.asyncMatchPlaySendingRematch
          : l10n.matchPlayRematch,
      onSecondaryPressed: _requestingRematch
          ? null
          : () => _requestRematch(
                context: context,
                opponentUid: opponentUid,
                categoryId: categoryId,
                difficulty: difficulty,
                totalQuestions: totalQuestions,
                timePerQuestionSec: timePerQuestionSec,
              ),
    );
  }
}

/// The server's clock for one question: how much was left when the call
/// returned, and a stopwatch running since then.
///
/// Elapsed time comes from a [Stopwatch] rather than wall-clock arithmetic
/// so a device clock that jumps mid-question — by accident or on purpose —
/// can't buy or burn time. The server judges the real deadline anyway; this
/// only has to keep the countdown honest on screen.
class _TurnAnchor {
  _TurnAnchor({required this.index, required this.remainingMs})
      : _since = Stopwatch()..start();

  final int index;
  final int remainingMs;
  final Stopwatch _since;

  int get leftMs => remainingMs - _since.elapsedMilliseconds;
}
