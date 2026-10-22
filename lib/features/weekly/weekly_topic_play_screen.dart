import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/life_service.dart';
import '../../services/sfx_service.dart';
import '../../services/weekly_topic_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/profile_avatar_button.dart';

/// A single round (fixed-size, freshly drawn from the category's pools —
/// see WeeklyTopicService.loadRandomRound) of Weekly Topic questions. This
/// replaces the old flow of reusing Solo's LevelSelectScreen/LevelPlayScreen
/// for the topic's fixed levels, which meant a repeat occurrence of the
/// same category showed byte-identical content to what was already played
/// in Solo.
class WeeklyTopicPlayScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final String weekId;

  const WeeklyTopicPlayScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.weekId,
  });

  @override
  State<WeeklyTopicPlayScreen> createState() => _WeeklyTopicPlayScreenState();
}

class _WeeklyTopicPlayScreenState extends State<WeeklyTopicPlayScreen> {
  late final String _uid = FirebaseAuth.instance.currentUser!.uid;

  List<Map<String, dynamic>> _questions = [];
  final List<Map<String, dynamic>> _answers = [];
  int _index = 0;
  int _correct = 0;

  int? _selectedIndex;
  bool? _lastCorrect;
  Color _flashColor = Colors.transparent;

  int _lifeUnits = 0;
  bool _endedByNoLives = false;

  bool _loading = true;
  bool _submitting = false;
  bool _submitFailed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Loads the round first and charges the entry life only once it is
  /// there. In the other order a round that failed to load had already
  /// cost a life, with nothing to play for it; and any failure here used
  /// to leave an endless spinner with no way back.
  Future<void> _init() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final questions = await WeeklyTopicService.instance.loadRandomRound(
        uid: _uid,
        weekId: widget.weekId,
        categoryId: widget.categoryId,
      );

      final entry = await LifeService.instance.tryConsumeLevelEntry(_uid);

      if (!mounted) return;

      if (!entry.applied) {
        Navigator.pop(context);
        return;
      }

      setState(() {
        _questions = questions;
        _lifeUnits = (entry.state['lifeUnits'] ?? 0) as int;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            AppLocalizations.of(context).commonConnectionError;
        _loading = false;
      });
    }
  }

  String _questionText(Map<String, dynamic> q) {
    return (q['q'] ?? q['question'] ?? '').toString();
  }

  List<String> _options(Map<String, dynamic> q) {
    return (q['options'] ?? q['answers'] ?? [])
        .map<String>((e) => e.toString())
        .toList();
  }

  int _answerIndex(Map<String, dynamic> q) {
    return ((q['answerIndex'] ?? q['correctIndex'] ?? 0) as num).toInt();
  }

  Future<void> _answer(int index, int correctIndex) async {
    if (_submitting || _selectedIndex != null) return;

    final isCorrect = index == correctIndex;
    final q = _questions[_index];

    if (isCorrect) {
      HapticFeedback.lightImpact();
      SfxService.instance.playCorrect();
    } else {
      HapticFeedback.heavyImpact();
      SfxService.instance.playWrong();
    }

    setState(() {
      _flashColor = isCorrect
          ? context.appColors.success.withValues(alpha: 0.18)
          : context.appColors.danger.withValues(alpha: 0.18);
      _selectedIndex = index;
      _lastCorrect = isCorrect;

      if (isCorrect) _correct++;

      _answers.add({
        'sourceDifficulty': q['sourceDifficulty'],
        'sourceQuestionId': q['sourceQuestionId'],
        'selectedIndex': index,
      });
    });

    if (!isCorrect) {
      // A failed call never stops the round: it used to throw here, with
      // the options already disabled, and leave the player on a locked
      // question.
      try {
        final life = await LifeService.instance.tryConsumeWrongAnswer(_uid);

        if (!mounted) return;

        final newLifeUnits = (life.state['lifeUnits'] ?? 0) as int;

        setState(() {
          _lifeUnits = newLifeUnits;
          if (life.applied && newLifeUnits <= 0) _endedByNoLives = true;
        });
      } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    if (_endedByNoLives || _index + 1 >= _questions.length) {
      await _finish();
      return;
    }

    setState(() {
      _index++;
      _selectedIndex = null;
      _lastCorrect = null;
      _flashColor = Colors.transparent;
    });
  }

  Future<void> _finish() async {
    setState(() {
      _submitting = true;
      _submitFailed = false;
    });

    try {
      final result = await WeeklyTopicService.instance.submitRound(
        weekId: widget.weekId,
        categoryId: widget.categoryId,
        answers: _answers,
      );

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);
      final correct = (result['correct'] ?? 0) as int;
      final total = _answers.length;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.weeklyTopicRoundResultTitle),
          content: Text(l10n.weeklyTopicRoundResultBody(correct, total)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.weeklyTopicRoundResultButton),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;

      // The round only counts once submitted, so a failure keeps the
      // answers here and offers to send them again rather than losing it.
      setState(() {
        _submitting = false;
        _submitFailed = true;
      });
    }
  }

  Color _buttonColor(int index, int correctIndex) {
    if (_selectedIndex == null) return Theme.of(context).colorScheme.primary;
    if (index == correctIndex) return context.appColors.success;
    if (index == _selectedIndex) {
      return _lastCorrect == true ? context.appColors.success : context.appColors.danger;
    }
    return Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  Color _buttonTextColor(int index, int correctIndex) {
    if (_selectedIndex != null &&
        index != correctIndex &&
        index != _selectedIndex) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return context.appColors.onAccent;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: AppBarTitle(widget.categoryName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: AppBarTitle(widget.categoryName),
          actions: const [ProfileAvatarButton(openProfileOnTap: false)],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _init,
                  child: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final q = _questions[_index];
    final options = _options(q);
    final correctIndex = _answerIndex(q);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(widget.categoryName),
        automaticallyImplyLeading: !_submitting,
        actions: const [ProfileAvatarButton(openProfileOnTap: false)],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: _flashColor,
        child: AbsorbPointer(
          absorbing: _submitting,
          // Scrolls instead of fitting with a Spacer: a long question with
          // four long answers overflowed a small phone or a large font.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      color: context.appColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      LifeService.instance.formatLives(_lifeUnits),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      l10n.weeklyTopicRoundQuestionCount(
                        _index + 1,
                        _questions.length,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  _questionText(q),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ...List.generate(options.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // The disabled colours too: once an answer is
                        // picked every option is disabled, and a disabled
                        // button ignores backgroundColor, so the right and
                        // wrong answers were never shown.
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonColor(i, correctIndex),
                          foregroundColor: _buttonTextColor(i, correctIndex),
                          disabledBackgroundColor:
                              _buttonColor(i, correctIndex),
                          disabledForegroundColor:
                              _buttonTextColor(i, correctIndex),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                        ),
                        onPressed: _selectedIndex != null || _submitting
                            ? null
                            : () => _answer(i, correctIndex),
                        child: Text(options[i], textAlign: TextAlign.center),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Text(
                  l10n.weeklyTopicRoundCorrectCount(_correct),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_submitFailed) ...[
                  const SizedBox(height: 16),
                  Text(
                    l10n.commonConnectionError,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _finish,
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
