import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  /// `users/{uid}/weekly_participation/{weekId}` is fully
  /// Cloud-Function-only (write:false) since submitDailyChallengeResult
  /// also writes there for weekly-league scoring, so this moved server-side
  /// entirely rather than just its coin-touching half.
  Future<void> markLevelCompleted({
    required String uid,
    required String weekId,
    required int levelNumber,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('markWeeklyTopicLevelCompleted')
        .call({'weekId': weekId, 'levelNumber': levelNumber});
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

  /// `rewardCoins` is accepted for call-site compatibility but ignored —
  /// the Cloud Function reads the authoritative amount from
  /// `weekly_topics/current` itself, since that doc is now locked against
  /// client writes (a client could otherwise inflate its own claim by
  /// editing the shared weekly topic doc first).
  Future<bool> claimCoinReward({
    required String uid,
    required String weekId,
    required int rewardCoins,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('claimWeeklyTopicCoinReward')
        .call({'weekId': weekId});

    return (result.data as Map)['claimed'] == true;
  }

  /// `rewardAvatarId` is accepted for call-site compatibility but ignored —
  /// the Cloud Function reads the authoritative avatar id from
  /// `weekly_topics/current` itself, same reasoning as [claimCoinReward].
  Future<bool> claimCompletionReward({
    required String uid,
    required String weekId,
    required String rewardAvatarId,
  }) async {
    if (rewardAvatarId.trim().isEmpty) return false;

    final result = await FirebaseFunctions.instance
        .httpsCallable('claimWeeklyTopicCompletionReward')
        .call({'weekId': weekId});

    return (result.data as Map)['claimed'] == true;
  }
}