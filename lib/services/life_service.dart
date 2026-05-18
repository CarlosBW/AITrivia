import 'package:cloud_firestore/cloud_firestore.dart';

class LifeService {
  LifeService._();
  static final instance = LifeService._();

  static const int defaultMaxLifeUnits = 10; // 5 vidas
  static const int defaultRegenSeconds = 150; // 2.5 min por media vida
  static const int unitsPerLife = 2;

  static const int levelEntryCostUnits = 2; // 1 vida
  static const int wrongAnswerCostUnits = 1; // media vida

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  double unitsToLives(int units) => units / unitsPerLife;

  String formatLives(int units) {
    final whole = units ~/ 2;
    final half = units % 2;

    if (half == 0) return '$whole';
    return '$whole.5';
  }

  Future<void> ensureUserLifeDoc(String uid) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    final now = Timestamp.now();

    if (!snap.exists) {
      await ref.set({
        'coins': 0,
        'xp': 0,
        'freeTopicPasses': 1,
        'lifeUnits': defaultMaxLifeUnits,
        'maxLifeUnits': defaultMaxLifeUnits,
        'lifeRegenSeconds': defaultRegenSeconds,
        'lastLifeTickAt': now,
        'createdAt': now,
      }, SetOptions(merge: true));
      return;
    }

    final data = snap.data() ?? {};
    final patch = <String, dynamic>{};

    final oldLives = data['lives'];
    final inferredUnits = oldLives is num
        ? (oldLives.toDouble() * unitsPerLife).round()
        : defaultMaxLifeUnits;

    if (data['lifeUnits'] == null) patch['lifeUnits'] = inferredUnits;
    if (data['maxLifeUnits'] == null) {
      patch['maxLifeUnits'] = defaultMaxLifeUnits;
    }
    if (data['lifeRegenSeconds'] == null) {
      patch['lifeRegenSeconds'] = defaultRegenSeconds;
    }
    if (data['lastLifeTickAt'] == null) patch['lastLifeTickAt'] = now;

    if (patch.isNotEmpty) {
      await ref.set(patch, SetOptions(merge: true));
    }
  }

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

  /// Calculates the life countdown in memory. No Firestore read/write.
  Map<String, dynamic> calculateLocalLifeState(Map<String, dynamic> state) {
    return _stateFromData(state);
  }

  /// Single read. Useful for screens that only need to paint the current state.
  Future<Map<String, dynamic>> readLives(String uid) async {
    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    return _stateFromData(snap.data() ?? {});
  }

  /// Reads Firestore and writes only when at least one life unit has really regenerated.
  Future<Map<String, dynamic>> refreshLives(String uid) async {
    final ref = _db.collection('users').doc(uid);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final beforeUnits =
          ((data['lifeUnits'] ?? defaultMaxLifeUnits) as num).toInt();
      final beforeTick = data['lastLifeTickAt'] as Timestamp?;

      final state = _stateFromData(data);
      final afterUnits = state['lifeUnits'] as int;
      final afterTick = state['lastLifeTickAt'] as Timestamp;

      final didRecover = afterUnits > beforeUnits;
      final missingTick = beforeTick == null;

      if (didRecover || missingTick) {
        tx.set(ref, {
          'lifeUnits': afterUnits,
          'lastLifeTickAt': afterTick,
          'maxLifeUnits': state['maxLifeUnits'],
          'lifeRegenSeconds': state['lifeRegenSeconds'],
        }, SetOptions(merge: true));
      }

      return state;
    });
  }

  Future<bool> hasEnoughLifeToEnterLevel(String uid) async {
    final state = await refreshLives(uid);
    final lifeUnits = (state['lifeUnits'] ?? 0) as int;
    return lifeUnits >= levelEntryCostUnits;
  }

  Future<bool> tryConsumeLevelEntry(String uid) async {
    final ref = _db.collection('users').doc(uid);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final state = _stateFromData(data);

      int lifeUnits = state['lifeUnits'] as int;
      final int maxLifeUnits = state['maxLifeUnits'] as int;
      Timestamp lastTick = state['lastLifeTickAt'] as Timestamp;
      final now = Timestamp.now();

      if (lifeUnits < levelEntryCostUnits) return false;

      final wasFull = lifeUnits >= maxLifeUnits;
      lifeUnits -= levelEntryCostUnits;
      if (wasFull && lifeUnits < maxLifeUnits) {
        lastTick = now;
      }

      tx.set(ref, {
        'lifeUnits': lifeUnits,
        'lastLifeTickAt': lastTick,
      }, SetOptions(merge: true));

      return true;
    });
  }

  Future<bool> tryConsumeWrongAnswer(String uid) async {
    final ref = _db.collection('users').doc(uid);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final state = _stateFromData(data);

      int lifeUnits = state['lifeUnits'] as int;
      final int maxLifeUnits = state['maxLifeUnits'] as int;
      Timestamp lastTick = state['lastLifeTickAt'] as Timestamp;
      final now = Timestamp.now();

      final wasFull = lifeUnits >= maxLifeUnits;
      if (lifeUnits < wrongAnswerCostUnits) {
        lifeUnits = 0;
      } else {
        lifeUnits -= wrongAnswerCostUnits;
      }
      if (wasFull && lifeUnits < maxLifeUnits) {
        lastTick = now;
      }

      tx.set(ref, {
        'lifeUnits': lifeUnits,
        'lastLifeTickAt': lastTick,
      }, SetOptions(merge: true));

      return true;
    });
  }

  Future<bool> buyFullLife({
    required String uid,
    required int cost,
  }) async {
    final ref = _db.collection('users').doc(uid);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final state = _stateFromData(data);

      int coins = ((data['coins'] ?? 0) as num).toInt();
      int lifeUnits = state['lifeUnits'] as int;
      final int maxLifeUnits = state['maxLifeUnits'] as int;

      if (coins < cost) return false;
      if (lifeUnits >= maxLifeUnits) return false;

      lifeUnits = (lifeUnits + unitsPerLife).clamp(0, maxLifeUnits);

      tx.set(ref, {
        'coins': coins - cost,
        'lifeUnits': lifeUnits,
        'lastLifeTickAt': Timestamp.now(),
      }, SetOptions(merge: true));

      return true;
    });
  }
}
