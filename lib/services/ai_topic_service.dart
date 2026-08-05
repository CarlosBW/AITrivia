import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'economy_service.dart';
import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';
import 'dart:async';

/// One existing pool entry found by [AiTopicService.findSimilarAiTopics] —
/// picking one reuses its content directly via `createAiTopic`'s
/// `fromPoolId` hint, at [cost] (the popular or plain reuse discount,
/// decided server-side by [isPopular]).
class SimilarAiTopic {
  final String poolId;
  final String title;
  final int usageCount;
  final bool isPopular;
  final int cost;

  const SimilarAiTopic({
    required this.poolId,
    required this.title,
    required this.usageCount,
    required this.isPopular,
    required this.cost,
  });

  factory SimilarAiTopic.fromMap(Map<Object?, Object?> map) {
    return SimilarAiTopic(
      poolId: (map['poolId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      usageCount: ((map['usageCount'] ?? 0) as num).toInt(),
      isPopular: map['isPopular'] == true,
      cost: ((map['cost'] ?? 0) as num).toInt(),
    );
  }
}

class AiTopicSearchResult {
  final bool blocked;
  final List<SimilarAiTopic> matches;

  const AiTopicSearchResult({required this.blocked, required this.matches});
}

/// One AI-proposed title from [AiTopicService.suggestAiTopicTitles]. Claude
/// can land on a title that already exists in the shared pool, in which
/// case [existsInPool] is true and [cost] is the discounted price the
/// server will really charge — so the picker never quotes full price for
/// something that's about to be discounted.
class AiTopicSuggestion {
  final String title;
  final bool existsInPool;
  final bool isPopular;
  final int cost;

  const AiTopicSuggestion({
    required this.title,
    required this.existsInPool,
    required this.isPopular,
    required this.cost,
  });

  factory AiTopicSuggestion.fromMap(Map<Object?, Object?> map) {
    return AiTopicSuggestion(
      title: (map['title'] ?? '').toString(),
      existsInPool: map['existsInPool'] == true,
      isPopular: map['isPopular'] == true,
      cost: ((map['cost'] ?? 0) as num).toInt(),
    );
  }
}

/// Server-side price for an "add more questions" purchase. Levels already
/// at the question-bank cap aren't charged for, and their sizes live on
/// the shared pool, so only the server can work this out — see
/// [AiTopicService.getRegenerateQuote].
class AiTopicRegenerateQuote {
  final int cost;
  final int levels;

  /// Every unlocked level is already at the bank cap: there is nothing
  /// left to sell, so the purchase must not be offered.
  final bool allFull;

  /// Whether the purchase can go ahead at all.
  final bool available;

  const AiTopicRegenerateQuote({
    required this.cost,
    required this.levels,
    required this.allFull,
    required this.available,
  });

  factory AiTopicRegenerateQuote.fromMap(Map<Object?, Object?> map) {
    return AiTopicRegenerateQuote(
      cost: ((map['cost'] ?? 0) as num).toInt(),
      levels: ((map['levels'] ?? 0) as num).toInt(),
      allFull: map['allFull'] == true,
      available: map['available'] == true,
    );
  }
}

class AiTopicSuggestionResult {
  final bool blocked;
  final List<AiTopicSuggestion> suggestions;

  const AiTopicSuggestionResult({
    required this.blocked,
    required this.suggestions,
  });
}

/// Thrown when [AiTopicService.suggestAiTopicTitles] couldn't produce
/// suggestions for a reason that says nothing about the request itself —
/// the model being unreachable, a timeout, a rate limit. Distinguished
/// from a plain [Exception] because those are genuine rejections (the
/// topic cap, a title that's too short) that the player has to act on,
/// whereas this one is safe to recover from by offering their own title.
class AiTopicSuggestionUnavailable implements Exception {
  final String message;

  const AiTopicSuggestionUnavailable(this.message);

  @override
  String toString() => message;
}

/// Whether a `suggestAiTopicTitles` failure code describes the call
/// breaking rather than the request being refused.
///
/// `internal` is what the server raises once Claude has failed every
/// retry; the other two are the call never completing at all. Everything
/// else is a decision about this specific request — most importantly
/// `resource-exhausted`, the AI-topic cap, which `createAiTopic` enforces
/// just as strictly, so "recovering" from it would only walk the player
/// into the same refusal one step later.
bool isRecoverableSuggestionFailure(String code) {
  return code == 'internal' ||
      code == 'unavailable' ||
      code == 'deadline-exceeded';
}

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

  /// Ready shared pool entries in the caller's own language that have
  /// crossed [EconomyService.aiTopicPopularUsageThreshold], most-reused
  /// first — surfaced as the "Popular Topics" picker on the create screen.
  /// Picking one of these and creating from it skips AI generation
  /// entirely (see createAiTopic's server-side pool-reuse logic), so it's
  /// discounted to [EconomyService.createAiTopicFromPoolCost] — the same
  /// threshold gates both this showcase and `findSimilarAiTopics`'s
  /// `isPopular` flag, so anything shown here is always priced the same.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPopularAiTopics({
    String? languageCode,
    int limit = 20,
  }) {
    final lang =
        languageCode ?? LocaleController.instance.locale.value.languageCode;

    return _db
        .collection('ai_topic_pool')
        .where('status', isEqualTo: 'ready')
        .where('languageCode', isEqualTo: lang)
        .where(
          'usageCount',
          isGreaterThanOrEqualTo: EconomyService.aiTopicPopularUsageThreshold,
        )
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

    if (targetLevels < EconomyService.aiLevelsPerTopic ||
        targetLevels % EconomyService.aiLevelsPerTopic != 0) {
      return false;
    }

    if (generatedLevels < EconomyService.aiInitialGeneratedLevels) {
      return false;
    }

    // `questionsCount` is deliberately not checked here any more. It used
    // to stand in for "the content really exists", but question content
    // now lives in the shared pool and `ensureSoloLevelSession` generates
    // any level whose bank is empty, so an out-of-date count says nothing
    // about whether the topic is playable. Worse, marking a topic invalid
    // is a dead end — the list refuses to open it, so nothing can ever
    // bring the count back in line, and a single stale write bricked the
    // topic permanently.
    return generatedLevels <= targetLevels;
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
        // Creating a topic generates two levels of real questions, roughly
        // 30s each. At 30s the caller gave up mid-generation and surfaced
        // an error for a topic that then finished creating anyway.
        options: HttpsCallableOptions(timeout: const Duration(seconds: 150)),
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

  /// Searches the shared pool for existing topics similar to [title], so
  /// the user can reuse one instead of creating a near-duplicate. Called
  /// once when the user taps to create (not live per-keystroke).
  Future<AiTopicSearchResult> findSimilarAiTopics({
    required String title,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
        'findSimilarAiTopics',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      )
          .call({'title': title});

      final data = result.data as Map;
      final matches = ((data['matches'] as List?) ?? [])
          .map((m) => SimilarAiTopic.fromMap(m as Map))
          .toList();

      return AiTopicSearchResult(
        blocked: data['blocked'] == true,
        matches: matches,
      );
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceCouldNotSearchTopics);
    }
  }

  /// Asks Claude for a bounded list of well-formed candidate titles for a
  /// raw (possibly misspelled or too-vague) topic request — used once
  /// [findSimilarAiTopics] found nothing close enough to reuse. Free of
  /// charge; the user must pick one of the returned titles to proceed.
  Future<AiTopicSuggestionResult> suggestAiTopicTitles({
    required String title,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
        'suggestAiTopicTitles',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      )
          .call({'title': title});

      final data = result.data as Map;
      final suggestions = ((data['suggestions'] as List?) ?? [])
          .map((s) => AiTopicSuggestion.fromMap(s as Map))
          .toList();

      return AiTopicSuggestionResult(
        blocked: data['blocked'] == true,
        suggestions: suggestions,
      );
    } on FirebaseFunctionsException catch (e) {
      final message = e.message ?? _l10n.serviceCouldNotSuggestTopics;

      if (isRecoverableSuggestionFailure(e.code)) {
        throw AiTopicSuggestionUnavailable(message);
      }
      throw Exception(message);
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
        // Deliberately shorter than the function's own 300s ceiling: nothing
        // waits on this call, so the client can stop listening while the
        // server keeps generating. At 30s it gave up partway through a
        // multi-level batch, which is how players ended up reaching a level
        // whose questions had never been generated.
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
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

  /// Asks the server what "add more questions" would actually cost for
  /// this topic, so the confirmation dialog quotes the price the player
  /// will really be charged.
  Future<AiTopicRegenerateQuote> getRegenerateQuote({
    required String topicId,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'getAiTopicRegenerateQuote',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'topicId': topicId});

      return AiTopicRegenerateQuote.fromMap(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceCouldNotRegenerateQuestions);
    }
  }

  Future<void> regenerateTopicQuestions({
    required String topicId,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
        'regenerateAiTopicQuestions',
        // Generates a batch per level, so the wait scales with how deep
        // the topic is. The function is allowed longer still: if this runs
        // out, the server keeps going and the questions the player paid
        // for land anyway.
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
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
