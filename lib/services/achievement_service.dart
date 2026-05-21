import 'package:cloud_firestore/cloud_firestore.dart';

class AchievementInfo {
  final String id;
  final String title;
  final String description;
  final int target;
  final int rewardCoins;
  final int rewardXp;
  final String icon;

  const AchievementInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.rewardCoins,
    required this.rewardXp,
    required this.icon,
  });
}

class AchievementService {
  AchievementService._();

  static final AchievementService instance = AchievementService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const List<AchievementInfo> achievements = [
    AchievementInfo(
      id: 'first_pvp_win',
      title: 'First Duel Win',
      description: 'Win your first 1 vs 1 match.',
      target: 1,
      rewardCoins: 10,
      rewardXp: 20,
      icon: '⚔️',
    ),
    AchievementInfo(
      id: 'pvp_wins_10',
      title: 'Duelist',
      description: 'Win 10 1 vs 1 matches.',
      target: 10,
      rewardCoins: 40,
      rewardXp: 80,
      icon: '🏆',
    ),
    AchievementInfo(
      id: 'pvp_streak_5',
      title: 'On Fire',
      description: 'Reach a 5-win streak in 1 vs 1.',
      target: 5,
      rewardCoins: 50,
      rewardXp: 100,
      icon: '🔥',
    ),
    AchievementInfo(
      id: 'solo_levels_10',
      title: 'Solo Explorer',
      description: 'Complete 10 solo levels.',
      target: 10,
      rewardCoins: 30,
      rewardXp: 60,
      icon: '🧭',
    ),
    AchievementInfo(
      id: 'daily_streak_7',
      title: 'Weekly Habit',
      description: 'Reach a 7-day Daily Challenge streak.',
      target: 7,
      rewardCoins: 50,
      rewardXp: 100,
      icon: '📅',
    ),
    AchievementInfo(
      id: 'friends_5',
      title: 'Social Player',
      description: 'Add 5 friends.',
      target: 5,
      rewardCoins: 25,
      rewardXp: 50,
      icon: '👥',
    ),
  ];

  AchievementInfo? getAchievementById(String id) {
    for (final a in achievements) {
      if (a.id == id) return a;
    }
    return null;
  }

  DocumentReference<Map<String, dynamic>> _achievementRef({
    required String uid,
    required String achievementId,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('achievements')
        .doc(achievementId);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUserAchievements({
    required String uid,
  }) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('achievements')
        .snapshots();
  }

  Future<void> setProgress({
    required String uid,
    required String achievementId,
    required int progress,
  }) async {
    final achievement = getAchievementById(achievementId);
    if (achievement == null) return;

    final ref = _achievementRef(
      uid: uid,
      achievementId: achievementId,
    );

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      final alreadyClaimed = data['claimed'] == true;
      final currentProgress = ((data['progress'] ?? 0) as num).toInt();

      if (alreadyClaimed) return;
      if (progress <= currentProgress) return;

      final completed = progress >= achievement.target;

      tx.set(
        ref,
        {
          'id': achievementId,
          'progress': progress.clamp(0, achievement.target),
          'target': achievement.target,
          'completed': completed,
          'claimed': false,
          'updatedAt': FieldValue.serverTimestamp(),
          if (completed) 'completedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> incrementProgress({
    required String uid,
    required String achievementId,
    int amount = 1,
  }) async {
    final achievement = getAchievementById(achievementId);
    if (achievement == null) return;

    final ref = _achievementRef(
      uid: uid,
      achievementId: achievementId,
    );

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      final alreadyClaimed = data['claimed'] == true;
      if (alreadyClaimed) return;

      final currentProgress = ((data['progress'] ?? 0) as num).toInt();
      final nextProgress = (currentProgress + amount).clamp(
        0,
        achievement.target,
      );

      final completed = nextProgress >= achievement.target;

      tx.set(
        ref,
        {
          'id': achievementId,
          'progress': nextProgress,
          'target': achievement.target,
          'completed': completed,
          'claimed': false,
          'updatedAt': FieldValue.serverTimestamp(),
          if (completed) 'completedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> claimAchievement({
    required String uid,
    required String achievementId,
  }) async {
    final achievement = getAchievementById(achievementId);
    if (achievement == null) {
      throw Exception('Achievement not found.');
    }

    final userRef = _db.collection('users').doc(uid);
    final achievementRef = _achievementRef(
      uid: uid,
      achievementId: achievementId,
    );

    await _db.runTransaction((tx) async {
      final snap = await tx.get(achievementRef);
      final data = snap.data();

      if (data == null) {
        throw Exception('Achievement not started.');
      }

      final completed = data['completed'] == true;
      final claimed = data['claimed'] == true;

      if (!completed) {
        throw Exception('Achievement not completed yet.');
      }

      if (claimed) {
        throw Exception('Reward already claimed.');
      }

      tx.set(
        userRef,
        {
          'coins': FieldValue.increment(achievement.rewardCoins),
          'xp': FieldValue.increment(achievement.rewardXp),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        achievementRef,
        {
          'claimed': true,
          'claimedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> syncPvpAchievements({
    required String uid,
    required int wins,
    required int currentWinStreak,
  }) async {
    await Future.wait([
      setProgress(
        uid: uid,
        achievementId: 'first_pvp_win',
        progress: wins,
      ),
      setProgress(
        uid: uid,
        achievementId: 'pvp_wins_10',
        progress: wins,
      ),
      setProgress(
        uid: uid,
        achievementId: 'pvp_streak_5',
        progress: currentWinStreak,
      ),
    ]);
  }

  Future<void> syncDailyAchievements({
    required String uid,
    required int dailyStreak,
  }) async {
    await setProgress(
      uid: uid,
      achievementId: 'daily_streak_7',
      progress: dailyStreak,
    );
  }

  Future<void> syncFriendsAchievements({
    required String uid,
    required int friendCount,
  }) async {
    await setProgress(
      uid: uid,
      achievementId: 'friends_5',
      progress: friendCount,
    );
  }

  Future<void> incrementSoloLevelCompleted({
    required String uid,
  }) async {
    await incrementProgress(
      uid: uid,
      achievementId: 'solo_levels_10',
      amount: 1,
    );
  }
}