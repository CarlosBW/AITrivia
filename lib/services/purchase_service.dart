import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
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

  // Lazy, and never touched on web — see [_hasStorePlugin].
  late final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// False on web, where there is no store and the plugin must not even be
  /// created.
  ///
  /// The plugin picks its store by `defaultTargetPlatform`, which on the
  /// web follows the *browser*: in a phone's browser it is Android, so it
  /// builds the Play Billing client, and that client throws from inside
  /// its own constructor, asynchronously, where nothing here can catch it.
  /// The checks below guard desktop; only skipping the plugin guards this.
  static const bool _hasStorePlugin = !kIsWeb;

  final _purchaseResultController =
      StreamController<PurchaseResult>.broadcast();

  /// Emits once per completed purchase attempt (success or failure), so a
  /// screen can react (show a snackbar, refresh the coin balance) without
  /// wiring into the raw `in_app_purchase` stream itself.
  Stream<PurchaseResult> get purchaseResults =>
      _purchaseResultController.stream;

  bool _started = false;

  /// Whether there is a store to buy from.
  ///
  /// `in_app_purchase` only registers one on Android and Apple devices;
  /// on web or desktop it throws rather than answering no. That has to
  /// read as "no store", or the shop waits forever on this and never
  /// shows the themes, which don't need a store at all.
  Future<bool> get isAvailable async {
    if (!_hasStorePlugin) return false;

    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  void start() {
    if (_started || !_hasStorePlugin) return;

    try {
      _subscription = _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (_) {},
      );
      _started = true;
    } catch (_) {
      // No store on this platform — see [isAvailable]. Nothing to hear.
    }
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
      // Whether it's safe to tell the store this purchase is fulfilled.
      // For a consumable, completePurchase consumes the token: the store
      // considers the item delivered and will never hand it back. So it
      // must only run once the coins are actually credited — a failed or
      // canceled purchase has nothing to deliver (safe to finish), but a
      // *paid* purchase whose verification failed has to stay pending so
      // the store re-delivers it on the next launch and crediting can be
      // retried. Completing it there would take the player's money and
      // give them nothing, with no way to recover it.
      var safeToComplete = false;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;

        case PurchaseStatus.error:
          // No message: the store's own is a technical string in English,
          // and this service has no context to translate one from. The
          // screen says it in the player's language.
          _purchaseResultController.add(
            PurchaseResult(productId: purchase.productID, success: false),
          );
          safeToComplete = true;
          break;

        case PurchaseStatus.canceled:
          _purchaseResultController.add(
            PurchaseResult(
              productId: purchase.productID,
              success: false,
              canceled: true,
            ),
          );
          safeToComplete = true;
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          safeToComplete = await _verifyAndCredit(purchase);
          break;
      }

      if (safeToComplete && purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  /// Verifies the purchase server-side and credits the coins.
  ///
  /// Returns whether the coins were actually credited — the caller uses
  /// this to decide if the purchase may be finished with the store.
  Future<bool> _verifyAndCredit(PurchaseDetails purchase) async {
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

      return true;
    } catch (e) {
      _purchaseResultController.add(
        PurchaseResult(
          productId: purchase.productID,
          success: false,
          // Left to the shop's own "purchase failed" text: the raw
          // exception was English, and often a Firebase error code.
          message: null,
        ),
      );

      return false;
    }
  }
}

class PurchaseResult {
  final String productId;
  final bool success;
  final int grantedCoins;

  /// The player backed out of the store's own sheet — not a failure.
  final bool canceled;

  /// Only set when the server said why it refused, already in the
  /// player's language. Null means "say the generic thing".
  final String? message;

  PurchaseResult({
    required this.productId,
    required this.success,
    this.grantedCoins = 0,
    this.canceled = false,
    this.message,
  });
}
