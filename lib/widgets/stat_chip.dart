import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Icon + label + value chip, replacing the many per-screen `_StatCard`
/// clones (Home, Profile, Weekly League, ...) that all built the same
/// shape with their own hardcoded colors/radius.
class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool fullWidth;
  final Color? accent;

  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.fullWidth = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisAlignment:
            fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
