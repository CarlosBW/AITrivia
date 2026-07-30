import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/life_service.dart';
import '../../services/sfx_service.dart';
import '../../services/weekly_topic_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await LifeService.instance.ensureUserLifeDoc(_uid);
    final consumed = await LifeService.instance.tryConsumeLevelEntry(_uid);

    if (!consumed) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final lifeState = await LifeService.instance.refreshLives(_uid);

    try {
      final questions = await WeeklyTopicService.instance.loadRandomRound(
        uid: _uid,
        weekId: widget.weekId,
        categoryId: widget.categoryId,
      );

      if (!mounted) return;

      setState(() {
        _questions = questions;
        _lifeUnits = (lifeState['lifeUnits'] ?? 0) as int;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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
          ? AppColors.success.withValues(alpha: 0.18)
          : AppColors.danger.withValues(alpha: 0.18);
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
      final lifeLost = await LifeService.instance.tryConsumeWrongAnswer(_uid);
      final state = await LifeService.instance.refreshLives(_uid);

      if (!mounted) return;

      final newLifeUnits = (state['lifeUnits'] ?? 0) as int;

      setState(() {
        _lifeUnits = newLifeUnits;
        if (lifeLost && newLifeUnits <= 0) _endedByNoLives = true;
      });
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
    setState(() => _submitting = true);

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
    } catch (e) {
      if (!mounted) return;

      setState(() => _submitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Color _buttonColor(int index, int correctIndex) {
    if (_selectedIndex == null) return Theme.of(context).colorScheme.primary;
    if (index == correctIndex) return AppColors.success;
    if (index == _selectedIndex) {
      return _lastCorrect == true ? AppColors.success : AppColors.danger;
    }
    return Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  Color _buttonTextColor(int index, int correctIndex) {
    if (_selectedIndex != null &&
        index != correctIndex &&
        index != _selectedIndex) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.categoryName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_errorMessage!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final q = _questions[_index];
    final options = _options(q);
    final correctIndex = _answerIndex(q);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        automaticallyImplyLeading: !_submitting,
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: _flashColor,
        child: AbsorbPointer(
          absorbing: _submitting,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      color: AppColors.danger,
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonColor(i, correctIndex),
                          foregroundColor: _buttonTextColor(i, correctIndex),
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
                const Spacer(),
                Text(
                  l10n.weeklyTopicRoundCorrectCount(_correct),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
