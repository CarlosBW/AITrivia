import 'package:flutter/material.dart';
import '../../services/daily_challenge_service.dart';

class DailyChallengeResultScreen extends StatelessWidget {
  final DailyChallengeSaveResult result;

  const DailyChallengeResultScreen({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Challenge Result'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.emoji_events,
              size: 80,
            ),

            const SizedBox(height: 24),

            const Text(
              'Daily Challenge Complete!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 32),

            _ResultRow(
              label: 'Correct answers',
              value: '${result.correct}',
            ),

            _ResultRow(
              label: 'Total answered',
              value: '${result.totalAnswered}',
            ),

            _ResultRow(
              label: 'Coins earned',
              value: '+${result.totalCoinsEarned}',
            ),

            _ResultRow(
              label: 'Daily streak',
              value: '${result.streak} days',
            ),

            if (result.streakBonusCoins > 0)
              _ResultRow(
                label: 'Streak bonus',
                value: '+${result.streakBonusCoins}',
              ),

            if (result.alreadyPlayed) ...[
              const SizedBox(height: 16),
              const Text(
                'You already played today. Coins were not awarded again.',
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 18),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}