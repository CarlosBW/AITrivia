import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import '../../services/sfx_service.dart';
import '../../services/presence_service.dart';
import '../../services/analytics_service.dart';
import 'pvp_result_card.dart';
import 'find_opponent_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/stat_chip.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/profile_avatar_button.dart';
import 'turn_anchor.dart';

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

  /// The right option for the question on screen, once the server has
  /// judged the answer. Null until then: the key isn't in the match doc.
  int? _revealCorrect;

  /// When the current question was answered, so the reveal pause can
  /// discount the round trip it waited on.
  DateTime? _answeredAt;

  /// The server's clock for the question on screen. Null means we don't
  /// know where the run is and have to ask.
  TurnAnchor? _anchor;
  bool _answerInFlight = false;
  bool _openingTurn = false;
  bool _turnError = false;

  /// When the opponent last banked an answer, as this screen saw it — the
  /// cue for asking the server whether they have stopped playing.
  int _opponentAnsweredCount = -1;
  DateTime _opponentLastProgressAt = DateTime.now();

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
  bool _disconnectCheckRunning = false;
  bool _disconnectFinalizing = false;

  bool _rematchPromptShowing = false;

  static const int _defaultTimePerQ = 15;
  static const Duration _revealDelay = Duration(seconds: 1);

  /// The least the revealed answer stays up, however slow the verdict was.
  static const Duration _minRevealTime = Duration(milliseconds: 600);

  /// How long past a question's time the opponent may go without
  /// answering before the server is asked to end the match. The server
  /// applies its own, matching grace; this only decides when to ask.
  static const Duration _opponentStallGrace = Duration(seconds: 35);
  static const Duration _switchDuration = Duration(milliseconds: 250);

  // Held rather than rebuilt in `build()`: the per-question countdown calls
  // setState once a second, and the disconnect watchdog once every ten, so
  // this was re-subscribing the live match document constantly.
  late final _matchDoc =
      FirebaseFirestore.instance.collection('matches').doc(widget.matchId)
          .snapshots();

  @override
  void initState() {
    super.initState();

    // Forces a rebuild every 10s so the StreamBuilder below re-runs
    // _checkOpponentDisconnect against its last cached snapshot even when
    // nothing else is triggering a rebuild — the per-question countdown
    // timer stops doing that once this player has answered all questions
    // and is just waiting on the opponent, which is exactly when detecting
    // a real disconnect matters most.
    _disconnectWatchTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
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
    _revealCorrect = null;
    _answeredAt = null;
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

  /// Runs the countdown off the server's anchor, like the async screen:
  /// the server judges every answer against its own deadline, so the
  /// clock shown here only has to agree with it.
  void _startTimerForQuestion(int questionIndex) {
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
        _answeredAt = DateTime.now();
        _statusMsg = AppLocalizations.of(context).levelPlayTimeUp;
      });

      SfxService.instance.playTimeout();
      unawaited(_persistAnswer(questionIndex, -1));
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

  void _onTapAnswer({required int tappedIndex}) {
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
      _answeredAt = DateTime.now();
      _statusMsg = null;
    });

    _timer?.cancel();

    // The verdict, the sound and the move on all come with the server's
    // answer: only the server knows which option is right.
    unawaited(_persistAnswer(questionIndex, tappedIndex));
  }

  /// Banks one answer server-side, reveals the verdict, and picks up the
  /// next question's clock from the response.
  ///
  /// A failure drops the anchor: the server owns the answers and the clock,
  /// so the rebuild re-opens the turn and takes its word for where the run
  /// is.
  Future<void> _persistAnswer(int questionIndex, int selected) async {
    _answerInFlight = true;

    try {
      final result = await _service.submitLiveAnswer(
        matchId: widget.matchId,
        questionIndex: questionIndex,
        selectedAnswerIndex: selected,
      );

      if (!mounted) return;

      if (_index == questionIndex && !result.timedOut && selected >= 0) {
        if (result.correct) {
          SfxService.instance.playCorrect();
        } else {
          SfxService.instance.playWrong();
        }
      }

      setState(() {
        if (_index == questionIndex) {
          _revealCorrect = result.correctIndex;
          if (_timedOut) _timeoutAnswerIndex = result.correctIndex;
        }
        _anchor = result.finished
            ? null
            : TurnAnchor(
                index: result.nextIndex,
                remainingMs: result.nextRemainingMs,
              );
      });

      _scheduleNextAfterReveal(questionIndex);
    } catch (_) {
      if (!mounted) return;
      setState(() => _anchor = null);
      if (_index == questionIndex) _goNextQuestion();
    } finally {
      _answerInFlight = false;
    }
  }

  /// Moves on after the reveal has been on screen for the usual pause,
  /// counting the time already spent waiting for the verdict.
  void _scheduleNextAfterReveal(int questionIndex) {
    if (_autoNextScheduled) return;
    _autoNextScheduled = true;

    final waited = _answeredAt == null
        ? Duration.zero
        : DateTime.now().difference(_answeredAt!);
    var delay = _revealDelay - waited;
    if (delay < _minRevealTime) delay = _minRevealTime;

    Future.delayed(delay, () {
      if (!mounted) return;
      if (_index == questionIndex) _goNextQuestion();
    });
  }

  /// Asks the server which question to show and how long is left on it —
  /// the only way in, also when coming back to a match already under way.
  Future<void> _openTurn(int questionCount) async {
    if (_openingTurn) return;
    _openingTurn = true;

    try {
      final turn = await _service.openLiveTurn(matchId: widget.matchId);
      if (!mounted) return;

      setState(() {
        _index = turn.finished ? questionCount : turn.index;
        _anchor = turn.finished
            ? null
            : TurnAnchor(index: turn.index, remainingMs: turn.remainingMs);
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

  /// Asks the server to end the match when the opponent has stopped
  /// answering. The server decides from the deadlines it stamped on their
  /// questions; this screen only watches their progress to know when the
  /// question is worth asking.
  Future<void> _checkOpponentDisconnect({
    required Map<String, dynamic> matchData,
    required String myUid,
  }) async {
    if (_disconnectCheckRunning || _disconnectFinalizing) return;

    final status = (matchData['status'] ?? '').toString();
    if (status != 'playing') return;

    final hostUid = (matchData['hostUid'] ?? '').toString();
    final guestUid = (matchData['guestUid'] ?? '').toString();
    final opponentUid = myUid == hostUid ? guestUid : hostUid;
    if (opponentUid.isEmpty || opponentUid == myUid) return;

    final players = Map<String, dynamic>.from(matchData['players'] ?? {});
    final opponent = Map<String, dynamic>.from(players[opponentUid] ?? {});
    if (opponent['finished'] == true) return;

    final answered = (opponent['answers'] as Map?)?.length ?? 0;
    if (answered != _opponentAnsweredCount) {
      _opponentAnsweredCount = answered;
      _opponentLastProgressAt = DateTime.now();
      return;
    }

    final timePerQ =
        ((matchData['timePerQuestionSec'] ?? _defaultTimePerQ) as num).toInt();
    final quietFor = DateTime.now().difference(_opponentLastProgressAt);
    if (quietFor < Duration(seconds: timePerQ) + _opponentStallGrace) return;

    _disconnectCheckRunning = true;
    try {
      _disconnectFinalizing = true;
      await _service.claimOpponentDisconnected(widget.matchId);
    } catch (_) {
      // The server still sees them inside their time: look again later.
      _disconnectFinalizing = false;
      _opponentLastProgressAt = DateTime.now();
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
      final rematchId = await _service.requestRematch(widget.matchId);
      if (rematchId != null && mounted) _goToRematch(rematchId);
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

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l10n.matchPlayTitle),
        actions: const [ProfileAvatarButton(openProfileOnTap: false)],
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
        stream: _matchDoc,
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
          if (status == 'finished') {
            _timer?.cancel();
            return _buildEnd(context, data, uid);
          }

          if (_turnError) {
            _timer?.cancel();
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.asyncMatchPlayConnectionError,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _openTurn(questions.length),
                      child: Text(l10n.commonRetry),
                    ),
                  ],
                ),
              ),
            );
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

          // Only the server knows which question is next and how long is
          // left on it. Mid-reveal the anchor already points at the next
          // question, so the revealed answer stays on screen.
          final anchored = _anchor?.index == _index;
          if (!anchored && !_locked) {
            if (!_answerInFlight) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _openTurn(questions.length);
              });
            }
            return const Center(child: CircularProgressIndicator());
          }

          final qMap = Map<String, dynamic>.from(
            questions[_index] as Map,
          );

          final qText = (qMap['q'] ?? '').toString();

          final options = (qMap['options'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();

          if (_timerForIndex != _index) {
            _startTimerForQuestion(_index);
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
                borderRadius: BorderRadius.circular(context.radii.md),
                border: context.surfaces.borderOr(null),
                boxShadow: context.surfaces.shadowsOr(null),
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
              // Known only once the server has judged the answer: the key
              // is no longer in the match doc.
              final revealed = _revealCorrect != null;
              final isCorrect = revealed && i == _revealCorrect;
              final letter = String.fromCharCode(65 + i);

              Color? fillColor;

              if (revealed && !_timedOut) {
                if (isCorrect) {
                  fillColor = context.appColors.success.withValues(alpha: 0.16);
                }

                if (isSelected && !isCorrect) {
                  fillColor = context.appColors.danger.withValues(alpha: 0.16);
                }
              } else if (!revealed && isSelected) {
                fillColor = colorScheme.surfaceContainerHighest;
              }

              Color borderColor = colorScheme.outline;
              double borderWidth = 1;

              if (_timedOut && _timeoutAnswerIndex != null) {
                if (i == _timeoutAnswerIndex) {
                  borderColor = context.appColors.reward;
                  borderWidth = 3;
                }
              } else if (revealed) {
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

              final badgeColor = (revealed && isCorrect)
                  ? context.appColors.success
                  : (revealed && isSelected && !isCorrect)
                      ? context.appColors.danger
                      : (!revealed && isSelected)
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest;

              final badgeTextColor =
                  badgeColor == colorScheme.surfaceContainerHighest
                      ? colorScheme.onSurfaceVariant
                      : context.appColors.onAccent;

              IconData? trailingIcon;
              Color? trailingIconColor;
              if (revealed && !_timedOut) {
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
                  onTap: () => _onTapAnswer(tappedIndex: i),
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
                      // El borde de arriba codifica la seleccion; solo la
                      // sombra pasa por el tema.
                      boxShadow: context.surfaces.shadowsOr(
                        isSelected
                            ? [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .shadow
                                      .withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [],
                      ),
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
              style: context.heading(24),
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
              style: context.heading(20),
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
      if (!_resultLogged) SfxService.instance.playReward();
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
