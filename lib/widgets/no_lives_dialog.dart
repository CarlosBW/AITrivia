import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

class NoLivesDialog extends StatelessWidget {
  final String currentLivesText;
  final String nextHalfLifeText;
  final String nextFullLifeText;
  final VoidCallback? onBuyLife;
  final int cost;

  const NoLivesDialog({
    super.key,
    required this.currentLivesText,
    required this.nextHalfLifeText,
    required this.nextFullLifeText,
    this.onBuyLife,
    this.cost = 10,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: context.appColors.dangerBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.favorite_border,
                size: 38,
                color: context.appColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.livesNoLivesTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.livesNoLivesMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(context.radii.md),
                border: context.surfaces.borderOr(null),
                boxShadow: context.surfaces.shadowsOr(null),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.favorite,
                    label: l10n.livesYourLives,
                    value: currentLivesText,
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.timer,
                    label: l10n.livesNextHalf,
                    value: nextHalfLifeText,
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.hourglass_bottom,
                    label: l10n.livesNextFull,
                    value: nextFullLifeText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.livesGoBack),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l10n.livesWait),
                  ),
                ),
              ],
            ),
            if (onBuyLife != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onBuyLife,
                  icon: const Icon(Icons.favorite),
                  label: Text(l10n.livesRecoverButton(cost)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
