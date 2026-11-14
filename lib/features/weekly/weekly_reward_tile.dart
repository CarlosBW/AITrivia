import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Where a Weekly Topic reward stands for the player.
enum WeeklyRewardState { locked, ready, claimed }

/// One reward of the Weekly Topic: its emblem, what it takes, how close
/// the player is, and the button that claims it.
///
/// The two rewards used to be lines of text and two always-present buttons
/// on a flat tinted block — nothing said "prize", nor how far away it was.
class WeeklyRewardTile extends StatelessWidget {
  const WeeklyRewardTile({
    super.key,
    required this.emblem,
    required this.title,
    required this.progressLabel,
    required this.progress,
    required this.state,
    required this.claimLabel,
    required this.claimedLabel,
    this.onClaim,
  });

  /// The prize itself: a coin, the avatar's emoji.
  final Widget emblem;
  final String title;

  /// "12 / 25 right answers".
  final String progressLabel;

  /// 0 to 1 towards this reward.
  final double progress;
  final WeeklyRewardState state;
  final String claimLabel;
  final String claimedLabel;

  /// Null while it can't be claimed (locked, claimed, or a claim running).
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final claimed = state == WeeklyRewardState.claimed;
    final ready = state == WeeklyRewardState.ready;

    final accent = claimed ? colors.success : colors.reward;
    // Mixed onto the surface rather than left translucent, so a theme's
    // solid shadow doesn't show through.
    final fill = Color.alphaBlend(
      accent.withValues(alpha: ready ? 0.22 : 0.12),
      scheme.surface,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(
          color: accent.withValues(alpha: ready ? 0.9 : 0.45),
          width: ready ? 2 : 1,
        ),
        boxShadow: context.surfaces.shadowsOr(
          ready
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2),
                ),
                child: emblem,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                claimed
                    ? Icons.check_circle_rounded
                    : ready
                        ? Icons.redeem_rounded
                        : Icons.lock_outline_rounded,
                color: claimed
                    ? colors.success
                    : ready
                        ? context.readableOnOwnTint(colors.reward, wash: 0)
                        : scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(context.radii.pill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: accent.withValues(alpha: 0.20),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            progressLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!claimed && state != WeeklyRewardState.locked) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onClaim,
                icon: const Icon(Icons.redeem_rounded, size: 18),
                label: Text(claimLabel),
              ),
            ),
          ],
          if (claimed) ...[
            const SizedBox(height: 8),
            Text(
              claimedLabel,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which state a reward is in, from the player's right answers this week.
WeeklyRewardState weeklyRewardState({
  required int correctAnswers,
  required int threshold,
  required bool claimed,
}) {
  if (claimed) return WeeklyRewardState.claimed;
  return correctAnswers >= threshold
      ? WeeklyRewardState.ready
      : WeeklyRewardState.locked;
}
