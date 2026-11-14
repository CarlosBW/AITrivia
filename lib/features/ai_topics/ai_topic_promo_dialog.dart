import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/result_hero_banner.dart';

/// Shows the custom-topic reminder. Resolves to true if the player chose to
/// create one.
Future<bool?> showAiTopicPromo(BuildContext context, {int freePasses = 0}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, _, __) => AiTopicPromoDialog(
      freePasses: freePasses,
      onCreate: () => Navigator.pop(context, true),
      onLater: () => Navigator.pop(context, false),
    ),
    // Pops in rather than fading: it is meant to be noticed.
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: child,
      ),
    ),
  );
}

/// The reminder that custom topics exist, and where: the theme's hero
/// banner with the feature's own illustration, what it does, and where to
/// find it on Home.
class AiTopicPromoDialog extends StatelessWidget {
  const AiTopicPromoDialog({
    super.key,
    required this.onCreate,
    required this.onLater,
    this.freePasses = 0,
  });

  final VoidCallback onCreate;
  final VoidCallback onLater;

  /// Free topics the player still has; shown as a badge when there are any.
  final int freePasses;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onHero = context.appColors.onAccent;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResultHeroBanner(
                sparkles: true,
                child: Column(
                  children: [
                    // Bounces in a beat after the card does.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.4, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.elasticOut,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Image.asset(
                        'assets/illustrations/ai_topic.png',
                        width: 112,
                        height: 112,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.aiTopicPromoTitle,
                      textAlign: TextAlign.center,
                      style: context.heading(26, color: onHero),
                    ),
                    if (freePasses > 0) ...[
                      const SizedBox(height: 10),
                      HeroBadge(
                        label: l10n.homeFreeTopicPasses(freePasses),
                        icon: Icons.card_giftcard_rounded,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(context.radii.md),
                  border: context.surfaces.borderOr(null),
                  boxShadow: context.surfaces.shadowsOr(null),
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.aiTopicPromoBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Where the option lives, so it can be found again.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(context.radii.sm),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.home_rounded,
                            size: 20,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.aiTopicPromoWhere,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(l10n.aiTopicPromoCta),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: onLater,
                        child: Text(l10n.aiTopicPromoLater),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
