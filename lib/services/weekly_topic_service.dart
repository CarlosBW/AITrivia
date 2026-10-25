import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'answer_service.dart';

class WeeklyTopicService {
  WeeklyTopicService._();

  static final WeeklyTopicService instance = WeeklyTopicService._();

  static const int coinRewardThreshold = 25;
  static const int completionRewardThreshold = 50;

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

  /// Draws a round of questions from the category's difficulty pools
  /// (same source as Daily Challenge) instead of Solo's static levels.
  ///
  /// The server draws it (`drawWeeklyTopicRound`): the bank is closed to
  /// the client, since every question carries its answer. It also keeps a
  /// week's rounds from repeating each other, using the player's
  /// `usedQuestionIds` for the week.
  ///
  /// Drawing the round pays its entry life, so it also returns the life
  /// balance after it; throws [NoLivesException] when there isn't enough.
  /// The questions come without their answers: each one is judged by
  /// [AnswerService.answerWeekly].
  Future<({List<Map<String, dynamic>> questions, int lifeUnits})>
      loadRandomRound({
    required String uid,
    required String weekId,
    required String categoryId,
  }) async {
    final Map<String, dynamic> data;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'drawWeeklyTopicRound',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'weekId': weekId, 'categoryId': categoryId});
      data = Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is Map && details['reason'] == 'no_lives') {
        throw const NoLivesException();
      }
      rethrow;
    }

    return (
      questions: (data['questions'] as List? ?? [])
          .map((q) => Map<String, dynamic>.from(q as Map))
          .toList(),
      lifeUnits: ((data['lifeUnits'] ?? 0) as num).toInt(),
    );
  }

  /// Grants the round result via the `submitWeeklyTopicRound` Cloud
  /// Function, which scores the answers it judged as they were given.
  Future<Map<String, dynamic>> submitRound({
    required String weekId,
    required String categoryId,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'submitWeeklyTopicRound',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({
      'weekId': weekId,
      'categoryId': categoryId,
    });

    return Map<String, dynamic>.from(result.data as Map);
  }

  bool canClaimCoinReward(Map<String, dynamic>? participationData) {
    final correctAnswers =
        ((participationData?['correctAnswers'] ?? 0) as num).toInt();

    final claimed = participationData?['coinRewardClaimed'] == true;

    return correctAnswers >= coinRewardThreshold && !claimed;
  }

  bool canClaimCompletionReward(Map<String, dynamic>? participationData) {
    final correctAnswers =
        ((participationData?['correctAnswers'] ?? 0) as num).toInt();

    final claimed = participationData?['completionRewardClaimed'] == true;

    return correctAnswers >= completionRewardThreshold && !claimed;
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
        .httpsCallable(
          'claimWeeklyTopicCoinReward',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
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
        .httpsCallable(
          'claimWeeklyTopicCompletionReward',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({'weekId': weekId});

    return (result.data as Map)['claimed'] == true;
  }
}