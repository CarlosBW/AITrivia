import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'economy_service.dart';

class AiTopicService {
  AiTopicService._();

  static final AiTopicService instance = AiTopicService._();

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
    final userRef = _db.collection('users').doc(uid);
    final topicRef = _topicsCol(uid).doc();

    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? {};

      final coins = ((userData['coins'] ?? 0) as num).toInt();
      final freePasses =
          ((userData['freeTopicPasses'] ??
                  EconomyService.firstAiTopicFreePasses)
              as num)
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

      tx.set(userRef, {
        if (usesFreePass)
          'freeTopicPasses': FieldValue.increment(-1)
        else
          'coins': FieldValue.increment(-cost),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

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
}