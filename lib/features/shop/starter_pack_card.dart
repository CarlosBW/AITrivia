import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/economy_service.dart';
import '../../theme/app_theme.dart';

/// Whether the starter pack is still on offer to the player whose user doc
/// is [userData]: it is sold once per account, and the server marks the
/// account when it is paid.
bool starterPackOffered(Map<String, dynamic> userData) {
  return userData['starterPackBought'] != true;
}

/// The one-time starter pack, at the top of the store: more coins than the
/// smallest pack for a little more money, plus streak protectors.
///
/// Drawn like the app's other hero cards — gradient, illustration on the
/// right — because it is the one offer in the store that goes away.
///
/// Only draws the card; the store owns the product and the purchase.
class StarterPackCard extends StatelessWidget {
  const StarterPackCard({
    super.key,
    required this.price,
    required this.buying,
    required this.onBuy,
  });

  /// The store's own price, in the player's currency.
  final String price;
  final bool buying;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final onHero = colors.onAccent;
    final start = colors.heroGradientStart;
    final end = colors.heroGradientEnd;
    final radius = BorderRadius.circular(context.radii.lg);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: context.surfaces.borderOr(null),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, end],
        ),
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: end.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ]),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.reward,
                    borderRadius: BorderRadius.circular(context.radii.pill),
                  ),
                  child: Text(
                    l10n.starterPackOnce,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: colors.onReward,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.starterPackTitle,
                  style: context.heading(21, color: onHero),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.starterPackContents(
                    EconomyService.starterPackCoins,
                    EconomyService.starterPackStreakFreezes,
                  ),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: onHero.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: onHero,
                    foregroundColor: readableInk(start, onHero),
                    disabledBackgroundColor: onHero.withValues(alpha: 0.7),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: buying ? null : onBuy,
                  child: buying
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: readableInk(start, onHero),
                          ),
                        )
                      : Text(
                          l10n.starterPackBuy(price),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Image.asset(
            'assets/illustrations/starter_pack.png',
            width: 116,
            height: 116,
            cacheWidth: (116 * MediaQuery.devicePixelRatioOf(context)).round(),
            filterQuality: FilterQuality.medium,
          ),
        ],
      ),
    );
  }
}
