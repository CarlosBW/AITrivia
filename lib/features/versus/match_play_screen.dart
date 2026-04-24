import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/match_service.dart';
import '../../services/sfx_service.dart';

class MatchPlayScreen extends StatefulWidget {
  final String matchId;
  const MatchPlayScreen({super.key, required this.matchId});

  @override
  State<MatchPlayScreen> createState() => _MatchPlayScreenState();
}

class _MatchPlayScreenState extends State<MatchPlayScreen> {
  final _service = MatchService();

  int _index = 0;

  int _secondsLeft = 0;
  Timer? _timer;
  int _timerForIndex = -1;

  bool _locked = false;
  int? _selected;

  bool _finishedSent = false;
  bool _finishing = false;

  // Timeout UX
  bool _timedOut = false;
  int? _timeoutAnswerIndex;
  bool _autoNextScheduled = false;

  String? _statusMsg;

  // ✅ Guard extra anti doble-tap
  bool _answerSubmitting = false;

  static const int _defaultTimePerQ = 10;
  static const Duration _revealDelay = Duration(seconds: 1); // ✅ 1 segundo
  static const Duration _switchDuration = Duration(
    milliseconds: 250,
  ); // animación

  @override
  void dispose() {
    _timer?.cancel();
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
          _secondsLeft = 0; // clamp
          t.cancel();

          // Timeout
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
      _timerForIndex = -1; // fuerza reinicio
      _timer = null;
      _resetPerQuestion();
    });
  }

  Future<void> _onTapAnswer({
    required int tappedIndex,
    required int answerIndex,
  }) async {
    // ✅ anti doble-tap
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
      SfxService.instance.playCorrect(); // sin await
      await _service.submitAnswer(matchId: widget.matchId, deltaScore: 1);
    } else {
      SfxService.instance.playWrong(); // sin await
    }

    // auto-next
    if (!_autoNextScheduled) {
      _autoNextScheduled = true;
      Future.delayed(_revealDelay, () {
        if (!mounted) return;
        _goNextQuestion();
      });
    }
  }

  Future<void> _finishMatch() async {
    if (_finishedSent || _finishing) return;

    _finishing = true;
    _finishedSent = true;
    _timer?.cancel();

    try {
      await _service.setFinished(widget.matchId);
    } catch (_) {
      // no crashear
    } finally {
      _finishing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref =
        FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

    return Scaffold(
      appBar: AppBar(title: const Text('1 vs 1')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();
          if (data == null)
            return const Center(child: Text('Match no encontrado'));

          final status = (data['status'] ?? 'waiting').toString();
          if (status != 'playing' && status != 'finished') {
            return const Center(child: Text('Esperando que inicie...'));
          }

          final timePerQ =
              (data['timePerQuestionSec'] ?? _defaultTimePerQ) as int;
          final questions = (data['questions'] as List<dynamic>? ?? []);
          if (questions.isEmpty) {
            return const Center(child: Text('Este match no tiene preguntas.'));
          }

          final players = Map<String, dynamic>.from(data['players'] ?? {});
          final me = Map<String, dynamic>.from(players[uid] ?? {});
          final myScore = (me['score'] ?? 0) as int;

          // terminado global
          if (status == 'finished') {
            _timer?.cancel();
            return _buildEnd(context, data, uid);
          }

          // fin local
          if (_index >= questions.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _finishMatch());
            return _buildWaitingFinish(context, data, myScore);
          }

          // pregunta actual
          final qMap = questions[_index] as Map<String, dynamic>;
          final qText = (qMap['q'] ?? '').toString();
          final options = (qMap['options'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          final answerIndex = (qMap['answerIndex'] ?? 0) as int;

          // timer 1 vez por pregunta
          if (_timerForIndex != _index) {
            _startTimerForQuestion(timePerQ, _index, answerIndex);
          }

          // ✅ Animación + anti-tap global
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
                child: SlideTransition(position: slide, child: child),
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
            Text('Tu puntaje: $myScore', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),

            Text(
              qText,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            ...List.generate(options.length, (i) {
              final isSelected = _selected == i;
              final isCorrect = i == answerIndex;

              // Fondo:
              // - timeout: NO pintamos verde (solo borde amarillo)
              // - respondió: verde correcta + rojo seleccionada incorrecta
              Color? fillColor;
              if (_locked && !_timedOut) {
                if (isCorrect) fillColor = Colors.green.withOpacity(0.2);
                if (isSelected && !isCorrect)
                  fillColor = Colors.red.withOpacity(0.2);
              } else if (!_locked && isSelected) {
                fillColor = Colors.black12;
              }

              // Borde:
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
                  onTap: () =>
                      _onTapAnswer(tappedIndex: i, answerIndex: answerIndex),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: fillColor ?? Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                    ),
                    child: Text(
                      options[i],
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              );
            }),

            // 👇 MENSAJE (layout fijo, sin duplicar)
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
            // ✅ Sin botón "Siguiente" (auto-next siempre)
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingFinish(
    BuildContext context,
    Map<String, dynamic> match,
    int myScore,
  ) {
    final players = Map<String, dynamic>.from(match['players'] ?? {});
    final hostUid = (match['hostUid'] ?? '').toString();
    final guestUid = (match['guestUid'] ?? '').toString();

    final hostScore = (players[hostUid]?['score'] ?? 0) as int;
    final guestScore = (players[guestUid]?['score'] ?? 0) as int;

    final winnerUid = match['winnerUid'] as String?;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Terminaste tus preguntas ✅',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text('Tu puntaje: $myScore'),
            const SizedBox(height: 12),
            Text('Host: $hostScore'),
            Text('Guest: $guestScore'),
            const SizedBox(height: 16),
            if (winnerUid == null)
              const Column(
                children: [
                  SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(height: 10),
                  Text('Esperando que el otro jugador termine...'),
                ],
              )
            else
              const Text('Calculando resultado...'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Salir'),
            ),
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

    final hostScore = (players[hostUid]?['score'] ?? 0) as int;
    final guestScore = (players[guestUid]?['score'] ?? 0) as int;

    final winnerUid = match['winnerUid'] as String?;

    String result;
    if (winnerUid == null) {
      result = 'Empate';
    } else if (winnerUid == uid) {
      result = '¡Ganaste!';
    } else {
      result = 'Perdiste';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              result,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Host: $hostScore'),
            Text('Guest: $guestScore'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Salir'),
            ),
          ],
        ),
      ),
    );
  }
}
