import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

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
  final int score;

  const DailyChallengeSaveResult({
    required this.saved,
    required this.alreadyPlayed,
    required this.correct,
    required this.totalAnswered,
    required this.coinsEarned,
    required this.streak,
    required this.streakBonusCoins,
    required this.score,
  });

  int get totalCoinsEarned => coinsEarned + streakBonusCoins;
}

class DailyChallengeService {
  DailyChallengeService._();
  static final instance = DailyChallengeService._();

  static const int defaultDurationSeconds = 120;
  static const int defaultQuestionLimit = 60;
  static const int coinsPerBlock = 5;
  static const int correctPerCoinBlock = 10;

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

  DocumentReference<Map<String, dynamic>> _leaderboardPlayerRef({
    required String uid,
    required String dateId,
  }) {
    return _db
        .collection('daily_leaderboards')
        .doc(dateId)
        .collection('players')
        .doc(uid);
  }

  int calculateCoinsEarned(int correct) {
    return (correct ~/ correctPerCoinBlock) * coinsPerBlock;
  }

  int calculateScore({
    required int correct,
    required int totalAnswered,
    required int streak,
  }) {
    final accuracyBonus = totalAnswered <= 0
        ? 0
        : ((correct / totalAnswered) * 100).round();

    final streakBonus = min(streak, 30) * 2;

    return (correct * 10) + accuracyBonus + streakBonus;
  }

  int calculateStreakBonusCoins(int streak) {
    if (streak > 0 && streak % 14 == 0) return 30;
    if (streak > 0 && streak % 7 == 0) return 15;
    if (streak > 0 && streak % 3 == 0) return 5;
    return 0;
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isYesterday(String? dateId) {
    if (dateId == null || dateId.isEmpty) return false;

    final lastDate = DateTime.tryParse(dateId);
    if (lastDate == null) return false;

    final today = _dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    final normalizedLast = _dateOnly(lastDate);
    return normalizedLast == yesterday;
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

    final questions = await loadRandomQuestions(limit: questionLimit);
    final startedAt = DateTime.now();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;

      tx.set(ref, {
        'dateId': dateId,
        'played': false,
        'durationSeconds': durationSeconds,
        'questions': questions,
        'correct': 0,
        'totalAnswered': 0,
        'coinsEarned': 0,
        'score': 0,
        'startedAt': Timestamp.fromDate(startedAt),
      }, SetOptions(merge: true));
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

  Future<List<Map<String, dynamic>>> loadRandomQuestions({
    int limit = defaultQuestionLimit,
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
      throw Exception('No hay categorías activas para Daily Challenge.');
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
      throw Exception('No hay preguntas disponibles en los pools fijos.');
    }

    all.shuffle(Random());
    return all.take(min(limit, all.length)).toList();
  }

  Future<DailyChallengeSaveResult> saveResult({
    required String uid,
    required int correct,
    required int totalAnswered,
  }) async {
    final dateId = todayDateId();
    final dailyRef = _dailyRef(uid: uid, dateId: dateId);
    final userRef = _db.collection('users').doc(uid);
    final leaderboardRef = _leaderboardPlayerRef(uid: uid, dateId: dateId);
    final coinsEarned = calculateCoinsEarned(correct);

    return _db.runTransaction((tx) async {
      final dailySnap = await tx.get(dailyRef);
      final userSnap = await tx.get(userRef);

      final alreadyPlayed = dailySnap.data()?['played'] == true;

      if (alreadyPlayed) {
        final data = dailySnap.data() ?? {};
        final userData = userSnap.data() ?? {};
        final streak =
            ((data['streak'] ?? userData['dailyStreak'] ?? 0) as num).toInt();
        final score = ((data['score'] ?? 0) as num).toInt();

        return DailyChallengeSaveResult(
          saved: false,
          alreadyPlayed: true,
          correct: ((data['correct'] ?? correct) as num).toInt(),
          totalAnswered:
              ((data['totalAnswered'] ?? totalAnswered) as num).toInt(),
          coinsEarned: ((data['coinsEarned'] ?? 0) as num).toInt(),
          streak: streak,
          streakBonusCoins:
              ((data['streakBonusCoins'] ?? 0) as num).toInt(),
          score: score,
        );
      }

      final userData = userSnap.data() ?? {};
      final previousStreak = ((userData['dailyStreak'] ?? 0) as num).toInt();
      final lastDailyPlayed = userData['lastDailyPlayed']?.toString();
      final displayName =
          (userData['displayName'] ?? userData['name'] ?? 'Player').toString();

      final newStreak = _isYesterday(lastDailyPlayed)
          ? previousStreak + 1
          : 1;

      final streakBonusCoins = calculateStreakBonusCoins(newStreak);
      final totalCoinsToAdd = coinsEarned + streakBonusCoins;
      final score = calculateScore(
        correct: correct,
        totalAnswered: totalAnswered,
        streak: newStreak,
      );

      tx.set(dailyRef, {
        'dateId': dateId,
        'played': true,
        'correct': correct,
        'totalAnswered': totalAnswered,
        'coinsEarned': coinsEarned,
        'streak': newStreak,
        'streakBonusCoins': streakBonusCoins,
        'totalCoinsEarned': totalCoinsToAdd,
        'score': score,
        'finishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(userRef, {
        'dailyStreak': newStreak,
        'lastDailyPlayed': dateId,
        if (totalCoinsToAdd > 0)
          'coins': FieldValue.increment(totalCoinsToAdd),
      }, SetOptions(merge: true));

      tx.set(leaderboardRef, {
        'uid': uid,
        'displayName': displayName,
        'dateId': dateId,
        'correct': correct,
        'totalAnswered': totalAnswered,
        'score': score,
        'streak': newStreak,
        'coinsEarned': coinsEarned,
        'streakBonusCoins': streakBonusCoins,
        'finishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return DailyChallengeSaveResult(
        saved: true,
        alreadyPlayed: false,
        correct: correct,
        totalAnswered: totalAnswered,
        coinsEarned: coinsEarned,
        streak: newStreak,
        streakBonusCoins: streakBonusCoins,
        score: score,
      );
    });
  }
}