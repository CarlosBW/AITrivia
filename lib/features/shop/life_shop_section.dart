import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/economy_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lives_card.dart';

/// Lives for coins, in the store.
///
/// Buying a life used to be offered only by the "not enough lives" dialog,
/// so a player who never ran dry never learned it was possible. This only
/// draws the section; the store owns the user doc it reads and the call
/// that does the buying.
class LifeShopSection extends StatelessWidget {
  const LifeShopSection({
    super.key,
    required this.lifeUnits,
    required this.maxLifeUnits,
    required this.coins,
    required this.countdownText,
    required this.buying,
    required this.onBuy,
  });

  final int lifeUnits;
  final int maxLifeUnits;
  final int coins;
  final String countdownText;
  final bool buying;

  /// Called on a tap even without enough coins: the store says so then,
  /// which tells the player more than a button that does nothing.
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isFull = lifeUnits >= maxLifeUnits;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.homeLivesLabel,
          style: context.heading(20, color: colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(context.radii.md),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr(null),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LivesCard(
                lifeUnits: lifeUnits,
                maxLifeUnits: maxLifeUnits,
                isFull: isFull,
                countdownText: countdownText,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.lifeShopHint,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (!isFull) ...[
                    const SizedBox(width: 12),
                    _buyButton(context, l10n),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buyButton(BuildContext context, AppLocalizations l10n) {
    if (buying) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    // Priced the way the themes below are: coin, then amount.
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.lifeShopBuyOne),
        const SizedBox(width: 8),
        const Text('🪙', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(
          '${EconomyService.buyFullLifeCost}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );

    // Outlined when the balance doesn't cover it, as the theme cards do.
    return coins >= EconomyService.buyFullLifeCost
        ? FilledButton(onPressed: onBuy, child: label)
        : OutlinedButton(onPressed: onBuy, child: label);
  }
}
