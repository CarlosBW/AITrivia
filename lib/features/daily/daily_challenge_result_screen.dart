import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/daily_challenge_service.dart';
import '../../services/question_report_service.dart';
import '../review/question_review_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'daily_leaderboard_screen.dart';
import '../../widgets/profile_avatar_button.dart';

class DailyChallengeResultScreen extends StatelessWidget {
  final DailyChallengeSaveResult result;

  /// The questions answered in this run, for "Review questions".
  final List<ReviewedQuestion> reviewQuestions;

  const DailyChallengeResultScreen({
    super.key,
    required this.result,
    this.reviewQuestions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        automaticallyImplyLeading: false,
      ),
      // Scrolls rather than overflows: the streak-bonus row and the
      // already-played note only show sometimes, and together with the
      // badge they outgrow a short screen.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const _TrophyBadge(),

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
                      value: result.correct,
                    ),
                    _ResultRow(
                      icon: Icons.quiz_outlined,
                      accent: Theme.of(context).colorScheme.primary,
                      background: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      label: l10n.dailyResultTotalAnswered,
                      value: result.totalAnswered,
                    ),
                    _ResultRow(
                      icon: Icons.monetization_on_outlined,
                      accent: context.appColors.reward,
                      background: context.appColors.rewardBg,
                      label: l10n.dailyResultCoinsEarned,
                      value: result.totalCoinsEarned,
                      format: (coins) => '+$coins',
                    ),
                    _ResultRow(
                      icon: Icons.local_fire_department_outlined,
                      accent: context.appColors.reward,
                      background: context.appColors.rewardBg,
                      label: l10n.dailyResultStreakLabel,
                      value: result.streak,
                      format: l10n.dailyResultDaysValue,
                    ),
                    if (result.streakBonusCoins > 0)
                      _ResultRow(
                        icon: Icons.bolt_outlined,
                        accent: context.appColors.reward,
                        background: context.appColors.rewardBg,
                        label: l10n.dailyResultStreakBonus,
                        value: result.streakBonusCoins,
                        format: (coins) => '+$coins',
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

              if (reviewQuestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuestionReviewScreen(
                          questions: reviewQuestions,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(l10n.questionReviewButton),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The trophy in reward gold, popped in the way the solo result pops its
/// stars — the one loud element on a screen that is otherwise a summary.
class _TrophyBadge extends StatelessWidget {
  const _TrophyBadge();

  @override
  Widget build(BuildContext context) {
    final reward = context.appColors.reward;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: context.appColors.rewardBg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: reward.withValues(alpha: 0.35),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(Icons.emoji_events, size: 68, color: reward),
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
  final int value;

  /// How [value] is written out; the bare number when omitted.
  final String Function(int value)? format;

  const _ResultRow({
    required this.icon,
    required this.accent,
    required this.background,
    required this.label,
    required this.value,
    this.format,
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
          // Counts up like the solo result's rewards, so the totals land
          // rather than just sit there.
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) {
              return Text(
                format?.call(animatedValue) ?? '$animatedValue',
                style: context.heading(20),
              );
            },
          ),
        ],
      ),
    );
  }
}