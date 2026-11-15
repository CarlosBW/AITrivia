import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/lives_format.dart';
import '../theme/app_theme.dart';

/// How long the celebration stays up when the player doesn't tap it away.
const Duration coinsEarnedCelebrationTime = Duration(milliseconds: 2200);

/// Shows the player the coins they just earned: the pile of coins popping
/// in over the screen, with the amount under it.
///
/// For a reward that arrives on its own, some seconds after what earned it
/// (an ad's coins come from the server once AdMob reports the ad). Without
/// this the only sign was a number changing in a corner. Call it when the
/// coins have actually landed, not when they were asked for.
///
/// Closes by itself after [coinsEarnedCelebrationTime], or on a tap.
Future<void> showCoinsEarned(BuildContext context, int coins) {
  return _showEarned(
    context,
    illustration: 'assets/illustrations/coins.png',
    label: AppLocalizations.of(context).coinShopPurchaseSuccess(coins),
    accent: context.appColors.reward,
  );
}

/// The same for lives, given in life units (two to a life) so half a life
/// reads as one. Like the coins: call it once the lives have landed, with
/// what was really gained — an ad's lives stop at the maximum.
Future<void> showLivesEarned(BuildContext context, int lifeUnits) {
  final l10n = AppLocalizations.of(context);
  return _showEarned(
    context,
    illustration: 'assets/illustrations/hearts.png',
    label: '+${l10n.homeLivesSuffix(l10n.lives(lifeUnits))}',
    accent: context.appColors.danger,
  );
}

Future<void> _showEarned(
  BuildContext context, {
  required String illustration,
  required String label,
  required Color accent,
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, _, __) => _Earned(
      illustration: illustration,
      label: label,
      accent: accent,
    ),
    transitionBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.elasticOut),
          ),
          child: child,
        ),
      );
    },
  );
}

class _Earned extends StatefulWidget {
  const _Earned({
    required this.illustration,
    required this.label,
    required this.accent,
  });

  /// An asset under `assets/illustrations/`.
  final String illustration;

  /// What was earned, as the player reads it: "+15 monedas".
  final String label;

  /// The reward's own colour: gold for coins, red for lives.
  final Color accent;

  @override
  State<_Earned> createState() => _EarnedState();
}

class _EarnedState extends State<_Earned> {
  late final Timer _close;

  @override
  void initState() {
    super.initState();
    _close = Timer(coinsEarnedCelebrationTime, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _close.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent;

    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(context.radii.lg),
              border: Border.all(color: accent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 28,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  widget.illustration,
                  width: 132,
                  height: 132,
                  cacheWidth:
                      (132 * MediaQuery.devicePixelRatioOf(context)).round(),
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.coinsEarnedTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: context.heading(
                    30,
                    color: readableInk(accent, scheme.surface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
