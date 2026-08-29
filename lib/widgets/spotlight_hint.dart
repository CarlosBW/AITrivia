import 'dart:async';

import 'package:flutter/material.dart';

import '../services/spotlight_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Wraps [child] with a one-time "spotlight" coach mark: the first time this
/// widget is built on a given device, a darkened overlay appears with a
/// cutout around [child] and a tooltip bubble explaining what it does.
/// Never shows again afterward (tracked by [SpotlightService]).
///
/// Use this for sections a new player wouldn't otherwise understand at a
/// glance — a whole feature screen's main action, not routine buttons.
class SpotlightHint extends StatefulWidget {
  final String id;
  final String title;
  final String description;
  final Widget child;

  const SpotlightHint({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  State<SpotlightHint> createState() => _SpotlightHintState();
}

class _SpotlightHintState extends State<SpotlightHint> {
  final _targetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    final alreadySeen = await SpotlightService.instance.hasSeen(widget.id);
    if (alreadySeen || !mounted) return;

    // Give layout one more frame to settle (e.g. after a StreamBuilder's
    // first data arrives and reflows the target) before measuring it.
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    await SpotlightOverlayController.show(
      context: context,
      targetKey: _targetKey,
      title: widget.title,
      description: widget.description,
    );

    await SpotlightService.instance.markSeen(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _targetKey, child: widget.child);
  }
}

/// Shows the spotlight overlay for a target identified by [targetKey], and
/// completes once the player dismisses it.
class SpotlightOverlayController {
  SpotlightOverlayController._();

  static Future<void> show({
    required BuildContext context,
    required GlobalKey targetKey,
    required String title,
    required String description,
  }) {
    final renderObject = targetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return Future.value();
    }

    final targetPosition = renderObject.localToGlobal(Offset.zero);
    final targetRect = targetPosition & renderObject.size;

    final overlayState = Overlay.of(context);
    final completer = Completer<void>();
    var dismissed = false;
    late OverlayEntry entry;

    void dismiss() {
      if (dismissed) return;
      dismissed = true;
      entry.remove();
      completer.complete();
    }

    entry = OverlayEntry(
      builder: (overlayContext) => _SpotlightScrim(
        targetRect: targetRect,
        title: title,
        description: description,
        buttonLabel: AppLocalizations.of(context).spotlightGotIt,
        onDismiss: dismiss,
      ),
    );

    overlayState.insert(entry);
    return completer.future;
  }
}

class _SpotlightScrim extends StatelessWidget {
  final Rect targetRect;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onDismiss;

  const _SpotlightScrim({
    required this.targetRect,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final holeRect = targetRect.inflate(10);

    final showBubbleBelow = targetRect.top < screenSize.height / 2;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  holeRect: holeRect,
                  scrimColor: Theme.of(context)
                      .colorScheme
                      .scrim
                      .withValues(alpha: 0.78),
                  ringColor: context.appColors.onScrim,
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: showBubbleBelow ? holeRect.bottom + 20 : null,
              bottom:
                  showBubbleBelow ? null : screenSize.height - holeRect.top + 20,
              child: _TooltipBubble(
                title: title,
                description: description,
                buttonLabel: buttonLabel,
                onDismiss: onDismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect holeRect;

  /// Painted, not built, so there is no `BuildContext` to read the theme
  /// from here — the colours come in from the widget that mounts it.
  final Color scrimColor;
  final Color ringColor;

  _SpotlightPainter({
    required this.holeRect,
    required this.scrimColor,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final holeRRect = RRect.fromRectAndRadius(holeRect, const Radius.circular(18));

    // Path.combine(PathOperation.difference, ...) isn't reliable on every
    // Flutter renderer (notably Flutter web), so the cutout is punched with
    // saveLayer + BlendMode.clear instead — the standard, portable way to
    // make a hole transparent rather than just outlining it.
    canvas.saveLayer(screenRect, Paint());
    canvas.drawRect(screenRect, Paint()..color = scrimColor);
    canvas.drawRRect(holeRRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawRRect(holeRRect, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.holeRect != holeRect;
  }
}

class _TooltipBubble extends StatelessWidget {
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onDismiss;

  const _TooltipBubble({
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: context.appColors.reward),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: context.heading(17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDismiss,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}
