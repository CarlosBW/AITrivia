import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/tier_badge.dart';

/// The pieces the PvP season screen is drawn with, kept apart from the
/// screen so they can be built and tested without Firestore.

/// A tab bar drawn as a row of pills, the selected one filled.
///
/// The season screen stacks three levels of tabs; as plain underlined bars
/// they read as three identical rules one under another. The top level
/// stays the app bar's own, and the ones inside the page use this.
class SeasonPillTabBar extends StatelessWidget {
  const SeasonPillTabBar({
    super.key,
    required this.tabs,
    this.controller,
    this.scrollable = false,
  });

  final List<Widget> tabs;
  final TabController? controller;

  /// For more tabs than fit: they start at the page's edge and scroll.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = BorderRadius.circular(context.radii.pill);

    final bar = TabBar(
      controller: controller,
      isScrollable: scrollable,
      tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
      padding: EdgeInsets.zero,
      labelPadding: EdgeInsets.symmetric(horizontal: scrollable ? 14 : 8),
      indicator: BoxDecoration(color: scheme.primary, borderRadius: pill),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      splashBorderRadius: pill,
      labelColor: scheme.onPrimary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      tabs: tabs,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: scrollable
          ? SizedBox(height: 38, child: bar)
          : Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: pill,
              ),
              child: bar,
            ),
    );
  }
}

/// A tab for [SeasonPillTabBar]: an icon and a word on one line.
class SeasonPillTab extends StatelessWidget {
  const SeasonPillTab({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// A surface washed with a league's colour, deeper at the top-left.
///
/// The colour is blended into the theme's surface rather than used as the
/// background: league colours run from pale silver to deep violet, and
/// text set straight on them would be unreadable on half of them.
BoxDecoration leagueWash(
  BuildContext context,
  Color color, {
  double strength = 0.30,
  double? radius,
}) {
  final surface = Theme.of(context).colorScheme.surface;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius ?? context.radii.lg),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(color.withValues(alpha: strength), surface),
        Color.alphaBlend(color.withValues(alpha: strength * 0.28), surface),
      ],
    ),
    border: context.surfaces.borderOr(
      Border.all(color: color.withValues(alpha: 0.45)),
    ),
    boxShadow: context.surfaces.shadowsOr([
      BoxShadow(
        color: color.withValues(alpha: 0.22),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ]),
  );
}

/// The player's standing this season: league, rating, how far the next
/// league is, with the trophy beside it.
class SeasonHeroCard extends StatelessWidget {
  const SeasonHeroCard({
    super.key,
    required this.seasonLabel,
    required this.leagueEmoji,
    required this.leagueTitle,
    required this.leagueColor,
    required this.rating,
    required this.progress,
    required this.progressLabel,
    this.deltaText,
    this.deltaPositive = true,
  });

  /// "Temporada: noviembre 2026".
  final String seasonLabel;
  final String leagueEmoji;
  final String leagueTitle;
  final Color leagueColor;
  final int rating;

  /// The last ranked match's change, already signed ("+18"); none if null.
  final String? deltaText;
  final bool deltaPositive;

  /// 0 to 1 through the current league.
  final double progress;

  /// What the bar is counting towards.
  final String progressLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final ink = context.readableOnOwnTint(leagueColor, wash: 0.3);
    final deltaColor = deltaPositive ? colors.success : colors.danger;
    // Smaller on a narrow phone, where the numbers need the room more.
    final trophy = MediaQuery.sizeOf(context).width < 350 ? 68.0 : 100.0;

    return Container(
      decoration: leagueWash(context, leagueColor),
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seasonLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                // Shrinks rather than overflows: a long league name at a
                // large text size is wider than what the trophy leaves.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: TierBadge(
                    emoji: leagueEmoji,
                    name: leagueTitle,
                    colorValue: leagueColor.toARGB32(),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$rating',
                            style: context.heading(38),
                          ),
                          TextSpan(
                            text: ' MMR',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (deltaText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: deltaColor.withValues(alpha: 0.16),
                          borderRadius:
                              BorderRadius.circular(context.radii.pill),
                        ),
                        child: Text(
                          deltaText!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: readableInk(deltaColor, scheme.surface),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(context.radii.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    color: ink,
                    backgroundColor: scheme.surface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Image.asset(
            'assets/illustrations/trophy.png',
            width: trophy,
            height: trophy,
            cacheWidth:
                (trophy * MediaQuery.devicePixelRatioOf(context)).round(),
            filterQuality: FilterQuality.medium,
          ),
        ],
      ),
    );
  }
}

