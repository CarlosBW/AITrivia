import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A question's countdown as a ring with the seconds inside, going from
/// green to amber to red as it runs out.
class CircularTimer extends StatelessWidget {
  final int secondsLeft;
  final int totalSeconds;
  final double size;

  const CircularTimer({
    super.key,
    required this.secondsLeft,
    required this.totalSeconds,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = totalSeconds == 0
        ? 0.0
        : (secondsLeft / totalSeconds).clamp(0.0, 1.0);

    final color = fraction > 0.5
        ? context.appColors.success
        : fraction > 0.2
            ? context.appColors.reward
            : context.appColors.danger;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
          ),
          CircularProgressIndicator(
            value: fraction,
            strokeWidth: 5,
            strokeCap: StrokeCap.round,
            backgroundColor: color.withValues(alpha: 0.18),
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Center(
            child: Text(
              '$secondsLeft',
              style: context.heading(
                20,
                color: readableInk(
                  color,
                  Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
