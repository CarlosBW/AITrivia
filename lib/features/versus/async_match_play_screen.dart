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
          _statusMsg = '⏰ Se acabó el tiempo';

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

    final ref = FirebaseFirestore.instance
        .collection('async_matches')
        .doc(widget.asyncMatchId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reto asíncrono'),
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
            return const Center(child: Text('Reto no encontrado'));
          }

          final timePerQ = ((data['timePerQuestionSec'] ?? 10) as num).toInt();

          final questions = data['questions'] as List<dynamic>? ?? [];

          if (questions.isEmpty) {
            return const Center(
              child: Text('Este reto no tiene preguntas.'),
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
            fallback: 'Tú',
          );

          final opponentName = _nameForRole(
            data: data,
            role: opponentRole,
            fallback: 'Rival',
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
  }) {
    final absorbing = _locked || _answerSubmitting;

    return AbsorbPointer(
      key: key,
      absorbing: absorbing,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pregunta ${_index + 1} / $total'),
            const SizedBox(height: 8),
            Text(
              'Tiempo: $_secondsLeft s',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Aciertos: $_correct',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              qText,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(options.length, (i) {
              final isSelected = _selected == i;
              final isCorrect = i == answerIndex;

              Color? fillColor;

              if (_locked && !_timedOut) {
                if (isCorrect) {
                  fillColor = Colors.green.withOpacity(0.2);
                }

                if (isSelected && !isCorrect) {
                  fillColor = Colors.red.withOpacity(0.2);
                }
              } else if (!_locked && isSelected) {
                fillColor = Colors.black12;
              }

              Color borderColor = Colors.black26;
              double borderWidth = 1;

              if (_timedOut && _timeoutAnswerIndex != null) {
                if (i == _timeoutAnswerIndex) {
                  borderColor = Colors.amber;
                  borderWidth = 3;
                }
              } else if (_locked) {
                if (isCorrect) {
                  borderColor = Colors.green;
                  borderWidth = 2;
                }

                if (isSelected && !isCorrect) {
                  borderColor = Colors.red;
                  borderWidth = 2;
                }
              } else if (isSelected) {
                borderColor = Colors.black54;
                borderWidth = 2;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _onTapAnswer(
                    tappedIndex: i,
                    answerIndex: answerIndex,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: fillColor ?? Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Text(
                      options[i],
                      style: const TextStyle(fontSize: 16),
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
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
            const Spacer(),
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
    return PvpResultCard(
      state: PvpResultState.waiting,
      title: 'Reto completado',
      subtitle: 'Enviando tu resultado. Luego esperaremos a tu rival.',
      myName: myName,
      opponentName: opponentName,
      myScore: myScore,
      opponentScore: null,
      primaryButtonText: 'Salir',
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
    if (status != 'completed') {
      return PvpResultCard(
        state: PvpResultState.waiting,
        title: 'Ya jugaste este reto',
        subtitle: opponentFinished
            ? 'Tu resultado fue enviado. Calculando resultado final.'
            : 'Tu resultado fue enviado. Esperando que tu rival juegue.',
        myName: myName,
        opponentName: opponentName,
        myScore: myScore,
        opponentScore: opponentFinished ? opponentScore : null,
        primaryButtonText: 'Salir',
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
      title = 'Empate';
      subtitle = 'Ambos terminaron con el mismo puntaje.';
    } else if (winnerUid == uid) {
      state = PvpResultState.victory;
      title = '¡Ganaste!';
      subtitle = 'Buen duelo. Sumaste una victoria 1 vs 1.';
    } else {
      state = PvpResultState.defeat;
      title = 'Perdiste';
      subtitle = 'Estuviste cerca. Intenta una revancha.';
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
      primaryButtonText: 'Salir',
      onPrimaryPressed: () async {
        _leavingScreen = true;

        try {
          await _presenceService.setAvailable();
        } catch (_) {}

        if (!context.mounted) return;

        Navigator.popUntil(context, (route) => route.isFirst);
      },
      secondaryButtonText:
          _requestingRematch ? 'Enviando revancha...' : 'Revancha',
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
