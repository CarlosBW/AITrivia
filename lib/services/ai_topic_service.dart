import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'economy_service.dart';
import 'dart:async';

class AiTopicService {
  AiTopicService._();

  static final AiTopicService instance = AiTopicService._();
  static const int expectedAiLevelsCount = 10;
  static const int expectedAiQuestionsPerLevel = 10;
  static const int expectedAiQuestionsCount =
      expectedAiLevelsCount * expectedAiQuestionsPerLevel;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _topicsCol(String userId) {
    return _db.collection('users').doc(userId).collection('ai_topics');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyAiTopics({
    int limit = 50,
  }) {
    return _topicsCol(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  static const Set<String> _reservedTopicNames = {
    'movies',
    'movie',
    'cine',
    'history',
    'historia',
    'science',
    'ciencia',
    'geography',
    'geografia',
    'geografía',
    'books',
    'libros',
    'video games',
    'videogames',
    'videojuegos',
    'sports',
    'deportes',
  };

  bool isReservedTopic(String normalizedTitle) {
    return _reservedTopicNames.contains(normalizedTitle);
  }

  bool isTopicStructurallyValid(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString();

    if (status != 'ready') return true;

    final targetLevels =
        ((data['targetLevels'] ?? EconomyService.aiLevelsPerTopic) as num)
            .toInt();

    final generatedLevels = ((data['generatedLevels'] ?? 0) as num).toInt();

    final questionsCount = ((data['questionsCount'] ?? 0) as num).toInt();

    if (targetLevels < EconomyService.aiLevelsPerTopic ||
        targetLevels % EconomyService.aiLevelsPerTopic != 0) {
      return false;
    }

    if (generatedLevels < EconomyService.aiInitialGeneratedLevels) {
      return false;
    }

    if (generatedLevels > targetLevels) {
      return false;
    }

    final expectedQuestions =
        generatedLevels * EconomyService.aiQuestionsPerLevel;

    return questionsCount >= expectedQuestions;
  }

  String normalizeTopicTitle(String title) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<String> createAiTopic({
    required String title,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createAiTopic')
          .call({'title': title});

      return (result.data as Map)['topicId'].toString();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo crear el tema.');
    }
  }

  Future<void> deleteAiTopic({
    required String topicId,
  }) async {
    if (topicId.trim().isEmpty) return;

    final ref = _topicsCol(uid).doc(topicId);

    await ref.set({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> generateMockLevel({
    required String topicId,
    required int levelNumber,
    bool force = false,
  }) async {
    if (levelNumber < 1) return;

    final topicRef = _topicsCol(uid).doc(topicId);
    final topicSnap = await topicRef.get();
    final topicData = topicSnap.data();

    if (topicData == null) return;

    final title = (topicData['title'] ?? 'Custom Topic').toString();

    final levelRef = topicRef.collection('levels').doc('level_$levelNumber');
    final levelSnap = await levelRef.get();

    if (levelSnap.exists && !force) return;

    final batch = _db.batch();

    batch.set(levelRef, {
      'levelNumber': levelNumber,
      'title': 'Level $levelNumber',
      'questionsCount': EconomyService.aiQuestionsPerLevel,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (int q = 1; q <= EconomyService.aiQuestionsPerLevel; q++) {
      final questionRef = levelRef.collection('questions').doc('q_$q');

      batch.set(questionRef, {
        'q': 'Mock question $q about $title - Level $levelNumber?',
        'options': [
          'Correct answer',
          'Wrong answer A',
          'Wrong answer B',
          'Wrong answer C',
        ],
        'answerIndex': 0,
        'explanation': 'This is a temporary mock question.',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  /// Buffers real AI-generated levels ahead of the player as they
  /// progress. Generation itself now happens server-side (Claude Haiku
  /// 4.5, via `ensureAiTopicLevelsGenerated`) — the client no longer
  /// writes question content directly.
  Future<void> ensureAiTopicBuffer({
    required String topicId,
    required int completedLevel,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('ensureAiTopicLevelsGenerated')
          .call({'topicId': topicId, 'completedLevel': completedLevel});
    } on FirebaseFunctionsException {
      // Best-effort buffering: a failure here just means the next level
      // isn't pre-generated yet. It retries on the next completed level.
    }
  }

  Future<void> generateMockTopic({
    required String topicId,
  }) async {
    final topicRef = _topicsCol(uid).doc(topicId);

    try {
      final topicSnap = await topicRef.get();
      final topicData = topicSnap.data();

      if (topicData == null) return;

      await Future.delayed(const Duration(seconds: 2));

      for (int level = 1;
          level <= EconomyService.aiInitialGeneratedLevels;
          level++) {
        await generateMockLevel(
          topicId: topicId,
          levelNumber: level,
        );
      }

      await topicRef.set({
        'status': 'ready',
        'targetLevels': EconomyService.aiLevelsPerTopic,
        'levelCount': EconomyService.aiLevelsPerTopic,
        'levelsCount': EconomyService.aiLevelsPerTopic,
        'generatedLevels': EconomyService.aiInitialGeneratedLevels,
        'questionsCount': EconomyService.aiInitialGeneratedLevels *
            EconomyService.aiQuestionsPerLevel,
        'generationMode': 'mock_buffered',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      await topicRef.set({
        'status': 'failed',
        'generationError': e.toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _refundAiTopicCostIfNeeded(topicId: topicId);

      rethrow;
    }
  }

  /// Refunds the coins/free pass spent creating a topic if its generation
  /// failed, so a failed AI call never leaves the player charged for
  /// nothing. Guarded server-side by `costRefunded` since a user can retry
  /// generation on a failed topic (see ai_topics_screen.dart), which must
  /// not refund twice. Only a safety net for topics created under the old
  /// client-side flow — `createAiTopic` now only charges after generation
  /// already succeeded, so new topics never need this.
  Future<void> _refundAiTopicCostIfNeeded({required String topicId}) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('refundAiTopicCost')
          .call({'topicId': topicId});
    } catch (_) {
      // Best-effort refund — don't let a refund failure mask the original
      // generation error via rethrow above.
    }
  }

  Future<void> regenerateTopicQuestions({
    required String topicId,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('regenerateAiTopicQuestions')
          .call({'topicId': topicId});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudieron regenerar las preguntas.');
    }
  }

  Future<void> expandTopic({
    required String topicId,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('expandAiTopic')
          .call({'topicId': topicId});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo ampliar el tema.');
    }
  }
}
