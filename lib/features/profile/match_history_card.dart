import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One finished duel in the Profile's history: a result medallion, the
/// opponent with the match's tags, and the score — in one row.
class MatchHistoryCard extends StatelessWidget {
  const MatchHistoryCard({
    super.key,
    required this.result,
    required this.resultLabel,
    required this.opponentLine,
    required this.myScore,
    required this.opponentScore,
    required this.modeLabel,
    this.ratingDelta,
    this.playedAt,
    this.onMore,
    this.moreTooltip,
  });

  /// 'victory', 'defeat', 'draw' or anything else for an unknown result.
  final String result;
  final String resultLabel;

  /// "vs Name", already localized.
  final String opponentLine;
  final int myScore;
  final int opponentScore;

  /// Ranked or casual, localized.
  final String modeLabel;

  /// MMR gained or lost, for ranked matches only.
  final int? ratingDelta;
  final DateTime? playedAt;

  /// Report or block the opponent; null hides the menu.
  final VoidCallback? onMore;
  final String? moreTooltip;

  IconData get _icon => switch (result) {
        'victory' => Icons.emoji_events_rounded,
        'defeat' => Icons.close_rounded,
        'draw' => Icons.handshake_rounded,
        _ => Icons.sports_esports_rounded,
      };

  Color _color(BuildContext context) => switch (result) {
        'victory' => context.appColors.success,
        'defeat' => context.appColors.danger,
        _ => Theme.of(context).colorScheme.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(context);
    final delta = ratingDelta;
    final date = playedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ]),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The result's colour down the left edge.
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.14),
                      ),
                      child: Icon(_icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            resultLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.heading(17, color: color),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            opponentLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _Tag(
                                label: modeLabel,
                                color: scheme.onSurfaceVariant,
                              ),
                              if (delta != null)
                                _Tag(
                                  label:
                                      '${delta > 0 ? '+' : ''}$delta MMR',
                                  color: delta > 0
                                      ? context.appColors.success
                                      : delta < 0
                                          ? context.appColors.danger
                                          : scheme.onSurfaceVariant,
                                  strong: true,
                                ),
                              if (date != null)
                                Text(
                                  MaterialLocalizations.of(context)
                                      .formatShortMonthDay(date),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Score(
                      mine: myScore,
                      theirs: opponentScore,
                      color: color,
                    ),
                    if (onMore != null)
                      IconButton(
                        tooltip: moreTooltip,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.more_vert,
                          color: scheme.onSurfaceVariant,
                        ),
                        onPressed: onMore,
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The score, mine in the result's colour and the opponent's quieter.
class _Score extends StatelessWidget {
  const _Score({required this.mine, required this.theirs, required this.color});

  final int mine;
  final int theirs;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$mine', style: context.heading(26, color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('–', style: context.heading(18, color: muted)),
        ),
        Text('$theirs', style: context.heading(20, color: muted)),
      ],
    );
  }
}

/// A small pill: the match mode, or the MMR change.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.strong = false});

  final String label;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          color: context.onTint(color, 0.12),
        ),
      ),
    );
  }
}
