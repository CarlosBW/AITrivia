import 'package:flutter/foundation.dart';

/// Where a shared result sends the people who see it.
class ShareLinks {
  ShareLinks._();

  static const String android =
      'https://play.google.com/store/apps/details?id=pe.massivedynamics.triviaia';

  /// The App Store page, once the app has one. Empty until then, and a
  /// result shared from an iPhone carries the Play link's absence rather
  /// than a link that leads nowhere.
  static const String ios = '';
}

/// The store link to add to a result shared from [platform], or null when
/// that platform has none to give.
String? shareLinkFor(
  TargetPlatform platform, {
  String android = ShareLinks.android,
  String ios = ShareLinks.ios,
}) {
  final link = switch (platform) {
    TargetPlatform.android => android,
    TargetPlatform.iOS => ios,
    _ => '',
  };
  return link.isEmpty ? null : link;
}

/// A shared result's text: the [message], and the store link under it when
/// there is one.
String shareTextWithLink(String message, String? link) {
  return link == null ? message : '$message\n$link';
}
