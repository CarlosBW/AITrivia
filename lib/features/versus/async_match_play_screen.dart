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

  int _index = 0;
  int _correct = 0;
  final Map<int, int> _answers = {};

  bool _locked = false;
  int? _selected;

  int _secondsLeft = 0;
  Timer? _timer;
  int _timerForIndex = -1;

  bool _timedOut = false;
  int? _timeoutAnswerIndex;
  bool _autoNextScheduled = false;
  String? _statusMsg;

  bool _answerSubmitting = false;
  bool _submittedFinal = false;
  bool _presenceInitialized = false;
  bool _leavingScreen = false;
  bool _resultLogged = false;
  bool _requestingRematch = false;

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
    _answers[_index] = tappedIndex;

    if (correct) {
      SfxService.instance.playCorrect();
      setState(() => _correct++);
    } else {
      SfxService.instance.playWrong();
    }

    if (!_autoNextScheduled) {
      _autoNextScheduled = true;
      Future.delayed(_revealDelay, () {
        if (!mounted) return;
        _goNextQuestion();
      });
    }
  }

  Future<void> _submitFinalScoreIfNeeded() async {
    if (_submittedFinal) return;

    _submittedFinal = true;

    try {
      await NotificationService.instance.markMatchNotificationsAsRead(
        matchId: widget.asyncMatchId,
      );
      await _service.submitAsyncResult(
        matchId: widget.asyncMatchId,
        score: _correct,
        answers: _answers,
      );
      try {
        await _presenceService.setAvailable();
      } catch (_) {}
    } catch (_) {
      // Silencioso para no romper UX.
    }
  }

  Future<void> _requestRematch({
    required BuildContext context,
    required String opponentUid,
    required String myName,
    required String opponentName,
    required String categoryId,
    required int difficulty,
    required int totalQuestions,
    required int timePerQuestionSec,
    required int winReward,
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
        winReward: winReward,
        challengerDisplayName: myName,
        challengedDisplayName: opponentName,
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

    final ref = FirebaseFirestore.instance
        .collection('async_matches')
        .doc(widget.asyncMatchId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.asyncMatchPlayTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            _leavingScreen = true;

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
            return Center(child: Text(l10n.asyncMatchPlayNotFound));
          }

          final timePerQ = ((data['timePerQuestionSec'] ?? 10) as num).toInt();

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
              winReward: ((data['winReward'] ?? 2) as num).toInt(),
            );
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

          final qMap = Map<String, dynamic>.from(questions[_index] as Map);
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
      onPrimaryPressed: () async {
        _leavingScreen = true;

        try {
          await _presenceService.setAvailable();
        } catch (_) {}

        if (!context.mounted) return;

        Navigator.popUntil(context, (route) => route.isFirst);
      },
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
    required int winReward,
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
        onPrimaryPressed: () async {
          _leavingScreen = true;

          try {
            await _presenceService.setAvailable();
          } catch (_) {}

          if (!context.mounted) return;

          Navigator.popUntil(context, (route) => route.isFirst);
        },
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
      onPrimaryPressed: () async {
        _leavingScreen = true;

        try {
          await _presenceService.setAvailable();
        } catch (_) {}

        if (!context.mounted) return;

        Navigator.popUntil(context, (route) => route.isFirst);
      },
      secondaryButtonText: _requestingRematch
          ? l10n.asyncMatchPlaySendingRematch
          : l10n.matchPlayRematch,
      onSecondaryPressed: _requestingRematch
          ? null
          : () => _requestRematch(
                context: context,
                opponentUid: opponentUid,
                myName: myName,
                opponentName: opponentName,
                categoryId: categoryId,
                difficulty: difficulty,
                totalQuestions: totalQuestions,
                timePerQuestionSec: timePerQuestionSec,
                winReward: winReward,
              ),
    );
  }
}
