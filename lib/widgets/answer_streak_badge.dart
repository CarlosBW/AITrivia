import 'package:flutter/material.dart';

import '../services/answer_streak.dart';
import '../theme/app_theme.dart';

/// The run of right answers the player is on, as a flame and a count that
/// pops each time it grows and burns hotter at each step that pays.
///
/// Takes no room until there is a run to show, and fades out when a miss
/// ends it.
class AnswerStreakBadge extends StatefulWidget {
  const AnswerStreakBadge({super.key, required this.streak});

  final int streak;

  @override
  State<AnswerStreakBadge> createState() => _AnswerStreakBadgeState();
}

class _AnswerStreakBadgeState extends State<AnswerStreakBadge>
    with SingleTickerProviderStateMixin {
  // Created in initState, not lazily: a badge that never showed a run
  // would otherwise build its controller in dispose, when it no longer can.
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(AnswerStreakBadge old) {
    super.didUpdateWidget(old);
    if (widget.streak > old.streak &&
        widget.streak >= AnswerStreak.shownFrom) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.streak >= AnswerStreak.shownFrom;
    final heat = AnswerStreak.heat(widget.streak);
    final steps = AnswerStreak.bonuses.length;
    final milestone = AnswerStreak.isMilestone(widget.streak);

    // From the theme's reward colour to its danger colour as the run
    // climbs the steps.
    final color = Color.lerp(
      context.appColors.reward,
      context.appColors.danger,
      steps == 0 ? 0 : heat / steps,
    )!;
    final ink = readableInk(color, Theme.of(context).colorScheme.surface);

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: shown ? 1 : 0,
        child: !shown
            ? const SizedBox.shrink()
            : ScaleTransition(
                // Past its size and back: a bigger jump on a paying step.
                scale: TweenSequence<double>([
                  TweenSequenceItem(
                    tween: Tween(begin: 1.0, end: milestone ? 1.45 : 1.2)
                        .chain(CurveTween(curve: Curves.easeOut)),
                    weight: 40,
                  ),
                  TweenSequenceItem(
                    tween: Tween(begin: milestone ? 1.45 : 1.2, end: 1.0)
                        .chain(CurveTween(curve: Curves.elasticOut)),
                    weight: 60,
                  ),
                ]).animate(_pop),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14 + 0.06 * heat),
                    borderRadius: BorderRadius.circular(context.radii.pill),
                    border: Border.all(
                      color: color.withValues(alpha: 0.5),
                      width: heat > 0 ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 20,
                        color: ink,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '×${widget.streak}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
