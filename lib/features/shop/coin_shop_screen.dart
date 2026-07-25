import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../services/economy_service.dart';
import '../../services/purchase_service.dart';
import '../../theme/app_theme.dart';

/// Coin pack storefront. Until the packs are configured in the Google Play
/// Console / App Store Connect, `queryCoinPackProducts` returns nothing, so
/// this shows a "coming soon" state instead of an empty/broken shop.
class CoinShopScreen extends StatefulWidget {
  const CoinShopScreen({super.key});

  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen> {
  bool _loading = true;
  bool _storeAvailable = false;
  Map<String, ProductDetails> _products = {};
  String? _purchasingProductId;

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.start();
    PurchaseService.instance.purchaseResults.listen(_onPurchaseResult);
    _load();
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? '+${result.grantedCoins} monedas'
              : result.message ?? 'La compra no se completó.',
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
      appBar: AppBar(title: const Text('Comprar monedas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _storeAvailable
              ? _buildShop(context)
              : _buildComingSoon(context),
    );
  }

  Widget _buildComingSoon(BuildContext context) {
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
              'Próximamente',
              style: GoogleFonts.baloo2(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La compra de monedas todavía no está disponible en esta '
              'versión.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShop(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
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
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.rewardBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monetization_on_outlined,
                  color: AppColors.reward,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pack.coins} monedas',
                      style: GoogleFonts.baloo2(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
                    : const Text('Comprar'),
              ),
            ],
          ),
        );
      },
    );
  }
}
