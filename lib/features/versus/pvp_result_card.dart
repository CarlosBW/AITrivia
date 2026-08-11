import 'package:flutter/material.dart';
import '../../widgets/player_avatar_widget.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

enum PvpResultState {
  victory,
  defeat,
  draw,
  waiting,
}

class PvpResultCard extends StatelessWidget {
  final PvpResultState state;
  final String title;
  final String subtitle;

  final String myName;
  final String opponentName;
  final String? myAvatarId;
  final String? opponentAvatarId;
  final String? myFrameId;
  final String? myBestLeagueId;
  final String? opponentFrameId;
  final String? opponentBestLeagueId;
  final int myScore;
  final int? opponentScore;

  final int? coinsEarned;
  final int? xpEarned;

  final int? oldRating;
  final int? newRating;
  final int? ratingDelta;
  final int? winStreak;
  final String? oldLeagueName;
  final String? newLeagueName;

  final String primaryButtonText;
  final VoidCallback onPrimaryPressed;

  final String? secondaryButtonText;
  final VoidCallback? onSecondaryPressed;

  const PvpResultCard({
    super.key,
    required this.state,
    required this.title,
    required this.subtitle,
    required this.myName,
    required this.opponentName,
    required this.myScore,
    this.opponentScore,
    this.coinsEarned,
    this.xpEarned,
    this.oldRating,
    this.newRating,
    this.ratingDelta,
    this.winStreak,
    this.oldLeagueName,
    this.newLeagueName,
    required this.primaryButtonText,
    required this.onPrimaryPressed,
    this.secondaryButtonText,
    this.onSecondaryPressed,
    this.myAvatarId,
    this.opponentAvatarId,
    this.myFrameId,
    this.myBestLeagueId,
    this.opponentFrameId,
    this.opponentBestLeagueId,
  });

  IconData get _icon {
    switch (state) {
      case PvpResultState.victory:
        return Icons.emoji_events;
      case PvpResultState.defeat:
        return Icons.sentiment_dissatisfied;
      case PvpResultState.draw:
        return Icons.handshake;
      case PvpResultState.waiting:
        return Icons.hourglass_bottom;
    }
  }

