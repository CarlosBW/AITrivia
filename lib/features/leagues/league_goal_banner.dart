import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/league_goal.dart';
import '../../theme/app_theme.dart';

/// The player's next step on the league board, said in one line: who is
/// just ahead and how many points pass them, or how big the lead is.
///
/// A ranking alone leaves the player to work that out from two rows of
/// numbers; this is what makes one more Daily Challenge feel worth it.
class LeagueGoalBanner extends StatelessWidget {
  const LeagueGoalBanner({super.key, required this.goal});

  final LeagueGoal goal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final accent =
        goal.isFirst ? context.appColors.reward : scheme.primary;

    final String text;
    if (!goal.isFirst) {
      text = l10n.leagueGoalPass(goal.pointsToPass, goal.rivalName ?? '');
    } else if (goal.lead == null) {
      text = l10n.leagueGoalFirstAlone;
    } else if (goal.lead! > 0) {
      text = l10n.leagueGoalFirstLead(goal.lead!);
    } else {
      text = l10n.leagueGoalFirstTied;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.14),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            goal.isFirst
                ? Icons.emoji_events_rounded
                : Icons.trending_up_rounded,
            color: context.readableOnOwnTint(accent, wash: 0.14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
