import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_themes.dart';

/// Owns which theme is equipped, and buying the ones that aren't free.
///
/// Split the way [LocaleController] is: the equipped id lives in a
/// [ValueNotifier] the root `MaterialApp` listens to, so equipping repaints
/// the whole app without any screen having to know. Ownership itself is
/// server-granted — see `purchaseTheme` in `functions/src/index.ts`.
class ThemeService {
  ThemeService._();

  static final ThemeService instance = ThemeService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The theme the app is currently painted with.
  final ValueNotifier<String> equippedThemeId =
      ValueNotifier(AppThemes.defaultId);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  String? _watchedUid;

  /// Which themes a player owns, read from their user doc.
  ///
  /// The free theme is always in the list even when the field is missing:
  /// a doc created before themes existed carries nothing, and that has to
  /// mean "owns the default", not "owns nothing".
  static Set<String> ownedThemeIds(Map<String, dynamic>? userData) {
    // Comprobado, no casteado: `as List?` lanza si el campo trae otro tipo,
    // y un campo mal escrito debe ignorarse, no tumbar la pantalla.
    final raw = userData?['ownedThemes'];
    final stored = raw is List ? raw : const [];

    return {
      AppThemes.defaultId,
      ...stored.map((id) => id.toString()).where(AppThemes.exists),
      // A theme that costs nothing is owned by definition; listing it in
      // Firestore would be storing a fact that is already true.
      ...AppThemes.all.where((spec) => spec.isFree).map((spec) => spec.id),
    };
  }

  /// The equipped theme id, falling back to the default when the field is
  /// missing or names a theme this build doesn't know.
  static String equippedIdFrom(Map<String, dynamic>? userData) {
    final stored = (userData?['equippedTheme'] ?? '').toString();
    return AppThemes.exists(stored) ? stored : AppThemes.defaultId;
  }

  /// Follows the signed-in player's equipped theme.
  ///
  /// Held as a subscription on the service rather than a `StreamBuilder`
  /// high in the tree: the theme has to be known before `MaterialApp`
  /// builds, and re-subscribing on every rebuild would re-read the doc.
  void watch(String uid) {
    if (_watchedUid == uid) return;

    _userSub?.cancel();
    _watchedUid = uid;

    _userSub = _db.collection('users').doc(uid).snapshots().listen(
      (snap) => equippedThemeId.value = equippedIdFrom(snap.data()),
      onError: (_) {},
    );
  }

  /// Stops following and goes back to the default — used on sign-out, so a
  /// player's purchased theme doesn't linger for the next account.
  void stop() {
    _userSub?.cancel();
    _userSub = null;
    _watchedUid = null;
    equippedThemeId.value = AppThemes.defaultId;
  }

  /// Equips an already-owned theme.
  ///
  /// A direct write, not a callable: `equippedTheme` is cosmetic, and
  /// firestore.rules already refuses to point it at a theme the player
  /// doesn't own — the same shape as equipping a frame.
  Future<void> equip(String themeId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !AppThemes.exists(themeId)) return;

    // Optimistic: the snapshot listener will confirm it, but waiting for
    // the round trip would leave the store visibly lagging the tap.
    equippedThemeId.value = themeId;

    await _db.collection('users').doc(uid).set(
      {'equippedTheme': themeId, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Buys a theme through the `purchaseTheme` callable and equips it.
  ///
  /// The price is not sent: the server reads it from its own table, the
  /// same way every other coin path in this app refuses to trust a
  /// client-reported amount.
  Future<PurchaseThemeResult> purchase(String themeId) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'purchaseTheme',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );

    final response = await callable.call({'themeId': themeId});
    final data = Map<String, dynamic>.from(response.data as Map);

    final result = PurchaseThemeResult(
      themeId: (data['themeId'] ?? themeId).toString(),
      coins: ((data['coins'] ?? 0) as num).toInt(),
      alreadyOwned: data['alreadyOwned'] == true,
    );

    await equip(result.themeId);
    return result;
  }
}

class PurchaseThemeResult {
  const PurchaseThemeResult({
    required this.themeId,
    required this.coins,
    required this.alreadyOwned,
  });

  final String themeId;

  /// The player's balance after the purchase, as the server computed it.
  final int coins;
  final bool alreadyOwned;
}
