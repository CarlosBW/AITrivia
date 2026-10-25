import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/purchase_service.dart';

void main() {
  // `in_app_purchase` only registers a store on Android and Apple devices.
  // Anywhere else — web, Windows — touching it throws instead of answering
  // "no store here", and the shop screen waited forever on that answer:
  // a spinner in place of the themes, which need no store at all.
  group('on a platform with no store', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('reports the store as unavailable instead of throwing', () async {
      expect(await PurchaseService.instance.isAvailable, isFalse);
    });

    test('starting to listen for purchases does not throw', () {
      expect(PurchaseService.instance.start, returnsNormally);
    });
  });

  // The server explains a refused purchase in the player's language ("the
  // payment is still pending", "this purchase was already used"); the shop
  // used to replace that with a generic "the purchase didn't complete".
  group('purchaseFailureMessage', () {
    test('passes on a message the server wrote for the player', () {
      final error = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'El pago todavía está pendiente.',
        details: {'localized': true},
      );
      expect(purchaseFailureMessage(error), 'El pago todavía está pendiente.');
    });

    test('not a technical message', () {
      final error = FirebaseFunctionsException(
        code: 'internal',
        message: 'INTERNAL',
      );
      expect(purchaseFailureMessage(error), isNull);
    });

    test('not any other error', () {
      expect(purchaseFailureMessage(StateError('offline')), isNull);
    });
  });
}
