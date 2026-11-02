import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A round's progress as one segment per question: green for a right
/// answer, red for a wrong one, the brand colour for the question on
/// screen and grey for the ones still ahead.
class SegmentedProgress extends StatelessWidget {
  /// One entry per question: true right, false wrong, null not answered.
  final List<bool?> results;

  /// The question on screen.
  final int current;

  const SegmentedProgress({
    super.key,
    required this.results,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        for (var i = 0; i < results.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              key: ValueKey('segment_$i'),
              duration: const Duration(milliseconds: 250),
              height: 8,
              decoration: BoxDecoration(
                color: switch (results[i]) {
                  true => context.appColors.success,
                  false => context.appColors.danger,
                  null => i == current
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                },
                borderRadius: BorderRadius.circular(context.radii.pill),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
