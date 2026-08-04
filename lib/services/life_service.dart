import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// What a life-spending call did, plus the life state the server was left
/// holding.
///
/// The two are bundled because `consumeLevelEntryLife` /
/// `consumeWrongAnswerLife` already return the post-action state alongside
/// their result. Callers used to throw that away and immediately call
/// `refreshLives`, paying for a second callable and a second Firestore
/// transaction to learn what the first one had just told them — on every
/// wrong answer, which is the most frequent action in the game.
class LifeActionResult {
  const LifeActionResult({required this.applied, required this.state});

  /// Whether the action actually took effect: for a level entry, that the
  /// player had enough life to get in; for a wrong answer, that half a life
  /// was really deducted (new players inside the grace window lose none).
  final bool applied;

  /// Life state as of immediately after the call, in the same shape
  /// [LifeService.refreshLives] returns.
  final Map<String, dynamic> state;
}

class LifeService {
  LifeService._();
  static final instance = LifeService._();

  static const int defaultMaxLifeUnits = 10; // 5 vidas
  static const int defaultRegenSeconds = 150; // 2.5 min por media vida
  static const int unitsPerLife = 2;

  static const int levelEntryCostUnits = 2; // 1 vida
  static const int wrongAnswerCostUnits = 1; // media vida

  // A brand-new player learning the format can burn through their whole
  // life bar failing questions before the game has hooked them — wrong
  // answers don't cost life during their first couple of levels (level
  // entry still costs a life either way; `gamesPlayed` only increments on
  // level completion, so this also covers their very first, still-unfinished
  // level).
  static const int newPlayerGraceLevels = 2;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  double unitsToLives(int units) => units / unitsPerLife;

  String formatLives(int units) {
    final whole = units ~/ 2;
    final half = units % 2;

    if (half == 0) return '$whole';
    return '$whole.5';
  }

  // lifeUnits/maxLifeUnits/lifeRegenSeconds/lastLifeTickAt are protected
  // fields in firestore.rules now, and every Cloud Function below already
  // defaults them when missing — there's nothing left for the client to
  // proactively create here.
  Future<void> ensureUserLifeDoc(String uid) async {}

  Map<String, dynamic> _stateFromData(
    Map<String, dynamic> data, {
    Timestamp? now,
  }) {
    final currentTime = now ?? Timestamp.now();

    int lifeUnits = ((data['lifeUnits'] ?? defaultMaxLifeUnits) as num).toInt();
    final int maxLifeUnits =
        ((data['maxLifeUnits'] ?? defaultMaxLifeUnits) as num).toInt();
    final int lifeRegenSeconds =
        ((data['lifeRegenSeconds'] ?? defaultRegenSeconds) as num).toInt();

    Timestamp lastTick =
        (data['lastLifeTickAt'] as Timestamp?) ?? currentTime;

    if (lifeUnits < maxLifeUnits) {
      final elapsedSeconds =
          (currentTime.millisecondsSinceEpoch - lastTick.millisecondsSinceEpoch) ~/
              1000;

      if (elapsedSeconds >= lifeRegenSeconds) {
        final recoveredUnits = elapsedSeconds ~/ lifeRegenSeconds;
        lifeUnits = (lifeUnits + recoveredUnits).clamp(0, maxLifeUnits);

        final consumedSeconds = recoveredUnits * lifeRegenSeconds;
        lastTick = Timestamp.fromMillisecondsSinceEpoch(
          lastTick.millisecondsSinceEpoch + (consumedSeconds * 1000),
        );

        if (lifeUnits >= maxLifeUnits) {
          lastTick = currentTime;
        }
      }
    } else {
      lifeUnits = maxLifeUnits;
      lastTick = currentTime;
    }

    int? secondsToNextHalfLife;
    if (lifeUnits < maxLifeUnits) {
      final elapsedSeconds =
          (currentTime.millisecondsSinceEpoch - lastTick.millisecondsSinceEpoch) ~/
              1000;
      final remainder = elapsedSeconds % lifeRegenSeconds;
      secondsToNextHalfLife = lifeRegenSeconds - remainder;
      if (secondsToNextHalfLife <= 0) {
        secondsToNextHalfLife = lifeRegenSeconds;
      }
    }

    return {
      'lifeUnits': lifeUnits,
      'maxLifeUnits': maxLifeUnits,
      'lifeRegenSeconds': lifeRegenSeconds,
      'lastLifeTickAt': lastTick,
      'secondsToNextHalfLife': secondsToNextHalfLife,
    };
  }

