import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import 'life_hearts.dart';

// Vidas + tiempo de regeneración are one system, so they read as one card
// instead of two separate stat chips.
class LivesCard extends StatelessWidget {
  final int lifeUnits;
  final int maxLifeUnits;
  final bool isFull;
  final String countdownText;

  const LivesCard({
    super.key,
    required this.lifeUnits,
    required this.maxLifeUnits,
    required this.isFull,
    required this.countdownText,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const iconColor = Color(0xFFFF6B5B);
    const labelColor = Color(0xFFD9695B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.appColors.dangerBg,
        borderRadius: BorderRadius.circular(context.radii.sm),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Row(
        children: [
          // Hearts instead of "8/10 lives": the number is information, the
          // row is a game. The exact figure still reaches screen readers.
          //
          // The hearts take whatever the label leaves and shrink to fit it:
          // ten of them plus "Vidas al máximo" are wider than a phone, and
          // of the two it is the text that has to stay readable.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: LifeHearts(
                lifeUnits: lifeUnits,
                maxLifeUnits: maxLifeUnits,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isFull ? Icons.check_circle_outline : Icons.timer_outlined,
            size: 16,
            color: labelColor,
          ),
          const SizedBox(width: 4),
          Text(
            isFull ? l10n.homeLivesFull : countdownText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}