/// One fact about the season in a small tile: when it ends, what it pays.
class SeasonFactTile extends StatelessWidget {
  const SeasonFactTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.illustration,
    this.accent,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// An asset under `assets/illustrations/`, instead of [icon].
  final String? illustration;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: context.surfaces.borderOr(
          Border.all(color: scheme.outlineVariant),
        ),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Row(
        children: [
          if (illustration != null)
            Image.asset(
              illustration!,
              width: 38,
              height: 38,
              cacheWidth:
                  (38 * MediaQuery.devicePixelRatioOf(context)).round(),
              filterQuality: FilterQuality.medium,
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: context.readableOnOwnTint(color, wash: 0.14),
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.heading(16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled list of steps, each with its own icon.
class SeasonStepsCard extends StatelessWidget {
  const SeasonStepsCard({
    super.key,
    required this.title,
    required this.steps,
    this.footnote,
  });

  final String title;

  /// Each step's icon and sentence. A leading bullet in the sentence is
  /// dropped: the icon stands in for it.
  final List<(IconData, String)> steps;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: context.surfaces.borderOr(
          Border.all(color: scheme.outlineVariant),
        ),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.heading(18)),
          const SizedBox(height: 12),
          for (final (icon, text) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color:
                          context.readableOnOwnTint(scheme.primary, wash: 0.12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        text.replaceFirst(RegExp(r'^\s*•\s*'), ''),
                        style: const TextStyle(height: 1.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (footnote != null) ...[
            const Divider(height: 16),
            Text(
              footnote!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The colours of the first three places.
const List<Color> _podium = [
  Color(0xFFFFC107),
  Color(0xFFB0BEC5),
  Color(0xFFCD7F32),
];

/// One player on a ranking: place, avatar, name, league line, record and
/// rating. The first three places wear a medal.
class SeasonRankRow extends StatelessWidget {
  const SeasonRankRow({
    super.key,
    required this.position,
    required this.avatar,
    required this.name,
    required this.leagueLine,
    required this.recordLine,
    required this.rating,
    required this.leagueColor,
    this.isMe = false,
    this.trailing,
    this.onTap,
  });

  /// 1 for the leader.
  final int position;

  /// The player's avatar, as an emoji.
  final String avatar;
  final String name;
  final String leagueLine;
  final String recordLine;
  final int rating;
  final Color leagueColor;
  final bool isMe;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(context.radii.md);
    final onPodium = position <= _podium.length;

    final Widget place;
    if (onPodium) {
      final medal = _podium[position - 1];
      place = Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: medal,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: medal.withValues(alpha: 0.5), blurRadius: 8),
          ],
        ),
        child: Text(
          '$position',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: readableInk(Colors.black, medal),
          ),
        ),
      );
    } else {
      place = SizedBox(
        width: 30,
        child: Text(
          '$position',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Ink(
          decoration: isMe
              ? leagueWash(
                  context,
                  leagueColor,
                  strength: 0.24,
                  radius: context.radii.md,
                ).copyWith(
                  border: Border.all(color: leagueColor, width: 2),
                )
              : BoxDecoration(
                  color: scheme.surface,
                  borderRadius: radius,
                  border: context.surfaces.borderOr(
                    Border.all(color: scheme.outlineVariant),
                  ),
                  boxShadow: context.surfaces.shadowsOr(null),
                ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              place,
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    leagueColor.withValues(alpha: 0.18),
                    scheme.surface,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: leagueColor.withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
                child: Text(avatar, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      leagueLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      recordLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$rating', style: context.heading(17)),
                  Text(
                    'MMR',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// One league on the rewards ladder: what reaching it pays at season's
/// end. The player's own league is washed in its colour and tagged.
class SeasonLeagueRewardRow extends StatelessWidget {
  const SeasonLeagueRewardRow({
    super.key,
    required this.emoji,
    required this.title,
    required this.range,
    required this.coinsText,
    required this.leagueColor,
    this.currentLabel,
  });

  final String emoji;
  final String title;

  /// The league's rating band.
  final String range;
  final String coinsText;
  final Color leagueColor;

  /// Said under the title when this is the player's league; null for the
  /// others.
  final String? currentLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final isCurrent = currentLabel != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: isCurrent
          ? leagueWash(
              context,
              leagueColor,
              strength: 0.26,
              radius: context.radii.md,
            ).copyWith(border: Border.all(color: leagueColor, width: 2))
          : BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(context.radii.md),
              border: context.surfaces.borderOr(
                Border.all(color: scheme.outlineVariant),
              ),
              boxShadow: context.surfaces.shadowsOr(null),
            ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                leagueColor.withValues(alpha: 0.2),
                scheme.surface,
              ),
              shape: BoxShape.circle,
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  range,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (isCurrent)
                  Text(
                    currentLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.readableOnOwnTint(leagueColor, wash: 0.26),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.rewardBg,
              borderRadius: BorderRadius.circular(context.radii.pill),
            ),
            child: Text(
              coinsText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: readableInk(colors.reward, colors.rewardBg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the season is on course to pay, with the coins beside it.
class SeasonRewardSummaryCard extends StatelessWidget {
  const SeasonRewardSummaryCard({
    super.key,
    required this.label,
    required this.leagueTitle,
    required this.endsLine,
    required this.coins,
    required this.leagueColor,
  });

  final String label;
  final String leagueTitle;
  final String endsLine;
  final int coins;
  final Color leagueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;

    return Container(
      decoration: leagueWash(context, leagueColor),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Row(
        children: [
          Image.asset(
            'assets/illustrations/coins.png',
            width: 68,
            height: 68,
            cacheWidth: (68 * MediaQuery.devicePixelRatioOf(context)).round(),
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(leagueTitle, style: context.heading(18)),
                const SizedBox(height: 2),
                Text(endsLine, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+$coins',
            style: context.heading(
              28,
              color: readableInk(colors.reward, scheme.surface),
            ),
          ),
        ],
      ),
    );
  }
}
