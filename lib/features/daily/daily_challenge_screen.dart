import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/daily_challenge_service.dart';
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

  int? _selectedIndex;
  bool? _lastCorrect;

  int get _liveCoinsEarned {
    return _service.calculateCoinsEarned(_correct);
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
        if (!mounted) return;
        setState(() => _timeLeft--);
      }
    });
  }

  Future<void> _answer(int index, int correctIndex) async {
    if (_finishing || _selectedIndex != null) return;

    final isCorrect = index == correctIndex;

    if (isCorrect) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    setState(() {
      _selectedIndex = index;
      _lastCorrect = isCorrect;
      _totalAnswered++;
      if (isCorrect) _correct++;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    setState(() {
      _currentIndex++;
      _selectedIndex = null;
      _lastCorrect = null;
    });
  }

  Future<void> _finish() async {
    if (_finishing) return;

    _finishing = true;
    _timer?.cancel();

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

    final q = _questions[_currentIndex % _questions.length];
    final options = _options(q);
    final correctIndex = _answerIndex(q);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Challenge'),
      ),
      body: Padding(
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

            const SizedBox(height: 24),

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
                    onPressed: _selectedIndex != null
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
        borderRadius: BorderRadius.circular(14),
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