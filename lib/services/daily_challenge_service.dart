import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'weekly_league_service.dart';
import 'economy_service.dart';
import 'analytics_service.dart';

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
  static const int coinsPerBlock = EconomyService.dailyCoinsPerBlock;
  static const int correctPerCoinBlock =
    EconomyService.dailyCorrectPerCoinBlock;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

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

  /// Reconstructs today's already-submitted result from the stored
  /// `daily_challenges/{dateId}` doc (written by `submitDailyChallengeResult`
  /// in [saveResult]), so a player who already played today can see a recap
  /// instead of a dead-end "you already played" message. Returns null if
  /// today's session hasn't been played yet.
  Future<DailyChallengeSaveResult?> getTodayResult(String uid) async {
    final dateId = todayDateId();
    final snap = await _dailyRef(uid: uid, dateId: dateId).get();
    final data = snap.data();
    if (data == null || data['played'] != true) return null;

    return DailyChallengeSaveResult(
      saved: true,
      alreadyPlayed: true,
      correct: ((data['correct'] ?? 0) as num).toInt(),
      totalAnswered: ((data['totalAnswered'] ?? 0) as num).toInt(),
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
  }

  /// Time remaining until tomorrow's Daily Challenge unlocks (local
  /// midnight) — used to give the "already played today" recap a concrete
  /// countdown instead of a dead end.
  Duration timeUntilReset([DateTime? now]) {
    final n = now ?? DateTime.now();
    final nextMidnight =
        DateTime(n.year, n.month, n.day).add(const Duration(days: 1));
    final diff = nextMidnight.difference(n);
    return diff.isNegative ? Duration.zero : diff;
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

  /// Ensures today's session exists via the `ensureDailyChallengeSession`
  /// Cloud Function, then reads it back. Session creation moved
  /// server-side — the client used to read the real fixed-pool question
  /// data and write its own copy straight into `daily_challenges/{dateId}`,
  /// which `submitDailyChallengeResult` then trusted as ground truth,
  /// letting a modified client farm rewards with self-chosen "correct"
  /// answers. firestore.rules now denies client `create` on that
  /// collection, so this call is the only way to populate it.
  Future<DailyChallengeSession> createTodaySession({
    required String uid,
  }) async {
    final dateId = todayDateId();

    final existing = await getTodaySession(uid);
    if (existing != null) return existing;

    final callable = FirebaseFunctions.instance.httpsCallable(
      'ensureDailyChallengeSession',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    await callable.call({'dateId': dateId});

    final session = await getTodaySession(uid);
    if (session != null) return session;

    return DailyChallengeSession(
      dateId: dateId,
      durationSeconds: defaultDurationSeconds,
      questions: const [],
      played: false,
      startedAt: DateTime.now(),
    );
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

    final callable = FirebaseFunctions.instance.httpsCallable(
      'submitDailyChallengeResult',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
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
