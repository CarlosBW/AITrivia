import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Generic rounded surface, replacing the hand-rolled
/// `Container(decoration: BoxDecoration(...))` every screen used to
/// build from scratch. Pass [accent] for a tinted surface (brand-colored
/// by default); leave it null for a neutral surface.
class AppCard extends StatelessWidget {
  final Widget child;
  final Color? accent;

  /// Null takes the theme's medium radius. It can't default to it in the
  /// parameter list — a `const` constructor's defaults have to be
  /// compile-time constants, and the scale now comes from the theme.
  final double? radius;

  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.accent,
    this.radius,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius ?? context.radii.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: child,
    );
  }
}
