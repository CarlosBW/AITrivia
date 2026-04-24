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