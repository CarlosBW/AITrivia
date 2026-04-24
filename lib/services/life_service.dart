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

    final oldLives = data['lives'];
    final inferredUnits = oldLives is num
        ? (oldLives.toDouble() * unitsPerLife).round()
        : defaultMaxLifeUnits;

    await ref.set({
      'lifeUnits': data['lifeUnits'] ?? inferredUnits,
      'maxLifeUnits': data['maxLifeUnits'] ?? defaultMaxLifeUnits,
      'lifeRegenSeconds': data['lifeRegenSeconds'] ?? defaultRegenSeconds,
      'lastLifeTickAt': data['lastLifeTickAt'] ?? now,
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> refreshLives(String uid) async {
    final ref = _db.collection('users').doc(uid);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      int lifeUnits = (data['lifeUnits'] ?? defaultMaxLifeUnits) as int;
      final int maxLifeUnits =
          (data['maxLifeUnits'] ?? defaultMaxLifeUnits) as int;
      final int lifeRegenSeconds =
          (data['lifeRegenSeconds'] ?? defaultRegenSeconds) as int;

      Timestamp lastTick =
          (data['lastLifeTickAt'] as Timestamp?) ?? Timestamp.now();
      final now = Timestamp.now();

      if (lifeUnits < maxLifeUnits) {
        final elapsedSeconds =
            (now.millisecondsSinceEpoch - lastTick.millisecondsSinceEpoch) ~/
                1000;

        if (elapsedSeconds >= lifeRegenSeconds) {
          final recoveredUnits = elapsedSeconds ~/ lifeRegenSeconds;
          lifeUnits = (lifeUnits + recoveredUnits).clamp(0, maxLifeUnits);

          final consumedSeconds = recoveredUnits * lifeRegenSeconds;
          lastTick = Timestamp.fromMillisecondsSinceEpoch(
            lastTick.millisecondsSinceEpoch + (consumedSeconds * 1000),
          );

          tx.set(ref, {
            'lifeUnits': lifeUnits,
            'lastLifeTickAt': lifeUnits >= maxLifeUnits ? now : lastTick,
          }, SetOptions(merge: true));
        }
      } else {
        tx.set(ref, {
          'lastLifeTickAt': now,
        }, SetOptions(merge: true));
      }

      int? secondsToNextHalfLife;
      if (lifeUnits < maxLifeUnits) {
        final elapsedSeconds =
            (now.millisecondsSinceEpoch - lastTick.millisecondsSinceEpoch) ~/
                1000;
        final remainder = elapsedSeconds % lifeRegenSeconds;
        secondsToNextHalfLife = lifeRegenSeconds - remainder;
      }

      return {
        'lifeUnits': lifeUnits,
        'maxLifeUnits': maxLifeUnits,
        'lifeRegenSeconds': lifeRegenSeconds,
        'secondsToNextHalfLife': secondsToNextHalfLife,
      };
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

      int lifeUnits = (data['lifeUnits'] ?? defaultMaxLifeUnits) as int;
      final int maxLifeUnits =
          (data['maxLifeUnits'] ?? defaultMaxLifeUnits) as int;
      final int lifeRegenSeconds =
          (data['lifeRegenSeconds'] ?? defaultRegenSeconds) as int;

      Timestamp lastTick =
          (data['lastLifeTickAt'] as Timestamp?) ?? Timestamp.now();
      final now = Timestamp.now();

      if (lifeUnits < maxLifeUnits) {
        final elapsedSeconds =
            (now.millisecondsSinceEpoch - lastTick.millisecondsSinceEpoch) ~/
                1000;

        if (elapsedSeconds >= lifeRegenSeconds) {
          final recoveredUnits = elapsedSeconds ~/ lifeRegenSeconds;
          lifeUnits = (lifeUnits + recoveredUnits).clamp(0, maxLifeUnits);

          final consumedSeconds = recoveredUnits * lifeRegenSeconds;
          lastTick = Timestamp.fromMillisecondsSinceEpoch(
            lastTick.millisecondsSinceEpoch + (consumedSeconds * 1000),
          );
        }
      }

      if (lifeUnits < levelEntryCostUnits) return false;

      lifeUnits -= levelEntryCostUnits;

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

      int lifeUnits = (data['lifeUnits'] ?? defaultMaxLifeUnits) as int;
      final int maxLifeUnits =
          (data['maxLifeUnits'] ?? defaultMaxLifeUnits) as int;
      final int lifeRegenSeconds =
          (data['lifeRegenSeconds'] ?? defaultRegenSeconds) as int;

      Timestamp lastTick =
          (data['lastLifeTickAt'] as Timestamp?) ?? Timestamp.now();
      final now = Timestamp.now();

      if (lifeUnits < maxLifeUnits) {
        final elapsedSeconds =
            (now.millisecondsSinceEpoch - lastTick.millisecondsSinceEpoch) ~/
                1000;

        if (elapsedSeconds >= lifeRegenSeconds) {
          final recoveredUnits = elapsedSeconds ~/ lifeRegenSeconds;
          lifeUnits = (lifeUnits + recoveredUnits).clamp(0, maxLifeUnits);

          final consumedSeconds = recoveredUnits * lifeRegenSeconds;
          lastTick = Timestamp.fromMillisecondsSinceEpoch(
            lastTick.millisecondsSinceEpoch + (consumedSeconds * 1000),
          );
        }
      }

      if (lifeUnits < wrongAnswerCostUnits) {
        lifeUnits = 0;
      } else {
        lifeUnits -= wrongAnswerCostUnits;
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

      int coins = (data['coins'] ?? 0) as int;
      int lifeUnits = (data['lifeUnits'] ?? defaultMaxLifeUnits) as int;
      final int maxLifeUnits =
          (data['maxLifeUnits'] ?? defaultMaxLifeUnits) as int;

      if (coins < cost) return false;

      lifeUnits = (lifeUnits + 2).clamp(0, maxLifeUnits);

      tx.set(ref, {
        'coins': coins - cost,
        'lifeUnits': lifeUnits,
        'lastLifeTickAt': Timestamp.now(),
      }, SetOptions(merge: true));

      return true;
    });
  }
}