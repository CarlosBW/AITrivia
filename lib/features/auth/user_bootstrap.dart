import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> bootstrapUserDoc(String uid) async {
  final db = FirebaseFirestore.instance;
  final ref = db.collection('users').doc(uid);

  await db.runTransaction((tx) async {
    final snap = await tx.get(ref);

    final defaultUsername = 'Player${uid.substring(0, 4)}';
    final defaultUsernameLower = defaultUsername.toLowerCase();

    if (!snap.exists) {
      tx.set(ref, {
        'coins': 0,
        'xp': 0,
        'freeTopicPasses': 1,

        // Perfil de jugador
        'username': defaultUsername,
        'usernameLower': defaultUsernameLower,
        'displayName': defaultUsername,
        'avatarId': 'avatar_1',

        'gamesPlayed': 0,
        'dailyGamesPlayed': 0,
        'correctAnswers': 0,
        'wrongAnswers': 0,

        // PvP stats
        'pvpRating': 1000,
        'wins1v1': 0,
        'losses1v1': 0,
        'draws1v1': 0,
        'matches1v1': 0,
        'currentWinStreak1v1': 0,
        'bestWinStreak1v1': 0,

        'bestDailyScore': 0,
        'dailyStreak': 0,
        'maxDailyStreak': 0,

        // Sistema nuevo de vidas:
        // 2 unidades = 1 vida
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

    final username = (data['username'] ??
            data['displayName'] ??
            defaultUsername)
        .toString();

    final displayName = (data['displayName'] ??
            data['username'] ??
            defaultUsername)
        .toString();

    final usernameLower = (data['usernameLower'] ??
            username)
        .toString()
        .toLowerCase();

    // Compatibilidad con el sistema anterior basado en "lives"
    final oldLives = data['lives'];
    final inferredUnits = oldLives is num
        ? (oldLives.toDouble() * 2).round()
        : 10;

    tx.set(
      ref,
      {
        'xp': data['xp'] ?? 0,
        'coins': data['coins'] ?? 0,
        'freeTopicPasses': data['freeTopicPasses'] ?? 1,

        'username': username,
        'usernameLower': usernameLower,
        'displayName': displayName,
        'avatarId': data['avatarId'] ?? 'avatar_1',

        'gamesPlayed': data['gamesPlayed'] ?? 0,
        'dailyGamesPlayed': data['dailyGamesPlayed'] ?? 0,
        'correctAnswers': data['correctAnswers'] ?? 0,
        'wrongAnswers': data['wrongAnswers'] ?? 0,

        // PvP stats
        'pvpRating': data['pvpRating'] ?? 1000,
        'wins1v1': data['wins1v1'] ?? 0,
        'losses1v1': data['losses1v1'] ?? 0,
        'draws1v1': data['draws1v1'] ?? 0,
        'matches1v1': data['matches1v1'] ?? 0,
        'currentWinStreak1v1': data['currentWinStreak1v1'] ?? 0,
        'bestWinStreak1v1': data['bestWinStreak1v1'] ?? 0,

        'bestDailyScore': data['bestDailyScore'] ?? 0,
        'dailyStreak': data['dailyStreak'] ?? 0,
        'maxDailyStreak':
            data['maxDailyStreak'] ?? data['dailyStreak'] ?? 0,

        'lifeUnits': data['lifeUnits'] ?? inferredUnits,
        'maxLifeUnits': data['maxLifeUnits'] ?? 10,
        'lifeRegenSeconds': data['lifeRegenSeconds'] ?? 150,
        'lastLifeTickAt':
            data['lastLifeTickAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': data['updatedAt'] ?? FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  });
}