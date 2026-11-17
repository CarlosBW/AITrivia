import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_rewards.dart';

/// How an attempt to watch an ad for a reward ended.
enum AdWatchResult {
  /// Watched to the end. The reward is on its way from the server.
  earned,

  /// Closed before the end: nothing is owed.
  dismissed,

  /// No ad could be shown (none available, no connection, no consent).
  unavailable,

  /// Today's allowance for this reward is already spent.
  capReached,
}

/// Rewarded ads: loads one ahead of time and shows it.
///
/// Showing an ad pays nothing by itself. Each ad carries the player's uid
/// and the reward it is for, and AdMob's servers report it to ours once it
/// has been watched (`admobRewardCallback`); the lives or coins then appear
/// on the user doc like any other server-side change.
class AdRewardService {
  AdRewardService._();

  static final AdRewardService instance = AdRewardService._();

  static const Duration _loadTimeout = Duration(seconds: 15);

  Future<bool>? _ready;
  RewardedAd? _loaded;

  /// Why the last attempt to get an ad failed, as a short code for the
  /// "no ads right now" message: without it a player's report says only
  /// that there was no ad, and nothing tells no fill from no consent from
  /// a wrong ad unit. Null once an ad loads.
  ///
  /// `C` consent not given or not resolved, `I` the SDK didn't start, `T`
  /// no answer in time, `S<n>` it loaded but wouldn't show, and a bare
  /// number is AdMob's own load error code.
  String? get lastFailure => _lastFailure;
  String? _lastFailure;
  Future<RewardedAd?>? _loading;

  String? get _adUnitId => rewardedAdUnitId(
        platform: defaultTargetPlatform,
        isWeb: kIsWeb,
        debugBuild: kDebugMode,
      );

  /// Whether this build shows ads at all. False on web and desktop, and in
  /// a release build until its ad units are configured.
  bool get supported => _adUnitId != null;

  /// Loads an ad so the next [watch] opens at once. Safe to call whenever
  /// an offer to watch one is about to be shown.
  void preload() {
    if (!supported || _loaded != null) return;
    unawaited(_load());
  }

  /// Shows an ad for [kind] and reports how it ended.
  Future<AdWatchResult> watch(AdRewardKind kind) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!supported || uid == null) return AdWatchResult.unavailable;

    if (await _leftToday(uid, kind) <= 0) return AdWatchResult.capReached;

    final ad = _loaded ?? await _load();
    if (ad == null) return AdWatchResult.unavailable;
    _loaded = null;

    final done = Completer<AdWatchResult>();
    var earned = false;

    void finish(AdWatchResult result) {
      ad.dispose();
      if (!done.isCompleted) done.complete(result);
      // The next one, for the next offer.
      preload();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) =>
          finish(earned ? AdWatchResult.earned : AdWatchResult.dismissed),
      onAdFailedToShowFullScreenContent: (_, error) {
        _lastFailure = 'S${error.code}';
        finish(AdWatchResult.unavailable);
      },
    );

    try {
      // What the server pays against: who watched, and what for.
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: uid, customData: kind.name),
      );
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
    } catch (_) {
      finish(AdWatchResult.unavailable);
    }

    return done.future;
  }

  Future<int> _leftToday(String uid, AdRewardKind kind) async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return adRewardsLeftToday(
        snap.data() ?? const {},
        kind,
        now: DateTime.now(),
      );
    } catch (_) {
      // Unknown, so not refused here: the server has the last word.
      return AdRewards.dailyCap(kind);
    }
  }

  /// Consent first, then the SDK. Asked once per run; a consent form is
  /// only shown where the law asks for one, and is set up in AdMob.
  Future<bool> _ensureReady() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    try {
      final consent = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired(
          (_) => consent.complete(),
        ),
        // Without an answer the SDK falls back on the last one it had.
        (_) => consent.complete(),
      );
      await consent.future.timeout(_loadTimeout, onTimeout: () {});

      if (!await ConsentInformation.instance.canRequestAds()) {
        _ready = null;
        _lastFailure = 'C';
        return false;
      }

      await MobileAds.instance.initialize();
      return true;
    } catch (_) {
      _ready = null;
      _lastFailure = 'I';
      return false;
    }
  }

  Future<RewardedAd?> _load() => _loading ??= _loadOne().whenComplete(() {
        _loading = null;
      });

  Future<RewardedAd?> _loadOne() async {
    final adUnitId = _adUnitId;
    if (adUnitId == null || !await _ensureReady()) return null;

    final loaded = Completer<RewardedAd?>();
    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (loaded.isCompleted) {
              ad.dispose();
            } else {
              loaded.complete(ad);
            }
          },
          onAdFailedToLoad: (error) {
            _lastFailure = '${error.code}';
            if (!loaded.isCompleted) loaded.complete(null);
          },
        ),
      );
    } catch (_) {
      if (!loaded.isCompleted) loaded.complete(null);
    }

    final ad = await loaded.future.timeout(_loadTimeout, onTimeout: () {
      _lastFailure = 'T';
      return null;
    });
    if (ad == null && !loaded.isCompleted) loaded.complete(null);
    if (ad != null) _lastFailure = null;
    return _loaded = ad;
  }
}
