import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/result_hero_banner.dart';

/// The top of a finished level: the stars, the score and the rank on the
/// theme's hero gradient, like a finished duel.
class LevelResultHero extends StatefulWidget {
  const LevelResultHero({
    super.key,
    required this.title,
    required this.stars,
    required this.correct,
    required this.total,
    required this.rankLabel,
    this.celebration,
  });

  final String title;

  /// Stars earned, 0 to 3.
  final int stars;
  final int correct;
  final int total;
  final String rankLabel;

  /// Drawn over the stars, for a three-star run, once the last one has
  /// filled in.
  final Widget? celebration;

  @override
  State<LevelResultHero> createState() => _LevelResultHeroState();
}

class _LevelResultHeroState extends State<LevelResultHero> {
  bool _starsFilled = false;

  @override
  Widget build(BuildContext context) {
    final onHero = context.appColors.onAccent;
    final title = widget.title;
    final stars = widget.stars;
    final correct = widget.correct;
    final total = widget.total;
    final rankLabel = widget.rankLabel;
    final celebration = widget.celebration;
    final pct = total == 0 ? 0 : (correct * 100 / total).round();

    return ResultHeroBanner(
      sparkles: stars > 0,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              _HeroStars(
                count: stars,
                onFilled: () {
                  if (mounted) setState(() => _starsFilled = true);
                },
              ),
              if (celebration != null && _starsFilled) celebration,
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.heading(30, color: onHero),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: correct),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  '$value',
                  style: context.heading(52, color: onHero),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '/ $total',
                style: context.heading(
                  24,
                  color: onHero.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              HeroBadge(label: '$pct%', icon: Icons.track_changes_rounded),
              HeroBadge(label: rankLabel, icon: Icons.military_tech_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

/// When star [index] (0 to 2) starts filling in, after the result opens.
int starFillStartMs(int index) => 400 + index * 450;

/// How long a star takes to pop once it starts.
const int starPopMs = 450;

/// How many of [count] earned stars have started filling [elapsedMs] in.
int starsFilledAt(int elapsedMs, int count) {
  var filled = 0;
  while (filled < count && elapsedMs >= starFillStartMs(filled)) {
    filled++;
  }
  return filled;
}

/// Three stars on the hero. All start as outlines; the earned ones then
/// fill in one after another, each with a pop, so the player watches the
/// result being counted instead of finding it already there.
class _HeroStars extends StatefulWidget {
  const _HeroStars({required this.count, required this.onFilled});

  final int count;

  /// Called once the last earned star has finished filling.
  final VoidCallback onFilled;

  @override
  State<_HeroStars> createState() => _HeroStarsState();
}

class _HeroStarsState extends State<_HeroStars>
    with SingleTickerProviderStateMixin {
  late final int _totalMs = widget.count <= 0
      ? 1
      : starFillStartMs(widget.count - 1) + starPopMs;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _totalMs),
  );
  int _announced = 0;

  @override
  void initState() {
    super.initState();
    if (widget.count <= 0) return;

    _controller
      ..addListener(_onTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onFilled();
      })
      ..forward();
  }

  /// A tap of haptics as each star lands.
  void _onTick() {
    final filled = starsFilledAt(
      (_controller.value * _totalMs).round(),
      widget.count,
    );
    if (filled > _announced) {
      _announced = filled;
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final starColor = colorOnHero(context, colors.reward);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsedMs = (_controller.value * _totalMs).round();

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final filled = i < starsFilledAt(elapsedMs, widget.count);
            // The middle star sits higher and larger, like a podium.
            final size = i == 1 ? 58.0 : 44.0;

            // From small to a little over its size, then settling.
            final pop = !filled
                ? 1.0
                : 0.5 +
                    0.5 *
                        Curves.elasticOut.transform(
                          ((elapsedMs - starFillStartMs(i)) / starPopMs)
                              .clamp(0.0, 1.0),
                        );

            return Padding(
              padding: EdgeInsets.only(
                left: 4,
                right: 4,
                bottom: i == 1 ? 10 : 0,
              ),
              child: Transform.scale(
                scale: pop,
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  size: size,
                  color: filled
                      ? starColor
                      : colors.onAccent.withValues(alpha: 0.45),
                  shadows: filled
                      ? [
                          Shadow(
                            color: starColor.withValues(alpha: 0.6),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// "Progress saved", as a quiet pill in the theme's success colour.
class ProgressSavedChip extends StatelessWidget {
  const ProgressSavedChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final success = context.appColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.successBg,
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(color: success.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done_rounded, size: 18, color: success),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.onTint(success, 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A short explanation under the rewards (already passed, not enough to
/// pass), in the theme's colours rather than a stock orange.
class ResultNote extends StatelessWidget {
  const ResultNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
