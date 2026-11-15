import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/economy_service.dart';
import '../../theme/app_theme.dart';

/// Streak protectors for coins, in the store: each one keeps the daily
/// streak through a day the player doesn't play.
///
/// Only draws the section; the store owns the user doc it reads and the
/// call that does the buying.
class StreakFreezeShopSection extends StatelessWidget {
  const StreakFreezeShopSection({
    super.key,
    required this.held,
    required this.coins,
    required this.buying,
    required this.onBuy,
  });

  /// Protectors the player holds.
  final int held;
  final int coins;
  final bool buying;

  /// Called on a tap even without enough coins: the store says so then,
  /// which tells the player more than a button that does nothing.
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isFull = held >= EconomyService.maxStreakFreezes;
    final accent = colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.streakFreezeTitle,
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
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      color: context.readableOnOwnTint(accent, wash: 0.14),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.streakFreezeHeld(
                        held,
                        EconomyService.maxStreakFreezes,
                      ),
                      style: context.heading(16),
                    ),
                  ),
                  if (!isFull) _buyButton(context),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isFull ? l10n.streakFreezeFull : l10n.streakFreezeHint,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buyButton(BuildContext context) {
    if (buying) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }

    // Priced the way lives and themes are: coin, then amount.
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🪙', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(
          '${EconomyService.streakFreezeCost}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );

    // Outlined when the balance doesn't cover it, as the life button is.
    return coins >= EconomyService.streakFreezeCost
        ? FilledButton(onPressed: onBuy, child: label)
        : OutlinedButton(onPressed: onBuy, child: label);
  }
}
