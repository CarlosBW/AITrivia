import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/result_share.dart';

/// "Share result": hands the phone's share sheet a picture of the result
/// card and a line of text with the store link.
///
/// [cardKey] is the key of a `RepaintBoundary` wrapped around what should
/// appear in the picture. If the picture can't be made, the text is shared
/// on its own rather than nothing.
class ShareResultButton extends StatefulWidget {
  const ShareResultButton({
    super.key,
    required this.cardKey,
    required this.message,
  });

  final GlobalKey cardKey;

  /// What the player says with it, without the link.
  final String message;

  @override
  State<ShareResultButton> createState() => _ShareResultButtonState();
}

class _ShareResultButtonState extends State<ShareResultButton> {
  bool _sharing = false;

  Future<Uint8List?> _picture() async {
    try {
      final boundary = widget.cardKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    // The iPad anchors its share sheet to the button that opened it.
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final text = shareTextWithLink(
      widget.message,
      shareLinkFor(defaultTargetPlatform),
    );

    try {
      final picture = await _picture();
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: picture == null
              ? null
              : [
                  XFile.fromData(
                    picture,
                    mimeType: 'image/png',
                    name: 'triviaia.png',
                  ),
                ],
          fileNameOverrides: picture == null ? null : const ['triviaia.png'],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      // Nothing to tell: the sheet didn't open, and the result is still
      // on screen.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _sharing ? null : _share,
      icon: const Icon(Icons.ios_share_rounded, size: 20),
      label: Text(AppLocalizations.of(context).shareResult),
    );
  }
}
