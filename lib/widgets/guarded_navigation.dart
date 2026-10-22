import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/user_facing_error.dart';

/// Runs [action] — some loading, then usually a `Navigator.push` — and tells
/// the player if it fails or hangs.
///
/// [action] is awaited to the end, and a push only completes when the
/// screen it opened is closed. So the clock would keep running on that
/// screen, and [limit] seconds into a challenge that is going fine the
/// player was told the action took too long. Running out of time only
/// means a hang while the caller's own screen is still the one on top.
Future<void> runGuardedNavigation(
  BuildContext context,
  Future<void> Function() action, {
  required String timeoutMessage,
  Duration limit = const Duration(seconds: 12),
}) async {
  try {
    await action().timeout(limit);
  } on TimeoutException {
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;

    // The message itself, not the exception: its toString() starts with
    // its own class name, which is how "TimeoutLa acción…" got on screen.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(timeoutMessage)),
    );
  } catch (e) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userFacingError(AppLocalizations.of(context), e),
        ),
      ),
    );
  }
}
