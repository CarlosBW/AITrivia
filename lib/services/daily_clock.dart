/// The Daily Challenge's seconds left once the server has said how much of
/// the run remains ([serverRemainingMs], with each answer).
///
/// The app counts down on its own between answers, but that count drifts:
/// the phone's clock can be off, and the countdown stands still while a
/// verdict is on its way. Without a figure from the server (an older
/// deploy) the app's own count, [current], stands.
int resyncedSecondsLeft({
  required int current,
  required int? serverRemainingMs,
  required int durationSeconds,
}) {
  if (serverRemainingMs == null) return current;
  final seconds = (serverRemainingMs / 1000).ceil();
  return seconds.clamp(0, durationSeconds);
}
