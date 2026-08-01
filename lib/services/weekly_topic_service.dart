import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class WeeklyTopicService {
  WeeklyTopicService._();

  static final WeeklyTopicService instance = WeeklyTopicService._();

  static const int roundSize = 10;
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

  /// Question ids already used by this player for this week's topic
  /// (any category), so [loadRandomRound] can avoid repeating them within
  /// the same weekly cycle — resets naturally every week since it's keyed
  /// per `weekId`.
  Future<Set<String>> _usedQuestionIdsThisWeek({
    required String uid,
    required String weekId,
  }) async {
    final snap = await userParticipationRef(uid: uid, weekId: weekId).get();
    final raw = snap.data()?['usedQuestionIds'] as List<dynamic>? ?? [];
    return raw.map((e) => e.toString()).toSet();
  }

  /// Draws a fresh round of questions straight from the category's
  /// difficulty pools (same source as Daily Challenge) instead of Solo's
  /// static levels — a repeat occurrence of this category won't show the
  /// exact same question sets a player already played in Solo, and
  /// [_usedQuestionIdsThisWeek] keeps a single week's rounds from repeating
  /// each other too.
  Future<List<Map<String, dynamic>>> loadRandomRound({
    required String uid,
    required String weekId,
    required String categoryId,
    int limit = roundSize,
  }) async {
    final excludeIds = await _usedQuestionIdsThisWeek(
      uid: uid,
      weekId: weekId,
    );

    final all = <Map<String, dynamic>>[];

    for (final difficulty in [1, 2, 3]) {
      final snap = await _db
          .collection('fixed_pools')
          .doc(categoryId)
          .collection('difficulty_$difficulty')
          .doc('pool')
          .collection('questions')
          .get();

      for (final doc in snap.docs) {
        all.add({
          ...doc.data(),
          'sourceDifficulty': difficulty,
          'sourceQuestionId': doc.id,
        });
      }
    }

    if (all.isEmpty) {
      throw Exception('No questions available for this category.');
    }

    all.shuffle(Random());

    final fresh = <Map<String, dynamic>>[];
    final recentlyUsed = <Map<String, dynamic>>[];
    for (final q in all) {
      if (excludeIds.contains(q['sourceQuestionId'])) {
        recentlyUsed.add(q);
      } else {
        fresh.add(q);
      }
    }

    final selected = fresh.take(limit).toList();
    if (selected.length < limit) {
      selected.addAll(recentlyUsed.take(limit - selected.length));
    }
    return selected;
  }

  /// Grants the round result via the `submitWeeklyTopicRound` Cloud
  /// Function — correct/totalAnswered are recomputed server-side from the
  /// submitted answers against the pool's own stored questions, never
  /// trusted from the client.
  Future<Map<String, dynamic>> submitRound({
    required String weekId,
    required String categoryId,
    required List<Map<String, dynamic>> answers,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'submitWeeklyTopicRound',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({
      'weekId': weekId,
      'categoryId': categoryId,
      'answers': answers,
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

  Future<void> createTestWeeklyTopic() async {
    await currentTopicRef.set({
      'active': true,
      'weekId': '2026-W24',
      'title': 'Cine Week',
      'description_es': 'Completa niveles de cine y gana recompensas.',
      'description_en': 'Complete cinema levels and earn rewards.',
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