  /// Calculates the life countdown in memory. No Firestore read/write —
  /// purely a local ticker for the UI between server refreshes, fed by a
  /// snapshot the server already vetted. Never authoritative for gating.
  Map<String, dynamic> calculateLocalLifeState(Map<String, dynamic> state) {
    return _stateFromData(state);
  }

  /// Single read. Useful for screens that only need to paint the current state.
  Future<Map<String, dynamic>> readLives(String uid) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    return _stateFromData(snap.data() ?? {});
  }

  Map<String, dynamic> _stateFromCallableResponse(Map response) {
    final lastTickMs = ((response['lastLifeTickAtMs'] ?? 0) as num).toInt();

    return {
      'lifeUnits': ((response['lifeUnits'] ?? 0) as num).toInt(),
      'maxLifeUnits': ((response['maxLifeUnits'] ?? defaultMaxLifeUnits) as num)
          .toInt(),
      'lifeRegenSeconds':
          ((response['lifeRegenSeconds'] ?? defaultRegenSeconds) as num)
              .toInt(),
      'lastLifeTickAt': Timestamp.fromMillisecondsSinceEpoch(lastTickMs),
      'secondsToNextHalfLife': response['secondsToNextHalfLife'] == null
          ? null
          : ((response['secondsToNextHalfLife']) as num).toInt(),
    };
  }

  /// Reads current life state server-side and, if at least one unit has
  /// really regenerated (or the doc predates lastLifeTickAt), persists the
  /// tick — mirrors the transaction the client used to run directly.
  /// `lifeUnits`/etc. are protected fields, so this now goes through the
  /// `refreshUserLives` Cloud Function instead of writing Firestore itself.
  Future<Map<String, dynamic>> refreshLives(String uid) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'refreshUserLives',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call();

    return _stateFromCallableResponse(Map<String, dynamic>.from(result.data as Map));
  }

  Future<bool> hasEnoughLifeToEnterLevel(String uid) async {
    final state = await refreshLives(uid);
    final lifeUnits = (state['lifeUnits'] ?? 0) as int;
    return lifeUnits >= levelEntryCostUnits;
  }

  Future<LifeActionResult> tryConsumeLevelEntry(String uid) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'consumeLevelEntryLife',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call();

    final data = Map<String, dynamic>.from(result.data as Map);
    return LifeActionResult(
      applied: data['ok'] == true,
      state: _stateFromCallableResponse(data),
    );
  }

  Future<LifeActionResult> tryConsumeWrongAnswer(String uid) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'consumeWrongAnswerLife',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call();

    final data = Map<String, dynamic>.from(result.data as Map);
    return LifeActionResult(
      applied: data['lifeLost'] == true,
      state: _stateFromCallableResponse(data),
    );
  }

  /// Refunds a level-entry charge (see [tryConsumeLevelEntry]) when session
  /// creation fails after the life was already spent, so the player isn't
  /// left with nothing to show for it.
  Future<void> refundLevelEntry(String uid) async {
    await FirebaseFunctions.instance
        .httpsCallable(
          'refundLevelEntryLife',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call();
  }

  /// `uid`/`cost` are kept for call-site compatibility but ignored — the
  /// exchange now happens server-side (Cloud Function `buyFullLife`) since
  /// `coins` is a protected field the client can no longer write directly.
  /// The server uses its own mirrored cost constant, never this argument.
  Future<bool> buyFullLife({
    required String uid,
    required int cost,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'buyFullLife',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call();
      return true;
    } on FirebaseFunctionsException {
      return false;
    }
  }
}
