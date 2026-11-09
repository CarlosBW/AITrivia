import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The banner a result screen opens on — a finished duel, a finished level:
/// the theme's hero gradient with two soft rings for depth, and a few
/// sparkles when it's worth celebrating. Text on it should use
/// `context.appColors.onAccent`.
class ResultHeroBanner extends StatelessWidget {
  const ResultHeroBanner({
    super.key,
    required this.child,
    this.sparkles = false,
  });

  final Widget child;
  final bool sparkles;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final onHero = colors.onAccent;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.heroGradientStart, colors.heroGradientEnd],
        ),
        borderRadius: BorderRadius.circular(context.radii.lg),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: colors.heroGradientEnd.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ]),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: _Ring(size: 180, color: onHero.withValues(alpha: 0.10)),
          ),
          Positioned(
            bottom: -70,
            left: -50,
            child: _Ring(size: 160, color: onHero.withValues(alpha: 0.08)),
          ),
          if (sparkles) ...[
            // Near the corners, clear of the centred title and badges.
            _Sparkle(left: 26, top: 24, size: 18, color: onHero),
            _Sparkle(right: 32, top: 40, size: 14, color: onHero),
            _Sparkle(left: 16, bottom: 70, size: 12, color: onHero),
            _Sparkle(right: 18, bottom: 84, size: 20, color: onHero),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// [color] if it stands out on the hero gradient, otherwise the banner's
/// foreground. A theme's reward colour is gold on most heroes but ink on
/// the Sketch theme's dark one, where it would vanish.
Color colorOnHero(BuildContext context, Color color) {
  final colors = context.appColors;
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  // Against the end of the gradient it stands out from most: gold reads
  // on violet even where it meets the pink, ink on charcoal reads nowhere.
  final best = [colors.heroGradientStart, colors.heroGradientEnd]
      .map((hero) => contrast(color, hero))
      .reduce((a, b) => a > b ? a : b);
  return best >= 1.8 ? color : colors.onAccent;
}

/// A pill on the hero banner: translucent, with the banner's foreground.
class HeroBadge extends StatelessWidget {
  const HeroBadge({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final onHero = context.appColors.onAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: onHero.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(color: onHero.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: onHero),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: onHero, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double size;
  final Color color;

  const _Ring({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 18),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double size;
  final Color color;

  const _Sparkle({
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Icon(
        Icons.auto_awesome,
        size: size,
        color: color.withValues(alpha: 0.7),
      ),
    );
  }
}
