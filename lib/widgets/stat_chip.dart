import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Icon + label + value chip, replacing the many per-screen `_StatCard`
/// clones (Home, Profile, Weekly League, ...) that all built the same
/// shape with their own hardcoded colors/radius.
///
/// Default (non-[fullWidth]) shape is a vertical tile — icon, big value,
/// small label — colored by [accent]/[background] so a row of these reads
/// as distinct, vivid stat cards rather than one flat gray strip.
class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool fullWidth;
  final Color? accent;
  final Color? background;

  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.fullWidth = false,
    this.accent,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    final bg = background ?? color.withValues(alpha: 0.18);
    final iconColor = Color.lerp(color, Colors.black, 0.25)!;
    final valueColor = Color.lerp(color, Colors.black, 0.35)!;
    final labelColor = Color.lerp(color, Colors.black, 0.10)!;

    if (fullWidth) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(context.radii.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Text(
              '$label: $value',
              style: context.heading(15, color: valueColor),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: context.heading(22, color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
