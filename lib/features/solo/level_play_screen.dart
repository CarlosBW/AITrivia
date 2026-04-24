import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/life_service.dart';
import '../../services/sfx_service.dart';

class LevelPlayScreen extends StatefulWidget {
  final String categoryId;
  final int levelNumber;

  const LevelPlayScreen({
    super.key,
    required this.categoryId,
    required this.levelNumber,
  });

  @override
  State<LevelPlayScreen> createState() => _LevelPlayScreenState();
}

class _LevelPlayScreenState extends State<LevelPlayScreen> {
  int _index = 0;
  int _correct = 0;

  bool _locked = false;
  int? _selected;

  bool _saved = false;
  bool _saving = false;
  String? _saveError;

  bool _creatingSession = false;
  String? _sessionError;

  int _earnedXp = 0;
  int _earnedCoins = 0;
  bool _rewardGrantedForLevel = false;
  int _userTotalXp = 0;

  int? _levelCount;

  final Map<int, Map<String, dynamic>> _shuffledCache = {};

  int _secondsLeft = 0;
  Timer? _timer;
  int _timerForIndex = -1;

  bool _timedOut = false;
  int? _timeoutAnswerIndex;
  bool _autoNextScheduled = false;
  String? _statusMsg;

  bool _answerSubmitting = false;

  bool _lifeChecked = false;
  bool _lifeLoading = false;
  String? _lifeGateError;

  int _lifeUnits = 10;
  int _maxLifeUnits = 10;
  int? _secondsToNextHalfLife;
  Timer? _lifeUiTimer;

  bool _isNavigating = false;
  bool _buyingLife = false;

  static const int _defaultTimePerQ = 10;
  static const int _buyLifeCost = 10;
  static const Duration _revealDelay = Duration(seconds: 1);
  static const Duration _switchDuration = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _lifeUiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshLivesUi();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifeUiTimer?.cancel();
    super.dispose();
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;

    setState(() => _isNavigating = true);

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  Future<void> _refreshLivesUi() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final state = await LifeService.instance.refreshLives(uid);

    if (!mounted) return;

