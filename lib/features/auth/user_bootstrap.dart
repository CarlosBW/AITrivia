import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../services/avatar_service.dart';
import '../../services/pvp_league_service.dart';
import '../../services/analytics_service.dart';
import '../../services/locale_controller.dart';

String _todayDateId([DateTime? now]) {
  final d = now ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Thrown by [bootstrapUserDoc] when the requested `username` is already
/// reserved by another account.
class UsernameTakenException implements Exception {}

/// Whether the Firestore user doc for [uid] already exists — used by
/// `AuthGate` to decide whether this is a brand-new account that still
/// needs to go through the username picker.
Future<bool> userDocExists(String uid) async {
  final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return snap.exists;
}

Future<bool> bootstrapUserDoc(String uid, {String? requestedUsername}) async {
  final db = FirebaseFirestore.instance;
  final ref = db.collection('users').doc(uid);

  final snap = await ref.get();

  final defaultUsername = 'Player${uid.substring(0, 8)}';
  final chosenUsername = requestedUsername ?? defaultUsername;
  final chosenUsernameLower = chosenUsername.toLowerCase();

  if (!snap.exists) {
    final defaultPvpLeague = PvpLeagueService.instance.leagueForRating(1000);

    final newUserFields = {
      'coins': 0,
      'xp': 0,
      'freeTopicPasses': 1,

      'username': chosenUsername,
      'usernameLower': chosenUsernameLower,
      'displayName': chosenUsername,

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

      'languageCode': LocaleController.instance.locale.value.languageCode,

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (requestedUsername != null) {
      // A caller-supplied username must be reserved atomically with the
      // account doc, or two brand-new accounts could race onto the same
      // name (the random-default path below has no such collision risk).
      final usernameRef = db.collection('usernames').doc(chosenUsernameLower);

      await db.runTransaction((tx) async {
        final usernameSnap = await tx.get(usernameRef);

        if (usernameSnap.exists) {
          throw UsernameTakenException();
        }

        tx.set(ref, newUserFields);
        tx.set(usernameRef, {
          'uid': uid,
          'username': chosenUsername,
          'usernameLower': chosenUsernameLower,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } else {
      await ref.set(newUserFields);
    }

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

  // Existing accounts predate onboarding — treat them as already onboarded.
  final hasSeenOnboarding = data['hasSeenOnboarding'] ?? true;

  final today = _todayDateId();
  final lastLoginDate = data['lastLoginDate']?.toString();
  final loginStreakIncreased = lastLoginDate != today;

  // `coins`/`xp`/`pvpRating`/`wins1v1`/... (and now `loginStreak`/
  // `lastLoginDate`/`unlockedAvatars`/`dynamicAvatars` themselves) are
  // server-owned and protected in firestore.rules, so this routine
  // per-launch bootstrap must not touch them at all anymore — it only
  // maintains genuinely client-owned profile/cosmetic fields. `avatarId`/
  // `equippedFrame` stay here since those are the user's own equip choice
  // (still validated against `unlockedAvatars`/`bestLeagueId` by the
  // rules), and their fallback defaults here are always allowed values.
  // The login-streak bump and its coin bonus are both handled by
  // `claimLoginStreakBonus`, which also sets the celebration-popup fields
  // home_screen.dart watches for.
  await ref.set(
    {
      'freeTopicPasses': data['freeTopicPasses'] ?? 1,

      'username': username,
      'usernameLower': usernameLower,
      'displayName': displayName,

      'avatarId': data['avatarId'] ?? 'avatar_1',

      'equippedFrame': data['equippedFrame'] ?? bestLeague.id,

      'dailyGamesPlayed': data['dailyGamesPlayed'] ?? 0,

      'lifeUnits': data['lifeUnits'] ?? inferredUnits,
      'maxLifeUnits': data['maxLifeUnits'] ?? 10,
      'lifeRegenSeconds': data['lifeRegenSeconds'] ?? 150,
      'lastLifeTickAt': data['lastLifeTickAt'] ?? FieldValue.serverTimestamp(),

      'hasSeenOnboarding': hasSeenOnboarding,

      'languageCode': data['languageCode'] ??
          LocaleController.instance.locale.value.languageCode,

      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  if (loginStreakIncreased) {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('claimLoginStreakBonus')
          .call({'todayDateId': today});

      final result = Map<String, dynamic>.from(response.data as Map);
      final newLoginStreak = ((result['streak'] ?? 0) as num).toInt();
      final loginCelebrationCoins =
          ((result['coinsEarned'] ?? 0) as num).toInt();

      await AnalyticsService.instance.logLoginStreak(
        streak: newLoginStreak,
        coinsEarned: loginCelebrationCoins,
      );
    } catch (_) {
      // No bloquear el bootstrap si falla el bono de racha o su analítica.
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