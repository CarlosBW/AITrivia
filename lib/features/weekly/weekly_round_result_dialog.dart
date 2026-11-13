import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/result_hero_banner.dart';

/// The result of a Weekly Topic round, on the same hero banner a finished
/// level and a finished duel open on. It used to be a plain system alert
/// with one line of text.
class WeeklyRoundResultDialog extends StatelessWidget {
  const WeeklyRoundResultDialog({
    super.key,
    required this.correct,
    required this.total,
    required this.onContinue,
    this.onReview,
  });

  final int correct;
  final int total;
  final VoidCallback onContinue;

  /// Opens the round's questions; null when there is nothing to review.
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onHero = context.appColors.onAccent;
    final pct = total == 0 ? 0 : (correct * 100 / total).round();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResultHeroBanner(
                // Worth celebrating from half the round up.
                sparkles: total > 0 && correct * 2 >= total,
                child: Column(
                  children: [
                    Icon(Icons.emoji_events_rounded, size: 44, color: onHero),
                    const SizedBox(height: 8),
                    Text(
                      l10n.weeklyTopicRoundResultTitle,
                      textAlign: TextAlign.center,
                      style: context.heading(26, color: onHero),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        TweenAnimationBuilder<int>(
                          tween: IntTween(begin: 0, end: correct),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => Text(
                            '$value',
                            style: context.heading(52, color: onHero),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '/ $total',
                          style: context.heading(
                            24,
                            color: onHero.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    HeroBadge(
                      label: '$pct%',
                      icon: Icons.track_changes_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(context.radii.md),
                  border: context.surfaces.borderOr(null),
                  boxShadow: context.surfaces.shadowsOr(null),
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.weeklyTopicRoundResultBody(correct, total),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onContinue,
                        child: Text(l10n.weeklyTopicRoundResultButton),
                      ),
                    ),
                    if (onReview != null) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: onReview,
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: Text(l10n.questionReviewButton),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