    setState(() {
      _lifeUnits = (state['lifeUnits'] ?? _lifeUnits) as int;
      _maxLifeUnits = (state['maxLifeUnits'] ?? _maxLifeUnits) as int;
      _secondsToNextHalfLife = state['secondsToNextHalfLife'] as int?;
    });
  }

  Future<void> _buyLifeAndRetryEntry(String uid) async {
    if (_buyingLife) return;

    setState(() => _buyingLife = true);

    try {
      final success = await LifeService.instance.buyFullLife(
        uid: uid,
        cost: _buyLifeCost,
      );

      await _refreshLivesUi();

      if (!mounted) return;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No tienes suficientes monedas'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❤️ Vida recuperada'),
        ),
      );

      setState(() {
        _lifeChecked = false;
        _lifeGateError = null;
      });
    } finally {
      if (mounted) {
        setState(() => _buyingLife = false);
      }
    }
  }

  String _formatSeconds(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

          final uid = FirebaseAuth.instance.currentUser!.uid;

          Future.microtask(() async {
            await LifeService.instance.tryConsumeWrongAnswer(uid);
            await _refreshLivesUi();

            if (!mounted) return;
            setState(() {
              _statusMsg = '⏰ Se acabó el tiempo - perdiste media vida';
            });

            if (!_autoNextScheduled) {
              _autoNextScheduled = true;
              Future.delayed(_revealDelay, () {
                if (!mounted) return;
                if (_index == questionIndex) _goNextQuestion();
              });
            }
          });
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

      final uid = FirebaseAuth.instance.currentUser!.uid;
      await LifeService.instance.tryConsumeWrongAnswer(uid);
      await _refreshLivesUi();

      if (mounted) {
        setState(() {
          _statusMsg = '❌ Incorrecto - perdiste media vida';
        });
      }
    }

    if (!_autoNextScheduled) {
      _autoNextScheduled = true;
      Future.delayed(_revealDelay, () {
        if (!mounted) return;
        _goNextQuestion();
      });
    }
  }

  Future<void> _checkAndConsumeLife(String uid) async {
    if (_lifeChecked || _lifeLoading) return;

    setState(() {
      _lifeLoading = true;
      _lifeGateError = null;
    });

    try {
      await LifeService.instance.ensureUserLifeDoc(uid);
      final ok = await LifeService.instance.tryConsumeLevelEntry(uid);

      await _refreshLivesUi();

      if (!ok) {
        _lifeGateError =
            'Necesitas 1 vida completa para entrar a este nivel.';
      }

      _lifeChecked = true;
    } catch (e) {
      _lifeGateError = 'Error verificando vidas: $e';
      _lifeChecked = true;
    } finally {
      if (mounted) {
        setState(() {
          _lifeLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final categoryRef =
        db.collection('fixed_categories').doc(widget.categoryId);

    final sessionId = '${widget.categoryId}_${widget.levelNumber}';
    final sessionRef = db
        .collection('users')
        .doc(uid)
        .collection('sessions_fixed')
        .doc(sessionId);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.categoryId} - Nivel ${widget.levelNumber}'),
      ),
      body: Stack(
        children: [
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: categoryRef.get(),
            builder: (context, catSnap) {
              if (!catSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final catData = catSnap.data!.data();
              _levelCount ??= (catData?['levelCount'] ?? 0) as int;

              if (!_lifeChecked && !_lifeLoading) {
                Future.microtask(() => _checkAndConsumeLife(uid));
              }

              if (_lifeLoading || !_lifeChecked) {
                return const Center(child: CircularProgressIndicator());
              }

              if (_lifeGateError != null) {
                return _buildNoLivesGate(context, uid);
              }

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: sessionRef.get(),
                builder: (context, sesGetSnap) {
                  if (!sesGetSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final sesExists = sesGetSnap.data!.exists;

                  if (!sesExists) {
                    if (!_creatingSession) {
                      _creatingSession = true;
                      Future.microtask(() async {
                        try {
                          await _ensureSession(
                            db: db,
                            uid: uid,
                            sessionRef: sessionRef,
                          );
                        } catch (e) {
                          _sessionError = e.toString();
                        } finally {
                          if (mounted) {
                            setState(() => _creatingSession = false);
                          }
                        }
                      });
                    }

                    if (_sessionError != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Error creando sesión',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _sessionError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () {
                                  setState(() {
                                    _sessionError = null;
                                    _creatingSession = false;
                                  });
                                },
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Generando preguntas del nivel...'),
                        ],
                      ),
                    );
                  }

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: sessionRef.snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final data = snap.data!.data();
                      if (data == null) {
                        return const Center(child: Text('Sesión no encontrada.'));
                      }

                      final questions =
                          (data['questions'] as List<dynamic>? ?? []);
                      if (questions.isEmpty) {
                        return const Center(
                          child: Text('Esta sesión no tiene preguntas.'),
                        );
                      }

                      if (_index >= questions.length) {
                        _timer?.cancel();

                        if (!_saved && !_saving) {
                          Future.microtask(
                            () => _saveProgress(total: questions.length),
                          );
                        }
                        return _buildEnd(context, questions.length);
                      }

                      final qMap = questions[_index] as Map<String, dynamic>;
                      final qText = (qMap['q'] ?? '').toString();

                      List<String> options;
                      int answerIndex;

                      final cached = _shuffledCache[_index];
                      if (cached != null) {
                        options = (cached['options'] as List).cast<String>();
                        answerIndex = cached['answerIndex'] as int;
                      } else {
                        final rawOptions =
                            (qMap['options'] as List<dynamic>? ?? [])
                                .map((e) => e.toString())
                                .toList();
                        final rawAnswerIndex =
                            (qMap['answerIndex'] ?? 0) as int;

                        final paired = List.generate(rawOptions.length, (i) {
                          return {
                            'text': rawOptions[i],
                            'isCorrect': i == rawAnswerIndex,
                          };
                        });

                        paired.shuffle();

                        options =
                            paired.map((e) => e['text'] as String).toList();
                        answerIndex =
                            paired.indexWhere((e) => e['isCorrect'] == true);

                        _shuffledCache[_index] = {
                          'options': options,
                          'answerIndex': answerIndex,
                        };
                      }

                      if (_timerForIndex != _index) {
                        _startTimerForQuestion(
                          _defaultTimePerQ,
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
                          key: ValueKey('q_$_index'),
                          qText: qText,
                          options: options,
                          answerIndex: answerIndex,
                          total: questions.length,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          if (_isNavigating || _buyingLife)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoLivesGate(BuildContext context, String uid) {
    final lifeText =
        '${LifeService.instance.formatLives(_lifeUnits)} / ${LifeService.instance.formatLives(_maxLifeUnits)}';

    final nextFullLifeSeconds = _lifeUnits == 1
        ? _secondsToNextHalfLife
        : (_secondsToNextHalfLife == null ? null : _secondsToNextHalfLife! + 150);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_border,
                  size: 40,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sin vidas suficientes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _lifeGateError ?? 'Necesitas 1 vida completa para entrar.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.favorite,
                      label: 'Tus vidas',
                      value: lifeText,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.timer,
                      label: 'Próx. media vida',
                      value: _lifeUnits >= _maxLifeUnits
                          ? 'MAX'
                          : _formatSeconds(_secondsToNextHalfLife),
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.hourglass_bottom,
                      label: 'Para 1 vida completa',
                      value: _formatSeconds(nextFullLifeSeconds),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _buyingLife
                      ? null
                      : () => _buyLifeAndRetryEntry(uid),
                  icon: const Icon(Icons.favorite),
                  label: const Text('Recuperar 1 vida (10 monedas)'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isNavigating || _buyingLife
                      ? null
                      : () {
                          _safeNavigate(() async {
                            Navigator.pop(context);
                          });
                        },
                  child: const Text('Volver'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLivesHeader() {
    final lifeText =
        '${LifeService.instance.formatLives(_lifeUnits)} / ${LifeService.instance.formatLives(_maxLifeUnits)}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Vidas: $lifeText',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            _lifeUnits >= _maxLifeUnits
                ? 'MAX'
                : '+0.5 en ${_formatSeconds(_secondsToNextHalfLife)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(int total) {
    final progress = total == 0 ? 0.0 : (_index / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Progreso: $_index / $total',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionView({
    required Key key,
    required String qText,
    required List<String> options,
    required int answerIndex,
    required int total,
  }) {
    final absorbing = _locked || _answerSubmitting || _isNavigating;

    return AbsorbPointer(
      key: key,
      absorbing: absorbing,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLivesHeader(),
            Text(
              'Pregunta ${_index + 1} / $total',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            _buildProgressBar(total),
            const SizedBox(height: 10),
            Text(
              'Tiempo: $_secondsLeft s',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
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

  int _difficultyForLevel(int levelNumber) {
    if (levelNumber <= 3) return 1;
    if (levelNumber <= 7) return 2;
    return 3;
  }

  int _fnv1a32(String input) {
    const int fnvPrime = 16777619;
    int hash = 2166136261;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }

  Map<String, int> _calculateLevelRewards({
    required int correct,
    required int total,
  }) {
    final pct = total == 0 ? 0.0 : correct / total;
    final xp = correct * 10;

    int coins = 0;
    if (pct >= 0.9) {
      coins = 8;
    } else if (pct >= 0.7) {
      coins = 5;
    } else if (pct >= 0.4) {
      coins = 3;
    }

    return {
      'xp': xp,
      'coins': coins,
    };
  }

  Future<void> _ensureSession({
    required FirebaseFirestore db,
    required String uid,
    required DocumentReference<Map<String, dynamic>> sessionRef,
  }) async {
    final existing = await sessionRef.get();
    if (existing.exists) return;

    final preferredDifficulty = _difficultyForLevel(widget.levelNumber);
    final difficulties = [preferredDifficulty, 1, 2, 3].toSet().toList();

    QuerySnapshot<Map<String, dynamic>>? poolSnap;
    int? usedDifficulty;

    for (final diff in difficulties) {
      final col = db
          .collection('fixed_pools')
          .doc(widget.categoryId)
          .collection('difficulty_$diff')
          .doc('pool')
          .collection('questions');

      final snap = await col.get();

      if (snap.docs.isNotEmpty) {
        poolSnap = snap;
        usedDifficulty = diff;
        break;
      }
    }

    if (poolSnap == null) {
      throw Exception(
        'No hay preguntas disponibles en ninguna dificultad para ${widget.categoryId}',
      );
    }

    final poolDocs = poolSnap.docs;

    final seed = _fnv1a32('$uid|${widget.categoryId}|${widget.levelNumber}');
    final rnd = math.Random(seed);

    final indices = List<int>.generate(poolDocs.length, (i) => i);
    indices.shuffle(rnd);

    final take = math.min(10, poolDocs.length);
    final chosen = indices.take(take).map((i) => poolDocs[i].data()).toList();

    await db.runTransaction((tx) async {
      final sesSnap = await tx.get(sessionRef);
      if (sesSnap.exists) return;

      tx.set(sessionRef, {
        'categoryId': widget.categoryId,
        'levelNumber': widget.levelNumber,
        'difficulty': usedDifficulty,
        'total': take,
        'seed': seed,
        'questions': chosen,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _saveProgress({required int total}) async {
    if (_saved) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final db = FirebaseFirestore.instance;

      final progressRef = db
          .collection('users')
          .doc(uid)
          .collection('progress_fixed')
          .doc(widget.categoryId);

      final userRef = db.collection('users').doc(uid);

      final percent = total == 0 ? 0.0 : (_correct / total);
      final levelCount = _levelCount ?? 0;

      final rewards = _calculateLevelRewards(correct: _correct, total: total);
      final levelXp = rewards['xp']!;
      final levelCoins = rewards['coins']!;

      await db.runTransaction((tx) async {
        final progressSnap = await tx.get(progressRef);
        final userSnap = await tx.get(userRef);

        final prev = progressSnap.data();
        final userData = userSnap.data() ?? {};
        final prevUserXp = ((userData['xp'] ?? 0) as num).toInt();

        final prevCompleted = (prev?['completedLevels'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toSet();

        final prevLevelStats =
            Map<String, dynamic>.from(prev?['levelStats'] as Map? ?? {});

        final wasAlreadyCompleted = prevCompleted.contains(widget.levelNumber);
        prevCompleted.add(widget.levelNumber);

        final levelKey = widget.levelNumber.toString();
        final oldStat = Map<String, dynamic>.from(
          prevLevelStats[levelKey] as Map? ?? {},
        );
        final oldPercent = ((oldStat['percent'] ?? -1.0) as num).toDouble();

        if (percent >= oldPercent) {
          prevLevelStats[levelKey] = {
            'correct': _correct,
            'total': total,
            'percent': percent,
            'updatedAt': FieldValue.serverTimestamp(),
          };
        }

        tx.set(
          progressRef,
          {
            'completedLevels': prevCompleted.toList()..sort(),
            'levelStats': prevLevelStats,
            'lastScore': {
              'correct': _correct,
              'total': total,
              'percent': percent,
              'levelNumber': widget.levelNumber,
            },
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        int grantedXp = 0;
        int grantedCoins = 0;

        if (!wasAlreadyCompleted) {
          grantedXp = levelXp;
          grantedCoins = levelCoins;

          tx.set(
            progressRef,
            {
              'lastLevelReward': {
                'levelNumber': widget.levelNumber,
                'xp': grantedXp,
                'coins': grantedCoins,
                'grantedAt': FieldValue.serverTimestamp(),
              },
            },
            SetOptions(merge: true),
          );

          tx.set(
            userRef,
            {
              'xp': FieldValue.increment(grantedXp),
              'coins': FieldValue.increment(grantedCoins),
            },
            SetOptions(merge: true),
          );
        }

        final completedAll =
            levelCount > 0 && prevCompleted.length >= levelCount;

        if (completedAll) {
          tx.set(
            progressRef,
            {'completedAllLevels': true},
            SetOptions(merge: true),
          );

          final rewardGranted = (prev?['categoryRewardGranted'] == true);
          if (!rewardGranted) {
            tx.set(
              progressRef,
              {
                'categoryRewardGranted': true,
                'rewardGrantedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );

            tx.set(
              userRef,
              {'coins': FieldValue.increment(10)},
              SetOptions(merge: true),
            );

            grantedCoins += 10;
          }
        }

        _earnedXp = grantedXp;
        _earnedCoins = grantedCoins;
        _rewardGrantedForLevel = !wasAlreadyCompleted;
        _userTotalXp = prevUserXp + grantedXp;
      });

      _saved = true;
    } catch (e) {
      _saveError = e.toString();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildEnd(BuildContext context, int total) {
    final pct = total == 0 ? 0.0 : (_correct / total);

    String label;
    if (pct >= 0.9) {
      label = 'Experto';
    } else if (pct >= 0.7) {
      label = 'Avanzado';
    } else if (pct >= 0.4) {
      label = 'Intermedio';
    } else {
      label = 'Novato';
    }

    final starCount = pct >= 0.9
        ? 3
        : pct >= 0.7
            ? 2
            : pct >= 0.4
                ? 1
                : 0;

    final pctText = '${(pct * 100).toStringAsFixed(0)}%';

    final nextLevel = widget.levelNumber + 1;
    final hasNext = (_levelCount != null && nextLevel <= _levelCount!);
    final previousXp = (_userTotalXp - _earnedXp).clamp(0, _userTotalXp);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  if (starCount == 3)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: _ThreeStarsCelebration(),
                      ),
                    ),
                  Column(
                    children: [
                      const Text(
                        '¡Nivel completado!',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      _BigStarsRow(count: starCount),
                      const SizedBox(height: 14),
                      Text(
                        'Puntaje: $_correct / $total ($pctText)',
                        style: const TextStyle(fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rango: $label',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Recompensas',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _RewardCard(
                            icon: Icons.auto_awesome,
                            label: 'XP',
                            child: _AnimatedRewardNumber(
                              value: _earnedXp,
                              prefix: '+',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RewardCard(
                            icon: Icons.monetization_on,
                            label: 'Monedas',
                            child: _AnimatedRewardNumber(
                              value: _earnedCoins,
                              prefix: '+',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_rewardGrantedForLevel) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Este nivel ya había sido completado antes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _AnimatedXpProgressCard(
              previousXp: previousXp,
              currentXp: _userTotalXp,
            ),
            if (_saving) ...[
              const SizedBox(height: 18),
              const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 8),
              const Text('Guardando progreso...'),
            ],
            if (_saveError != null) ...[
              const SizedBox(height: 18),
              Text(
                'Error guardando: $_saveError',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : () => _saveProgress(total: total),
                child: const Text('Reintentar guardado'),
              ),
            ],
            if (_saved && _saveError == null && !_saving) ...[
              const SizedBox(height: 18),
              const Text(
                '✅ Progreso guardado',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _isNavigating
                        ? null
                        : () {
                            _safeNavigate(() async {
                              _timer?.cancel();
                              _shuffledCache.clear();
                              Navigator.pop(context);
                            });
                          },
                    child: const Text('Volver'),
                  ),
                ),
                if (hasNext) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isNavigating
                          ? null
                          : () {
                              _safeNavigate(() async {
                                _timer?.cancel();

                                if (!context.mounted) return;

                                await Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LevelPlayScreen(
                                      categoryId: widget.categoryId,
                                      levelNumber: nextLevel,
                                    ),
                                  ),
                                );
                              });
                            },
                      child: Text('Continuar (Nivel $nextLevel)'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _RewardCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _RewardCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _AnimatedRewardNumber extends StatelessWidget {
  final int value;
  final String prefix;

  const _AnimatedRewardNumber({
    required this.value,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(
          '$prefix$animatedValue',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }
}

class _BigStarsRow extends StatelessWidget {
  final int count;

  const _BigStarsRow({required this.count});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      children: List.generate(3, (i) {
        final filled = i < count;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.7, end: 1),
          duration: Duration(milliseconds: 300 + (i * 140)),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: child,
            );
          },
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_border_rounded,
            size: 42,
          ),
        );
      }),
    );
  }
}

class _AnimatedXpProgressCard extends StatefulWidget {
  final int previousXp;
  final int currentXp;

  const _AnimatedXpProgressCard({
    required this.previousXp,
    required this.currentXp,
  });

  @override
  State<_AnimatedXpProgressCard> createState() =>
      _AnimatedXpProgressCardState();
}

class _AnimatedXpProgressCardState extends State<_AnimatedXpProgressCard> {
  late final List<_XpSegment> _segments;

  int _visibleSegmentIndex = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _segments = _buildSegments(widget.previousXp, widget.currentXp);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _started = true);
    });
  }

  int _playerLevelFromXp(int xp) => (xp ~/ 100) + 1;

  int _xpFloorForLevel(int playerLevel) => (playerLevel - 1) * 100;

  int _xpCeilForLevel(int playerLevel) => playerLevel * 100;

  List<_XpSegment> _buildSegments(int previousXp, int currentXp) {
    if (currentXp <= previousXp) {
      final level = _playerLevelFromXp(currentXp);
      final floor = _xpFloorForLevel(level);
      final ceil = _xpCeilForLevel(level);
      return [
        _XpSegment(
          level: level,
          startXp: currentXp,
          endXp: currentXp,
          floorXp: floor,
          ceilXp: ceil,
        ),
      ];
    }

    final segments = <_XpSegment>[];
    int cursor = previousXp;

    while (cursor < currentXp) {
      final level = _playerLevelFromXp(cursor);
      final floor = _xpFloorForLevel(level);
      final ceil = _xpCeilForLevel(level);
      final segmentEnd = currentXp < ceil ? currentXp : ceil;

      segments.add(
        _XpSegment(
          level: level,
          startXp: cursor,
          endXp: segmentEnd,
          floorXp: floor,
          ceilXp: ceil,
        ),
      );

      if (segmentEnd == currentXp) break;
      cursor = segmentEnd;
    }

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final currentLevel = _playerLevelFromXp(widget.currentXp);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nivel de jugador $currentLevel',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(_segments.length, (i) {
            final segment = _segments[i];
            final isVisible = i <= _visibleSegmentIndex;

            return AnimatedOpacity(
              opacity: isVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding:
                    EdgeInsets.only(bottom: i == _segments.length - 1 ? 0 : 14),
                child: _XpSegmentView(
                  segment: segment,
                  animate: _started && i == _visibleSegmentIndex,
                  onCompleted: () {
                    if (!mounted) return;
                    if (i == _visibleSegmentIndex && i < _segments.length - 1) {
                      setState(() => _visibleSegmentIndex++);
                    }
                  },
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: widget.previousXp, end: widget.currentXp),
            duration: Duration(milliseconds: 700 + (_segments.length * 450)),
            curve: Curves.easeOutCubic,
            builder: (context, animatedXp, _) {
              return Text(
                'XP total: $animatedXp',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _XpSegment {
  final int level;
  final int startXp;
  final int endXp;
  final int floorXp;
  final int ceilXp;

  const _XpSegment({
    required this.level,
    required this.startXp,
    required this.endXp,
    required this.floorXp,
    required this.ceilXp,
  });
}

class _XpSegmentView extends StatefulWidget {
  final _XpSegment segment;
  final bool animate;
  final VoidCallback onCompleted;

  const _XpSegmentView({
    required this.segment,
    required this.animate,
    required this.onCompleted,
  });

  @override
  State<_XpSegmentView> createState() => _XpSegmentViewState();
}

class _XpSegmentViewState extends State<_XpSegmentView>
    with SingleTickerProviderStateMixin {
  bool _completedCallbackSent = false;
  bool _showLevelUp = false;

  late final AnimationController _levelUpController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _levelUpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _levelUpController,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _levelUpController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _levelUpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final span = widget.segment.ceilXp - widget.segment.floorXp;
    final beginProgress = span == 0
        ? 0.0
        : ((widget.segment.startXp - widget.segment.floorXp) / span)
            .clamp(0.0, 1.0);
    final endProgress = span == 0
        ? 0.0
        : ((widget.segment.endXp - widget.segment.floorXp) / span)
            .clamp(0.0, 1.0);

    final crossedLevel = widget.segment.endXp >= widget.segment.ceilXp &&
        widget.segment.startXp < widget.segment.ceilXp;

    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: beginProgress,
        end: widget.animate ? endProgress : beginProgress,
      ),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      onEnd: () async {
        if (_completedCallbackSent) return;
        _completedCallbackSent = true;

        if (crossedLevel && mounted) {
          setState(() => _showLevelUp = true);
          await _levelUpController.forward();
          await Future.delayed(const Duration(milliseconds: 350));
        }

        if (mounted) {
          widget.onCompleted();
        }
      },
      builder: (context, value, _) {
        final displayedXp = widget.segment.floorXp + (span * value).round();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nivel ${widget.segment.level}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 12,
                  ),
                ),
                if (_showLevelUp)
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          'LEVEL UP! ${widget.segment.level + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              crossedLevel && value >= 0.999
                  ? '¡Subiste al nivel ${widget.segment.level + 1}!'
                  : '${displayedXp - widget.segment.floorXp} / $span XP en este nivel',
              style: TextStyle(
                fontSize: 13,
                fontWeight: crossedLevel && value >= 0.999
                    ? FontWeight.w700
                    : FontWeight.normal,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ThreeStarsCelebration extends StatefulWidget {
  const _ThreeStarsCelebration();

  @override
  State<_ThreeStarsCelebration> createState() => _ThreeStarsCelebrationState();
}

class _ThreeStarsCelebrationState extends State<_ThreeStarsCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_SparkleParticle> _particles;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    final rnd = math.Random(42);
    _particles = List.generate(22, (i) {
      final angle = (-math.pi / 2) + ((rnd.nextDouble() - 0.5) * 1.8);
      final distance = 50 + rnd.nextDouble() * 110;
      final size = 6 + rnd.nextDouble() * 10;
      final dx = math.cos(angle) * distance;
      final dy = math.sin(angle) * distance;
      return _SparkleParticle(
        dx: dx,
        dy: dy,
        size: size,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        final fade = (1 - _controller.value).clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ..._particles.map((p) {
              return Transform.translate(
                offset: Offset(p.dx * t, 20 + (p.dy * t)),
                child: Opacity(
                  opacity: fade,
                  child: Transform.rotate(
                    angle: _controller.value * math.pi * 2,
                    child: Icon(
                      Icons.star_rounded,
                      size: p.size,
                      color: Colors.amber.withOpacity(0.9),
                    ),
                  ),
                ),
              );
            }),
            Opacity(
              opacity: fade,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'PERFECT!',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SparkleParticle {
  final double dx;
  final double dy;
  final double size;

  const _SparkleParticle({
    required this.dx,
    required this.dy,
    required this.size,
  });
}