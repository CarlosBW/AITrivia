import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../services/economy_service.dart';
import '../../services/purchase_service.dart';
import '../../l10n/generated/app_localizations.dart';
import 'theme_shop_section.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_avatar_button.dart';

/// Coin pack storefront. Until the packs are configured in the Google Play
/// Console / App Store Connect, `queryCoinPackProducts` returns nothing, so
/// this shows a "coming soon" state instead of an empty/broken shop.
class CoinShopScreen extends StatefulWidget {
  /// True when this is the store tab rather than a pushed route.
  ///
  /// The navigation shell paints the language switch, the bell and the
  /// profile avatar in an overlay above whatever tab is showing, so a tab
  /// must not draw its own copy: the avatar would sit stacked under the
  /// overlay's, and a long title runs underneath the two of them.
  final bool embeddedInShell;

  const CoinShopScreen({super.key, this.embeddedInShell = false});

  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen> {
  bool _loading = true;
  bool _storeAvailable = false;
  Map<String, ProductDetails> _products = {};
  String? _purchasingProductId;

  StreamSubscription<PurchaseResult>? _purchaseResultsSub;

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.start();
    _purchaseResultsSub =
        PurchaseService.instance.purchaseResults.listen(_onPurchaseResult);
    _load();
  }

  @override
  void dispose() {
    _purchaseResultsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final available = await PurchaseService.instance.isAvailable;
    final products = available
        ? await PurchaseService.instance.queryCoinPackProducts()
        : <ProductDetails>[];

    if (!mounted) return;

    setState(() {
      _storeAvailable = available && products.isNotEmpty;
      _products = {for (final p in products) p.id: p};
      _loading = false;
    });
  }

  void _onPurchaseResult(PurchaseResult result) {
    if (!mounted) return;

    setState(() => _purchasingProductId = null);

    final l10n = AppLocalizations.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? l10n.coinShopPurchaseSuccess(result.grantedCoins)
              : result.message ?? l10n.coinShopPurchaseFailed,
        ),
      ),
    );
  }

  Future<void> _buy(CoinPack pack) async {
    final product = _products[pack.id];
    if (product == null || _purchasingProductId != null) return;

    setState(() => _purchasingProductId = pack.id);

    try {
      await PurchaseService.instance.buy(product);
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchasingProductId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.embeddedInShell
              ? AppLocalizations.of(context).storeTabTitle
              : AppLocalizations.of(context).coinShopTitle,
        ),
        actions: widget.embeddedInShell
            ? const []
            : const [ProfileAvatarButton()],
      ),
      // Themes are bought with coins the player already has, so they show
      // whether or not the IAP store is reachable — only the coin packs
      // below wait on the app-store accounts.
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ThemeShopSection(),
                const SizedBox(height: 28),
                Text(
                  AppLocalizations.of(context).coinShopCoinsSectionTitle,
                  style: context.heading(
                    20,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                if (_storeAvailable)
                  _buildShop(context)
                else
                  _buildComingSoon(context),
              ],
            ),
    );
  }

  Widget _buildComingSoon(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.coinShopComingSoonTitle,
              style: context.heading(20, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.coinShopComingSoonBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShop(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Nested inside the screen's own ListView now, so it must size to its
    // children and leave the scrolling to the parent.
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: EconomyService.coinPacks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final pack = EconomyService.coinPacks[index];
        final product = _products[pack.id];
        final isPurchasing = _purchasingProductId == pack.id;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(context.radii.md),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr(null),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.appColors.rewardBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.monetization_on_outlined,
                  color: context.appColors.reward,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.coinShopCoinsAmount(pack.coins),
                      style: context.heading(16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product?.price ?? '\$${pack.usd.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: isPurchasing ? null : () => _buy(pack),
                child: isPurchasing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.coinShopBuyButton),
              ),
            ],
          ),
        );
      },
    );
  }
}
