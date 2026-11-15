import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

/// Whether a function last warmed at [last] is worth warming again at
/// [now].
///
/// An idle instance stays up for some minutes, so a second ask inside
/// [after] buys nothing; past it, the instance may be gone.
bool shouldWarm(
  DateTime? last,
  DateTime now, {
  Duration after = FunctionWarmer.rewarmAfter,
}) {
  return last == null || now.difference(last) >= after;
}

/// Asks Cloud Functions to be ready before the player needs them.
///
/// Each callable is its own service, and one nobody has called for a while
/// takes seconds to answer its first request. In a timed game those
/// seconds came out of the first question: the question was slow to
/// arrive and its answer slow to be judged, with the clock running. A
/// screen that leads to a game calls [warm] with the functions that game
/// will use, and by the time the player gets there they answer at once.
///
/// The functions answer `{warm: true}` without doing their work (see
/// `functions/src/warm_up.ts`). Only functions that validate their input
/// before acting belong here: a server that doesn't know the flag yet has
/// to refuse the call, not act on it.
class FunctionWarmer {
  FunctionWarmer._();

  static final FunctionWarmer instance = FunctionWarmer._();

  static const Duration rewarmAfter = Duration(minutes: 4);

  final Map<String, DateTime> _lastWarmed = {};

  /// Fire and forget: nothing waits on this, and a warm-up that fails only
  /// means the first real call is as slow as it used to be.
  void warm(List<String> functions) {
    final now = DateTime.now();
    for (final name in functions) {
      if (!shouldWarm(_lastWarmed[name], now)) continue;
      _lastWarmed[name] = now;
      unawaited(_ping(name));
    }
  }

  Future<void> _ping(String name) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call({'warm': true});
    } catch (_) {
      // Offline, signed out, or no Firebase at all (tests): the real call
      // will say so if it matters.
    }
  }
}
