import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A big gradient call to action with a 3D illustration on the right —
/// the daily challenge, finding a rival, picking a category back up.
class HeroCard extends StatelessWidget {
  final Color gradientStart;
  final Color gradientEnd;

  /// An asset under `assets/illustrations/`.
  final String illustration;
  final String title;
  final String? subtitle;

  /// A small pill above the title, e.g. the daily streak.
  final String? badge;

  /// The label of the white pill button; the whole card is the tap target.
  final String? actionLabel;
  final VoidCallback? onTap;

  const HeroCard({
    super.key,
    required this.gradientStart,
    required this.gradientEnd,
    required this.illustration,
    required this.title,
    this.subtitle,
    this.badge,
    this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onHero = context.appColors.onAccent;
    final radius = BorderRadius.circular(context.radii.lg);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: gradientEnd.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ]),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: context.surfaces.borderOr(null),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [gradientStart, gradientEnd],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 6, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (badge != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: onHero.withValues(alpha: 0.2),
                              borderRadius:
                                  BorderRadius.circular(context.radii.pill),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: onHero,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(title, style: context.heading(21, color: onHero)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: onHero.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                        if (actionLabel != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: onHero,
                              borderRadius:
                                  BorderRadius.circular(context.radii.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                  color: readableInk(gradientStart, onHero),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  actionLabel!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: readableInk(gradientStart, onHero),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Image.asset(
                    illustration,
                    width: 104,
                    height: 104,
                    cacheWidth:
                        (104 * MediaQuery.devicePixelRatioOf(context)).round(),
                    filterQuality: FilterQuality.medium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
