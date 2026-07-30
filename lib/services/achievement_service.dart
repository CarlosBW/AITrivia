import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'notification_service.dart';
import 'analytics_service.dart';
import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

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
  final _notificationService = NotificationService.instance;

  // Resolved from the acting user's own device locale — correct for
  // exceptions and achievement-completed notifications, since both always
  // concern the same user whose device just triggered this.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  /// Achievement metadata, localized for display. Titles/descriptions are
  /// computed fresh from [l10n] rather than stored as static const text.
  static List<AchievementInfo> achievementsFor(AppLocalizations l10n) => [
        AchievementInfo(
          id: 'first_pvp_win',
          title: l10n.achievementFirstPvpWinTitle,
          description: l10n.achievementFirstPvpWinDescription,
          target: 1,
          rewardCoins: 10,
          rewardXp: 20,
          icon: '⚔️',
        ),
        AchievementInfo(
          id: 'pvp_wins_10',
          title: l10n.achievementPvpWins10Title,
          description: l10n.achievementPvpWins10Description,
          target: 10,
          rewardCoins: 40,
          rewardXp: 80,
          icon: '🏆',
        ),
        AchievementInfo(
          id: 'pvp_streak_5',
          title: l10n.achievementPvpStreak5Title,
          description: l10n.achievementPvpStreak5Description,
          target: 5,
          rewardCoins: 50,
          rewardXp: 100,
          icon: '🔥',
        ),
        AchievementInfo(
          id: 'solo_levels_10',
          title: l10n.achievementSoloLevels10Title,
          description: l10n.achievementSoloLevels10Description,
          target: 10,
          rewardCoins: 30,
          rewardXp: 60,
          icon: '🧭',
        ),
        AchievementInfo(
          id: 'daily_streak_7',
          title: l10n.achievementDailyStreak7Title,
          description: l10n.achievementDailyStreak7Description,
          target: 7,
          rewardCoins: 50,
          rewardXp: 100,
          icon: '📅',
        ),
        AchievementInfo(
          id: 'friends_5',
          title: l10n.achievementFriends5Title,
          description: l10n.achievementFriends5Description,
          target: 5,
          rewardCoins: 25,
          rewardXp: 50,
          icon: '👥',
        ),
        AchievementInfo(
          id: 'pvp_wins_25',
          title: l10n.achievementPvpWins25Title,
          description: l10n.achievementPvpWins25Description,
          target: 25,
          rewardCoins: 100,
          rewardXp: 150,
          icon: '🗡️',
        ),
        AchievementInfo(
          id: 'solo_levels_25',
          title: l10n.achievementSoloLevels25Title,
          description: l10n.achievementSoloLevels25Description,
          target: 25,
          rewardCoins: 60,
          rewardXp: 100,
          icon: '🧗',
        ),
        AchievementInfo(
          id: 'daily_streak_21',
          title: l10n.achievementDailyStreak21Title,
          description: l10n.achievementDailyStreak21Description,
          target: 21,
          rewardCoins: 90,
          rewardXp: 150,
          icon: '🗓️',
        ),
        AchievementInfo(
          id: 'friends_10',
          title: l10n.achievementFriends10Title,
          description: l10n.achievementFriends10Description,
          target: 10,
          rewardCoins: 50,
          rewardXp: 80,
          icon: '🤝',
        ),
        AchievementInfo(
          id: 'weekly_topics_completed_3',
          title: l10n.achievementWeeklyTopics3Title,
          description: l10n.achievementWeeklyTopics3Description,
          target: 3,
          rewardCoins: 60,
          rewardXp: 100,
          icon: '🧩',
        ),
        AchievementInfo(
          id: 'categories_explored_5',
          title: l10n.achievementCategoriesExplored5Title,
          description: l10n.achievementCategoriesExplored5Description,
          target: 5,
          rewardCoins: 40,
          rewardXp: 70,
          icon: '🔎',
        ),
      ];

  AchievementInfo? getAchievementById(String id) {
    for (final a in achievementsFor(_l10n)) {
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

    // =========================================================
    // ACHIEVEMENT NOTIFICATION
    // =========================================================

    try {
      final snap = await ref.get();
      final data = snap.data();

      if (data != null &&
          data['completed'] == true &&
          data['notificationSent'] != true) {
        await ref.set({
          'notificationSent': true,
          'notificationSentAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _notificationService.createNotification(
          targetUid: uid,
          type: 'achievement_completed',
          title: _l10n.serviceAchievementCompletedTitle,
          body: _l10n.serviceAchievementCompletedBody(achievement.title),
          data: {
            'achievementId': achievement.id,
          },
        );

        await AnalyticsService.instance.logAchievementUnlocked(
          achievementId: achievement.id,
        );
      }
    } catch (_) {}
  }

  Future<void> claimAchievement({
    required String uid,
    required String achievementId,
  }) async {
    if (getAchievementById(achievementId) == null) {
      throw Exception(_l10n.serviceAchievementNotFound);
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('claimAchievementReward')
          .call({'achievementId': achievementId});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceCouldNotClaimReward);
    }
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
}
