import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MatchService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  // ============================================================
  // LIVE MATCHMAKING (buscar jugador en tiempo real)
  // Colección: live_search/{uid}
  // ============================================================

  DocumentReference<Map<String, dynamic>> _liveSearchRef(String userId) =>
      _db.collection('live_search').doc(userId);

  /// Stream de mi doc en cola (para UI)
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyLiveQueue() {
    return _liveSearchRef(uid).snapshots();
  }

  /// Limpieza suave después de matchear/navegar (no borra doc; solo lo “resetea”)
  Future<void> cleanupMyLiveQueueAfterMatch() async {
    final ref = _liveSearchRef(uid);
    await ref.set({
      'status': 'stopped',
      'matchId': null,
      'opponentUid': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> startLiveSearch({
    required String categoryId,
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 10,
    int winReward = 2,
    String displayName = 'Player',
  }) async {
    final ref = _liveSearchRef(uid);

    await ref.set({
      'uid': uid,
      'displayName': displayName,
      'categoryId': categoryId,
      'difficulty': difficulty,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
      'winReward': winReward,
      'status': 'searching', // searching | matched | stopped
      'matchId': null,
      'opponentUid': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> stopLiveSearch() async {
    final ref = _liveSearchRef(uid);

    await ref.set({
      'status': 'stopped',
      'matchId': null,
      'opponentUid': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Busca candidatos con query normal (FUERA del transaction),
  /// y luego intenta "reclamar" a uno con transaction (solo docs).
  ///
  /// Retorna matchId si logró crear o reclamar match, o null si no.
  Future<String?> tryFindLiveOpponent({
    required String categoryId,
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 10,
    int winReward = 2,
    String myDisplayName = 'Host',
  }) async {
    final meRef = _liveSearchRef(uid);

    // 0) asegurar que YO sigo en searching
    final meSnap = await meRef.get();
    final meData = meSnap.data();
    if (meData == null || (meData['status'] ?? '') != 'searching') {
      return null;
    }

    // Si mi doc tiene settings, úsalo como fuente (no dependas solo de UI)
    final myTotal = (meData['totalQuestions'] as int?) ?? totalQuestions;
    final myTime = (meData['timePerQuestionSec'] as int?) ?? timePerQuestionSec;
    final myWinReward = (meData['winReward'] as int?) ?? winReward;

    // 1) Query FUERA del transaction
    final qs = await _db
        .collection('live_search')
        .where('status', isEqualTo: 'searching')
        .where('categoryId', isEqualTo: categoryId)
        .where('difficulty', isEqualTo: difficulty)
        .limit(10)
        .get();

    final candidates = qs.docs.where((d) => d.id != uid).toList();
    if (candidates.isEmpty) return null;

    // 2) intenta reclamar en orden (si uno falla, prueba el siguiente)
    for (final oppDoc in candidates) {
      final oppUid = oppDoc.id;
      final oppRef = _liveSearchRef(oppUid);
      final matchId = _db.collection('matches').doc().id;

      final claimed = await _db.runTransaction<bool>((tx) async {
        final meTxSnap = await tx.get(meRef);
        final oppTxSnap = await tx.get(oppRef);

        final meTx = meTxSnap.data();
        final oppTx = oppTxSnap.data();

        if (meTx == null || oppTx == null) return false;

        // Ambos deben seguir searching y sin matchId asignado
        final meOk =
            (meTx['status'] == 'searching') && (meTx['matchId'] == null);
        final oppOk =
            (oppTx['status'] == 'searching') && (oppTx['matchId'] == null);

        if (!meOk || !oppOk) return false;

        tx.update(meRef, {
          'status': 'matched',
          'matchId': matchId,
          'opponentUid': oppUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.update(oppRef, {
          'status': 'matched',
          'matchId': matchId,
          'opponentUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (!claimed) continue;

      // 3) crear match (una sola vez)
      final matchRef = _db.collection('matches').doc(matchId);
      final existing = await matchRef.get();
      if (existing.exists) return matchId;

      final oppName = (oppDoc.data()['displayName'] ?? 'Guest').toString();

      final questions = await _generateFixedQuestions(
        categoryId: categoryId,
        difficulty: difficulty,
        total: myTotal,
      );

      final code = _randomCode(5);

      await matchRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'waiting',
        'mode': 'fixed',
        'categoryId': categoryId,
        'difficulty': difficulty,
        'aiTopic': null,
        'entryFee': 0,
        'winReward': myWinReward,
        'loseReward': 0,
        'totalQuestions': myTotal,
        'timePerQuestionSec': myTime,
        'questions': questions,
        'hostUid': uid,
        'guestUid': oppUid,
        'players': {
          uid: {
            'displayName': myDisplayName,
            'score': 0,
            'ready': false,
            'finished': false,
          },
          oppUid: {
            'displayName': oppName,
            'score': 0,
            'ready': false,
            'finished': false,
          },
        },
        'startAt': null,
        'endedAt': null,
        'winnerUid': null,
        'rewarded': false,
        'matchCode': code,
      });

      return matchId;
    }

    return null;
  }

  // ============================================================
  // LIVE 1 vs 1 (matches) - lo que ya tenías
  // ============================================================

  Future<String> createFixedMatch({
    required String categoryId,
    int totalQuestions = 10,
    int timePerQuestionSec = 10,
    int winReward = 2,
    int difficulty = 1,
    String displayName = 'Host',
  }) async {
    final matchRef = _db.collection('matches').doc();

    final questions = await _generateFixedQuestions(
      categoryId: categoryId,
      difficulty: difficulty,
      total: totalQuestions,
    );

    final code = _randomCode(5);

    await matchRef.set({
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'waiting',
      'mode': 'fixed',
      'categoryId': categoryId,
      'difficulty': difficulty,
      'aiTopic': null,
      'entryFee': 0,
      'winReward': winReward,
      'loseReward': 0,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
      'questions': questions,
      'hostUid': uid,
      'guestUid': null,
      'players': {
        uid: {
          'displayName': displayName,
          'score': 0,
          'ready': false,
          'finished': false,
        },
      },
      'startAt': null,
      'endedAt': null,
      'winnerUid': null,
      'rewarded': false,
      'matchCode': code,
    });

    return matchRef.id;
  }

  Future<String> createAiPlaceholderMatch({
    required String categoryId,
    required int difficulty,
    required String topic,
    required int entryFee,
    required int winReward,
    int totalQuestions = 10,
    int timePerQuestionSec = 10,
    String displayName = 'Host',
  }) async {
    if (topic.trim().isEmpty) {
      throw Exception('Tema IA no puede estar vacío');
    }

    final matchRef = _db.collection('matches').doc();
    final code = _randomCode(5);

    await matchRef.set({
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'waiting',
      'mode': 'ai',
      'categoryId': categoryId,
      'difficulty': difficulty,
      'aiTopic': topic.trim(),
      'entryFee': entryFee,
      'winReward': winReward,
      'loseReward': 0,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
      'questions': [],
      'hostUid': uid,
      'guestUid': null,
      'players': {
        uid: {
          'displayName': displayName,
          'score': 0,
          'ready': false,
          'finished': false,
        },
      },
      'startAt': null,
      'endedAt': null,
      'winnerUid': null,
      'rewarded': false,
      'matchCode': code,
    });

    return matchRef.id;
  }

  Future<void> joinMatch({
    required String matchId,
    String displayName = 'Guest',
  }) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Sala no existe');

      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'waiting').toString();
      if (status != 'waiting') throw Exception('La sala ya inició o terminó');

      final hostUid = data['hostUid'] as String?;
      final guestUid = data['guestUid'] as String?;

      if (hostUid == uid || guestUid == uid) return;
      if (guestUid != null) throw Exception('Sala llena');

      tx.update(ref, {
        'guestUid': uid,
        'players.$uid': {
          'displayName': displayName,
          'score': 0,
          'ready': false,
          'finished': false,
        },
      });
    });
  }

  Future<void> setReady(String matchId, bool ready) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Sala no existe');

      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'waiting').toString();
      if (status != 'waiting') return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      if (!players.containsKey(uid)) {
        throw Exception('No estás dentro de esta sala');
      }

      tx.update(ref, {'players.$uid.ready': ready});
    });

    await tryStartMatchIfReady(matchId);
  }

  Future<void> tryStartMatchIfReady(String matchId) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? 'waiting').toString();
      if (status != 'waiting') return;

      final mode = (data['mode'] ?? 'fixed').toString();
      if (mode != 'fixed') return;

      final hostUid = data['hostUid'] as String?;
      final guestUid = data['guestUid'] as String?;
      if (hostUid == null || guestUid == null) return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      final hostReady = (players[hostUid]?['ready'] == true);
      final guestReady = (players[guestUid]?['ready'] == true);
      if (!hostReady || !guestReady) return;

      tx.update(ref, {
        'status': 'playing',
        'startAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> submitAnswer({
    required String matchId,
    required int deltaScore,
  }) async {
    final ref = _db.collection('matches').doc(matchId);
    await ref.update({'players.$uid.score': FieldValue.increment(deltaScore)});
  }

  Future<void> submitAnswerOncePerQuestion({
    required String matchId,
    required int questionIndex,
    required int deltaScore,
  }) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      if (!players.containsKey(uid)) {
        throw Exception('No estás dentro de esta sala');
      }

      final me = Map<String, dynamic>.from(players[uid] ?? {});
      final answered = Map<String, dynamic>.from(me['answered'] ?? {});

      final key = questionIndex.toString();
      if (answered[key] == true) return;

      tx.update(ref, {
        'players.$uid.answered.$key': true,
        if (deltaScore > 0)
          'players.$uid.score': FieldValue.increment(deltaScore),
      });
    });
  }

  Future<void> setFinished(String matchId) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      if (!players.containsKey(uid)) return;

      tx.update(ref, {'players.$uid.finished': true});
    });

    await finalizeMatchIfComplete(matchId);
  }

  Future<void> finalizeMatchIfComplete(String matchId) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? 'waiting').toString();
      if (status == 'finished') return;

      final rewarded = data['rewarded'] == true;
      if (rewarded) return;

      final hostUid = data['hostUid'] as String?;
      final guestUid = data['guestUid'] as String?;
      if (hostUid == null || guestUid == null) return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      final host = Map<String, dynamic>.from(players[hostUid] ?? {});
      final guest = Map<String, dynamic>.from(players[guestUid] ?? {});

      if (host['finished'] != true || guest['finished'] != true) return;

      final hostScore = (host['score'] ?? 0) as int;
      final guestScore = (guest['score'] ?? 0) as int;

      String? winnerUid;
      if (hostScore > guestScore) winnerUid = hostUid;
      if (guestScore > hostScore) winnerUid = guestUid;

      final winReward = (data['winReward'] ?? 0) as int;

      tx.update(ref, {
        'status': 'finished',
        'endedAt': FieldValue.serverTimestamp(),
        'winnerUid': winnerUid,
        'rewarded': true,
      });

      if (winnerUid != null && winReward > 0) {
        final winnerRef = _db.collection('users').doc(winnerUid);
        tx.set(
          winnerRef,
          {'coins': FieldValue.increment(winReward)},
          SetOptions(merge: true),
        );
      }
    });
  }

  // ============================================================
  // ASYNC (diferido) 1 vs 1 (async_matches) - existente
  // ============================================================

 Future<String> createAsyncFixedMatch({
  required String challengedUid,
  required String categoryId,
  int difficulty = 1,
  int totalQuestions = 10,
  int timePerQuestionSec = 10,
  int winReward = 2,
  String challengerDisplayName = 'Player',
  String challengedDisplayName = 'Player',
}) async {
  if (challengedUid.trim().isEmpty) throw Exception('challengedUid vacío');
  if (challengedUid == uid) throw Exception('No puedes retarte a ti mismo');

  final matchRef = _db.collection('async_matches').doc();

  final questions = await _generateFixedQuestions(
    categoryId: categoryId,
    difficulty: difficulty,
    total: totalQuestions,
  );

  final now = FieldValue.serverTimestamp();

  await matchRef.set({
    'createdAt': now,
    'lastUpdatedAt': now, // ✅ nuevo: para ordenar Inbox/Outbox

    'status': 'waiting_challenged', // waiting_challenged | completed
    'mode': 'fixed',
    'categoryId': categoryId,
    'difficulty': difficulty,
    'totalQuestions': totalQuestions,
    'timePerQuestionSec': timePerQuestionSec,
    'questions': questions,

    'challengerUid': uid,
    'challengedUid': challengedUid,

    'challengerDisplayName': challengerDisplayName,
    'challengedDisplayName': challengedDisplayName,

    'challengerStatus': 'pending', // pending | finished
    'challengedStatus': 'pending',

    // scores (map)
    'challenger': {'score': 0, 'finishedAt': null},
    'challenged': {'score': 0, 'finishedAt': null},

    // ✅ opcional recomendado: scores planos (más fácil para listas)
    'challengerScore': 0,
    'challengedScore': 0,

    'winnerUid': null,
    'rewarded': false,
    'winReward': winReward,
    'endedAt': null,
  });

  return matchRef.id;
}


  Future<void> submitAsyncResult({
    required String matchId,
    required int score,
  }) async {
    final ref = _db.collection('async_matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) throw Exception('Async match no existe');

      final challengerUid = (data['challengerUid'] ?? '').toString();
      final challengedUid = (data['challengedUid'] ?? '').toString();

      if (uid != challengerUid && uid != challengedUid) {
        throw Exception('No perteneces a este match');
      }

      if (uid == challengerUid) {
        final st = (data['challengerStatus'] ?? 'pending').toString();
        if (st == 'finished') return;

        tx.update(ref, {
          'challengerStatus': 'finished',
          'challenger.score': score,
          'challenger.finishedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final st = (data['challengedStatus'] ?? 'pending').toString();
        if (st == 'finished') return;

        tx.update(ref, {
          'challengedStatus': 'finished',
          'challenged.score': score,
          'challenged.finishedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    await finalizeAsyncMatchIfReady(matchId);
  }

  Future<void> finalizeAsyncMatchIfReady(String matchId) async {
    final ref = _db.collection('async_matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? 'waiting_challenged').toString();
      if (status == 'completed') return;

      final rewarded = data['rewarded'] == true;
      if (rewarded) return;

      final challengerStatus =
          (data['challengerStatus'] ?? 'pending').toString();
      final challengedStatus =
          (data['challengedStatus'] ?? 'pending').toString();

      if (challengerStatus != 'finished' || challengedStatus != 'finished') {
        return;
      }

      final challengerUid = (data['challengerUid'] ?? '').toString();
      final challengedUid = (data['challengedUid'] ?? '').toString();

      final challengerScore = ((data['challenger']?['score']) ?? 0) as int;
      final challengedScore = ((data['challenged']?['score']) ?? 0) as int;

      String? winnerUid;
      if (challengerScore > challengedScore) winnerUid = challengerUid;
      if (challengedScore > challengerScore) winnerUid = challengedUid;

      final winReward = (data['winReward'] ?? 0) as int;

      tx.update(ref, {
        'status': 'completed',
        'endedAt': FieldValue.serverTimestamp(),
        'winnerUid': winnerUid,
        'rewarded': true,
      });

      if (winnerUid != null && winReward > 0) {
        final winnerRef = _db.collection('users').doc(winnerUid);
        tx.set(
          winnerRef,
          {'coins': FieldValue.increment(winReward)},
          SetOptions(merge: true),
        );
      }
    });
  }

  // ============================================================
  // ASYNC SEARCH (para elegir a quién retar)
  // Colección: async_search/{uid}
  // ============================================================

  DocumentReference<Map<String, dynamic>> _asyncSearchRef(String userId) =>
      _db.collection('async_search').doc(userId);

  /// Me marca como "available" o "offline" para aparecer en la lista de retos.
  Future<void> setAsyncChallengeAvailability({
    required bool available,
    String displayName = 'Player',
  }) async {
    final ref = _asyncSearchRef(uid);
    await ref.set({
      'uid': uid,
      'displayName': displayName,
      'status': available ? 'available' : 'offline', // available | offline
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream de candidatos disponibles (para listar y elegir rival).
  /// Nota: filtra tu propio uid en la UI.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAsyncChallengeCandidates({
    int limit = 50,
  }) {
    return _db
        .collection('async_search')
        .where('status', isEqualTo: 'available')
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Inbox de retos: soy el retado.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyAsyncChallengesInbox({
    int limit = 50,
  }) {
    return _db
        .collection('async_matches')
        .where('challengedUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Retos enviados por mí (historial).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyAsyncChallengesSent({
    int limit = 50,
  }) {
    return _db
        .collection('async_matches')
        .where('challengerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ============================================================
  // UTIL
  // ============================================================

  Future<String> getMyDisplayNameFallback(String fallback) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data();
      final name = (data?['displayName'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return fallback;
  }

  Future<String> resolveMatchIdByCode(String code) async {
    final snap = await _db
        .collection('matches')
        .where('matchCode', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) throw Exception('Código no encontrado');
    return snap.docs.first.id;
  }

  String _randomCode(int len) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    var x = now;
    final b = StringBuffer();
    for (int i = 0; i < len; i++) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      b.write(chars[x % chars.length]);
    }
    return b.toString();
  }

  Future<List<Map<String, dynamic>>> _generateFixedQuestions({
    required String categoryId,
    required int difficulty,
    required int total,
  }) async {
    if (categoryId == 'random') {
      return _generateRandomAcrossCategories(
        difficulty: difficulty,
        total: total,
      );
    }

    final col = _db
        .collection('fixed_pools')
        .doc(categoryId)
        .collection('difficulty_$difficulty')
        .doc('pool')
        .collection('questions');

    final snap = await col.get();
    final docs = snap.docs;
    if (docs.isEmpty) throw Exception('Pool vacío para $categoryId');

    docs.shuffle(Random());
    return docs.take(min(total, docs.length)).map((d) => d.data()).toList();
  }

  Future<List<Map<String, dynamic>>> _generateRandomAcrossCategories({
    required int difficulty,
    required int total,
  }) async {
    final catsSnap = await _db
        .collection('fixed_categories')
        .where('isActive', isEqualTo: true)
        .get();

    final categories = catsSnap.docs.map((d) => d.id).toList();
    if (categories.isEmpty) throw Exception('No hay categorías activas');

    final rnd = Random();
    categories.shuffle(rnd);

    final out = <Map<String, dynamic>>[];

    while (out.length < total) {
      final cat = categories[rnd.nextInt(categories.length)];
      final col = _db
          .collection('fixed_pools')
          .doc(cat)
          .collection('difficulty_$difficulty')
          .doc('pool')
          .collection('questions');

      final snap = await col.get();
      if (snap.docs.isEmpty) continue;

      final pick = snap.docs[rnd.nextInt(snap.docs.length)].data();
      out.add(pick);
    }

    return out;
  }
}
