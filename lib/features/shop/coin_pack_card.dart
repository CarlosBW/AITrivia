import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

/// The picture that goes with each coin pack: a few coins for the smallest,
/// a treasure chest for the biggest, so the size of a pack reads before its
/// number does.
const Map<String, String> _packIllustrations = {
  'coins_pack_small': 'assets/illustrations/coins_few.png',
  'coins_pack_ai_topic': 'assets/illustrations/coins.png',
  'coins_pack_medium': 'assets/illustrations/chest.png',
  'coins_pack_large': 'assets/illustrations/chest_big.png',
};

/// The illustration for the pack with this product id; a pile of coins for
/// a pack this doesn't know yet.
String coinPackIllustration(String packId) {
  return _packIllustrations[packId] ?? 'assets/illustrations/coins.png';
}

/// How many more coins per unit of money a pack gives than the base pack,
/// as a whole percentage rounded down, or 0 when it gives no more.
///
/// Worked out from prices rather than written next to each pack, so the
/// badge can't promise more than the store actually charges for.
int coinPackBonusPercent({
  required int coins,
  required double price,
  required int baseCoins,
  required double basePrice,
}) {
  if (coins <= 0 || price <= 0 || baseCoins <= 0 || basePrice <= 0) return 0;
  final ratio = (coins / price) / (baseCoins / basePrice);
  // The nudge keeps an exact 20% from landing on 19.999… and showing 19.
  final percent = ((ratio - 1) * 100 + 1e-6).floor();
  return percent > 0 ? percent : 0;
}

/// One coin pack in the store's grid: its picture, how many coins, what
/// they buy, and the price on the button that buys it.
///
/// Only draws the card; the store owns the products and the purchase.
class CoinPackCard extends StatelessWidget {
  const CoinPackCard({
    super.key,
    required this.illustration,
    required this.coins,
    required this.price,
    required this.buying,
    required this.onBuy,
    this.bonusPercent = 0,
    this.bestValue = false,
    this.aiTopics = 0,
  });

  /// An asset under `assets/illustrations/`.
  final String illustration;
  final int coins;

  /// The store's own price, in the player's currency.
  final String price;
  final bool buying;
  final VoidCallback onBuy;

  /// See [coinPackBonusPercent]; no badge at 0.
  final int bonusPercent;

  /// The pack that gives the most coins for the money.
  final bool bestValue;

  /// How many AI topics these coins pay for; no line at 0.
  final int aiTopics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final radius = BorderRadius.circular(context.radii.lg);
    final glow = Color.alphaBlend(
      colors.reward.withValues(alpha: bestValue ? 0.3 : 0.18),
      scheme.surface,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: context.surfaces.shadowsOr(
          bestValue
              ? [
                  BoxShadow(
                    color: colors.reward.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: scheme.surface, borderRadius: radius),
        // Drawn over the card's contents, not under them: the picture's
        // square box reaches into the rounded corners and would paint over
        // a border that sat beneath it.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: bestValue
              ? Border.all(color: colors.reward, width: 2)
              : context.surfaces.borderOr(
                  Border.all(color: scheme.outlineVariant),
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Container(
                  height: 116,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      // Gone before the edge of the box, so the glow
                      // reads as light behind the picture, not as a panel.
                      center: const Alignment(0, 0.1),
                      radius: 0.56,
                      colors: [glow, scheme.surface],
                    ),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(top: 10),
                  child: Image.asset(
                    illustration,
                    width: 104,
                    height: 104,
                    cacheWidth:
                        (104 * MediaQuery.devicePixelRatioOf(context)).round(),
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                if (bestValue)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _Tag(
                      label: l10n.coinPackBestValue,
                      background: colors.reward,
                      foreground: colors.onReward,
                      corner: BorderRadius.only(
                        bottomRight: Radius.circular(context.radii.md),
                      ),
                    ),
                  ),
                if (bonusPercent > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _Tag(
                      label: l10n.coinPackBonus(bonusPercent),
                      background: colors.success,
                      foreground: readableInk(scheme.surface, colors.success),
                      corner: BorderRadius.circular(context.radii.pill),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                children: [
                  Text(
                    l10n.coinShopCoinsAmount(coins),
                    textAlign: TextAlign.center,
                    style: context.heading(17),
                  ),
                  const SizedBox(height: 2),
                  // Kept even when empty, so the buttons of a row line up.
                  Text(
                    aiTopics > 0 ? l10n.coinPackAiTopics(aiTopics) : '',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: buying ? null : onBuy,
                      child: buying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              price,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.background,
    required this.foreground,
    required this.corner,
  });

  final String label;
  final Color background;
  final Color foreground;
  final BorderRadius corner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: corner),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
          color: foreground,
        ),
      ),
    );
  }
}
