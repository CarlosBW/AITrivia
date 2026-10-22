/// The server's clock for one question in a PvP match: how much was left
/// when the call returned, and a stopwatch running since then.
///
/// Elapsed time comes from a [Stopwatch] rather than wall-clock arithmetic
/// so a device clock that jumps mid-question — by accident or on purpose —
/// can't buy or burn time. The server judges the real deadline anyway; this
/// only has to keep the countdown honest on screen.
///
/// Shared by the async and live play screens, which run the same clock.
class TurnAnchor {
  TurnAnchor({required this.index, required this.remainingMs})
      : _since = Stopwatch()..start();

  final int index;
  final int remainingMs;
  final Stopwatch _since;

  int get leftMs => remainingMs - _since.elapsedMilliseconds;
}