  Color _colorFor(BuildContext context) {
    switch (state) {
      case PvpResultState.victory:
        return context.appColors.reward;
      case PvpResultState.defeat:
        return context.appColors.danger;
      case PvpResultState.draw:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case PvpResultState.waiting:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _scoreDifferenceText(AppLocalizations l10n) {
    if (opponentScore == null) return '';

    final diff = myScore - opponentScore!;

    if (diff == 0) return l10n.pvpResultPerfectDraw;
    if (diff > 0) return l10n.pvpResultWonByPoints(diff);
    return l10n.pvpResultLostByPoints(diff.abs());
  }

  int get _accuracy {
    if (myScore <= 0) return 0;

    final total =
        myScore > (opponentScore ?? 0) ? myScore : (opponentScore ?? myScore);

    if (total <= 0) return 0;

    return ((myScore / total) * 100).round().clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultColor = _colorFor(context);
    final hasOpponentScore = opponentScore != null;
    final hasRatingChange =
        oldRating != null && newRating != null && ratingDelta != null;
    final scoreDifferenceText = _scoreDifferenceText(l10n);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: resultColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(
                  color: resultColor.withValues(alpha: 0.55),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: resultColor.withValues(alpha: 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                _icon,
                size: 52,
                color: resultColor,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.heading(30),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (scoreDifferenceText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(context.radii.pill),
                  border: Border.all(
                    color: resultColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  scoreDifferenceText,
                  style: TextStyle(
                    color: resultColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(context.radii.lg),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.pvpResultFinalResult,
                    style: context.heading(19),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ScoreColumn(
                          label: myName,
                          avatarId: myAvatarId,
                          frameId: myFrameId,
                          bestLeagueId: myBestLeagueId,
                          score: myScore,
                          highlight: true,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(context.radii.pill),
                        ),
                        child: Text(
                          l10n.pvpResultVs,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: hasOpponentScore
                            ? _ScoreColumn(
                                label: opponentName,
                                avatarId: opponentAvatarId,
                                frameId: opponentFrameId,
                                bestLeagueId: opponentBestLeagueId,
                                score: opponentScore!,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _MatchSummaryCard(
                    myScore: myScore,
                    opponentScore: opponentScore,
                    accuracy: _accuracy,
                  ),
                  if (coinsEarned != null || xpEarned != null) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (xpEarned != null)
                          Expanded(
                            child: _RewardMiniCard(
                              icon: Icons.auto_awesome_outlined,
                              label: l10n.homeXp,
                              value: '+$xpEarned',
                            ),
                          ),
                        if (xpEarned != null && coinsEarned != null)
                          const SizedBox(width: 12),
                        if (coinsEarned != null)
                          Expanded(
                            child: _RewardMiniCard(
                              icon: Icons.monetization_on_outlined,
                              label: l10n.homeCoins,
                              value: '+$coinsEarned',
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (hasRatingChange) ...[
                    const SizedBox(height: 18),
                    _RatingChangeCard(
                      oldRating: oldRating!,
                      newRating: newRating!,
                      ratingDelta: ratingDelta!,
                      winStreak: winStreak,
                      oldLeagueName: oldLeagueName,
                      newLeagueName: newLeagueName,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onPrimaryPressed,
                child: Text(primaryButtonText),
              ),
            ),
            if (secondaryButtonText != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: onSecondaryPressed,
                  child: Text(secondaryButtonText!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  final String label;
  final int score;
  final bool highlight;
  final String? avatarId;
  final String? frameId;
  final String? bestLeagueId;

  const _ScoreColumn({
    required this.label,
    required this.score,
    this.highlight = false,
    this.avatarId,
    this.frameId,
    this.bestLeagueId,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;

    return Column(
      children: [
        if (avatarId != null) ...[
          PlayerAvatarWidget(
            avatarId: avatarId,
            frameId: frameId,
            bestLeagueId: bestLeagueId,
            radius: 28,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            '$score',
            key: ValueKey(score),
            style: context.heading(38, color: color),
          ),
        ),
      ],
    );
  }
}

class _MatchSummaryCard extends StatelessWidget {
  final int myScore;
  final int? opponentScore;
  final int accuracy;

  const _MatchSummaryCard({
    required this.myScore,
    required this.opponentScore,
    required this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.pvpResultMatchSummary,
                style: context.headingFace,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: l10n.pvpResultYourScore,
                  value: '$myScore',
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: l10n.pvpResultOpponent,
                  value: opponentScore == null ? '—' : '$opponentScore',
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: l10n.pvpResultPerformance,
                  value: '$accuracy%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: context.heading(18),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _RewardMiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RewardMiniCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Column(
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(label),
          const SizedBox(height: 4),
          Text(
            value,
            style: context.heading(17),
          ),
        ],
      ),
    );
  }
}

class _RatingChangeCard extends StatelessWidget {
  final int oldRating;
  final int newRating;
  final int ratingDelta;
  final int? winStreak;
  final String? oldLeagueName;
  final String? newLeagueName;

  const _RatingChangeCard({
    required this.oldRating,
    required this.newRating,
    required this.ratingDelta,
    this.winStreak,
    this.oldLeagueName,
    this.newLeagueName,
  });

  String get _deltaText {
    if (ratingDelta > 0) return '+$ratingDelta';
    return '$ratingDelta';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final positive = ratingDelta > 0;
    final neutral = ratingDelta == 0;

    final color = neutral
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : positive
            ? context.appColors.success
            : context.appColors.danger;

    final hasLeague = (oldLeagueName != null && oldLeagueName!.isNotEmpty) ||
        (newLeagueName != null && newLeagueName!.isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                positive
                    ? Icons.trending_up
                    : neutral
                        ? Icons.remove_circle_outline
                        : Icons.trending_down,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.profileRankedMmr,
                  style: context.heading(16),
                ),
              ),
              Text(
                _deltaText,
                style: context.heading(18, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MmrBox(
                  label: l10n.pvpResultBefore,
                  value: oldRating,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 20),
              ),
              Expanded(
                child: _MmrBox(
                  label: l10n.pvpResultNow,
                  value: newRating,
                  highlight: true,
                ),
              ),
            ],
          ),
          if (hasLeague) ...[
            const SizedBox(height: 10),
            Text(
              oldLeagueName != null &&
                      newLeagueName != null &&
                      oldLeagueName != newLeagueName
                  ? '$oldLeagueName → $newLeagueName'
                  : (newLeagueName ?? oldLeagueName ?? ''),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (winStreak != null && winStreak! > 1) ...[
            const SizedBox(height: 8),
            Text(
              l10n.pvpResultCurrentStreak(winStreak!),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MmrBox extends StatelessWidget {
  final String label;
  final int value;
  final bool highlight;

  const _MmrBox({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: highlight
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: context.heading(highlight ? 18 : 16),
          ),
        ],
      ),
    );
  }
}
