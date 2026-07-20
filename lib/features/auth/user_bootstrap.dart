import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/avatar_service.dart';
import '../../services/pvp_league_service.dart';
import '../../services/analytics_service.dart';
import '../../services/economy_service.dart';

String _todayDateId([DateTime? now]) {
  final d = now ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

bool _wasYesterday(String? dateId) {
  if (dateId == null || dateId.isEmpty) return false;

  final lastDate = DateTime.tryParse(dateId);
  if (lastDate == null) return false;

  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  final yesterday = todayOnly.subtract(const Duration(days: 1));

  final normalizedLast = DateTime(lastDate.year, lastDate.month, lastDate.day);
  return normalizedLast == yesterday;
}

int _loginStreakBonusCoins(int streak) {
  if (streak > 0 && streak % 14 == 0) return EconomyService.loginStreak14DaysCoins;
  if (streak > 0 && streak % 7 == 0) return EconomyService.loginStreak7DaysCoins;
  if (streak > 0 && streak % 3 == 0) return EconomyService.loginStreak3DaysCoins;
  return 0;
}

Future<bool> bootstrapUserDoc(String uid) async {
  final db = FirebaseFirestore.instance;
  final ref = db.collection('users').doc(uid);

  final snap = await ref.get();

  final defaultUsername = 'Player${uid.substring(0, 8)}';
  final defaultUsernameLower = defaultUsername.toLowerCase();

  if (!snap.exists) {
    final defaultPvpLeague = PvpLeagueService.instance.leagueForRating(1000);

    await ref.set({
      'coins': 0,
      'xp': 0,
      'freeTopicPasses': 1,

      'username': defaultUsername,
      'usernameLower': defaultUsernameLower,
      'displayName': defaultUsername,

      'avatarId': 'avatar_1',
      'unlockedAvatars': AvatarService.instance.defaultUnlockedAvatarIds(),
      'lastUnlockedAvatarId': null,
      'lastUnlockedAvatarReason': null,
      'lastUnlockedAvatarAt': null,

      'equippedFrame': defaultPvpLeague.id,
      'bestLeagueId': defaultPvpLeague.id,
      'bestLeagueName': defaultPvpLeague.name,
      'bestLeagueEmoji': defaultPvpLeague.emoji,
      'bestLeagueColorValue': defaultPvpLeague.colorValue,

      'gamesPlayed': 0,
      'dailyGamesPlayed': 0,
      'correctAnswers': 0,
      'wrongAnswers': 0,

      'pvpRating': 1000,
      'pvpRatingDelta': 0,
      'pvpLeagueId': defaultPvpLeague.id,
      'pvpLeagueName': defaultPvpLeague.name,
      'pvpAbandonCount': 0,
      'pvpCooldownUntil': null,
      'lastPvpPenaltyReason': null,
      'wins1v1': 0,
      'losses1v1': 0,
      'draws1v1': 0,
      'matches1v1': 0,
      'currentWinStreak1v1': 0,
      'bestWinStreak1v1': 0,

      'bestDailyScore': 0,
      'dailyStreak': 0,
      'maxDailyStreak': 0,

      'loginStreak': 1,
      'lastLoginDate': _todayDateId(),

      'lifeUnits': 10,
      'maxLifeUnits': 10,
      'lifeRegenSeconds': 150,
      'lastLifeTickAt': FieldValue.serverTimestamp(),

      'hasSeenOnboarding': false,

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await AnalyticsService.instance.logSignUp();
    } catch (_) {
      // No bloquear el bootstrap si falla el registro de analítica.
    }

    return false;
  }

  final data = snap.data() ?? {};

  final currentPvpRating = data['pvpRating'] is num
      ? (data['pvpRating'] as num).toInt()
      : int.tryParse(data['pvpRating']?.toString() ?? '') ?? 1000;

  final currentPvpLeague =
      PvpLeagueService.instance.leagueForRating(currentPvpRating);

  final username =
      (data['username'] ?? data['displayName'] ?? defaultUsername).toString();

  final displayName =
      (data['displayName'] ?? data['username'] ?? username).toString();

  final usernameLower =
      (data['usernameLower'] ?? username).toString().toLowerCase();

  final oldLives = data['lives'];
  final inferredUnits =
      oldLives is num ? (oldLives.toDouble() * 2).round() : 10;

  final bestLeagueId =
      (data['bestLeagueId'] ?? data['pvpLeagueId'] ?? currentPvpLeague.id)
          .toString();

  final bestLeague = PvpLeagueService.instance.leagueById(bestLeagueId);

  final unlockedAvatars = data['unlockedAvatars'] ??
      AvatarService.instance.defaultUnlockedAvatarIds();

  // Existing accounts predate onboarding — treat them as already onboarded.
  final hasSeenOnboarding = data['hasSeenOnboarding'] ?? true;

  final today = _todayDateId();
  final lastLoginDate = data['lastLoginDate']?.toString();
  final previousLoginStreak = ((data['loginStreak'] ?? 0) as num).toInt();
  final loginStreakIncreased = lastLoginDate != today;

  final newLoginStreak = loginStreakIncreased
      ? (_wasYesterday(lastLoginDate) ? previousLoginStreak + 1 : 1)
      : previousLoginStreak;

  final loginCelebrationCoins =
      loginStreakIncreased ? _loginStreakBonusCoins(newLoginStreak) : 0;

  // Note: coins/xp/pvpRating/wins1v1/... are now server-owned (Cloud
  // Functions write them via the Admin SDK) and protected in
  // firestore.rules, so this routine per-launch bootstrap must not touch
  // them at all anymore — it only maintains genuinely client-owned
  // profile/cosmetic fields. The login-streak coin bonus itself moves to
  // the `claimLoginStreakBonus` Cloud Function (see Phase 7); for now
  // `loginStreakCelebrationCoins` is computed for the celebration popup's
  // copy but no longer paid out here.
  await ref.set(
    {
      'freeTopicPasses': data['freeTopicPasses'] ?? 1,

      'username': username,
      'usernameLower': usernameLower,
      'displayName': displayName,

      'avatarId': data['avatarId'] ?? 'avatar_1',
      'unlockedAvatars': unlockedAvatars,
      'lastUnlockedAvatarId': data['lastUnlockedAvatarId'],
      'lastUnlockedAvatarReason': data['lastUnlockedAvatarReason'],
      'lastUnlockedAvatarAt': data['lastUnlockedAvatarAt'],

      'equippedFrame': data['equippedFrame'] ?? bestLeague.id,

      'gamesPlayed': data['gamesPlayed'] ?? 0,
      'dailyGamesPlayed': data['dailyGamesPlayed'] ?? 0,
      'correctAnswers': data['correctAnswers'] ?? 0,
      'wrongAnswers': data['wrongAnswers'] ?? 0,

      'bestDailyScore': data['bestDailyScore'] ?? 0,
      'dailyStreak': data['dailyStreak'] ?? 0,
      'maxDailyStreak': data['maxDailyStreak'] ?? data['dailyStreak'] ?? 0,

      'loginStreak': newLoginStreak,
      'lastLoginDate': today,
      // The celebration popup is suppressed until claimLoginStreakBonus
      // (Phase 7) actually grants these coins server-side — showing it now
      // would claim a reward the player doesn't receive.

      'lifeUnits': data['lifeUnits'] ?? inferredUnits,
      'maxLifeUnits': data['maxLifeUnits'] ?? 10,
      'lifeRegenSeconds': data['lifeRegenSeconds'] ?? 150,
      'lastLifeTickAt': data['lastLifeTickAt'] ?? FieldValue.serverTimestamp(),

      'hasSeenOnboarding': hasSeenOnboarding,

      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  if (loginStreakIncreased) {
    try {
      await AnalyticsService.instance.logLoginStreak(
        streak: newLoginStreak,
        coinsEarned: loginCelebrationCoins,
      );
    } catch (_) {
      // No bloquear el bootstrap si falla el registro de analítica.
    }
  }

  return hasSeenOnboarding == true;
}

Future<void> markOnboardingSeen(String uid) async {
  await FirebaseFirestore.instance.collection('users').doc(uid).set(
    {'hasSeenOnboarding': true},
    SetOptions(merge: true),
  );
}