import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/life_service.dart';
import '../../services/player_level_service.dart';
import '../../services/sfx_service.dart';
import '../../services/economy_service.dart';
import '../../services/ai_topic_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/question_answer_card.dart';

class LevelPlayScreen extends StatefulWidget {
  final String categoryId;
  final int levelNumber;
  final bool isAiTopic;
  final String? aiTopicId;

  const LevelPlayScreen({
    super.key,
    required this.categoryId,
    required this.levelNumber,
    this.isAiTopic = false,
    this.aiTopicId,
  });

  @override
  State<LevelPlayScreen> createState() => _LevelPlayScreenState();
}

class _LevelPlayScreenState extends State<LevelPlayScreen> {
  int _index = 0;
  int _correct = 0;
  final List<Map<String, dynamic>> _answers = [];

  bool _locked = false;
  int? _selected;

  bool _saved = false;
  bool _saving = false;
  String? _saveError;

  bool _creatingSession = false;
  String? _sessionError;

  bool _bufferKicked = false;

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

  bool _endedByNoLives = false;

  /// Set once the player reaches the end of the level, so the results
  /// screen stops depending on the session document.
  ///
  /// `submitSoloLevelResult` deletes that document, and the widgets below
  /// read it to decide what to render — so after finishing, any rebuild
  /// saw "no session", flashed the "generating questions" placeholder and
  /// called `ensureSoloLevelSession` all over again. That second session
  /// also marked another slate of questions as already seen, quietly
  /// burning content the player never played.
  bool _levelFinished = false;
  int _finishedTotal = 0;

  int _lifeUnits = 10;
  int _maxLifeUnits = 10;
  int _lifeRegenSeconds = LifeService.defaultRegenSeconds;
  int? _secondsToNextHalfLife;
  Timestamp? _lastLifeTickAt;
  Timer? _lifeUiTimer;

  bool _isNavigating = false;
  bool _buyingLife = false;

  // Held rather than rebuilt in `build()`: the per-question countdown calls
  // setState once a second, and each of those used to re-subscribe the
  // session document. The ref is the same for the whole screen (it's keyed
  // by the level being played), so the first one wins.
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _session;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _sessionStream(
    DocumentReference<Map<String, dynamic>> ref,
  ) {
    return _session ??= ref.snapshots();
  }

  static const int _defaultTimePerQ = 15;
  static const int _buyLifeCost = EconomyService.buyFullLifeCost;
  static const Duration _revealDelay = Duration(seconds: 1);
  static const Duration _switchDuration = Duration(milliseconds: 250);

  bool _reportingQuestion = false;

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

  void _refreshLivesUi() {
    if (!mounted) return;

    final localState = LifeService.instance.calculateLocalLifeState({
      'lifeUnits': _lifeUnits,
      'maxLifeUnits': _maxLifeUnits,
      'lifeRegenSeconds': _lifeRegenSeconds,
      'lastLifeTickAt': _lastLifeTickAt,
    });

    setState(() {
      _lifeUnits = (localState['lifeUnits'] ?? _lifeUnits) as int;
      _maxLifeUnits = (localState['maxLifeUnits'] ?? _maxLifeUnits) as int;
      _lifeRegenSeconds =
          (localState['lifeRegenSeconds'] ?? _lifeRegenSeconds) as int;
      _secondsToNextHalfLife = localState['secondsToNextHalfLife'] as int?;
      _lastLifeTickAt = localState['lastLifeTickAt'] as Timestamp?;
    });
  }

