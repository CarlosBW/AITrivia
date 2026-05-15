import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> bootstrapUserDoc(String uid) async {
  final db = FirebaseFirestore.instance;
  final ref = db.collection('users').doc(uid);

  await db.runTransaction((tx) async {
    final snap = await tx.get(ref);

    if (!snap.exists) {
      tx.set(ref, {
        'coins': 0,
        'xp': 0,
        'freeTopicPasses': 1,

        // Perfil de jugador
        'username': 'Player${uid.substring(0, 4)}',
        'displayName': 'Player${uid.substring(0, 4)}',
        'avatarId': 'avatar_1',
        'gamesPlayed': 0,
        'dailyGamesPlayed': 0,
        'correctAnswers': 0,
        'wrongAnswers': 0,
        'wins1v1': 0,
        'losses1v1': 0,
        'bestDailyScore': 0,
        'dailyStreak': 0,
        'maxDailyStreak': 0,

        // Sistema nuevo de vidas:
        // 2 unidades = 1 vida
        'lifeUnits': 10, // 5 vidas
        'maxLifeUnits': 10,
        'lifeRegenSeconds': 150, // 2.5 min = media vida

        'lastLifeTickAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final data = snap.data() ?? {};

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

        'username': data['username'] ?? data['displayName'] ?? 'Player${uid.substring(0, 4)}',
        'displayName': data['displayName'] ?? data['username'] ?? 'Player${uid.substring(0, 4)}',
        'avatarId': data['avatarId'] ?? 'avatar_1',
        'gamesPlayed': data['gamesPlayed'] ?? 0,
        'dailyGamesPlayed': data['dailyGamesPlayed'] ?? 0,
        'correctAnswers': data['correctAnswers'] ?? 0,
        'wrongAnswers': data['wrongAnswers'] ?? 0,
        'wins1v1': data['wins1v1'] ?? 0,
        'losses1v1': data['losses1v1'] ?? 0,
        'bestDailyScore': data['bestDailyScore'] ?? 0,
        'dailyStreak': data['dailyStreak'] ?? 0,
        'maxDailyStreak': data['maxDailyStreak'] ?? data['dailyStreak'] ?? 0,

        'lifeUnits': data['lifeUnits'] ?? inferredUnits,
        'maxLifeUnits': data['maxLifeUnits'] ?? 10,
        'lifeRegenSeconds': data['lifeRegenSeconds'] ?? 150,
        'lastLifeTickAt':
            data['lastLifeTickAt'] ?? FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  });
}