import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/avatar_service.dart';
import '../../services/pvp_league_service.dart';

Future<void> bootstrapUserDoc(String uid) async {
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

      'lifeUnits': 10,
      'maxLifeUnits': 10,
      'lifeRegenSeconds': 150,
      'lastLifeTickAt': FieldValue.serverTimestamp(),

      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return;
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

  await ref.set(
    {
      'xp': data['xp'] ?? 0,
      'coins': data['coins'] ?? 0,
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
      'bestLeagueId': bestLeague.id,
      'bestLeagueName': data['bestLeagueName'] ?? bestLeague.name,
      'bestLeagueEmoji': data['bestLeagueEmoji'] ?? bestLeague.emoji,
      'bestLeagueColorValue':
          data['bestLeagueColorValue'] ?? bestLeague.colorValue,

      'gamesPlayed': data['gamesPlayed'] ?? 0,
      'dailyGamesPlayed': data['dailyGamesPlayed'] ?? 0,
      'correctAnswers': data['correctAnswers'] ?? 0,
      'wrongAnswers': data['wrongAnswers'] ?? 0,

      'pvpRating': currentPvpRating,
      'pvpRatingDelta': data['pvpRatingDelta'] ?? 0,
      'pvpLeagueId': data['pvpLeagueId'] ?? currentPvpLeague.id,
      'pvpLeagueName': data['pvpLeagueName'] ?? currentPvpLeague.name,
      'pvpAbandonCount': data['pvpAbandonCount'] ?? 0,
      'pvpCooldownUntil': data['pvpCooldownUntil'],
      'lastPvpPenaltyReason': data['lastPvpPenaltyReason'],
      'wins1v1': data['wins1v1'] ?? 0,
      'losses1v1': data['losses1v1'] ?? 0,
      'draws1v1': data['draws1v1'] ?? 0,
      'matches1v1': data['matches1v1'] ?? 0,
      'currentWinStreak1v1': data['currentWinStreak1v1'] ?? 0,
      'bestWinStreak1v1': data['bestWinStreak1v1'] ?? 0,

      'bestDailyScore': data['bestDailyScore'] ?? 0,
      'dailyStreak': data['dailyStreak'] ?? 0,
      'maxDailyStreak': data['maxDailyStreak'] ?? data['dailyStreak'] ?? 0,

      'lifeUnits': data['lifeUnits'] ?? inferredUnits,
      'maxLifeUnits': data['maxLifeUnits'] ?? 10,
      'lifeRegenSeconds': data['lifeRegenSeconds'] ?? 150,
      'lastLifeTickAt': data['lastLifeTickAt'] ?? FieldValue.serverTimestamp(),

      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}