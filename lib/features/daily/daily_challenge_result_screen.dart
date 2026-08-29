import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/daily_challenge_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'daily_leaderboard_screen.dart';
import '../../widgets/profile_avatar_button.dart';

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
        actions: const [ProfileAvatarButton()],
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
              style: context.heading(26),
            ),

            const SizedBox(height: 32),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(context.radii.md),
                border: context.surfaces.borderOr(null),
                boxShadow: context.surfaces.shadowsOr(null),
              ),
              child: Column(
                children: [
                  _ResultRow(
                    icon: Icons.check_circle_outline,
                    accent: context.appColors.success,
                    background: context.appColors.successBg,
                    label: l10n.dailyResultCorrectAnswers,
                    value: '${result.correct}',
                  ),
                  _ResultRow(
                    icon: Icons.quiz_outlined,
                    accent: Theme.of(context).colorScheme.primary,
                    background:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    label: l10n.dailyResultTotalAnswered,
                    value: '${result.totalAnswered}',
                  ),
                  _ResultRow(
                    icon: Icons.monetization_on_outlined,
                    accent: context.appColors.reward,
                    background: context.appColors.rewardBg,
                    label: l10n.dailyResultCoinsEarned,
                    value: '+${result.totalCoinsEarned}',
                  ),
                  _ResultRow(
                    icon: Icons.local_fire_department_outlined,
                    accent: context.appColors.reward,
                    background: context.appColors.rewardBg,
                    label: l10n.dailyResultStreakLabel,
                    value: l10n.dailyResultDaysValue(result.streak),
                  ),
                  if (result.streakBonusCoins > 0)
                    _ResultRow(
                      icon: Icons.bolt_outlined,
                      accent: context.appColors.reward,
                      background: context.appColors.rewardBg,
                      label: l10n.dailyResultStreakBonus,
                      value: '+${result.streakBonusCoins}',
                    ),
                ],
              ),
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
  final IconData icon;
  final Color accent;
  final Color background;
  final String label;
  final String value;

  const _ResultRow({
    required this.icon,
    required this.accent,
    required this.background,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16),
            ),
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