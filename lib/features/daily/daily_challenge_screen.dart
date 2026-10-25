import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/answer_service.dart';
import '../../services/daily_challenge_service.dart';
import '../../services/question_report_service.dart';
import '../../services/sfx_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../l10n/localized_content.dart';
import '../../widgets/question_answer_card.dart';
import 'daily_challenge_result_screen.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/count_pill.dart';
import '../../widgets/profile_avatar_button.dart';

class DailyChallengeScreen extends StatefulWidget {
  final String uid;

  const DailyChallengeScreen({
    super.key,
    required this.uid,
  });

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  final _service = DailyChallengeService.instance;

  List<Map<String, dynamic>> _questions = [];
  int _currentIndex = 0;
  int _correct = 0;
  int _totalAnswered = 0;
  final List<Map<String, dynamic>> _answers = [];

  int _timeLeft = 120;
  Timer? _timer;
  bool _loading = true;
  bool _loadFailed = false;
  bool _finishing = false;
  bool _savingResults = false;
  bool _saveFailed = false;
  String _dateId = '';

  int? _selectedIndex;

  /// The question being answered, held on screen until the next one: once
  /// its answer is counted the pick below would move on to another.
  int? _shownQuestionIndex;

  /// The current question's right option once the server has judged it.
  int? _revealedIndex;

  /// Waiting for the server's verdict. The clock stands still meanwhile,
  /// so the round trip costs the player nothing.
  bool _awaitingVerdict = false;

  /// Each judged question's right option, for the review.
  final Map<int, int> _correctIndexByQuestion = {};
  Color _flashColor = Colors.transparent;

  String? _coinPopupText;
  int _lastCoinMilestone = 0;

  int get _liveCoinsEarned {
    return _service.calculateCoinsEarned(_correct);
  }

  int _getTargetDifficulty() {
    if (_correct >= 16) return 3;
    if (_correct >= 6) return 2;
    return 1;
  }

  Map<String, dynamic> _currentQuestion() {
    final shown = _shownQuestionIndex;
    if (shown != null) return _questions[shown];

    final targetDifficulty = _getTargetDifficulty();

    final filtered = _questions.where((q) {
      final rawDifficulty = q['sourceDifficulty'] ?? 1;
      final difficulty = rawDifficulty is num
          ? rawDifficulty.toInt()
          : int.tryParse(rawDifficulty.toString()) ?? 1;

      return difficulty == targetDifficulty;
    }).toList();

    // Never one already answered: the first answer is final on the
    // server, so a repeat would only be counted twice here.
    final answered = {for (final a in _answers) a['questionIndex']};
    bool open(Map<String, dynamic> q) =>
        !answered.contains(_questions.indexOf(q));
    final fresh = filtered.where(open).toList();
    final pool = fresh.isNotEmpty
        ? fresh
        : _questions.where(open).toList();
    if (pool.isEmpty) return _questions.first;
    return pool[_currentIndex % pool.length];
  }

  bool get _allAnswered => _answers.length >= _questions.length;

