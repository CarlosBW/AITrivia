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
    final colorScheme = Theme.of(context).colorScheme;
    final accent = context.appColors.reward;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.14),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.rocket_launch_rounded,
                color: context.readableOnOwnTint(accent, wash: 0.14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.starterPackTitle, style: context.heading(18)),
              ),
              Text(
                l10n.starterPackOnce,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.readableOnOwnTint(accent, wash: 0.14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.starterPackContents(
              EconomyService.starterPackCoins,
              EconomyService.starterPackStreakFreezes,
            ),
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: buying ? null : onBuy,
            child: buying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.starterPackBuy(price)),
          ),
        ],
      ),
    );
  }
}
