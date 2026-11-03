import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// One stop of [NavTour]: the bottom-bar item to tap, and what the section
/// it opens is for.
class NavTourStep {
  final int tabIndex;
  final GlobalKey targetKey;
  final String tabName;
  final String title;
  final String description;

  /// Explains from the top of the screen rather than just above the bar,
  /// when what the text points at sits low in the section.
  final bool explainAtTop;

  const NavTourStep({
    required this.tabIndex,
    required this.targetKey,
    required this.tabName,
    required this.title,
    required this.description,
    this.explainAtTop = false,
  });
}

/// A first-visit walk through the bottom bar, laid over the whole shell.
///
/// Each step darkens the screen around one bar item and waits for the
/// player to tap it — only that item counts — then opens its tab through
/// [onSelectTab] and explains it over a lighter scrim, so the section shows
/// through behind the text. Unlike [SpotlightHint] it shows nothing on its
/// own: the shell decides when the tour runs.
class NavTour extends StatefulWidget {
  final List<NavTourStep> steps;
  final ValueChanged<int> onSelectTab;

  /// Called once, when the last step is done or the tour is skipped.
  final VoidCallback onFinished;

  const NavTour({
    super.key,
    required this.steps,
    required this.onSelectTab,
    required this.onFinished,
  });

  @override
  State<NavTour> createState() => _NavTourState();
}

class _NavTourState extends State<NavTour> with SingleTickerProviderStateMixin {
  int _step = 0;
  bool _explaining = false;
  bool _finished = false;
  Rect? _hole;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  NavTourStep get _current => widget.steps[_step];

  @override
  void initState() {
    super.initState();
    _measureSoon();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// The bar is laid out before this frame ends, not before this build.
  void _measureSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _current.targetKey.currentContext?.findRenderObject();
      final self = context.findRenderObject();
      if (target is! RenderBox || !target.attached || self is! RenderBox) {
        return;
      }
      final topLeft = self.globalToLocal(target.localToGlobal(Offset.zero));
      final bounds = topLeft & target.size;
      // A square on the icon rather than the whole item: a bar cell is a
      // fifth of the screen wide, and the end ones run off its edges.
      setState(() => _hole = Rect.fromCenter(
            center: bounds.center,
            width: bounds.shortestSide + 14,
            height: bounds.shortestSide + 14,
          ));
    });
  }

  void _handleTap(TapUpDetails details) {
    final hole = _hole;
    if (_explaining || hole == null || !hole.contains(details.localPosition)) {
      return;
    }
    widget.onSelectTab(_current.tabIndex);
    setState(() => _explaining = true);
  }

  void _next() {
    if (_step == widget.steps.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _step++;
      _explaining = false;
    });
    _measureSoon();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hole = _hole;
    final screenSize = MediaQuery.sizeOf(context);
    final scrim = Theme.of(context).colorScheme.scrim;
    final progress = l10n.navTourProgress(_step + 1, widget.steps.length);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _TourScrimPainter(
                    hole: hole,
                    // Lighter while explaining: the tab just opened is
                    // what the text is about.
                    scrimColor:
                        scrim.withValues(alpha: _explaining ? 0.62 : 0.8),
                    ringColor: context.appColors.reward,
                    pulse: _explaining ? 0 : _pulse.value,
                  ),
                ),
              ),
            ),
            if (hole != null && _explaining)
              Positioned(
                left: 16,
                right: 16,
                top: _current.explainAtTop
                    ? MediaQuery.paddingOf(context).top + 72
                    : null,
                bottom: _current.explainAtTop
                    ? null
                    : screenSize.height - hole.top + 18,
                child: _TourCard(
                  progress: progress,
                  title: _current.title,
                  description: _current.description,
                  actionLabel: _step == widget.steps.length - 1
                      ? l10n.navTourDone
                      : l10n.navTourNext,
                  onAction: _next,
                ),
              ),
            if (hole != null && !_explaining) ...[
              Positioned(
                left: 16,
                right: 16,
                bottom: screenSize.height - hole.top + 54,
                child: _TapPrompt(
                  progress: progress,
                  prompt: l10n.navTourTapPrompt(_current.tabName),
                  skipLabel: l10n.navTourSkip,
                  onSkip: _finish,
                ),
              ),
              // Over the lit icon, wherever along the bar it is.
              Positioned(
                left: hole.center.dx - 18,
                bottom: screenSize.height - hole.top + 10,
                child: Icon(
                  Icons.south,
                  color: context.appColors.reward,
                  size: 36,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TapPrompt extends StatelessWidget {
  final String progress;
  final String prompt;
  final String skipLabel;
  final VoidCallback onSkip;

  const _TapPrompt({
    required this.progress,
    required this.prompt,
    required this.skipLabel,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // On a card, not straight on the scrim: the tab behind still shows
    // through it, and its text muddled the prompt's.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Column(
        children: [
          Text(
            progress,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            prompt,
            textAlign: TextAlign.center,
            style: context.heading(19),
          ),
          TextButton(onPressed: onSkip, child: Text(skipLabel)),
        ],
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  final String progress;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  const _TourCard({
    required this.progress,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.35),
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
              Expanded(child: Text(title, style: context.heading(19))),
              Text(
                progress,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(fontSize: 15, height: 1.35)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ),
        ],
      ),
    );
  }
}

class _TourScrimPainter extends CustomPainter {
  final Rect? hole;
  final Color scrimColor;
  final Color ringColor;

  /// 0..1, how far the ring around the hole has swelled.
  final double pulse;

  _TourScrimPainter({
    required this.hole,
    required this.scrimColor,
    required this.ringColor,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Offset.zero & size;
    final hole = this.hole;
    if (hole == null) {
      canvas.drawRect(screenRect, Paint()..color = scrimColor);
      return;
    }

    final holeRRect = RRect.fromRectAndRadius(hole, const Radius.circular(18));

    // The same saveLayer + BlendMode.clear cutout as SpotlightHint, which
    // works on every renderer where Path.combine doesn't.
    canvas.saveLayer(screenRect, Paint());
    canvas.drawRect(screenRect, Paint()..color = scrimColor);
    canvas.drawRRect(holeRRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawRRect(
      holeRRect.inflate(pulse * 6),
      Paint()
        ..color = ringColor.withValues(alpha: 1 - pulse * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _TourScrimPainter old) =>
      old.hole != hole ||
      old.pulse != pulse ||
      old.scrimColor != scrimColor ||
      old.ringColor != ringColor;
}
