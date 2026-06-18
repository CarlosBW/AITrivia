import 'package:cloud_firestore/cloud_firestore.dart';
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

    final levelsCount = ((data['levelsCount'] ?? 0) as num).toInt();
    final questionsCount = ((data['questionsCount'] ?? 0) as num).toInt();

    return levelsCount >= expectedAiLevelsCount &&
        questionsCount >= expectedAiQuestionsCount;
  }

  Future<void> _validateTopicIsAvailable({
    required String normalizedTitle,
  }) async {
    if (isReservedTopic(normalizedTitle)) {
      throw Exception(
        'Ese tema ya existe como categoría oficial.',
      );
    }

    final existing = await _topicsCol(uid)
        .where('normalizedTitle', isEqualTo: normalizedTitle)
        .where(
          'status',
          whereIn: [
            'pending_generation',
            'ready',
          ],
        )
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception(
        'Ya tienes un tema con ese nombre.',
      );
    }
  }

  String normalizeTopicTitle(String title) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<String> createAiTopic({
    required String title,
  }) async {
    final cleanTitle = title.trim();

    if (cleanTitle.length < 3) {
      throw Exception('Escribe un tema más específico.');
    }

    if (cleanTitle.length > 60) {
      throw Exception('El tema no puede superar 60 caracteres.');
    }

    final normalizedTitle = normalizeTopicTitle(cleanTitle);
    await _validateTopicIsAvailable(
      normalizedTitle: normalizedTitle,
    );
    final existing = await _topicsCol(uid)
        .where(
          'normalizedTitle',
          isEqualTo: normalizedTitle,
        )
        .where(
          'status',
          whereIn: [
            'pending_generation',
            'ready',
          ],
        )
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception(
        'Ya tienes un tema con ese nombre.',
      );
    }
    final userRef = _db.collection('users').doc(uid);
    final topicRef = _topicsCol(uid).doc();

    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? {};

      final coins = ((userData['coins'] ?? 0) as num).toInt();
      final freePasses = ((userData['freeTopicPasses'] ??
              EconomyService.firstAiTopicFreePasses) as num)
          .toInt();

      final usesFreePass = freePasses > 0;
      final cost = usesFreePass ? 0 : EconomyService.createAiTopicCost;

      if (!usesFreePass && coins < cost) {
        throw Exception(
          'Necesitas $cost monedas para crear un tema IA.',
        );
      }

      tx.set(topicRef, {
        'topicId': topicRef.id,
        'title': cleanTitle,
        'normalizedTitle': normalizedTitle,
        'status': 'pending_generation',
        'source': 'ai',
        'levelsCount': 0,
        'questionsCount': 0,
        'generationCostCoins': cost,
        'usedFreePass': usesFreePass,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(
          userRef,
          {
            if (usesFreePass)
              'freeTopicPasses': FieldValue.increment(-1)
            else
              'coins': FieldValue.increment(-cost),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });

    unawaited(
      generateMockTopic(
        topicId: topicRef.id,
      ),
    );

    return topicRef.id;
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

  Future<void> generateMockTopic({
    required String topicId,
  }) async {
    final topicRef = _topicsCol(uid).doc(topicId);

    try {
      final topicSnap = await topicRef.get();
      final topicData = topicSnap.data();

      if (topicData == null) return;

      final title = (topicData['title'] ?? 'Custom Topic').toString();

      await Future.delayed(const Duration(seconds: 2));

      final batch = _db.batch();

      const levelsCount = 10;
      const questionsPerLevel = 10;

      for (int level = 1; level <= levelsCount; level++) {
        final levelRef = topicRef.collection('levels').doc('level_$level');

        batch.set(levelRef, {
          'levelNumber': level,
          'title': 'Level $level',
          'questionsCount': questionsPerLevel,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        for (int q = 1; q <= questionsPerLevel; q++) {
          final questionRef = levelRef.collection('questions').doc('q_$q');

          batch.set(questionRef, {
            'q': 'Mock question $q about $title?',
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
      }

      batch.set(
          topicRef,
          {
            'status': 'ready',
            'levelsCount': levelsCount,
            'questionsCount': levelsCount * questionsPerLevel,
            'generationMode': 'mock',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      await topicRef.set({
        'status': 'failed',
        'generationError': e.toString(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      rethrow;
    }
  }
}
