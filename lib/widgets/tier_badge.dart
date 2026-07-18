import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Emoji + name pill for a league/rank tier, in one shared shape/style
/// instead of every leaderboard screen (Weekly League, PvP Season, ...)
/// inventing its own rank colors. Callers pass in whichever tier's
/// emoji/name/color they already look up (LeagueInfo, PvpLeagueInfo,
/// ProfileFrameInfo all already share the same hex values per tier id) —
/// this widget only standardizes how a tier is drawn, not the tier list.
class TierBadge extends StatelessWidget {
  final String emoji;
  final String name;
  final int colorValue;
  final bool compact;

  const TierBadge({
    super.key,
    required this.emoji,
    required this.name,
    required this.colorValue,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: compact ? 13 : 16)),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: compact ? 11.5 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
