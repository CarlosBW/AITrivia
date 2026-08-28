import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_themes.dart';

/// The themes half of the store.
///
/// Lives apart from the coin packs because the two are bought with
/// different currencies and gated differently: coin packs wait on the app
/// stores, themes only need coins the player already has.
class ThemeShopSection extends StatefulWidget {
  const ThemeShopSection({super.key});

  @override
  State<ThemeShopSection> createState() => _ThemeShopSectionState();
}

class _ThemeShopSectionState extends State<ThemeShopSection> {
  // Held here, not built in `build()`: a stream rebuilt on every frame
  // makes StreamBuilder cancel and re-subscribe, re-reading the doc.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDoc =
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .snapshots();

  String? _busyThemeId;

  String _nameOf(AppLocalizations l10n, String id) {
    switch (id) {
      case AppThemes.playfulId:
        return l10n.themeNamePlayful;
      default:
        return l10n.themeNameDefault;
    }
  }

  String _descriptionOf(AppLocalizations l10n, String id) {
    switch (id) {
      case AppThemes.playfulId:
        return l10n.themeDescriptionPlayful;
      default:
        return l10n.themeDescriptionDefault;
    }
  }

  Future<void> _equip(String themeId) async {
    setState(() => _busyThemeId = themeId);
    try {
      await ThemeService.instance.equip(themeId);
    } finally {
      if (mounted) setState(() => _busyThemeId = null);
    }
  }

  Future<void> _buy(AppThemeSpec spec, int coins) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (coins < spec.price) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.themeShopNotEnoughCoins)),
      );
      return;
    }

    setState(() => _busyThemeId = spec.id);

    try {
      await ThemeService.instance.purchase(spec.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.themeShopPurchased(_nameOf(l10n, spec.id))),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyThemeId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final coins = ((data?['coins'] ?? 0) as num).toInt();
        final owned = ThemeService.ownedThemeIds(data);
        final equipped = ThemeService.equippedIdFrom(data);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.themeShopSectionTitle,
              style: context.heading(20, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.themeShopSectionSubtitle,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final spec in AppThemes.all) ...[
              _ThemeCard(
                spec: spec,
                name: _nameOf(l10n, spec.id),
                description: _descriptionOf(l10n, spec.id),
                owned: owned.contains(spec.id),
                equipped: equipped == spec.id,
                busy: _busyThemeId == spec.id,
                onEquip: () => _equip(spec.id),
                onBuy: () => _buy(spec, coins),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.spec,
    required this.name,
    required this.description,
    required this.owned,
    required this.equipped,
    required this.busy,
    required this.onEquip,
    required this.onBuy,
  });

  final AppThemeSpec spec;
  final String name;
  final String description;
  final bool owned;
  final bool equipped;
  final bool busy;
  final VoidCallback onEquip;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final surfaces = context.surfaces;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: equipped
            ? Border.all(color: colorScheme.primary, width: 2)
            : (surfaces.hasBorder
                ? Border.all(
                    color: surfaces.borderColor,
                    width: surfaces.borderWidth,
                  )
                : Border.all(color: colorScheme.outline)),
        boxShadow: surfaces.shadows,
      ),
      child: Row(
        children: [
          _Swatch(colors: spec.preview),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: context.heading(17, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Action(
            l10n: l10n,
            spec: spec,
            owned: owned,
            equipped: equipped,
            busy: busy,
            onEquip: onEquip,
            onBuy: onBuy,
          ),
        ],
      ),
    );
  }
}

/// The three-colour chip that lets a player tell two themes apart without
/// equipping either.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.radii.sm),
        child: Column(
          children: [
            for (final color in colors)
              Expanded(child: Container(color: color)),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.l10n,
    required this.spec,
    required this.owned,
    required this.equipped,
    required this.busy,
    required this.onEquip,
    required this.onBuy,
  });

  final AppLocalizations l10n;
  final AppThemeSpec spec;
  final bool owned;
  final bool equipped;
  final bool busy;
  final VoidCallback onEquip;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (equipped) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: context.appColors.success,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.themeShopEquipped,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.appColors.success,
            ),
          ),
        ],
      );
    }

    if (owned) {
      return OutlinedButton(
        onPressed: onEquip,
        child: Text(l10n.themeShopEquip),
      );
    }

    return FilledButton.icon(
      onPressed: onBuy,
      icon: const Text('🪙', style: TextStyle(fontSize: 14)),
      label: Text(l10n.themeShopPriceButton(spec.price)),
    );
  }
}
