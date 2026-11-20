import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/practice_pack_service.dart';
import '../../theme/app_theme.dart';
import 'practice_round_screen.dart';

/// Whether the offline screen covers the app: while the phone has no
/// connection, and after it is back for as long as a practice round is
/// still open, so the round isn't pulled from under the player.
bool offlineGateShown({required bool offline, required bool practising}) =>
    offline || practising;

/// Covers the app while the phone has no connection.
///
/// Everything in the game goes through the server, so offline none of it
/// works; rather than let each screen fail in its own way, this says so
/// once and offers the one thing that does work: practice rounds. The app
/// underneath is kept as it was and shows again when the connection does.
///
/// Sits in `MaterialApp.builder`, above the app's navigator, and brings a
/// navigator of its own for the practice round.
class OfflineGate extends StatefulWidget {
  const OfflineGate({
    super.key,
    required this.offline,
    required this.child,
    this.hasPack,
    this.loadRound,
  });

  final ValueListenable<bool> offline;
  final Widget child;

  /// Whether the phone has questions to practise with, and the next round
  /// of them. From [PracticePackService] when left out.
  final Future<bool> Function()? hasPack;
  final Future<List<Map<String, dynamic>>> Function()? loadRound;

  @override
  State<OfflineGate> createState() => _OfflineGateState();
}

class _OfflineGateState extends State<OfflineGate> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  bool _practising = false;

  Future<void> _practise() async {
    setState(() => _practising = true);
    await _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeRoundScreen(
          loadRound:
              widget.loadRound ?? PracticePackService.instance.nextRound,
          offline: widget.offline,
        ),
      ),
    );
    if (mounted) setState(() => _practising = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.offline,
      child: widget.child,
      builder: (context, offline, child) {
        final shown =
            offlineGateShown(offline: offline, practising: _practising);

        return Stack(
          children: [
            // Kept in the tree, so coming back online finds it as it was.
            child!,
            if (shown)
              Positioned.fill(
                child: NavigatorPopHandler(
                  onPopWithResult: (_) => _navigator.currentState?.maybePop(),
                  // The app's navigator already has the hero controller.
                  child: HeroControllerScope.none(
                    child: Navigator(
                      key: _navigator,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => OfflineNotice(
                          hasPack: widget.hasPack ??
                              PracticePackService.instance.hasPack,
                          onPractise: _practise,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// What the player reads with no connection: that only practice rounds
/// work until it is back, and the way into one.
class OfflineNotice extends StatefulWidget {
  const OfflineNotice({
    super.key,
    required this.hasPack,
    required this.onPractise,
  });

  final Future<bool> Function() hasPack;
  final VoidCallback onPractise;

  @override
  State<OfflineNotice> createState() => _OfflineNoticeState();
}

class _OfflineNoticeState extends State<OfflineNotice> {
  late final Future<bool> _hasPack = widget.hasPack();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.wifi_off_rounded, size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  l10n.offlineTitle,
                  textAlign: TextAlign.center,
                  style: context.heading(26),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.offlineBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.offlineAutoReturn,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FutureBuilder<bool>(
                  future: _hasPack,
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox(height: 48);
                    if (snap.data != true) {
                      return Text(
                        l10n.offlineNoPack,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      );
                    }
                    return FilledButton.icon(
                      onPressed: widget.onPractise,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l10n.offlinePractise),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
