import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Codes a call comes back with when it never got a real answer: the
/// connection dropped, the wait ran out, or the function was still starting.
const _connectionCodes = {
  'unavailable',
  'deadline-exceeded',
  'internal',
  'unknown',
  'cancelled',
  'aborted',
  'network-request-failed',
};

/// Whether [error] is a call that never got an answer, rather than the
/// server saying no.
///
/// The life check on entering a level used to show any failure as "not
/// enough lives", so a dropped connection told a player with full lives
/// they had none.
bool isConnectionFailure(Object error) {
  if (error is TimeoutException) return true;
  if (error is FirebaseFunctionsException) {
    return _connectionCodes.contains(error.code);
  }
  if (error is FirebaseException) {
    return _connectionCodes.contains(error.code);
  }
  return false;
}

/// Runs [call], and once more after [delay] if the first try never got an
/// answer (see [isConnectionFailure]) — a cold start or a blip, which a
/// second try usually gets through. A real answer is never retried.
Future<T> withConnectionRetry<T>(
  Future<T> Function() call, {
  Duration delay = const Duration(milliseconds: 800),
}) async {
  try {
    return await call();
  } catch (error) {
    if (!isConnectionFailure(error)) rethrow;
    await Future<void>.delayed(delay);
    return call();
  }
}
