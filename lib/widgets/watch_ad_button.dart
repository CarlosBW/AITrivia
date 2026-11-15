import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/ad_reward_service.dart';
import '../services/ad_rewards.dart';

/// "Watch an ad" for a reward: shows the ad and tells the player how it
/// went.
///
/// Draws nothing where this build has no ads (web, desktop, a release
/// without ad units) or when [leftToday] says today's allowance is spent,
/// so a screen can place it without asking either question itself.
///
/// The reward isn't granted here — the server pays once AdMob reports the
/// ad as watched, a few seconds later. [onEarned] is for a screen that has
/// to do something when it lands, such as letting a level go on.
class WatchAdButton extends StatefulWidget {
  const WatchAdButton({
    super.key,
    required this.kind,
    required this.label,
    this.leftToday,
    this.enabled = true,
    this.onEarned,
    this.onBusyChanged,
  });

  final AdRewardKind kind;
  final String label;

  /// How many more ads of this kind pay today, when the screen knows it.
  final int? leftToday;
  final bool enabled;

  /// The ad was watched to the end; the reward is on its way.
  final VoidCallback? onEarned;

  /// True while an ad is loading or showing.
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<WatchAdButton> createState() => _WatchAdButtonState();
}

class _WatchAdButtonState extends State<WatchAdButton> {
  bool _busy = false;

  bool get _offered =>
      AdRewardService.instance.supported && (widget.leftToday ?? 1) > 0;

  @override
  void initState() {
    super.initState();
    // So the ad opens on the tap rather than after a wait.
    if (_offered) AdRewardService.instance.preload();
  }

  void _setBusy(bool busy) {
    if (mounted) setState(() => _busy = busy);
    widget.onBusyChanged?.call(busy);
  }

  Future<void> _watch() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    _setBusy(true);
    final result = await AdRewardService.instance.watch(widget.kind);
    _setBusy(false);

    final message = switch (result) {
      AdWatchResult.earned => l10n.adRewardOnItsWay,
      AdWatchResult.unavailable => l10n.adUnavailable,
      AdWatchResult.capReached => l10n.adCapReached,
      // Closed early by choice: nothing to explain.
      AdWatchResult.dismissed => null,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    if (result == AdWatchResult.earned) widget.onEarned?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_offered) return const SizedBox.shrink();

    return FilledButton.tonalIcon(
      onPressed: widget.enabled && !_busy ? _watch : null,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.smart_display_rounded, size: 20),
      label: Text(widget.label),
    );
  }
}
