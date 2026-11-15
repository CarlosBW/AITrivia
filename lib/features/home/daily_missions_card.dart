import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../services/daily_missions.dart';
import '../../services/daily_missions_service.dart';
import '../../services/sfx_service.dart';
import '../../theme/app_theme.dart';

/// Today's missions on Home, with the chest that opens when all three are
/// done.
///
/// Holds the day's stream itself (never built in `build()`), and moves on
/// to the next day's when Lima's midnight passes with the app open.
class DailyMissionsSection extends StatefulWidget {
  const DailyMissionsSection({super.key});

  @override
  State<DailyMissionsSection> createState() => _DailyMissionsSectionState();
}

class _DailyMissionsSectionState extends State<DailyMissionsSection> {
  late String _dateId;
  late Stream<MissionsDay> _day;
  Timer? _rollover;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _followToday();
  }

  void _followToday() {
    final now = DateTime.now();
    _dateId = DailyMissions.dateId(now);
    _day = DailyMissionsService.instance.watchDay(_dateId);

    _rollover?.cancel();
    _rollover = Timer(
      DailyMissions.nextReset(now).difference(now) +
          const Duration(seconds: 1),
      () {
        if (mounted) setState(_followToday);
      },
    );
  }

  @override
  void dispose() {
    _rollover?.cancel();
    super.dispose();
  }

  Future<void> _claim() async {
    if (_claiming) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _claiming = true);
    try {
      final reward = await DailyMissionsService.instance.claimChest();
      SfxService.instance.playReward();
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.missionsChestReward(reward.coins, reward.xp)),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(userFacingError(l10n, e))),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MissionsDay>(
      stream: _day,
      builder: (context, snap) {
        // Not until the day arrives: three empty missions that fill in a
        // moment later read as lost progress.
        final day = snap.data;
        if (day == null || day.missions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DailyMissionsCard(
            day: day,
            claiming: _claiming,
            onClaim: _claim,
          ),
        );
      },
    );
  }
}

/// The card itself: the day's three missions with their progress, and the
/// chest.
class DailyMissionsCard extends StatelessWidget {
  const DailyMissionsCard({
    super.key,
    required this.day,
    required this.claiming,
    required this.onClaim,
  });

  final MissionsDay day;
  final bool claiming;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final missions = day.missions;
    final accent = day.chestClaimed ? colors.success : colors.reward;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: day.chestReady
            ? Border.all(color: accent, width: 2)
            : context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                day.chestClaimed
                    ? Icons.inventory_2_outlined
                    : Icons.inventory_2_rounded,
                color: readableInk(accent, scheme.surface),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.missionsTitle, style: context.heading(17)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(context.radii.pill),
                ),
                child: Text(
                  '${day.doneCount}/${missions.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: readableInk(accent, scheme.surface),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final mission in missions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MissionRow(
                label: missionLabel(l10n, mission),
                progress: day.progress(mission),
                target: mission.target,
              ),
            ),
          if (day.chestClaimed)
            Text(
              l10n.missionsChestOpened,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: readableInk(colors.success, scheme.surface),
              ),
            )
          else if (day.chestReady)
            FilledButton.icon(
              onPressed: claiming ? null : onClaim,
              icon: claiming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.redeem_rounded, size: 20),
              label: Text(l10n.missionsOpenChest),
            )
          else
            Text(
              l10n.missionsChestHint(
                DailyMissions.chestCoins,
                DailyMissions.chestXp,
              ),
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// What a mission asks for, in the player's language.
String missionLabel(AppLocalizations l10n, Mission mission) {
  return switch (mission.stat) {
    MissionStat.correct => l10n.missionCorrect(mission.target),
    MissionStat.soloLevels => l10n.missionSoloLevels(mission.target),
    MissionStat.dailyPlayed => l10n.missionPlayDaily,
    MissionStat.weeklyRounds => l10n.missionWeeklyRound,
    MissionStat.streakLevels =>
      l10n.missionStreakLevel(DailyMissions.streakLevelRun),
    MissionStat.greatLevels =>
      l10n.missionGreatLevel(DailyMissions.greatLevelPercent),
  };
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({
    required this.label,
    required this.progress,
    required this.target,
  });

  final String label;
  final int progress;
  final int target;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = context.appColors.success;
    final done = progress >= target;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          done
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 22,
          color: done
              ? readableInk(success, scheme.surface)
              : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: done ? scheme.onSurfaceVariant : scheme.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
              // A bar only where there is something to count up to.
              if (target > 1 && !done) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(context.radii.pill),
                  child: LinearProgressIndicator(
                    value: progress / target,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (target > 1) ...[
          const SizedBox(width: 10),
          Text(
            '$progress/$target',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
