import 'package:flutter/material.dart';

import '../app/app.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/account_link_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import 'google_logo.dart';

/// Offers the sign-ins the player can save their game under.
///
/// Returns true when the current game ended up saved. When the sign-in
/// turns out to own a different, already-saved game and the player chooses
/// it, the app restarts into that game and this never returns.
///
/// [recovering] is the first-launch "I already have an account" entry:
/// the wording asks to sign in rather than to save, and switching needs no
/// confirmation because the guest it replaces has nothing in it yet.
Future<bool> showSaveProgressSheet(
  BuildContext context, {
  bool recovering = false,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SaveProgressSheet(recovering: recovering),
  );
  return saved ?? false;
}

class _SaveProgressSheet extends StatefulWidget {
  const _SaveProgressSheet({required this.recovering});

  final bool recovering;

  @override
  State<_SaveProgressSheet> createState() => _SaveProgressSheetState();
}

class _SaveProgressSheetState extends State<_SaveProgressSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _link(AccountProvider provider) async {
    if (_busy) return;

    final l10n = AppLocalizations.of(context);
    final service = AccountLinkService.instance;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final outcome = await service.link(provider);
      if (!mounted) return;

      switch (outcome) {
        case LinkCancelled():
          break;
        case LinkSaved():
          Navigator.pop(context, true);
          return;
        case LinkFoundSavedGame(:final credential):
          final confirmed = widget.recovering || await _confirmSwitch();
          if (!confirmed || !mounted) break;

          await service.switchToSavedAccount(credential);
          _restartApp();
          return;
      }
    } catch (_) {
      // A switch that got as far as deleting the guest leaves nobody
      // signed in. Nothing on screen belongs to anyone at that point, so
      // start over rather than show an error over a dead session.
      if (!service.hasSession) {
        _restartApp();
        return;
      }
      if (mounted) setState(() => _error = l10n.saveProgressError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmSwitch() async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.saveProgressSwitchTitle),
        content: Text(l10n.saveProgressSwitchBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.saveProgressSwitchConfirm,
              style: TextStyle(color: context.appColors.danger),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Same restart the profile screen does after deleting an account: the
  /// whole tree was built for a user who is no longer the one signed in.
  void _restartApp() {
    ThemeService.instance.stop();
    runApp(const TriviaIAApp());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final providers = AccountLinkService.instance.availableProviders;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.recovering
                  ? l10n.saveProgressRecoverTitle
                  : l10n.saveProgressTitle,
              textAlign: TextAlign.center,
              style: context.heading(22),
            ),
            const SizedBox(height: 10),
            Text(
              widget.recovering
                  ? l10n.saveProgressRecoverBody
                  : l10n.saveProgressBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            for (final provider in providers) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _link(provider),
                icon: provider == AccountProvider.apple
                    ? const Icon(Icons.apple)
                    : const GoogleLogo(),
                label: Text(
                  provider == AccountProvider.apple
                      ? l10n.saveProgressWithApple
                      : l10n.saveProgressWithGoogle,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
