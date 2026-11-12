/// How many times [shouldRetryLevelSession] lets a level's session be
/// asked for again before the error is shown.
const int maxLevelSessionRetries = 2;

/// Whether a failed `ensureSoloLevelSession` call should be retried on its
/// own instead of showing a connection error.
///
/// A level no one has generated yet takes a real AI call, and the server
/// finishes and saves it even when the client stops waiting — so a wait cut
/// short by the app going to the background, or by the client's own
/// timeout, is worth asking again: the retry finds the questions ready.
/// Anything else is a real answer from the server and is shown — even after
/// a trip to the background, which explains a dropped connection but not a
/// locked level or an exhausted daily allowance.
bool shouldRetryLevelSession({
  required String? errorCode,
  required bool wentToBackground,
  required int retriesSoFar,
}) {
  if (retriesSoFar >= maxLevelSessionRetries) return false;
  if (errorCode == 'deadline-exceeded') return true;
  return wentToBackground && _connectionErrors.contains(errorCode);
}

/// What a connection cut off mid-call comes back as. Null is an error that
/// isn't a Functions one at all, such as a dropped socket.
const _connectionErrors = {null, 'unavailable', 'internal', 'unknown',
    'cancelled', 'aborted'};

/// Whether the level screen should ask the server for the session now.
///
/// Not while an attempt is in flight, and not while a failed one is on
/// screen: the build that shows the error is the same one that would start
/// the next attempt, so without the second check a failure retried itself
/// forever behind the "Retry" button. The button clears the error.
bool shouldStartLevelSession({
  required bool creating,
  required bool hasError,
}) {
  return !creating && !hasError;
}
