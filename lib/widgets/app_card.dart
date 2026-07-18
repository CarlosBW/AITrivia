import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Generic rounded surface, replacing the hand-rolled
/// `Container(decoration: BoxDecoration(...))` every screen used to
/// build from scratch. Pass [accent] for a tinted surface (brand-colored
/// by default); leave it null for a neutral surface.
class AppCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final double radius;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.accent,
    this.radius = AppRadius.md,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: child,
    );
  }
}
