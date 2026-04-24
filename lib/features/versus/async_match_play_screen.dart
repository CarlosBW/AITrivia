import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import '../../services/sfx_service.dart';

class AsyncMatchPlayScreen extends StatefulWidget {
  final String asyncMatchId;
  const AsyncMatchPlayScreen({super.key, required this.asyncMatchId});

  @override
  State<AsyncMatchPlayScreen> createState() => _AsyncMatchPlayScreenState();
}

class _AsyncMatchPlayScreenState extends State<AsyncMatchPlayScreen> {
  final _service = MatchService();

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

  static const Duration _revealDelay = Duration(seconds: 1);

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
      await _service.submitAsyncResult(
        matchId: widget.asyncMatchId,
        score: _correct,
      );
    } catch (_) {
      // Silencioso para no romper UX
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('async_matches')
        .doc(widget.asyncMatchId);

    return Scaffold(
      appBar: AppBar(title: const Text('Reto asíncrono')),
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

          final timePerQ = (data['timePerQuestionSec'] ?? 10) as int;
          final questions = (data['questions'] as List<dynamic>? ?? []);
          if (questions.isEmpty) {
            return const Center(child: Text('Este reto no tiene preguntas.'));
          }

          final challengerUid = (data['challengerUid'] ?? '').toString();
          final challengedUid = (data['challengedUid'] ?? '').toString();

          final myRole = uid == challengerUid ? 'challenger' : 'challenged';
          final myStatusKey =
              myRole == 'challenger' ? 'challengerStatus' : 'challengedStatus';
          final myStatus = (data[myStatusKey] ?? 'pending').toString();

          // Scores guardados (para cuando reabres la pantalla)
          final challengerScore = ((data['challenger']?['score']) ?? 0) as int;
          final challengedScore = ((data['challenged']?['score']) ?? 0) as int;

          final status = (data['status'] ?? '').toString(); // waiting_challenged | completed | ...
          final winnerUid = data['winnerUid'] as String?;

          // Si ya jugué: mostrar resultado desde Firestore (no desde _correct)
          if (myStatus == 'finished') {
            _timer?.cancel();

            final mySavedScore = myRole == 'challenger'
                ? challengerScore
                : challengedScore;

            final oppSavedScore = myRole == 'challenger'
                ? challengedScore
                : challengerScore;

            return _buildAlreadyPlayed(
              context,
              status: status,
              winnerUid: winnerUid,
              myScore: mySavedScore,
              oppScore: oppSavedScore,
              opponentFinished: (myRole == 'challenger'
                      ? (data['challengedStatus'] ?? 'pending')
                      : (data['challengerStatus'] ?? 'pending'))
                  .toString() ==
              'finished',
            );
          }

          // Fin de preguntas: enviar score una sola vez y mostrar “en espera”
          if (_index >= questions.length) {
            _timer?.cancel();

            if (!_submittedFinal) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _submitFinalScoreIfNeeded();
              });
            }

            // Mientras Firestore se actualiza, mostramos tu score local.
            // Luego cuando termine, Inbox/Outbox reflejarán completed.
            return _buildDone(
              context,
              status: status,
              winnerUid: winnerUid,
              myScore: _correct,
            );
          }

          // Pregunta actual
          final qMap = questions[_index] as Map<String, dynamic>;
          final qText = (qMap['q'] ?? '').toString();
          final options = (qMap['options'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          final answerIndex = (qMap['answerIndex'] ?? 0) as int;

          if (_timerForIndex != _index) {
            _startTimerForQuestion(timePerQ, _index, answerIndex);
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pregunta ${_index + 1} / ${questions.length}'),
                const SizedBox(height: 8),
                Text(
                  'Tiempo: $_secondsLeft s',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Aciertos: $_correct', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 12),

                Text(
                  qText,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                ...List.generate(options.length, (i) {
                  final isSelected = _selected == i;
                  final isCorrect = i == answerIndex;

                  Color? fillColor;
                  if (_locked && !_timedOut) {
                    if (isCorrect) fillColor = Colors.green.withOpacity(0.2);
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
                      onTap: _locked
                          ? null
                          : () => _onTapAnswer(
                                tappedIndex: i,
                                answerIndex: answerIndex,
                              ),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: fillColor ?? Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: borderWidth),
                        ),
                        child: Text(options[i], style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 6),

                // Mensaje debajo (no mueve layout)
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
          );
        },
      ),
    );
  }

  Widget _buildAlreadyPlayed(
    BuildContext context, {
    required String status,
    required String? winnerUid,
    required int myScore,
    required int oppScore,
    required bool opponentFinished,
  }) {
    String resultLine = 'Tu score: $myScore';
    if (status == 'completed') {
      if (winnerUid == null) {
        resultLine = 'Empate — $myScore vs $oppScore';
      } else if (winnerUid == FirebaseAuth.instance.currentUser!.uid) {
        resultLine = 'Ganaste ✅ — $myScore vs $oppScore';
      } else {
        resultLine = 'Perdiste ❌ — $myScore vs $oppScore';
      }
    } else {
      resultLine = opponentFinished
          ? 'Tu score: $myScore — esperando resultado...'
          : 'Tu score: $myScore — esperando que tu rival juegue...';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Ya jugaste este reto ✅',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(resultLine, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone(
    BuildContext context, {
    required String status,
    required String? winnerUid,
    required int myScore,
  }) {
    String msg = 'Enviando tu resultado...';
    if (status == 'completed') {
      if (winnerUid == null) {
        msg = 'Empate';
      } else if (winnerUid == FirebaseAuth.instance.currentUser!.uid) {
        msg = 'Ganaste ✅';
      } else {
        msg = 'Perdiste ❌';
      }
    } else {
      msg = 'Listo. Esperando a tu rival...';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Reto completado ✅',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Tu score: $myScore'),
            const SizedBox(height: 12),
            Text(msg),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
