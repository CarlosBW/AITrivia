import 'package:flutter/material.dart';

import '../services/life_service.dart';

/// A row of hearts standing in for the "8/10 lives" text.
///
/// The count is derived from [maxLifeUnits] rather than fixed, so it follows
/// the balance instead of having to be corrected every time it moves — the
/// lives went from 5 to 10 once already, and every hardcoded copy of that
/// number had to be chased down afterwards.
///
/// One heart per life, drawn full, half or empty. Halves are not decorative:
/// a wrong answer costs [LifeService.wrongAnswerCostUnits] — half a life —
/// so a row that could only show whole hearts would sit unchanged through a
/// wrong answer and read as a bug.
class LifeHearts extends StatelessWidget {
  const LifeHearts({
    super.key,
    required this.lifeUnits,
    required this.maxLifeUnits,
    required this.color,
    this.size = 18,
    this.spacing = 2,
  });

  final int lifeUnits;
  final int maxLifeUnits;
  final Color color;
  final double size;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final perLife = LifeService.unitsPerLife;
    final hearts = (maxLifeUnits / perLife).ceil();
    final units = lifeUnits.clamp(0, maxLifeUnits);

    return Semantics(
      // The hearts are the display; this is what a screen reader gets, and
      // it stays the precise number the text used to show.
      label: '${LifeService.instance.formatLives(units)}'
          '/${LifeService.instance.formatLives(maxLifeUnits)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < hearts; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            _Heart(
              // Units this heart would need to be full, vs. what's left.
              fill: ((units - i * perLife) / perLife).clamp(0.0, 1.0),
              color: color,
              size: size,
            ),
          ],
        ],
      ),
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({required this.fill, required this.color, required this.size});

  /// 0 empty, 0.5 half, 1 full.
  final double fill;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final outline = Icon(
      Icons.favorite_border,
      size: size,
      color: color.withValues(alpha: 0.45),
    );

    if (fill <= 0) return outline;

    return Stack(
      alignment: Alignment.center,
      children: [
        outline,
        // Clipped from the left so a half heart reads as half-drained
        // rather than as a smaller heart.
        ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: fill,
            child: Icon(Icons.favorite, size: size, color: color),
          ),
        ),
      ],
    );
  }
}
