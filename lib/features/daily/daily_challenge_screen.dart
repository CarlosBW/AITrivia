import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/daily_challenge_service.dart';
import '../../theme/app_theme.dart';
import 'daily_challenge_result_screen.dart';

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

  int _timeLeft = 120;
  Timer? _timer;
  bool _loading = true;
  bool _finishing = false;
  bool _savingResults = false;

  int? _selectedIndex;
  bool? _lastCorrect;
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
    final targetDifficulty = _getTargetDifficulty();

    final filtered = _questions.where((q) {
      final rawDifficulty = q['sourceDifficulty'] ?? 1;
      final difficulty = rawDifficulty is num
          ? rawDifficulty.toInt()
          : int.tryParse(rawDifficulty.toString()) ?? 1;

      return difficulty == targetDifficulty;
    }).toList();

    final pool = filtered.isNotEmpty ? filtered : _questions;
    return pool[_currentIndex % pool.length];
  }

  void _checkCoinMilestone() {
    final milestone = _correct ~/ 10;

    if (milestone > _lastCoinMilestone) {
      _lastCoinMilestone = milestone;

      setState(() {
        _coinPopupText = '+5 Coins 🎉';
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
    final session = await _service.createTodaySession(uid: widget.uid);

    if (!mounted) return;

    setState(() {
      _questions = session.questions;
      _timeLeft = session.remainingSeconds;
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
        setState(() => _timeLeft--);
      }
    });
  }

  Future<void> _answer(int index, int correctIndex) async {
    if (_finishing || _savingResults || _selectedIndex != null) return;

    final isCorrect = index == correctIndex;

    if (isCorrect) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    setState(() {
      _flashColor = isCorrect
          ? Colors.green.withOpacity(0.18)
          : Colors.red.withOpacity(0.18);
      _selectedIndex = index;
      _lastCorrect = isCorrect;
      _totalAnswered++;

      if (isCorrect) {
        _correct++;
      }
    });

    if (isCorrect) {
      _checkCoinMilestone();
    }

    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted || _finishing) return;

    setState(() {
      _currentIndex++;
      _selectedIndex = null;
      _lastCorrect = null;
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
          builder: (_) => DailyChallengeResultScreen(result: result),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _savingResults = false;
        _finishing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving results: $e'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

  Color _buttonColor(int index, int correctIndex) {
    if (_selectedIndex == null) return Colors.blue;

    if (index == correctIndex) return Colors.green;

    if (index == _selectedIndex) {
      return _lastCorrect == true ? Colors.green : Colors.red;
    }

    return Colors.grey;
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _difficultyLabel() {
    final difficulty = _getTargetDifficulty();

    if (difficulty == 3) return 'Hard';
    if (difficulty == 2) return 'Medium';
    return 'Easy';
  }

  Widget _savingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events,
                size: 54,
              ),
              SizedBox(height: 16),
              Text(
                'Daily completed!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Saving your results...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 20),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No questions available')),
      );
    }

    final q = _currentQuestion();
    final options = _options(q);
    final correctIndex = _answerIndex(q);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Challenge'),
        automaticallyImplyLeading: !_savingResults,
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        color: _flashColor,
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _savingResults,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _HeaderCard(
                            icon: Icons.timer,
                            label: 'Time',
                            value: _formatTime(_timeLeft),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HeaderCard(
                            icon: Icons.star,
                            label: 'Score',
                            value: '$_correct',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HeaderCard(
                            icon: Icons.monetization_on,
                            label: 'Coins',
                            value: '+$_liveCoinsEarned',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Difficulty: ${_difficultyLabel()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
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
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                            ),
                            onPressed: _selectedIndex != null || _savingResults
                                ? null
                                : () => _answer(i, correctIndex),
                            child: Text(
                              options[i],
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    }),
                    const Spacer(),
                    Text(
                      'Answered: $_totalAnswered',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
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
                      color: Colors.amber.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      _coinPopupText!,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            if (_savingResults) _savingOverlay(),
          ],
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
        color: Colors.black12,
        borderRadius: BorderRadius.circular(AppRadius.sm),
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