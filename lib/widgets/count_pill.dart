import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A running count shown during a round (right answers, questions
/// answered), as a tinted pill rather than a line of plain text.
class CountPill extends StatelessWidget {
  final IconData icon;
  final String label;

  /// The pill's tint; the text is darkened from it until it reads.
  final Color color;

  const CountPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ink = readableInk(color, Theme.of(context).colorScheme.surface);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
