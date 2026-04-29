import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/daily_challenge_service.dart';

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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final session = await _service.createTodaySession(uid: widget.uid);

    setState(() {
      _questions = session.questions;
      _timeLeft = session.durationSeconds;
      _loading = false;
    });

    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft <= 0) {
        _finish();
      } else {
        setState(() => _timeLeft--);
      }
    });
  }

  void _answer(bool isCorrect) {
    if (_timeLeft <= 0) return;

    setState(() {
      _totalAnswered++;
      if (isCorrect) _correct++;
      _currentIndex++;
    });
  }

  Future<void> _finish() async {
    _timer?.cancel();

    final result = await _service.saveResult(
      uid: widget.uid,
      correct: _correct,
      totalAnswered: _totalAnswered,
    );

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      '/daily-result',
      arguments: result,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

    final question = _questions[_currentIndex % _questions.length];

    final answers = List<String>.from(question['answers'] ?? []);
    final correctIndex = question['correctIndex'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Challenge'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),

          Text(
            'Time: $_timeLeft',
            style: const TextStyle(fontSize: 24),
          ),

          const SizedBox(height: 16),

          Text(
            question['question'] ?? '',
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          ...List.generate(answers.length, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 16,
              ),
              child: ElevatedButton(
                onPressed: () => _answer(index == correctIndex),
                child: Text(answers[index]),
              ),
            );
          }),

          const Spacer(),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Correct: $_correct | Answered: $_totalAnswered',
            ),
          ),
        ],
      ),
    );
  }
}