import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../services/economy_service.dart';
import '../../services/life_service.dart';
import '../../services/my_profile_service.dart';
import '../../services/purchase_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import 'life_shop_section.dart';
import 'theme_shop_section.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';
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

  // Held, not built in build(): see CLAUDE.md on Firestore streams.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _me =
      MyProfileService.instance.watchMe();

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
    var available = false;
    var products = <ProductDetails>[];
    // A store that can't be reached shows the packs as unavailable; before
    // this an error left the whole tab, themes included, on a spinner.
    try {
      available = await PurchaseService.instance.isAvailable;
      if (available) {
        products = await PurchaseService.instance.queryCoinPackProducts();
      }
    } catch (_) {
      available = false;
    }

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
              : result.canceled
                  ? l10n.coinShopPurchaseCanceled
                  : result.pending
                      ? l10n.coinShopPurchasePending
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
        SnackBar(content: Text(userFacingError(AppLocalizations.of(context), e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(
          widget.embeddedInShell
              ? AppLocalizations.of(context).storeTabTitle
              : AppLocalizations.of(context).coinShopTitle,
        ),
        actions: widget.embeddedInShell
            ? const []
            : const [ProfileAvatarButton()],
      ),
      // Coin packs first: "Comprar monedas" on Home opens this screen. The
      // themes below are bought with coins the player already has, so they
      // show whether or not the app store is reachable.
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).coinShopCoinsSectionTitle,
                        style: context.heading(
                          20,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    // A price means nothing without the balance next to it.
                    // Not until the doc arrives: a 0 that turns into the
                    // real figure a moment later reads as lost coins.
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _me,
                      builder: (context, snap) {
                        final data = snap.data?.data();
                        if (data == null) return const SizedBox.shrink();
                        return CoinBalance(
                          coins: ((data['coins'] ?? 0) as num).toInt(),
                          l10n: AppLocalizations.of(context),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_storeAvailable)
                  _buildShop(context)
                else
                  _buildUnavailable(context),
                const SizedBox(height: 28),
                // Bought with coins the player already has, like the
                // themes, so it shows whether or not the store is reachable.
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _me,
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    if (data == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: _LivesForCoins(userData: data),
                    );
                  },
                ),
                const ThemeShopSection(),
              ],
            ),
    );
  }

  Widget _buildUnavailable(BuildContext context) {
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
              l10n.coinShopUnavailableTitle,
              style: context.heading(20, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.coinShopUnavailableBody,
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

/// [LifeShopSection] with what it needs: the lives worked out from the user
/// doc, a countdown that ticks, and the purchase itself.
class _LivesForCoins extends StatefulWidget {
  const _LivesForCoins({required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<_LivesForCoins> createState() => _LivesForCoinsState();
}

class _LivesForCoinsState extends State<_LivesForCoins> {
  bool _buying = false;

  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Only to move the countdown along: the lives themselves come from the
    // user doc, which the server updates on every change.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // The store tab stays alive while another tab is showing; there is
      // no countdown to move there.
      if (mounted && TickerMode.valuesOf(context).enabled) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _buy(int coins) async {
    if (_buying) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (coins < EconomyService.buyFullLifeCost) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.soloNotEnoughCoins)));
      return;
    }

    setState(() => _buying = true);
    try {
      await LifeService.instance.buyLife();
      messenger.showSnackBar(SnackBar(content: Text(l10n.soloLifeRecovered)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(l10n, e, fallback: l10n.coinShopPurchaseFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lives =
        LifeService.instance.calculateLocalLifeState(widget.userData);
    final coins = ((widget.userData['coins'] ?? 0) as num).toInt();
    final seconds = lives['secondsToNextHalfLife'] as int?;
    final countdown = seconds == null
        ? ''
        : '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
            '${(seconds % 60).toString().padLeft(2, '0')}';

    return LifeShopSection(
      lifeUnits: lives['lifeUnits'] as int,
      maxLifeUnits: lives['maxLifeUnits'] as int,
      coins: coins,
      countdownText: countdown,
      buying: _buying,
      onBuy: () => _buy(coins),
    );
  }
}