  void _checkCoinMilestone() {
    final milestone = _correct ~/ 10;

    if (milestone > _lastCoinMilestone) {
      _lastCoinMilestone = milestone;

      SfxService.instance.playReward();

      setState(() {
        _coinPopupText = AppLocalizations.of(context).dailyChallengeCoinsPopup;
      });

      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;

        setState(() {
          _coinPopupText = null;
        });
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    final DailyChallengeSession session;
    try {
      session = await _service.createTodaySession(uid: widget.uid);
    } catch (_) {
      // Used to have no handling at all: the spinner never stopped.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }

    if (!mounted) return;

    // Answers the server already judged today, if the player left and came
    // back.
    setState(() {
      _dateId = session.dateId;
      _questions = session.questions;
      _timeLeft = session.remainingSeconds;
      _answers
        ..clear()
        ..addAll(session.answers);
      _correctIndexByQuestion
        ..clear()
        ..addAll(session.correctIndexByQuestion);
      _correct = session.correct;
      _totalAnswered = session.answers.length;
      _currentIndex = session.answers.length;
      _lastCoinMilestone = _correct ~/ 10;
      _loading = false;
    });

    if (_timeLeft <= 0) {
      await _finish();
      return;
    }

    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timeLeft <= 0) {
        _finish();
      } else {
        if (!mounted || _finishing) return;
        // Paused while the server judges an answer.
        if (_awaitingVerdict) return;
        setState(() => _timeLeft--);
      }
    });
  }

  Future<void> _answer(int index) async {
    if (_finishing || _savingResults || _selectedIndex != null) return;
    if (_awaitingVerdict) return;

    final questionIndex = _questions.indexOf(_currentQuestion());

    setState(() {
      _shownQuestionIndex = questionIndex;
      _selectedIndex = index;
      _awaitingVerdict = true;
    });

    final AnswerVerdict verdict;
    try {
      verdict = await AnswerService.instance.answerDaily(
        dateId: _dateId,
        questionIndex: questionIndex,
        selectedIndex: index,
      );
    } catch (e) {
      if (!mounted) return;
      // The tap can be tried again; one the server did get comes back with
      // the same verdict.
      setState(() {
        _shownQuestionIndex = null;
        _selectedIndex = null;
        _awaitingVerdict = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(AppLocalizations.of(context), e)),
        ),
      );
      return;
    }
    if (!mounted) return;

    final isCorrect = verdict.correct;
    if (isCorrect) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    setState(() {
      _awaitingVerdict = false;
      _revealedIndex = verdict.correctIndex;
      _correctIndexByQuestion[questionIndex] = verdict.correctIndex;
      _flashColor = isCorrect
          ? context.appColors.success.withValues(alpha: 0.18)
          : context.appColors.danger.withValues(alpha: 0.18);
      _totalAnswered++;

      if (isCorrect) {
        _correct++;
      }

      _answers.add({
        'questionIndex': questionIndex,
        'selectedIndex': index,
      });
    });

    if (isCorrect) {
      _checkCoinMilestone();
    }

    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted || _finishing) return;

    if (_allAnswered) {
      await _finish();
      return;
    }

    setState(() {
      _currentIndex++;
      _shownQuestionIndex = null;
      _selectedIndex = null;
      _revealedIndex = null;
      _flashColor = Colors.transparent;
    });
  }

  Future<void> _finish() async {
    if (_finishing) return;

    _finishing = true;
    _timer?.cancel();

    if (mounted) {
      setState(() {
        _savingResults = true;
        _saveFailed = false;
        _selectedIndex = null;
        _coinPopupText = null;
        _flashColor = Colors.transparent;
      });
    }

    try {
      final result = await _service.saveResult(
        uid: widget.uid,
        correct: _correct,
        totalAnswered: _totalAnswered,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DailyChallengeResultScreen(
            result: result,
            // Only the questions this run reached: the day's set is larger
            // than what fits in the clock.
            reviewQuestions: reviewedQuestions(
              questions: [
                for (var i = 0; i < _questions.length; i++)
                  {
                    ..._questions[i],
                    'answerIndex': _correctIndexByQuestion[i],
                  },
              ],
              answers: _answers,
              onlyAnswered: true,
              languageCode: Localizations.localeOf(context).languageCode,
              targetFor: (index, _) => {
                'mode': 'daily',
                'dateId': _dateId,
                'questionIndex': index,
              },
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      // The clock is already over, so nothing would ever call this again:
      // the run stays on screen with a way to send it again. The answers
      // are kept on the device too, in case the player leaves instead.
      setState(() {
        _saveFailed = true;
        _finishing = false;
      });
    }
  }

  /// Confirms leaving while the clock is still running.
  Future<void> _confirmLeave() async {
    if (_loading || _loadFailed || _savingResults || _timeLeft <= 0) {
      Navigator.of(context).pop();
      return;
    }

    final l10n = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dailyChallengeLeaveTitle),
        content: Text(l10n.dailyChallengeLeaveBody),
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

    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _questionText(Map<String, dynamic> q) {
    return localizedQuestion(q, Localizations.localeOf(context).languageCode).text;
  }

  List<String> _options(Map<String, dynamic> q) {
    return localizedQuestion(q, Localizations.localeOf(context).languageCode).options;
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _difficultyLabel() {
    final difficulty = _getTargetDifficulty();
    final l10n = AppLocalizations.of(context);

    if (difficulty == 3) return l10n.friendChallengeDiffHard;
    if (difficulty == 2) return l10n.friendChallengeDiffMedium;
    return l10n.friendChallengeDiffEasy;
  }

  Widget _savingOverlay() {
    final l10n = AppLocalizations.of(context);

    return Container(
      color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.decor.pageColor,
            borderRadius: BorderRadius.circular(context.radii.lg),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr([
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ]),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emoji_events_outlined,
                size: 54,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.dailyChallengeCompletedTitle,
                textAlign: TextAlign.center,
                style: context.heading(24),
              ),
              const SizedBox(height: 8),
              Text(
                _saveFailed
                    ? l10n.commonConnectionError
                    : l10n.dailyChallengeSavingResults,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (_saveFailed)
                FilledButton(
                  onPressed: _finish,
                  child: Text(l10n.commonRetry),
                )
              else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // These used to have no AppBar: on iOS, with no back gesture to fall
    // back on, there was no way out of a load that never finished.
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.commonConnectionError,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _init, child: Text(l10n.commonRetry)),
              ],
            ),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.dailyChallengeNoQuestions)),
      );
    }

    final q = _currentQuestion();
    final options = _options(q);

    // Every way back goes through the warning: the clock keeps running
    // while the player is away.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: const [ProfileAvatarButton(openProfileOnTap: false)],
          title: AppBarTitle(l10n.homeDailyChallengeTitle),
          automaticallyImplyLeading: !_savingResults,
        ),
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color: _flashColor,
          child: Stack(
            children: [
              AbsorbPointer(
                absorbing: _savingResults,
                // SafeArea keeps the answered count off the gesture bar.
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _HeaderCard(
                                icon: Icons.timer_outlined,
                                label: l10n.dailyChallengeTimeLabel,
                                value: _formatTime(_timeLeft),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HeaderCard(
                                icon: Icons.star_border,
                                label: l10n.dailyLeaderboardScoreLabel,
                                value: '$_correct',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HeaderCard(
                                icon: Icons.monetization_on_outlined,
                                label: l10n.homeCoins,
                                value: '+$_liveCoinsEarned',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.dailyChallengeDifficultyLine(_difficultyLabel()),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        QuestionAnswerCard(
                          qText: _questionText(q),
                          options: options,
                          // -1 until the server's verdict reveals it.
                          answerIndex: _revealedIndex ?? -1,
                          selectedIndex: _selectedIndex,
                          locked: _revealedIndex != null,
                          onTapAnswer: _answer,
                        ),
                        const Spacer(),
                        CountPill(
                          icon: Icons.quiz_rounded,
                          label: l10n.dailyChallengeAnsweredCount(_totalAnswered),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_coinPopupText != null && !_savingResults)
                Center(
                  child: AnimatedOpacity(
                    opacity: _coinPopupText == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.reward,
                        borderRadius: BorderRadius.circular(context.radii.md),
                        border: context.surfaces.borderOr(null),
                        boxShadow: context.surfaces.shadowsOr([
                          BoxShadow(
                            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ]),
                      ),
                      child: Text(
                        _coinPopupText!,
                        style: context.heading(
                          24,
                          color: context.appColors.onReward,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_savingResults) _savingOverlay(),
            ],
          ),
        ),
    ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeaderCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.sm),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
