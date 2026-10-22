import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'generated/app_localizations.dart';

/// Error codes that mean the request never got a real answer.
const _connectionCodes = {
  'unavailable',
  'deadline-exceeded',
  'network-request-failed'
};

/// What to tell the player when [error] stops something they asked for.
///
/// Screens used to print `error.toString()`, which put Firebase's English
/// error text in front of the player. Only two kinds of message reach the
/// screen now: one the server wrote for the player (it marks those with
/// `details.localized`, see `localizedError` in functions/src/index.ts),
/// and one a service already translated and threw as an [Exception].
/// Anything else becomes [fallback] — the action's own text, when the
/// caller has one — or a generic message.
String userFacingError(
  AppLocalizations l10n,
  Object error, {
  String? fallback,
}) {
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    final message = error.message?.trim() ?? '';
    if (details is Map && details['localized'] == true && message.isNotEmpty) {
      return message;
    }
    if (_connectionCodes.contains(error.code)) {
      return l10n.commonConnectionError;
    }
    return fallback ?? l10n.commonGenericError;
  }

  if (error is FirebaseException) {
    if (_connectionCodes.contains(error.code)) {
      return l10n.commonConnectionError;
    }
    return fallback ?? l10n.commonGenericError;
  }

  if (error is TimeoutException) {
    return l10n.commonConnectionError;
  }

  // Services throw `Exception(l10n.something)` for the cases they know.
  const prefix = 'Exception: ';
  final text = error.toString();
  if (error is Exception && text.startsWith(prefix)) {
    final message = text.substring(prefix.length).trim();
    if (message.isNotEmpty) return message;
  }

  return fallback ?? l10n.commonGenericError;
}
