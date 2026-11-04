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
/// Anything else is a real answer from the server and is shown.
bool shouldRetryLevelSession({
  required String? errorCode,
  required bool wentToBackground,
  required int retriesSoFar,
}) {
  if (retriesSoFar >= maxLevelSessionRetries) return false;
  return wentToBackground || errorCode == 'deadline-exceeded';
}