  /// Repaints the life bar. Pass [knownState] when a call that just spent
  /// life already returned the server's post-action state — re-fetching it
  /// would be a second callable and a second Firestore transaction for an
  /// answer already in hand.
  Future<void> _syncLivesUiFromFirestore({
    Map<String, dynamic>? knownState,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final state = knownState ?? await LifeService.instance.refreshLives(uid);

    if (!mounted) return;

    setState(() {
      _lifeUnits = (state['lifeUnits'] ?? _lifeUnits) as int;
      _maxLifeUnits = (state['maxLifeUnits'] ?? _maxLifeUnits) as int;
      _lifeRegenSeconds =
          (state['lifeRegenSeconds'] ?? _lifeRegenSeconds) as int;
      _secondsToNextHalfLife = state['secondsToNextHalfLife'] as int?;
      _lastLifeTickAt = state['lastLifeTickAt'] as Timestamp?;
    });
  }

  /// As [_syncLivesUiFromFirestore], but also ends the level when the bar
  /// hits zero. [knownState] serves the same purpose here.
  Future<void> _refreshLivesAndStopIfEmpty({
    Map<String, dynamic>? knownState,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final state = knownState ?? await LifeService.instance.refreshLives(uid);

    if (!mounted) return;

    final lifeUnits = (state['lifeUnits'] ?? 0) as int;

    setState(() {
      _lifeUnits = lifeUnits;
      _maxLifeUnits = (state['maxLifeUnits'] ?? _maxLifeUnits) as int;
      _lifeRegenSeconds =
          (state['lifeRegenSeconds'] ?? _lifeRegenSeconds) as int;
      _secondsToNextHalfLife = state['secondsToNextHalfLife'] as int?;
      _lastLifeTickAt = state['lastLifeTickAt'] as Timestamp?;

      if (lifeUnits <= 0) {
        _endedByNoLives = true;
        _locked = true;
        _answerSubmitting = false;
        _timer?.cancel();
      }
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

      await _syncLivesUiFromFirestore();

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.soloNotEnoughCoins),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.soloLifeRecovered),
        ),
      );

      setState(() {
        _lifeChecked = false;
        _lifeGateError = null;
        _endedByNoLives = false;
      });
    } finally {
      if (mounted) {
        setState(() => _buyingLife = false);
      }
    }
  }

  Future<void> _buyLifeMidLevel(String uid) async {
    if (_buyingLife) return;

    setState(() => _buyingLife = true);

    try {
      final success = await LifeService.instance.buyFullLife(
        uid: uid,
        cost: _buyLifeCost,
      );

      await _syncLivesUiFromFirestore();

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.soloNotEnoughCoins),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.soloLifeRecovered),
        ),
      );

      setState(() {
        _endedByNoLives = false;
        _locked = false;
        _answerSubmitting = false;
        _timerForIndex = -1;
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
        if (_locked || _endedByNoLives) {
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

          final uid = FirebaseAuth.instance.currentUser!.uid;

          Future.microtask(() async {
            final life = await LifeService.instance.tryConsumeWrongAnswer(uid);
            final lifeLost = life.applied;
            await _refreshLivesAndStopIfEmpty(knownState: life.state);

            if (!mounted) return;

            final l10n = AppLocalizations.of(context);

            setState(() {
              _statusMsg = _endedByNoLives
                  ? l10n.levelPlayTimeUpNoLives
                  : lifeLost
                      ? l10n.levelPlayTimeUpLostHalfLife
                      : l10n.levelPlayTimeUpNoLifeLoss;
            });

            if (_endedByNoLives) return;

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
    if (!mounted || _endedByNoLives) return;
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
    if (_endedByNoLives) return;
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

    // `tappedIndex` refers to the locally-shuffled options order, but the
    // server only knows the original (pre-shuffle) answerIndex stored in
    // the session doc — map back through `originalIndexByShuffled` so
    // submitSoloLevelResult can verify this selection independently.
    final originalIndexByShuffled =
        (_shuffledCache[_index]?['originalIndexByShuffled'] as List?)
            ?.cast<int>();
    final originalSelectedIndex =
        (originalIndexByShuffled != null && tappedIndex < originalIndexByShuffled.length)
            ? originalIndexByShuffled[tappedIndex]
            : tappedIndex;

    // A mid-level life refill can bring the player back to the same
    // question (see _buyLifeMidLevel) — replace any earlier attempt at
    // this questionIndex instead of appending a second entry, or the
    // server-side scoring in submitSoloLevelResult would see two answers
    // for one question and could drop the legitimate retry.
    _answers.removeWhere((a) => a['questionIndex'] == _index);
    _answers.add({
      'questionIndex': _index,
      'selectedIndex': originalSelectedIndex,
    });

    if (correct) {
      SfxService.instance.playCorrect();
      setState(() => _correct++);
    } else {
      SfxService.instance.playWrong();

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final life = await LifeService.instance.tryConsumeWrongAnswer(uid);
      final lifeLost = life.applied;
      await _refreshLivesAndStopIfEmpty(knownState: life.state);

      if (mounted) {
        final l10n = AppLocalizations.of(context);

        setState(() {
          _statusMsg = _endedByNoLives
              ? l10n.levelPlayWrongNoLives
              : lifeLost
                  ? l10n.levelPlayWrongLostHalfLife
                  : l10n.levelPlayWrongNoLifeLoss;
        });
      }
    }

    if (_endedByNoLives) return;

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

    final l10n = AppLocalizations.of(context);

    setState(() {
      _lifeLoading = true;
      _lifeGateError = null;
    });

    try {
      await LifeService.instance.ensureUserLifeDoc(uid);
      final entry = await LifeService.instance.tryConsumeLevelEntry(uid);

      await _syncLivesUiFromFirestore(knownState: entry.state);

      if (!entry.applied) {
        _lifeGateError = l10n.levelPlayNeedFullLife;
      }

      _lifeChecked = true;
    } catch (e) {
      _lifeGateError = l10n.levelPlayLifeCheckError(e.toString());
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
    final l10n = AppLocalizations.of(context);

    final categoryRef = widget.isAiTopic
        ? db
            .collection('users')
            .doc(uid)
            .collection('ai_topics')
            .doc(widget.aiTopicId)
        : db.collection('fixed_categories').doc(widget.categoryId);

    final sessionId = widget.isAiTopic
        ? '${widget.aiTopicId}_${widget.levelNumber}'
        : '${widget.categoryId}_${widget.levelNumber}';
    final sessionRef = db
        .collection('users')
        .doc(uid)
        .collection(
          widget.isAiTopic ? 'sessions_ai' : 'sessions_fixed',
        )
        .doc(sessionId);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.levelPlayAppBarTitle(
            widget.isAiTopic ? l10n.levelPlayAiTopicLabel : widget.categoryId,
            widget.levelNumber,
          ),
        ),
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
              _levelCount ??= widget.isAiTopic
                  ? ((catData?['targetLevels'] ??
                          catData?['levelsCount'] ??
                          EconomyService.aiLevelsPerTopic) as num)
                      .toInt()
                  : ((catData?['levelCount'] ?? 0) as num).toInt();

              // Before anything that touches the session: it's deleted on
              // submit, and the results are already fully in local state.
              if (_levelFinished) {
                return _buildEnd(context, _finishedTotal);
              }

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

                  if (sesExists) {
                    Future.microtask(_kickAiBuffer);
                  }

                  if (!sesExists) {
                    if (!_creatingSession) {
                      _creatingSession = true;
                      Future.microtask(() async {
                        try {
                          await _ensureSession(
                            sessionRef: sessionRef,
                          );
                          _kickAiBuffer();
                        } catch (e) {
                          // The life for this level entry was already
                          // charged in _checkAndConsumeLife before session
                          // creation was attempted — refund it here so a
                          // failed session creation (empty pool, transient
                          // error) doesn't leave the player down a life for
                          // nothing. _lifeChecked is reset by the Retry
                          // button below, not here, so this doesn't loop.
                          await LifeService.instance.refundLevelEntry(uid);
                          // Just the message: `e.toString()` on a
                          // FirebaseFunctionsException drags the whole
                          // async stack trace onto the screen, which the
                          // player can neither read nor act on.
                          _sessionError = e is FirebaseFunctionsException
                              ? (e.message ?? l10n.levelPlaySessionCreateError)
                              : l10n.levelPlaySessionCreateError;
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
                              Text(
                                l10n.levelPlaySessionCreateErrorTitle,
                                style: GoogleFonts.baloo2(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
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
                                    // Refunded above — re-run the life
                                    // gate so retrying charges again
                                    // instead of skipping the life check.
                                    _lifeChecked = false;
                                  });
                                },
                                child: Text(l10n.commonRetry),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(l10n.levelPlayGeneratingQuestions),
                        ],
                      ),
                    );
                  }

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _sessionStream(sessionRef),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final data = snap.data!.data();
                      if (data == null) {
                        return Center(
                          child: Text(l10n.levelPlaySessionNotFound),
                        );
                      }

                      final questions =
                          (data['questions'] as List<dynamic>? ?? []);
                      if (questions.isEmpty) {
                        return Center(
                          child: Text(l10n.levelPlaySessionNoQuestions),
                        );
                      }

                      if (_endedByNoLives) {
                        _timer?.cancel();
                        return _buildNoLivesMidLevel(context, uid);
                      }

                      if (_index >= questions.length) {
                        _timer?.cancel();

                        // Latched here rather than via setState: the build
                        // above already returns the results screen, and
                        // every later rebuild short-circuits to it before
                        // the session is consulted at all.
                        _levelFinished = true;
                        _finishedTotal = questions.length;

                        if (!_saved && !_saving) {
                          Future.microtask(
                            () => _saveProgress(total: questions.length),
                          );
                        }
                        return _buildEnd(context, questions.length);
                      }

                      final qMap = questions[_index] as Map<String, dynamic>;
                      final qText = (qMap['q'] ?? '').toString();
                      final questionId = (qMap['questionId'] ?? '').toString();

                      List<String> options;
                      int answerIndex;
                      List<int> originalIndexByShuffled;

                      final cached = _shuffledCache[_index];
                      if (cached != null) {
                        options = (cached['options'] as List).cast<String>();
                        answerIndex = cached['answerIndex'] as int;
                        originalIndexByShuffled =
                            (cached['originalIndexByShuffled'] as List)
                                .cast<int>();
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
                            'originalIndex': i,
                          };
                        });

                        paired.shuffle();

                        options =
                            paired.map((e) => e['text'] as String).toList();
                        answerIndex =
                            paired.indexWhere((e) => e['isCorrect'] == true);
                        originalIndexByShuffled = paired
                            .map((e) => e['originalIndex'] as int)
                            .toList();

                        _shuffledCache[_index] = {
                          'options': options,
                          'answerIndex': answerIndex,
                          'originalIndexByShuffled': originalIndexByShuffled,
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
                          questionId: questionId,
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
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      l10n.commonLoading,
                      style: const TextStyle(color: Colors.white),
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
    final l10n = AppLocalizations.of(context);
    final lifeText =
        '${LifeService.instance.formatLives(_lifeUnits)} / ${LifeService.instance.formatLives(_maxLifeUnits)}';

    final nextFullLifeSeconds = _lifeUnits == 1
        ? _secondsToNextHalfLife
        : (_secondsToNextHalfLife == null
            ? null
            : _secondsToNextHalfLife! + 150);

    return _NoLivesCard(
      title: l10n.livesNoLivesTitle,
      message: _lifeGateError ?? l10n.levelPlayNeedFullLife,
      lifeText: lifeText,
      nextHalfLifeText: _lifeUnits >= _maxLifeUnits
          ? l10n.levelPlayLivesMax
          : _formatSeconds(_secondsToNextHalfLife),
      nextFullLifeText: _formatSeconds(nextFullLifeSeconds),
      buyLabel: l10n.livesRecoverButton(_buyLifeCost),
      onBuyLife: _buyingLife ? null : () => _buyLifeAndRetryEntry(uid),
      onBack: _isNavigating || _buyingLife
          ? null
          : () {
              _safeNavigate(() async {
                Navigator.pop(context);
              });
            },
    );
  }

  Widget _buildNoLivesMidLevel(BuildContext context, String uid) {
    final l10n = AppLocalizations.of(context);
    final lifeText =
        '${LifeService.instance.formatLives(_lifeUnits)} / ${LifeService.instance.formatLives(_maxLifeUnits)}';

    final nextFullLifeSeconds = _lifeUnits == 1
        ? _secondsToNextHalfLife
        : (_secondsToNextHalfLife == null
            ? null
            : _secondsToNextHalfLife! + 150);

    return _NoLivesCard(
      title: l10n.levelPlayOutOfLivesTitle,
      message: l10n.levelPlayOutOfLivesMessage,
      lifeText: lifeText,
      nextHalfLifeText: _lifeUnits >= _maxLifeUnits
          ? l10n.levelPlayLivesMax
          : _formatSeconds(_secondsToNextHalfLife),
      nextFullLifeText: _formatSeconds(nextFullLifeSeconds),
      buyLabel: l10n.livesRecoverButton(_buyLifeCost),
      onBuyLife: _buyingLife ? null : () => _buyLifeMidLevel(uid),
      onBack: _isNavigating || _buyingLife
          ? null
          : () {
              _safeNavigate(() async {
                Navigator.pop(context);
              });
            },
    );
  }

  Widget _buildLivesHeader() {
    final l10n = AppLocalizations.of(context);
    final lifeText =
        '${LifeService.instance.formatLives(_lifeUnits)} / ${LifeService.instance.formatLives(_maxLifeUnits)}';
    final isFull = _lifeUnits >= _maxLifeUnits;

    const iconColor = Color(0xFFFF6B5B);
    const valueColor = Color(0xFFB23A2C);
    const labelColor = Color(0xFFD9695B);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite_border, size: 22, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.levelPlayLivesHeader(lifeText),
              style: GoogleFonts.baloo2(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
          Icon(
            isFull ? Icons.check_circle_outline : Icons.timer_outlined,
            size: 16,
            color: labelColor,
          ),
          const SizedBox(width: 4),
          Text(
            isFull
                ? l10n.levelPlayLivesMax
                : l10n.levelPlayHalfLifeIn(
                    _formatSeconds(_secondsToNextHalfLife),
                  ),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }

  static const List<String> _reportReasonKeys = [
    'wrong_answer',
    'confusing',
    'inappropriate',
    'other',
  ];

  String _reportReasonLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'wrong_answer':
        return l10n.aiReportReasonWrongAnswer;
      case 'confusing':
        return l10n.aiReportReasonConfusing;
      case 'inappropriate':
        return l10n.aiReportReasonInappropriate;
      default:
        return l10n.aiReportReasonOther;
    }
  }

  Future<void> _showReportQuestionDialog({
    required String questionId,
    required String questionText,
  }) async {
    final l10n = AppLocalizations.of(context);
    String selectedReason = _reportReasonKeys.first;
    final detailsController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.aiReportDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<String>(
                groupValue: selectedReason,
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedReason = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _reportReasonKeys
                      .map(
                        (key) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: key,
                          title: Text(_reportReasonLabel(l10n, key)),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: detailsController,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: l10n.aiReportDialogDetailsHint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.aiReportDialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.aiReportDialogSubmit),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    await _reportQuestion(
      questionId: questionId,
      questionText: questionText,
      reason: selectedReason,
      details: detailsController.text,
    );
  }

  Future<void> _reportQuestion({
    required String questionId,
    required String questionText,
    required String reason,
    required String details,
  }) async {
    if (_reportingQuestion) return;
    setState(() => _reportingQuestion = true);

    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'reportAiQuestion',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({
        'topicId': widget.aiTopicId,
        'levelNumber': widget.levelNumber,
        'questionId': questionId,
        'questionText': questionText,
        'reason': reason,
        if (details.trim().isNotEmpty) 'details': details.trim(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).aiReportSent)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _reportingQuestion = false);
    }
  }

  Widget _buildQuestionView({
    required Key key,
    required String qText,
    required String questionId,
    required List<String> options,
    required int answerIndex,
    required int total,
  }) {
    final l10n = AppLocalizations.of(context);
    final absorbing =
        _locked || _answerSubmitting || _isNavigating || _endedByNoLives;

    final colorScheme = Theme.of(context).colorScheme;

    final progress = total == 0 ? 0.0 : (_index / total).clamp(0.0, 1.0);

    final timeFraction = _defaultTimePerQ == 0
        ? 0.0
        : (_secondsLeft / _defaultTimePerQ).clamp(0.0, 1.0);

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
            _buildLivesHeader(),
            const SizedBox(height: 14),
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
                if (widget.isAiTopic && _locked && questionId.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: l10n.aiReportQuestionTooltip,
                    onPressed: _reportingQuestion
                        ? null
                        : () => _showReportQuestionDialog(
                              questionId: questionId,
                              questionText: qText,
                            ),
                    icon: const Icon(Icons.flag_outlined),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 22),
            QuestionAnswerCard(
              qText: qText,
              options: options,
              answerIndex: answerIndex,
              selectedIndex: _selected,
              locked: _locked,
              timedOut: _timedOut,
              timeoutAnswerIndex: _timeoutAnswerIndex,
              onTapAnswer: (i) => _onTapAnswer(
                tappedIndex: i,
                answerIndex: answerIndex,
              ),
            ),
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

  // Session creation moved server-side (ensureSoloLevelSession Cloud
  // Function) — the client used to read the real level/pool questions and
  // write its own copy (including answerIndex) straight into
  // sessions_ai/sessions_fixed, which submitSoloLevelResult then trusted
  // as ground truth, letting a modified client farm rewards with
  // self-chosen "correct" answers. firestore.rules now denies client
  // `create` on those collections, so this call is the only way to
  // populate them.
  /// Starts generating the levels ahead of this one, as soon as this level
  /// opens.
  ///
  /// Buffering used to be kicked off only from `_saveProgress`, when a level
  /// was submitted — but players tap "continue" a few seconds later and a
  /// real generation takes ~30s, so the next level was never ready in time
  /// and every level start fell into `ensureSoloLevelSession`'s on-demand
  /// path with the player watching a spinner. Firing it here instead gives
  /// generation the whole time the player spends answering.
  ///
  /// Still fire-and-forget, and still safe to overlap with the submit-time
  /// call: the server takes a per-level lock, so whichever arrives second
  /// waits for the first's questions rather than generating duplicates.
  void _kickAiBuffer() {
    final topicId = widget.aiTopicId;
    if (_bufferKicked || !widget.isAiTopic || topicId == null) return;
    _bufferKicked = true;

    unawaited(
      AiTopicService.instance.ensureAiTopicBuffer(
        topicId: topicId,
        completedLevel: widget.levelNumber,
      ),
    );
  }

  Future<void> _ensureSession({
    required DocumentReference<Map<String, dynamic>> sessionRef,
  }) async {
    final existing = await sessionRef.get();
    if (existing.exists) return;

    await FirebaseFunctions.instance
        .httpsCallable(
          'ensureSoloLevelSession',
          // 15s was fine while this only ever read existing questions, but
          // it now generates the level when its bank was never buffered,
          // which takes a real Claude call. The function is allowed longer
          // than this on purpose: if the wait here runs out, the server
          // still finishes and persists the questions, so the Retry button
          // resolves instantly instead of starting over.
          options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
        )
        .call({
      'isAiTopic': widget.isAiTopic,
      'categoryId': widget.categoryId,
      'aiTopicId': widget.aiTopicId,
      'levelNumber': widget.levelNumber,
    });
  }

  Future<void> _saveProgress({required int total}) async {
    if (_saved) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'submitSoloLevelResult',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      final response = await callable.call({
        'isAiTopic': widget.isAiTopic,
        'categoryId': widget.categoryId,
        'aiTopicId': widget.aiTopicId,
        'levelNumber': widget.levelNumber,
        'correct': _correct,
        'total': total,
        'answers': _answers,
      });

      final data = Map<String, dynamic>.from(response.data as Map);

      final grantedXp = ((data['grantedXp'] ?? 0) as num).toInt();
      final grantedCoins = ((data['grantedCoins'] ?? 0) as num).toInt();
      final shouldEnsureAiBuffer = data['shouldEnsureAiBuffer'] == true;

      setState(() {
        _earnedXp = grantedXp;
        _earnedCoins = grantedCoins;
        _rewardGrantedForLevel = grantedXp > 0 || grantedCoins > 0;
        _userTotalXp = ((data['userTotalXp'] ?? 0) as num).toInt();
      });

      // The solo_levels_10 achievement's progress is now granted
      // server-side, inside submitSoloLevelResult, since completed/
      // progress/claimed are locked against direct client writes for this
      // id in firestore.rules.

      if (shouldEnsureAiBuffer && widget.aiTopicId != null) {
        unawaited(
          AiTopicService.instance.ensureAiTopicBuffer(
            topicId: widget.aiTopicId!,
            completedLevel: widget.levelNumber,
          ),
        );
      }

      _saved = true;
    } catch (e) {
      _saveError = e.toString();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildEnd(BuildContext context, int total) {
    final l10n = AppLocalizations.of(context);
    final pct = total == 0 ? 0.0 : (_correct / total);

    String label;
    if (pct >= 0.9) {
      label = l10n.levelPlayRankExpert;
    } else if (pct >= 0.7) {
      label = l10n.levelPlayRankAdvanced;
    } else if (pct >= 0.4) {
      label = l10n.levelPlayRankIntermediate;
    } else {
      label = l10n.levelPlayRankBeginner;
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
            Text(
              pct >= 0.4 ? l10n.levelPlayLevelPassed : l10n.levelPlayLevelFinished,
              style: GoogleFonts.baloo2(
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                _BigStarsRow(count: starCount),
                if (starCount == 3) const _ThreeStarsCelebration(),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l10n.levelPlayScoreLine(_correct, total, pctText),
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.levelPlayRankLine(label),
              style: GoogleFonts.baloo2(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.levelPlayRewardsTitle,
                    style: GoogleFonts.baloo2(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _RewardCard(
                          icon: Icons.auto_awesome_outlined,
                          label: l10n.homeXp,
                          accent: Theme.of(context).colorScheme.primary,
                          background:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: _AnimatedRewardNumber(
                            value: _earnedXp,
                            prefix: '+',
                            color: Color.lerp(
                              Theme.of(context).colorScheme.primary,
                              Colors.black,
                              0.35,
                            )!,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RewardCard(
                          icon: Icons.monetization_on_outlined,
                          label: l10n.homeCoins,
                          accent: AppColors.reward,
                          background: AppColors.rewardBg,
                          child: _AnimatedRewardNumber(
                            value: _earnedCoins,
                            prefix: '+',
                            color: Color.lerp(AppColors.reward, Colors.black, 0.35)!,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_saving &&
                      (_saved || _saveError != null) &&
                      !_rewardGrantedForLevel) ...[
                    const SizedBox(height: 12),
                    Text(
                      pct >= 0.4
                          ? l10n.levelPlayAlreadyPassedBefore
                          : l10n.levelPlayNeed40Percent,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            _AnimatedXpProgressCard(
              previousXp: previousXp,
              currentXp: _userTotalXp,
            ),
            if (_saving) ...[
              const SizedBox(height: 18),
              const CircularProgressIndicator(strokeWidth: 3),
              const SizedBox(height: 8),
              Text(l10n.levelPlaySavingProgress),
            ],
            if (_saveError != null) ...[
              const SizedBox(height: 18),
              Text(
                l10n.levelPlaySaveError(_saveError!),
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : () => _saveProgress(total: total),
                child: Text(l10n.levelPlayRetrySave),
              ),
            ],
            if (_saved && _saveError == null && !_saving) ...[
              const SizedBox(height: 18),
              Text(
                l10n.levelPlayProgressSaved,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (!hasNext)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isNavigating
                          ? null
                          : () {
                              _safeNavigate(() async {
                                _timer?.cancel();
                                _shuffledCache.clear();
                                Navigator.pop(context);
                              });
                            },
                      child: Text(l10n.livesGoBack),
                    ),
                  ),
                if (hasNext) ...[
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
                                      isAiTopic: widget.isAiTopic,
                                      aiTopicId: widget.aiTopicId,
                                    ),
                                  ),
                                );
                              });
                            },
                      child: Text(l10n.levelPlayContinueNextLevel(nextLevel)),
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

class _NoLivesCard extends StatelessWidget {
  final String title;
  final String message;
  final String lifeText;
  final String nextHalfLifeText;
  final String nextFullLifeText;
  final String buyLabel;
  final VoidCallback? onBuyLife;
  final VoidCallback? onBack;

  const _NoLivesCard({
    required this.title,
    required this.message,
    required this.lifeText,
    required this.nextHalfLifeText,
    required this.nextFullLifeText,
    required this.buyLabel,
    required this.onBuyLife,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_border,
                  size: 40,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.favorite,
                      label: l10n.livesYourLives,
                      value: lifeText,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.timer,
                      label: l10n.livesNextHalf,
                      value: nextHalfLifeText,
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.hourglass_bottom,
                      label: l10n.livesNextFull,
                      value: nextFullLifeText,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onBuyLife,
                  icon: const Icon(Icons.favorite),
                  label: Text(buyLabel),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onBack,
                  child: Text(l10n.livesGoBack),
                ),
              ),
            ],
          ),
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
  final Color accent;
  final Color background;
  final Widget child;

  const _RewardCard({
    required this.icon,
    required this.label,
    required this.accent,
    required this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = Color.lerp(accent, Colors.black, 0.25)!;
    final labelColor = Color.lerp(accent, Colors.black, 0.10)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: labelColor),
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
  final Color color;

  const _AnimatedRewardNumber({
    required this.value,
    required this.color,
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
          style: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: color,
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
    const gradientStart = Color(0xFF8A6BFF);
    const gradientEnd = Color(0xFFFF5C93);
    final unfilledColor = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.35);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      children: List.generate(3, (i) {
        final filled = i < count;
        final color = filled
            ? Color.lerp(gradientStart, gradientEnd, i / 2)!
            : unfilledColor;

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
            color: color,
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

  // Mirrors PlayerLevelService's actual (non-flat) per-level XP cost — used
  // to only assume a flat 100 XP/level here, which silently diverged from
  // the real level/progress shown on the profile screen as soon as XP grew
  // past level 1 (e.g. 500 XP is level 4 for real, but showed as level 6
  // here).
  _XpLevelBounds _levelBoundsForXp(int xp) {
    final info = PlayerLevelService.instance.getLevelInfo(xp);
    final floor = xp - info.currentLevelXp;
    return _XpLevelBounds(
      level: info.level,
      floorXp: floor,
      ceilXp: floor + info.xpRequired,
    );
  }

  List<_XpSegment> _buildSegments(int previousXp, int currentXp) {
    if (currentXp <= previousXp) {
      final bounds = _levelBoundsForXp(currentXp);
      return [
        _XpSegment(
          level: bounds.level,
          startXp: currentXp,
          endXp: currentXp,
          floorXp: bounds.floorXp,
          ceilXp: bounds.ceilXp,
        ),
      ];
    }

    final segments = <_XpSegment>[];
    int cursor = previousXp;

    while (cursor < currentXp) {
      final bounds = _levelBoundsForXp(cursor);
      final segmentEnd = currentXp < bounds.ceilXp ? currentXp : bounds.ceilXp;

      segments.add(
        _XpSegment(
          level: bounds.level,
          startXp: cursor,
          endXp: segmentEnd,
          floorXp: bounds.floorXp,
          ceilXp: bounds.ceilXp,
        ),
      );

      if (segmentEnd == currentXp) break;
      cursor = segmentEnd;
    }

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLevel = PlayerLevelService.instance
        .getLevelInfo(widget.currentXp)
        .level;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.levelPlayPlayerLevel(currentLevel),
            style: GoogleFonts.baloo2(
              fontSize: 18,
              fontWeight: FontWeight.w800,
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
                l10n.levelPlayTotalXp(animatedXp),
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

class _XpLevelBounds {
  final int level;
  final int floorXp;
  final int ceilXp;

  const _XpLevelBounds({
    required this.level,
    required this.floorXp,
    required this.ceilXp,
  });
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

    final l10n = AppLocalizations.of(context);

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
          SfxService.instance.playReward();
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
              l10n.levelSelectLevelNumber(widget.segment.level),
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
                          color: Colors.amber.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          l10n.levelPlayLevelUp(widget.segment.level + 1),
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
                  ? l10n.levelPlayLeveledUpTo(widget.segment.level + 1)
                  : l10n.levelPlayXpInLevel(
                      displayedXp - widget.segment.floorXp,
                      span,
                    ),
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
                      color: Colors.amber.withValues(alpha: 0.9),
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
                  color: Colors.amber.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.35),
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
