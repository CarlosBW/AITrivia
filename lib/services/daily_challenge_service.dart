import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'weekly_league_service.dart';
import 'economy_service.dart';
import 'analytics_service.dart';
import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

class DailyChallengeSession {
  final String dateId;
  final int durationSeconds;
  final List<Map<String, dynamic>> questions;
  final bool played;
  final DateTime? startedAt;

  const DailyChallengeSession({
    required this.dateId,
    required this.durationSeconds,
    required this.questions,
    required this.played,
    this.startedAt,
  });

  int get remainingSeconds {
    if (startedAt == null) return durationSeconds;

    final elapsed = DateTime.now().difference(startedAt!).inSeconds;
    final remaining = durationSeconds - elapsed;

    return remaining < 0 ? 0 : remaining;
  }
}

class DailyChallengeSaveResult {
  final bool saved;
  final bool alreadyPlayed;
  final int correct;
  final int totalAnswered;
  final int coinsEarned;
  final int streak;
  final int streakBonusCoins;
  final int levelUpBonusCoins;
  final int score;
  final bool leveledUp;
  final int oldLevel;
  final int newLevel;
  final int xpEarned;

  const DailyChallengeSaveResult({
    required this.saved,
    required this.alreadyPlayed,
    required this.correct,
    required this.totalAnswered,
    required this.coinsEarned,
    required this.streak,
    required this.streakBonusCoins,
    required this.levelUpBonusCoins,
    required this.score,
    required this.leveledUp,
    required this.oldLevel,
    required this.newLevel,
    required this.xpEarned,
  });

  int get totalCoinsEarned =>
      coinsEarned + streakBonusCoins + levelUpBonusCoins;
}

class DailyChallengeService {
  DailyChallengeService._();
  static final instance = DailyChallengeService._();

  static const int defaultDurationSeconds = 120;
  static const int defaultQuestionLimit = 60;
  static const int coinsPerBlock = EconomyService.dailyCoinsPerBlock;
  static const int correctPerCoinBlock =
    EconomyService.dailyCorrectPerCoinBlock;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Resolved from the acting user's own device locale — correct for
  // exceptions, since they always surface back to whoever called this.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  String todayDateId([DateTime? now]) {
    final d = now ?? DateTime.now();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  DocumentReference<Map<String, dynamic>> _dailyRef({
    required String uid,
    required String dateId,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('daily_challenges')
        .doc(dateId);
  }

  /// Display-only preview of coins earned so far while the challenge is in
  /// progress (daily_challenge_screen.dart's live "+X coins" indicator) —
  /// the actual grant is computed authoritatively by the
  /// `submitDailyChallengeResult` Cloud Function in `saveResult`.
  int calculateCoinsEarned(int correct) {
    return (correct ~/ correctPerCoinBlock) * coinsPerBlock;
  }

  Future<bool> hasPlayedToday(String uid) async {
    final dateId = todayDateId();
    final snap = await _dailyRef(uid: uid, dateId: dateId).get();
    final data = snap.data();
    return data != null && data['played'] == true;
  }

  Future<DailyChallengeSession?> getTodaySession(String uid) async {
    final dateId = todayDateId();
    final snap = await _dailyRef(uid: uid, dateId: dateId).get();
    final data = snap.data();
    if (data == null) return null;

    final rawQuestions = data['questions'] as List<dynamic>? ?? [];
    final questions = rawQuestions
        .whereType<Map>()
        .map((q) => Map<String, dynamic>.from(q))
        .toList();

    final startedAtRaw = data['startedAt'];
    final startedAt = startedAtRaw is Timestamp ? startedAtRaw.toDate() : null;

    return DailyChallengeSession(
      dateId: dateId,
      durationSeconds:
          ((data['durationSeconds'] ?? defaultDurationSeconds) as num).toInt(),
      questions: questions,
      played: data['played'] == true,
      startedAt: startedAt,
    );
  }

  Future<DailyChallengeSession> createTodaySession({
    required String uid,
    int durationSeconds = defaultDurationSeconds,
    int questionLimit = defaultQuestionLimit,
  }) async {
    final dateId = todayDateId();
    final ref = _dailyRef(uid: uid, dateId: dateId);

    final existing = await ref.get();
    final existingData = existing.data();
    if (existingData != null) {
      final rawQuestions = existingData['questions'] as List<dynamic>? ?? [];
      final questions = rawQuestions
          .whereType<Map>()
          .map((q) => Map<String, dynamic>.from(q))
          .toList();

      final startedAtRaw = existingData['startedAt'];
      final startedAt =
          startedAtRaw is Timestamp ? startedAtRaw.toDate() : null;

      return DailyChallengeSession(
        dateId: dateId,
        durationSeconds:
            ((existingData['durationSeconds'] ?? durationSeconds) as num)
                .toInt(),
        questions: questions,
        played: existingData['played'] == true,
        startedAt: startedAt,
      );
    }

    final excludeQuestionIds = await _recentlyUsedQuestionIds(uid: uid);
    final questions = await loadRandomQuestions(
      limit: questionLimit,
      excludeQuestionIds: excludeQuestionIds,
    );
    final startedAt = DateTime.now();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;

      tx.set(
          ref,
          {
            'dateId': dateId,
            'played': false,
            'durationSeconds': durationSeconds,
            'questions': questions,
            'correct': 0,
            'totalAnswered': 0,
            'coinsEarned': 0,
            'score': 0,
            'startedAt': Timestamp.fromDate(startedAt),
          },
          SetOptions(merge: true));
    });

    final session = await getTodaySession(uid);
    if (session != null) return session;

