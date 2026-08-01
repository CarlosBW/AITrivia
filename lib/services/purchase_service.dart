import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'economy_service.dart';

/// Wraps `in_app_purchase` for the coin packs in [EconomyService.coinPacks].
///
/// Product ids only resolve once the packs are actually configured in the
/// Google Play Console / App Store Connect — until then, [products] stays
/// empty and [isAvailable] may be false, which [CoinShopScreen] treats as
/// "coming soon" rather than an error.
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final _purchaseResultController =
      StreamController<PurchaseResult>.broadcast();

  /// Emits once per completed purchase attempt (success or failure), so a
  /// screen can react (show a snackbar, refresh the coin balance) without
  /// wiring into the raw `in_app_purchase` stream itself.
  Stream<PurchaseResult> get purchaseResults =>
      _purchaseResultController.stream;

  bool _started = false;

  Future<bool> get isAvailable => _iap.isAvailable();

  void start() {
    if (_started) return;
    _started = true;

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (_) {},
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  Future<List<ProductDetails>> queryCoinPackProducts() async {
    final ids = EconomyService.coinPacks.map((p) => p.id).toSet();
    final response = await _iap.queryProductDetails(ids);
    return response.productDetails;
  }

  Future<void> buy(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    // Coins are consumable — the player can buy the same pack again.
    await _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;

        case PurchaseStatus.error:
          _purchaseResultController.add(
            PurchaseResult(
              productId: purchase.productID,
              success: false,
              message: purchase.error?.message ?? 'Purchase failed.',
            ),
          );
          break;

        case PurchaseStatus.canceled:
          _purchaseResultController.add(
            PurchaseResult(
              productId: purchase.productID,
              success: false,
              message: 'Purchase canceled.',
            ),
          );
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndCredit(purchase);
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndCredit(PurchaseDetails purchase) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'verifyCoinPurchase',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({
        'productId': purchase.productID,
        'source': purchase.verificationData.source,
        'verificationData':
            purchase.verificationData.serverVerificationData,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final grantedCoins = (data['grantedCoins'] as num?)?.toInt() ?? 0;

      _purchaseResultController.add(
        PurchaseResult(
          productId: purchase.productID,
          success: true,
          grantedCoins: grantedCoins,
        ),
      );
    } catch (e) {
      _purchaseResultController.add(
        PurchaseResult(
          productId: purchase.productID,
          success: false,
          message: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}

class PurchaseResult {
  final String productId;
  final bool success;
  final int grantedCoins;
  final String? message;

  PurchaseResult({
    required this.productId,
    required this.success,
    this.grantedCoins = 0,
    this.message,
  });
}
