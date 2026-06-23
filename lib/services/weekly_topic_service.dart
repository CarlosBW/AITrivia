import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyTopicService {
  WeeklyTopicService._();

  static final WeeklyTopicService instance = WeeklyTopicService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get currentTopicRef {
    return _db.collection('weekly_topics').doc('current');
  }

  DocumentReference<Map<String, dynamic>> userParticipationRef({
    required String uid,
    required String weekId,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('weekly_participation')
        .doc(weekId);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchCurrentTopic() {
    return currentTopicRef.snapshots();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getCurrentTopic() {
    return currentTopicRef.get();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyParticipation({
    required String uid,
    required String weekId,
  }) {
    return userParticipationRef(uid: uid, weekId: weekId).snapshots();
  }

  Future<void> markLevelCompleted({
    required String uid,
    required String weekId,
    required int levelNumber,
  }) async {
    final ref = userParticipationRef(uid: uid, weekId: weekId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      final completedLevels = (data['completedLevels'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toSet();

      if (completedLevels.contains(levelNumber)) return;

      completedLevels.add(levelNumber);

      tx.set(
        ref,
        {
          'weekId': weekId,
          'completedLevels': completedLevels.toList()..sort(),
          'levelsCompleted': completedLevels.length,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  bool canClaimCoinReward(Map<String, dynamic>? participationData) {
    final levelsCompleted =
        ((participationData?['levelsCompleted'] ?? 0) as num).toInt();

    final claimed = participationData?['coinRewardClaimed'] == true;

    return levelsCompleted >= 5 && !claimed;
  }

  bool canClaimCompletionReward(Map<String, dynamic>? participationData) {
    final levelsCompleted =
        ((participationData?['levelsCompleted'] ?? 0) as num).toInt();

    final claimed = participationData?['completionRewardClaimed'] == true;

    return levelsCompleted >= 10 && !claimed;
  }

  Future<void> createTestWeeklyTopic() async {
    await currentTopicRef.set({
      'active': true,
      'weekId': '2026-W24',
      'title': 'Cine Week',
      'description': 'Completa niveles de cine y gana recompensas.',
      'categoryId': 'cine',
      'rewardCoins': 10,
      'rewardAvatarId': 'weekly_cine',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> claimCoinReward({
    required String uid,
    required String weekId,
    required int rewardCoins,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final participationRef = userParticipationRef(
      uid: uid,
      weekId: weekId,
    );

    return _db.runTransaction((tx) async {
      final participationSnap = await tx.get(participationRef);
      final data = participationSnap.data() ?? {};

      if (!canClaimCoinReward(data)) return false;

      tx.set(
        participationRef,
        {
          'coinRewardClaimed': true,
          'coinRewardClaimedAt': FieldValue.serverTimestamp(),
          'coinRewardCoins': rewardCoins,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        userRef,
        {
          'coins': FieldValue.increment(rewardCoins),
          'lastWeeklyTopicRewardWeekId': weekId,
          'lastWeeklyTopicRewardCoins': rewardCoins,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return true;
    });
  }

  Future<bool> claimCompletionReward({
    required String uid,
    required String weekId,
    required String rewardAvatarId,
  }) async {
    if (rewardAvatarId.trim().isEmpty) return false;

    final userRef = _db.collection('users').doc(uid);
    final participationRef = userParticipationRef(
      uid: uid,
      weekId: weekId,
    );

    return _db.runTransaction((tx) async {
      final participationSnap = await tx.get(participationRef);
      final participationData = participationSnap.data() ?? {};

      if (!canClaimCompletionReward(participationData)) return false;

      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? {};

      final unlockedAvatars =
          (userData['unlockedAvatars'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toSet();

      final alreadyUnlocked = unlockedAvatars.contains(rewardAvatarId);
      unlockedAvatars.add(rewardAvatarId);

      tx.set(
        participationRef,
        {
          'completionRewardClaimed': true,
          'completionRewardClaimedAt': FieldValue.serverTimestamp(),
          'completionRewardAvatarId': rewardAvatarId,
          'completionRewardAlreadyUnlocked': alreadyUnlocked,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        userRef,
        {
          'unlockedAvatars': unlockedAvatars.toList()..sort(),
          'lastUnlockedAvatarId': rewardAvatarId,
          'lastUnlockedAvatarReason': 'Weekly Topic completed',
          'lastUnlockedAvatarAt': FieldValue.serverTimestamp(),
          'lastWeeklyTopicCompletionRewardWeekId': weekId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return true;
    });
  }
}