    return DailyChallengeSession(
      dateId: dateId,
      durationSeconds: durationSeconds,
      questions: questions,
      played: false,
      startedAt: startedAt,
    );
  }

  /// Question ids (`sourceQuestionId`) this user was already served on the
  /// last [days] Daily Challenges, so `loadRandomQuestions` can avoid
  /// repeating them — the random draw from `fixed_pools` has no memory of
  /// its own, so without this a question can resurface the very next day.
  Future<Set<String>> _recentlyUsedQuestionIds({
    required String uid,
    int days = 2,
  }) async {
    final ids = <String>{};
    final now = DateTime.now();

    for (var i = 1; i <= days; i++) {
      final dateId = todayDateId(now.subtract(Duration(days: i)));
      final snap = await _dailyRef(uid: uid, dateId: dateId).get();
      final rawQuestions = snap.data()?['questions'] as List<dynamic>? ?? [];
      for (final q in rawQuestions) {
        if (q is Map && q['sourceQuestionId'] != null) {
          ids.add(q['sourceQuestionId'].toString());
        }
      }
    }

    return ids;
  }

  Future<List<Map<String, dynamic>>> loadRandomQuestions({
    int limit = defaultQuestionLimit,
    Set<String> excludeQuestionIds = const {},
  }) async {
    final categoriesSnap = await _db
        .collection('fixed_categories')
        .where('isActive', isEqualTo: true)
        .get();

    var categoryIds = categoriesSnap.docs.map((d) => d.id).toList();

    if (categoryIds.isEmpty) {
      final poolsSnap = await _db.collection('fixed_pools').get();
      categoryIds = poolsSnap.docs.map((d) => d.id).toList();
    }

    if (categoryIds.isEmpty) {
      throw Exception(_l10n.serviceNoActiveDailyCategories);
    }

    final all = <Map<String, dynamic>>[];

    for (final categoryId in categoryIds) {
      for (final difficulty in [1, 2, 3]) {
        final snap = await _db
            .collection('fixed_pools')
            .doc(categoryId)
            .collection('difficulty_$difficulty')
            .doc('pool')
            .collection('questions')
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          all.add({
            ...data,
            'sourceCategoryId': categoryId,
            'sourceDifficulty': difficulty,
            'sourceQuestionId': doc.id,
          });
        }
      }
    }

    if (all.isEmpty) {
      throw Exception(_l10n.serviceNoQuestionsInPools);
    }

    all.shuffle(Random());

    if (excludeQuestionIds.isEmpty) {
      return all.take(min(limit, all.length)).toList();
    }

    final fresh = <Map<String, dynamic>>[];
    final recentlyUsed = <Map<String, dynamic>>[];
    for (final q in all) {
      if (excludeQuestionIds.contains(q['sourceQuestionId'])) {
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

  /// Grants the Daily Challenge result via the `submitDailyChallengeResult`
  /// Cloud Function — coins/xp/streak/level/league are computed
  /// server-side, and `correct`/`totalAnswered` are now independently
  /// recomputed there too from `answers` (this player's actual selected
  /// option per question, keyed by that question's index in the stored
  /// session) against the session doc's own `questions`, so a modified
  /// client reporting an inflated correct count can no longer affect the
  /// real result.
  Future<DailyChallengeSaveResult> saveResult({
    required String uid,
    required int correct,
    required int totalAnswered,
    required List<Map<String, dynamic>> answers,
  }) async {
    final dateId = todayDateId();
    final weekId = WeeklyLeagueService.instance.currentWeekId();

    final callable =
        FirebaseFunctions.instance.httpsCallable('submitDailyChallengeResult');
    final response = await callable.call({
      'correct': correct,
      'totalAnswered': totalAnswered,
      'answers': answers,
      'dateId': dateId,
      'weekId': weekId,
    });
    final data = Map<String, dynamic>.from(response.data as Map);

    final result = DailyChallengeSaveResult(
      saved: data['saved'] == true,
      alreadyPlayed: data['alreadyPlayed'] == true,
      correct: ((data['correct'] ?? correct) as num).toInt(),
      totalAnswered: ((data['totalAnswered'] ?? totalAnswered) as num).toInt(),
      coinsEarned: ((data['coinsEarned'] ?? 0) as num).toInt(),
      streak: ((data['streak'] ?? 0) as num).toInt(),
      streakBonusCoins: ((data['streakBonusCoins'] ?? 0) as num).toInt(),
      levelUpBonusCoins: ((data['levelUpBonusCoins'] ?? 0) as num).toInt(),
      score: ((data['score'] ?? 0) as num).toInt(),
      leveledUp: data['leveledUp'] == true,
      oldLevel: ((data['oldLevel'] ?? 1) as num).toInt(),
      newLevel: ((data['newLevel'] ?? 1) as num).toInt(),
      xpEarned: ((data['xpEarned'] ?? 0) as num).toInt(),
    );

    if (result.saved) {
      unawaited(_syncDailyRetentionHooks(
        uid: uid,
        dailyStreak: result.streak,
        score: result.score,
      ));
    }

    return result;
  }

  // Achievement-avatar unlocking and the daily_streak_7 achievement's
  // progress are both handled server-side, inside
  // submitDailyChallengeResult, since those fields are now locked against
  // direct client writes in firestore.rules.
  Future<void> _syncDailyRetentionHooks({
    required String uid,
    required int dailyStreak,
    required int score,
  }) async {
    try {
      await AnalyticsService.instance.logDailyChallengeComplete(
        streak: dailyStreak,
        score: score,
      );
    } catch (e) {
      debugPrint('Daily retention hook sync failed: $e');
    }
  }
}
