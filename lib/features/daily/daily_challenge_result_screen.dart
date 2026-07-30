import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/daily_challenge_service.dart';
import '../../l10n/generated/app_localizations.dart';
import 'daily_leaderboard_screen.dart';

class DailyChallengeResultScreen extends StatelessWidget {
  final DailyChallengeSaveResult result;

  const DailyChallengeResultScreen({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dailyResultTitle),
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

            Text(
              l10n.dailyResultComplete,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 32),

            _ResultRow(
              label: l10n.dailyResultCorrectAnswers,
              value: '${result.correct}',
            ),

            _ResultRow(
              label: l10n.dailyResultTotalAnswered,
              value: '${result.totalAnswered}',
            ),

            _ResultRow(
              label: l10n.dailyResultCoinsEarned,
              value: '+${result.totalCoinsEarned}',
            ),

            _ResultRow(
              label: l10n.dailyResultStreakLabel,
              value: l10n.dailyResultDaysValue(result.streak),
            ),

            if (result.streakBonusCoins > 0)
              _ResultRow(
                label: l10n.dailyResultStreakBonus,
                value: '+${result.streakBonusCoins}',
              ),

            if (result.alreadyPlayed) ...[
              const SizedBox(height: 16),
              Text(
                l10n.dailyResultAlreadyPlayed,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const _ResetCountdown(),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DailyLeaderboardScreen(),
                    ),
                  );
                },
                child: Text(l10n.dailyResultViewLeaderboard),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                child: Text(l10n.dailyResultBackHome),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetCountdown extends StatefulWidget {
  const _ResetCountdown();

  @override
  State<_ResetCountdown> createState() => _ResetCountdownState();
}

class _ResetCountdownState extends State<_ResetCountdown> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timeLeft = DailyChallengeService.instance.timeUntilReset();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _timeLeft = DailyChallengeService.instance.timeUntilReset();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    return '${hours}h ${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Text(
      l10n.dailyResultNextChallengeIn(_formatDuration(_timeLeft)),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
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