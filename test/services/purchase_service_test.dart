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
}
