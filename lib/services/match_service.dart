import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'achievement_service.dart';
import 'notification_service.dart';

class MatchService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _achievementService = AchievementService.instance;
  final _notificationService = NotificationService.instance;

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

  /// Limpieza suave después de matchear/navegar.
  ///
  /// Solo deja la cola en un estado inactivo para que la UI no siga pensando
  /// que el usuario está buscando. No borra el documento para evitar errores
  /// si alguna pantalla todavía lo escucha.
  Future<void> cleanupMyLiveQueueAfterMatch() async {
    final ref = _liveSearchRef(uid);
    await ref.set({
      'status': 'stopped',
      'matchId': null,
      'opponentUid': null,
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
    final now = FieldValue.serverTimestamp();

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
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  Future<void> stopLiveSearch() async {
    final ref = _liveSearchRef(uid);

    final snap = await ref.get();
    final data = snap.data();

    // Evita writes duplicados si ya está detenido.
    if (data != null &&
        (data['status'] ?? '') == 'stopped' &&
        data['matchId'] == null &&
        data['opponentUid'] == null) {
      return;
    }

    await ref.set({
      'status': 'stopped',
      'matchId': null,
      'opponentUid': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Busca candidatos con query normal (FUERA del transaction),
  /// y luego intenta reclamar a uno con transaction.
  ///
  /// Retorna matchId si logró crear/reclamar match, o null si no.
  Future<String?> tryFindLiveOpponent({
    required String categoryId,
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 10,
    int winReward = 2,
    String myDisplayName = 'Host',
  }) async {
    final meRef = _liveSearchRef(uid);

    final meSnap = await meRef.get();
    final meData = meSnap.data();
    if (meData == null || (meData['status'] ?? '') != 'searching') {
      return null;
    }

    final myTotal = (meData['totalQuestions'] as int?) ?? totalQuestions;
    final myTime = (meData['timePerQuestionSec'] as int?) ?? timePerQuestionSec;
    final myWinReward = (meData['winReward'] as int?) ?? winReward;

    final qs = await _db
        .collection('live_search')
        .where('status', isEqualTo: 'searching')
        .where('categoryId', isEqualTo: categoryId)
        .where('difficulty', isEqualTo: difficulty)
        .limit(8)
        .get();

    final candidates = qs.docs.where((d) => d.id != uid).toList();
    if (candidates.isEmpty) return null;

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

      final matchRef = _db.collection('matches').doc(matchId);
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

  Future<void> _queuePvpStatsUpdates({
    required Transaction tx,
    required String playerAUid,
    required String playerBUid,
    required int playerAScore,
    required int playerBScore,
    required String? winnerUid,
  }) async {
    final playerARef = _db.collection('users').doc(playerAUid);
    final playerBRef = _db.collection('users').doc(playerBUid);

    if (winnerUid == null) {
      tx.set(
        playerARef,
        {
          'matches1v1': FieldValue.increment(1),
          'draws1v1': FieldValue.increment(1),
          'currentWinStreak1v1': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        playerBRef,
        {
          'matches1v1': FieldValue.increment(1),
          'draws1v1': FieldValue.increment(1),
          'currentWinStreak1v1': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return;
    }

    final loserUid = winnerUid == playerAUid ? playerBUid : playerAUid;

    final winnerRef = _db.collection('users').doc(winnerUid);
    final loserRef = _db.collection('users').doc(loserUid);

    final winnerSnap = await tx.get(winnerRef);
    final loserSnap = await tx.get(loserRef);

    final winnerData = winnerSnap.data() ?? {};
    final loserData = loserSnap.data() ?? {};

    final currentWinnerStreak =
        ((winnerData['currentWinStreak1v1'] ?? 0) as num).toInt();

    final bestWinnerStreak =
        ((winnerData['bestWinStreak1v1'] ?? 0) as num).toInt();

    final winnerWins = ((winnerData['wins1v1'] ?? 0) as num).toInt() + 1;

    final loserWins = ((loserData['wins1v1'] ?? 0) as num).toInt();

    final newCurrentWinnerStreak = currentWinnerStreak + 1;

    final newBestWinnerStreak = newCurrentWinnerStreak > bestWinnerStreak
        ? newCurrentWinnerStreak
        : bestWinnerStreak;

    tx.set(
      winnerRef,
      {
        'matches1v1': FieldValue.increment(1),
        'wins1v1': FieldValue.increment(1),
        'currentWinStreak1v1': newCurrentWinnerStreak,
        'bestWinStreak1v1': newBestWinnerStreak,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    tx.set(
      loserRef,
      {
        'matches1v1': FieldValue.increment(1),
        'losses1v1': FieldValue.increment(1),
        'currentWinStreak1v1': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // =========================================================
    // ACHIEVEMENTS
    // =========================================================

    Future.microtask(() async {
      try {
        await _achievementService.syncPvpAchievements(
          uid: winnerUid,
          wins: winnerWins,
          currentWinStreak: newCurrentWinnerStreak,
        );

        await _achievementService.syncPvpAchievements(
          uid: loserUid,
          wins: loserWins,
          currentWinStreak: 0,
        );
      } catch (_) {}
    });
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

      final status = (data['status'] ?? '').toString();
      if (status == 'finished') return;

      final hostUid = (data['hostUid'] ?? '').toString();
      final guestUid = (data['guestUid'] ?? '').toString();
      if (hostUid.isEmpty || guestUid.isEmpty) return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      final host = Map<String, dynamic>.from(players[hostUid] ?? {});
      final guest = Map<String, dynamic>.from(players[guestUid] ?? {});

      if (host['finished'] != true || guest['finished'] != true) return;

      final hostScore = ((host['score'] ?? 0) as num).toInt();
      final guestScore = ((guest['score'] ?? 0) as num).toInt();

      String? winnerUid;
      if (hostScore > guestScore) winnerUid = hostUid;
      if (guestScore > hostScore) winnerUid = guestUid;

      final winReward = ((data['winReward'] ?? 0) as num).toInt();

      tx.update(ref, {
        'status': 'finished',
        'endedAt': FieldValue.serverTimestamp(),
        'winnerUid': winnerUid,
        'rewarded': true,
      });

      if (winnerUid != null && winReward > 0) {
        tx.set(
          _db.collection('users').doc(winnerUid),
          {
            'coins': FieldValue.increment(winReward),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> forceFinalizeMatch(String matchId) async {
    final ref = _db.collection('matches').doc(matchId);

    final snap = await ref.get();
    final data = snap.data();

    if (data == null) return;

    final status = (data['status'] ?? '').toString();
    if (status == 'finished') return;

    final hostUid = (data['hostUid'] ?? '').toString();
    final guestUid = (data['guestUid'] ?? '').toString();

    if (hostUid.isEmpty || guestUid.isEmpty) return;

    final players = Map<String, dynamic>.from(data['players'] ?? {});
    final host = Map<String, dynamic>.from(players[hostUid] ?? {});
    final guest = Map<String, dynamic>.from(players[guestUid] ?? {});

    if (host['finished'] != true || guest['finished'] != true) return;

    final hostScore = ((host['score'] ?? 0) as num).toInt();
    final guestScore = ((guest['score'] ?? 0) as num).toInt();

    String? winnerUid;
    if (hostScore > guestScore) winnerUid = hostUid;
    if (guestScore > hostScore) winnerUid = guestUid;

    final winReward = ((data['winReward'] ?? 0) as num).toInt();
    final rewardAlreadyGiven = data['rewarded'] == true;

    await ref.set({
      'status': 'finished',
      'endedAt': FieldValue.serverTimestamp(),
      'winnerUid': winnerUid,
      'rewarded': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (winnerUid != null && winReward > 0 && !rewardAlreadyGiven) {
      await _db.collection('users').doc(winnerUid).set({
        'coins': FieldValue.increment(winReward),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // ============================================================
  // REMATCH SYSTEM
  // ============================================================

  Future<void> requestRematch(String matchId) async {
    final ref = _db.collection('matches').doc(matchId);

    await ref.set({
      'rematchRequests': {
        uid: true,
      },
    }, SetOptions(merge: true));

    await createRematchIfReady(matchId);
  }

  Future<String?> createRematchIfReady(String matchId) async {
    final oldRef = _db.collection('matches').doc(matchId);

    return _db.runTransaction<String?>((tx) async {
      final snap = await tx.get(oldRef);

      final data = snap.data();
      if (data == null) return null;

      final status = (data['status'] ?? '').toString();
      if (status != 'finished') return null;

      // ✅ evita crear revancha duplicada
      final existingRematchId = (data['rematchMatchId'] ?? '').toString();

      if (existingRematchId.isNotEmpty) {
        return existingRematchId;
      }

      final hostUid = (data['hostUid'] ?? '').toString();
      final guestUid = (data['guestUid'] ?? '').toString();

      if (hostUid.isEmpty || guestUid.isEmpty) {
        return null;
      }

      final rematchRequests =
          Map<String, dynamic>.from(data['rematchRequests'] ?? {});

      final hostAccepted = rematchRequests[hostUid] == true;
      final guestAccepted = rematchRequests[guestUid] == true;

      // ❌ todavía falta uno
      if (!hostAccepted || !guestAccepted) {
        return null;
      }

      final categoryId = (data['categoryId'] ?? '').toString();
      final difficulty = ((data['difficulty'] ?? 1) as num).toInt();
      final totalQuestions = ((data['totalQuestions'] ?? 10) as num).toInt();

      final timePerQuestionSec =
          ((data['timePerQuestionSec'] ?? 10) as num).toInt();

      final winReward = ((data['winReward'] ?? 0) as num).toInt();

      final players = Map<String, dynamic>.from(data['players'] ?? {});

      final hostPlayer = Map<String, dynamic>.from(players[hostUid] ?? {});

      final guestPlayer = Map<String, dynamic>.from(players[guestUid] ?? {});

      final hostName = (hostPlayer['displayName'] ?? 'Host').toString();

      final guestName = (guestPlayer['displayName'] ?? 'Guest').toString();

      final questions = await _generateFixedQuestions(
        categoryId: categoryId,
        difficulty: difficulty,
        total: totalQuestions,
      );

      final newRef = _db.collection('matches').doc();

      final code = _randomCode(5);

      tx.set(newRef, {
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

        'hostUid': hostUid,
        'guestUid': guestUid,

        'players': {
          hostUid: {
            'displayName': hostName,
            'score': 0,
            'ready': false,
            'finished': false,
          },
          guestUid: {
            'displayName': guestName,
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

        // referencia al match anterior
        'previousMatchId': matchId,
      });

      // ✅ marca el match viejo
      tx.update(oldRef, {
        'rematchMatchId': newRef.id,
      });

      return newRef.id;
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

    // =========================================================
    // NOTIFICATIONS
    // =========================================================

    try {
      await _notificationService.createNotification(
        targetUid: challengedUid,
        type: 'match_invite',
        title: 'New async challenge',
        body: '$challengerDisplayName challenged you to a 1 vs 1 match.',
        data: {
          'matchId': matchRef.id,
          'challengerUid': uid,
        },
      );
    } catch (_) {}

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

    // =========================================================
// TURN / RESULT NOTIFICATIONS
// =========================================================

    try {
      final snap = await ref.get();
      final data = snap.data();

      if (data != null) {
        final challengerUid = (data['challengerUid'] ?? '').toString();
        final challengedUid = (data['challengedUid'] ?? '').toString();

        final challengerName =
            (data['challengerDisplayName'] ?? 'Player').toString();
        final challengedName =
            (data['challengedDisplayName'] ?? 'Player').toString();

        final challengerStatus =
            (data['challengerStatus'] ?? 'pending').toString();
        final challengedStatus =
            (data['challengedStatus'] ?? 'pending').toString();

        final opponentUid =
            uid == challengerUid ? challengedUid : challengerUid;
        final myName = uid == challengerUid ? challengerName : challengedName;

        if (challengerStatus != 'finished' || challengedStatus != 'finished') {
          await _notificationService.createNotification(
            targetUid: opponentUid,
            type: 'match_turn',
            title: 'Your turn',
            body: '$myName finished their async match. Now it is your turn.',
            data: {
              'matchId': matchId,
              'opponentUid': uid,
            },
          );
        }
      }
    } catch (_) {}

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

      final winReward = ((data['winReward'] ?? 0) as num).toInt();

      tx.update(ref, {
        'status': 'completed',
        'endedAt': FieldValue.serverTimestamp(),
        'winnerUid': winnerUid,
        'rewarded': true,
        'challengerScore': challengerScore,
        'challengedScore': challengedScore,
        'resultNotificationsSent': false,
      });

      await _queuePvpStatsUpdates(
        tx: tx,
        playerAUid: challengerUid,
        playerBUid: challengedUid,
        playerAScore: challengerScore,
        playerBScore: challengedScore,
        winnerUid: winnerUid,
      );

      if (winnerUid != null && winReward > 0) {
        final winnerRef = _db.collection('users').doc(winnerUid);
        tx.set(
          winnerRef,
          {
            'coins': FieldValue.increment(winReward),
          },
          SetOptions(merge: true),
        );
      }
    });

    // =========================================================
    // FINAL RESULT NOTIFICATIONS
    // =========================================================

    try {
      final snap = await ref.get();
      final data = snap.data();

      if (data != null &&
          (data['status'] ?? '') == 'completed' &&
          data['resultNotificationsSent'] != true) {
        final challengerUid = (data['challengerUid'] ?? '').toString();
        final challengedUid = (data['challengedUid'] ?? '').toString();
        final winnerUid = data['winnerUid'] as String?;

        final challengerName =
            (data['challengerDisplayName'] ?? 'Player').toString();
        final challengedName =
            (data['challengedDisplayName'] ?? 'Player').toString();

        await ref.set({
          'resultNotificationsSent': true,
          'resultNotificationsSentAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (winnerUid == null) {
          await Future.wait([
            _notificationService.createNotification(
              targetUid: challengerUid,
              type: 'match_result',
              title: 'Async match finished',
              body: 'Your match against $challengedName ended in a draw.',
              data: {'matchId': matchId},
            ),
            _notificationService.createNotification(
              targetUid: challengedUid,
              type: 'match_result',
              title: 'Async match finished',
              body: 'Your match against $challengerName ended in a draw.',
              data: {'matchId': matchId},
            ),
          ]);
        } else {
          final loserUid =
              winnerUid == challengerUid ? challengedUid : challengerUid;

          final winnerOpponentName =
              winnerUid == challengerUid ? challengedName : challengerName;

          final loserOpponentName =
              loserUid == challengerUid ? challengedName : challengerName;

          await Future.wait([
            _notificationService.createNotification(
              targetUid: winnerUid,
              type: 'match_result',
              title: 'You won!',
              body: 'You won your async match against $winnerOpponentName.',
              data: {'matchId': matchId},
            ),
            _notificationService.createNotification(
              targetUid: loserUid,
              type: 'match_result',
              title: 'Match finished',
              body: 'You lost your async match against $loserOpponentName.',
              data: {'matchId': matchId},
            ),
          ]);
        }
      }
    } catch (_) {}
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
