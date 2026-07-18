import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import '../../services/sfx_service.dart';
import '../../services/presence_service.dart';
import 'pvp_result_card.dart';
import 'find_opponent_screen.dart';

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

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Solicitud de revancha'),
          content: Text('$opponentName quiere jugar una revancha.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Luego'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _requestRematch(match);
              },
              child: const Text('Aceptar'),
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
      await _service.submitAnswer(
        matchId: widget.matchId,
        deltaScore: 1,
      );
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

    final ref =
        FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('1 vs 1'),
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
            return const Center(child: Text('Match no encontrado'));
          }

          final status = (data['status'] ?? 'waiting').toString();

          if (status != 'playing' && status != 'finished') {
            return const Center(child: Text('Esperando que inicie...'));
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
            return const Center(
              child: Text('Este match no tiene preguntas.'),
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
              'Tu puntaje: $myScore',
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
            const Text(
              'Esperando resultado final...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tu rival todavía está respondiendo preguntas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Text(
              'Tu puntaje: $myScore',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
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

    late final PvpResultState state;
    late final String title;
    late final String subtitle;

    int coinsEarned = 0;

    if (winnerUid == null) {
      state = PvpResultState.draw;
      title = 'Empate';
      subtitle = 'Ambos terminaron con el mismo puntaje.';
    } else if (winnerUid == uid) {
      state = PvpResultState.victory;
      title = '¡Ganaste!';
      subtitle = affectsPvpRating
          ? 'Buen duelo. Tu rating competitivo fue actualizado.'
          : 'Buen duelo. Sumaste una victoria 1 vs 1.';
      coinsEarned =
          affectsPvpRating ? (rankedCoinsEarned ?? winReward) : winReward;
    } else {
      state = PvpResultState.defeat;
      title = 'Perdiste';
      subtitle = affectsPvpRating
          ? 'Estuviste cerca. Tu rating competitivo fue actualizado.'
          : 'Estuviste cerca. Intenta una revancha.';
    }

    String secondaryText = 'Revancha';

    if (_requestingRematch) {
      secondaryText = 'Enviando solicitud...';
    } else if (myRematchAccepted && !opponentRematchAccepted) {
      secondaryText = 'Solicitud enviada ✓';
    } else if (myRematchAccepted && opponentRematchAccepted) {
      secondaryText = 'Creando revancha...';
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
      primaryButtonText: 'Salir',
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
