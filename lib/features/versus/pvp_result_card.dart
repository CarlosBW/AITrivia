import 'package:flutter/material.dart';
import '../../widgets/player_avatar_widget.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/league_names.dart';
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

  /// Who gets the crown: +1 me, -1 the opponent, 0 nobody. Taken from the
  /// result, not the scores: a live duel is also won when the opponent
  /// disconnects, and an async one by forfeit, whatever the points say.
  int get _leader => switch (state) {
        PvpResultState.victory => 1,
        PvpResultState.defeat => -1,
        PvpResultState.draw || PvpResultState.waiting => 0,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resultColor = _colorFor(context);
    final hasRatingChange =
        oldRating != null && newRating != null && ratingDelta != null;
    final scoreDifferenceText = _scoreDifferenceText(l10n);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ResultHero(
              state: state,
              icon: _icon,
              accent: resultColor,
              title: title,
              subtitle: subtitle,
              badge: scoreDifferenceText,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(context.radii.lg),
                border: context.surfaces.borderOr(null),
                boxShadow: context.surfaces.shadowsOr([
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .shadow
                        .withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]),
              ),
              child: Column(
                children: [
                  Text(
                    l10n.pvpResultFinalResult.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _PlayerScore(
                          name: myName,
                          avatarId: myAvatarId,
                          frameId: myFrameId,
                          bestLeagueId: myBestLeagueId,
                          score: myScore,
                          isMe: true,
                          crowned: _leader > 0,
                          dimmed: _leader < 0,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 34),
                        child: _VsBadge(label: l10n.pvpResultVs),
                      ),
                      Expanded(
                        child: _PlayerScore(
                          name: opponentName,
                          avatarId: opponentAvatarId,
                          frameId: opponentFrameId,
                          bestLeagueId: opponentBestLeagueId,
                          score: opponentScore,
                          crowned: _leader < 0,
                          dimmed: _leader > 0,
                        ),
                      ),
                    ],
                  ),
                  if (opponentScore != null &&
                      state != PvpResultState.waiting) ...[
                    const SizedBox(height: 16),
                    _ScoreBar(
                      key: const ValueKey('pvp-score-bar'),
                      myScore: myScore,
                      opponentScore: opponentScore!,
                    ),
                  ],
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
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: onPrimaryPressed,
                child: Text(primaryButtonText),
              ),
            ),
            if (secondaryButtonText != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onSecondaryPressed,
                  icon: const Icon(Icons.replay),
                  label: Text(secondaryButtonText!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The banner on top: the theme's hero gradient, the result's medal popping
/// in, and a few sparkles when it's a win.
class _ResultHero extends StatelessWidget {
  final PvpResultState state;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String badge;

  const _ResultHero({
    required this.state,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onHero = colors.onAccent;
    final victory = state == PvpResultState.victory;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.heroGradientStart, colors.heroGradientEnd],
        ),
        borderRadius: BorderRadius.circular(context.radii.lg),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: colors.heroGradientEnd.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ]),
      ),
      child: Stack(
        children: [
          // Soft rings behind the medal give the flat gradient some depth.
          Positioned(
            top: -60,
            right: -40,
            child: _Ring(size: 180, color: onHero.withValues(alpha: 0.10)),
          ),
          Positioned(
            bottom: -70,
            left: -50,
            child: _Ring(size: 160, color: onHero.withValues(alpha: 0.08)),
          ),
          if (victory) ...[
            _Sparkle(left: 28, top: 26, size: 18, color: onHero),
            _Sparkle(right: 34, top: 44, size: 14, color: onHero),
            _Sparkle(left: 52, top: 112, size: 12, color: onHero),
            _Sparkle(right: 56, top: 120, size: 20, color: onHero),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.onAccent.withValues(alpha: 0.18),
                      border: Border.all(
                        color: onHero.withValues(alpha: 0.55),
                        width: 2,
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: victory
                            ? colors.reward
                            : Theme.of(context).colorScheme.surface,
                        boxShadow: [
                          BoxShadow(
                            color: (victory ? colors.reward : accent)
                                .withValues(alpha: 0.45),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        size: 40,
                        color: victory ? colors.onReward : accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: context.heading(32, color: onHero),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: onHero.withValues(alpha: 0.88),
                  ),
                ),
                if (badge.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: onHero.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(context.radii.pill),
                      border: Border.all(
                        color: onHero.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: onHero,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double size;
  final Color color;

  const _Ring({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 18),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  final double? left;
  final double? right;
  final double top;
  final double size;
  final Color color;

  const _Sparkle({
    this.left,
    this.right,
    required this.top,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      child: Icon(
        Icons.auto_awesome,
        size: size,
        color: color.withValues(alpha: 0.7),
      ),
    );
  }
}

class _VsBadge extends StatelessWidget {
  final String label;

  const _VsBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary,
        border: context.surfaces.borderOr(null),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: context.appColors.onAccent,
        ),
      ),
    );
  }
}

/// One side of the scoreboard. The winner gets a crown and the score in
/// the reward colour; the loser is drawn quieter.
class _PlayerScore extends StatelessWidget {
  final String name;
  final int? score;
  final bool isMe;
  final bool crowned;
  final bool dimmed;
  final String? avatarId;
  final String? frameId;
  final String? bestLeagueId;

  const _PlayerScore({
    required this.name,
    required this.score,
    this.isMe = false,
    this.crowned = false,
    this.dimmed = false,
    this.avatarId,
    this.frameId,
    this.bestLeagueId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final nameColor = isMe ? scheme.primary : scheme.onSurface;
    final scoreColor = crowned
        ? colors.reward
        : dimmed
            ? scheme.onSurfaceVariant
            : scheme.onSurface;

    return Column(
      children: [
        SizedBox(
          height: 20,
          child: crowned
              ? Icon(Icons.workspace_premium, size: 20, color: colors.reward)
              : null,
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: crowned ? colors.reward : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: avatarId != null
              ? PlayerAvatarWidget(
                  avatarId: avatarId,
                  frameId: frameId,
                  bestLeagueId: bestLeagueId,
                  radius: 26,
                )
              : CircleAvatar(
                  radius: 26,
                  backgroundColor: (isMe ? scheme.primary : scheme.secondary)
                      .withValues(alpha: 0.16),
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: context.heading(
                      22,
                      color: isMe ? scheme.primary : scheme.secondary,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: nameColor,
          ),
        ),
        const SizedBox(height: 2),
        score == null
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Icon(
                  Icons.hourglass_bottom,
                  size: 30,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: score),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  '$value',
                  style: context.heading(44, color: scoreColor),
                ),
              ),
      ],
    );
  }
}

/// A tug-of-war bar: how the points split between the two players.
class _ScoreBar extends StatelessWidget {
  final int myScore;
  final int opponentScore;

  const _ScoreBar({
    super.key,
    required this.myScore,
    required this.opponentScore,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = myScore + opponentScore;
    final myShare = total == 0 ? 0.5 : myScore / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(context.radii.pill),
      child: SizedBox(
        height: 10,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: myShare),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, share, _) => Row(
            children: [
              Expanded(
                flex: (share * 1000).round().clamp(1, 999),
                child: Container(color: scheme.primary),
              ),
              const SizedBox(width: 3),
              Expanded(
                flex: ((1 - share) * 1000).round().clamp(1, 999),
                child: Container(color: scheme.outlineVariant),
              ),
            ],
          ),
        ),
      ),
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
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
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
        boxShadow: context.surfaces.shadowsOr(null),
        border: context.surfaces.borderOr(Border.all(
          color: color.withValues(alpha: 0.35),
        )),
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
                  ? '${l10n.leagueName(oldLeagueName!)} → '
                      '${l10n.leagueName(newLeagueName!)}'
                  : l10n.leagueName(newLeagueName ?? oldLeagueName ?? ''),
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
        borderRadius: BorderRadius.circular(context.radii.sm),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
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
