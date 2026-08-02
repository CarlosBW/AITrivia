import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'economy_service.dart';
import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';
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

  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

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

  /// Ready shared pool entries in the caller's own language, most-reused
  /// first — surfaced as the "Popular Topics" picker on the create screen.
  /// Picking one of these and creating from it skips AI generation
  /// entirely (see createAiTopic's server-side pool-reuse logic), so it's
  /// discounted to [EconomyService.createAiTopicFromPoolCost].
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPopularAiTopics({
    String? languageCode,
    int limit = 20,
  }) {
    final lang = languageCode ??
        LocaleController.instance.locale.value.languageCode;

    return _db
        .collection('ai_topic_pool')
        .where('status', isEqualTo: 'ready')
        .where('languageCode', isEqualTo: lang)
        .orderBy('usageCount', descending: true)
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

  /// [fromPoolId] is purely an optional hint from the "Popular Topics"
  /// picker — the server always auto-detects an exact title+language pool
  /// match itself (see createAiTopic in functions/src/index.ts), so this
  /// is safe to omit and doesn't affect pricing on its own.
  Future<String> createAiTopic({
    required String title,
    String? fromPoolId,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'createAiTopic',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call({
            'title': title,
            if (fromPoolId != null) 'fromPoolId': fromPoolId,
          });

      return (result.data as Map)['topicId'].toString();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceCouldNotCreateTopic);
    }
  }

  /// Deletes the topic, refunding its creation cost first if it never
  /// became (or stopped being) usable — anything other than `'ready'`,
  /// including `'blocked'` (a later level got refused after the topic was
  /// already paid for; see functions/src/index.ts's AI-topics economy
  /// comment). `refundAiTopicCost` itself is guarded against a double
  /// refund and against refunding a genuinely healthy topic, so this is
  /// safe to call unconditionally for any non-ready status.
  Future<void> deleteAiTopic({
    required String topicId,
  }) async {
    if (topicId.trim().isEmpty) return;

    final ref = _topicsCol(uid).doc(topicId);

    final snap = await ref.get();
    final status = (snap.data()?['status'] ?? '').toString();

    if (status.isNotEmpty && status != 'ready') {
      await refundAiTopicCostIfNeeded(topicId: topicId);
    }

    await ref.set({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
          .httpsCallable(
            'ensureAiTopicLevelsGenerated',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call({'topicId': topicId, 'completedLevel': completedLevel});
    } on FirebaseFunctionsException {
      // Best-effort buffering: a failure here just means the next level
      // isn't pre-generated yet. It retries on the next completed level.
    }
  }

  /// Refunds the coins/free pass spent creating a topic that never became
  /// (or stopped being) usable. Guarded server-side both by `costRefunded`
  /// (no double refund on repeated calls) and by `status === 'ready'` (no
  /// refunding a topic that's actually fine) — safe to call whenever a
  /// topic's status isn't `'ready'`, see `deleteAiTopic`.
  Future<void> refundAiTopicCostIfNeeded({required String topicId}) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'refundAiTopicCost',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'topicId': topicId});
    } catch (_) {
      // Best-effort refund — don't block deleting the topic if this fails.
    }
  }

  Future<void> regenerateTopicQuestions({
    required String topicId,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'regenerateAiTopicQuestions',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call({'topicId': topicId});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceCouldNotRegenerateQuestions);
    }
  }

  Future<void> expandTopic({
    required String topicId,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'expandAiTopic',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'topicId': topicId});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceCouldNotExpandTopic);
    }
  }
}
