import 'package:flutter/foundation.dart';

/// What a player can earn by watching an ad. The name is what the server
/// reads from the ad's `custom_data`, so it must match `AdRewardKind` in
/// functions/src/ad_rewards.ts.
enum AdRewardKind { lives, coins }

/// What watching an ad pays, how many count per day, and which ad unit
/// shows it.
///
/// The figures mirror `AD_REWARDS` in functions/src/ad_rewards.ts, which is
/// what actually pays; `test/services/ad_rewards_sync_test.dart` keeps the
/// two from drifting apart. Nothing here grants anything: the reward comes
/// from AdMob's servers calling ours, never from this app saying an ad was
/// watched.
class AdRewards {
  AdRewards._();

  /// Lives one ad pays (six units on the server, two per life).
  static const int livesPerAd = 3;
  static const int livesDailyCap = 5;

  static const int coinsPerAd = 15;
  static const int coinsDailyCap = 5;

  /// This app's rewarded ad units in AdMob. Left empty, a release build
  /// offers no ads at all. The server pays only for the units listed in
  /// `ADMOB_REWARDED_AD_UNITS` (in `functions/.env.<project>`), so the two
  /// must name the same ones.
  static const String androidAdUnitId =
      'ca-app-pub-8705386398614418/3795043144';
  static const String iosAdUnitId =
      'ca-app-pub-8705386398614418/6646448090';

  /// Google's public test units, which always fill and never earn money.
  static const String _androidTestAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _iosTestAdUnitId =
      'ca-app-pub-3940256099942544/1712485313';

  static int dailyCap(AdRewardKind kind) =>
      kind == AdRewardKind.lives ? livesDailyCap : coinsDailyCap;
}

/// How long a screen waiting on lives from an ad keeps looking for them:
/// the server pays when AdMob reports the ad, usually within seconds.
const Duration adLivesPollInterval = Duration(seconds: 2);
const int adLivesPollAttempts = 10;

/// The ad unit to load, or null when this build shows no ads.
///
/// Only the phones have an ads SDK. A debug build uses Google's test units
/// whatever is configured: tapping a real ad while developing gets an AdMob
/// account suspended. A release build with no unit configured has nothing
/// to show.
String? rewardedAdUnitId({
  required TargetPlatform platform,
  required bool isWeb,
  required bool debugBuild,
  String androidAdUnitId = AdRewards.androidAdUnitId,
  String iosAdUnitId = AdRewards.iosAdUnitId,
}) {
  if (isWeb) return null;

  final String configured;
  final String test;
  switch (platform) {
    case TargetPlatform.android:
      configured = androidAdUnitId;
      test = AdRewards._androidTestAdUnitId;
    case TargetPlatform.iOS:
      configured = iosAdUnitId;
      test = AdRewards._iosTestAdUnitId;
    default:
      return null;
  }

  if (debugBuild) return test;
  return configured.isEmpty ? null : configured;
}

/// The server's date id for [now]: its day runs on UTC.
String adRewardsDateId(DateTime now) {
  final utc = now.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

/// How many more ads of [kind] will pay today, from the counts the server
/// keeps on the user doc. Counts from another day are that day's.
///
/// Only for what to offer: the server decides again when the ad is
/// watched. Offering an ad that would pay nothing is the thing to avoid.
int adRewardsLeftToday(
  Map<String, dynamic> userData,
  AdRewardKind kind, {
  required DateTime now,
}) {
  final cap = AdRewards.dailyCap(kind);
  return (cap - adRewardsPaidToday(userData, kind, now: now)).clamp(0, cap);
}

/// How many ads of [kind] the server has paid today, from the same counts.
/// Zero when the counts are another day's.
int adRewardsPaidToday(
  Map<String, dynamic> userData,
  AdRewardKind kind, {
  required DateTime now,
}) {
  if (userData['adRewardsDate'] != adRewardsDateId(now)) return 0;

  final raw = userData[
      kind == AdRewardKind.lives ? 'adLivesToday' : 'adCoinsToday'];
  return raw is num && raw > 0 ? raw.toInt() : 0;
}

/// How many ads of [kind] were paid between two readings of the user doc:
/// what a screen watching the doc has just seen land. Zero when nothing
/// new was paid.
int adRewardsJustPaid(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
  AdRewardKind kind, {
  required DateTime now,
}) {
  final paid = adRewardsPaidToday(after, kind, now: now) -
      adRewardsPaidToday(before, kind, now: now);
  return paid > 0 ? paid : 0;
}
