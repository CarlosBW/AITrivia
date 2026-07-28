import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/daily_challenge_service.dart';
import '../../l10n/generated/app_localizations.dart';

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
            ],

            const SizedBox(height: 40),

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