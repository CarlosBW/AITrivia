import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';
import 'pvp_league_service.dart';

class MatchService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
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
    bool ranked = false,
  }) async {
    final ref = _liveSearchRef(uid);
    final userSnap = await _userRef(uid).get();
    final userData = userSnap.data() ?? {};
    final avatarId = (userData['avatarId'] ?? 'avatar_1').toString();

    final resolvedDisplayName =
        (userData['displayName'] ?? userData['username'] ?? displayName)
                .toString()
                .trim()
                .isEmpty
            ? displayName
            : (userData['displayName'] ?? userData['username'] ?? displayName)
                .toString()
                .trim();

    if (ranked) {
      final cooldownUntil = _activePvpCooldownUntil(userData);
      if (cooldownUntil != null) {
        throw Exception(
          'Tienes cooldown de ranked por abandono. Intenta de nuevo en ${_formatCooldownRemaining(cooldownUntil)}.',
        );
      }
    }

    final pvpRating = _safeInt(userData['pvpRating'], _defaultPvpRating);
    final pvpLeague = PvpLeagueService.instance.leagueForRating(pvpRating);
    final now = FieldValue.serverTimestamp();

    await ref.set({
      'uid': uid,
      'displayName': resolvedDisplayName,
      'avatarId': avatarId,
      'categoryId': categoryId,
      'difficulty': difficulty,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
      'winReward': winReward,
      'ranked': ranked,
      'matchType': ranked ? 'ranked' : 'casual',
      'pvpRating': pvpRating,
      'pvpLeagueId': pvpLeague.id,
      'pvpLeagueName': pvpLeague.name,
      'pvpLeagueEmoji': pvpLeague.emoji,
      'status': 'searching', // searching | matched | stopped
      'matchId': null,
      'opponentUid': null,
      'createdAt': now,
      'searchStartedAt': now,
      'updatedAt': now,
      'lastHeartbeatAt': now,
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(_liveSearchMaxAge),
      ),
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
      'lastHeartbeatAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateLiveSearchHeartbeat() async {
    final ref = _liveSearchRef(uid);
    final snap = await ref.get();
    final data = snap.data();

    if (data == null || (data['status'] ?? '') != 'searching') return;

    await ref.set({
      'updatedAt': FieldValue.serverTimestamp(),
      'lastHeartbeatAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(_liveSearchMaxAge),
      ),
    }, SetOptions(merge: true));
  }

  Future<void> recoverMyRealtimeStateOnAppStart() async {
    final queueRef = _liveSearchRef(uid);
    final userRef = _userRef(uid);

    final queueSnap = await queueRef.get();
    final userSnap = await userRef.get();

    final queue = queueSnap.data();
    final user = userSnap.data();
    final presence = Map<String, dynamic>.from(
      user?['presence'] as Map? ?? {},
    );

    final queueIsActive = _isLiveQueueEntryValid(queue);
    final presenceStatus = (presence['status'] ?? '').toString();
    final inMatch = presence['inMatch'] == true;

    if (queue != null &&
        !queueIsActive &&
        (queue['status'] ?? '') == 'searching') {
      await queueRef.set({
        'status': 'stopped',
        'matchId': null,
        'opponentUid': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if ((presenceStatus == 'searching_match' && !queueIsActive) ||
        (presenceStatus == 'in_match' && !inMatch)) {
      await userRef.set({
        'presence': {
          'status': 'online',
          'inMatch': false,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static const Duration _liveSearchMaxAge = Duration(seconds: 30);
  static const Duration _presenceMaxAge = Duration(seconds: 45);

  static const int _defaultPvpRating = 1000;

  Timestamp? _activePvpCooldownUntil(Map<String, dynamic>? userData) {
    final raw = userData?['pvpCooldownUntil'];
    if (raw is! Timestamp) return null;

    if (raw.toDate().isAfter(DateTime.now())) return raw;
    return null;
  }

  String _formatCooldownRemaining(Timestamp cooldownUntil) {
    final seconds = cooldownUntil
        .toDate()
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, 999999)
        .toInt();

    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;

    if (minutes <= 0) return '${remainingSeconds}s';
    return '${minutes}m ${remainingSeconds.toString().padLeft(2, '0')}s';
  }

  Future<Timestamp?> getActivePvpCooldownUntil() async {
    final snap = await _userRef(uid).get();
    return _activePvpCooldownUntil(snap.data());
  }

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _db.collection('users').doc(userId);

  bool _timestampIsRecent(
    dynamic value, {
    required Duration maxAge,
  }) {
    if (value is! Timestamp) return true;

    final age = DateTime.now().difference(value.toDate());
    return age <= maxAge;
  }

  int _safeInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _searchAgeSeconds(Map<String, dynamic>? data) {
    if (data == null) return 0;

    final raw = data['searchStartedAt'] ?? data['createdAt'];
    if (raw is! Timestamp) return 0;

    final age = DateTime.now().difference(raw.toDate()).inSeconds;
    return age < 0 ? 0 : age;
  }

  int _allowedRatingGapForSearchAge(int secondsSearching) {
    return PvpLeagueService.instance
        .windowForSearchSeconds(secondsSearching)
        .allowedRatingGap;
  }

  bool _ratingsAreCompatible({
    required Map<String, dynamic>? myQueue,
    required Map<String, dynamic>? opponentQueue,
  }) {
    final myRating = _safeInt(myQueue?['pvpRating'], _defaultPvpRating);
    final opponentRating = _safeInt(
      opponentQueue?['pvpRating'],
      _defaultPvpRating,
    );

    final longestSearchAge = max(
      _searchAgeSeconds(myQueue),
      _searchAgeSeconds(opponentQueue),
    );

    final allowedGap = _allowedRatingGapForSearchAge(longestSearchAge);
    final ratingGap = (myRating - opponentRating).abs();

    return ratingGap <= allowedGap;
  }

  bool _isLiveQueueEntryValid(Map<String, dynamic>? data) {
    if (data == null) return false;

    final status = (data['status'] ?? '').toString();
    if (status != 'searching') return false;
    if (data['matchId'] != null) return false;

    return _timestampIsRecent(
      data['lastHeartbeatAt'] ?? data['updatedAt'],
      maxAge: _liveSearchMaxAge,
    );
  }

  bool _isAvailableForLiveMatch(Map<String, dynamic>? userData) {
    final presence = Map<String, dynamic>.from(
      userData?['presence'] as Map? ?? {},
    );

    final status = (presence['status'] ?? 'offline').toString();
    final inMatch = presence['inMatch'] == true;

    if (inMatch) return false;

    // Para matchmaking público exigimos que el jugador esté activamente
    // buscando. Esto evita emparejar usuarios online que ya salieron de cola.
    if (status != 'searching_match') return false;

    return _timestampIsRecent(
      presence['updatedAt'] ?? presence['lastSeenAt'],
      maxAge: _presenceMaxAge,
    );
  }

  /// Busca candidatos con query normal (FUERA del transaction),
  /// y luego intenta reclamar a uno con transaction.
  ///
  /// Además valida Presence dentro del transaction para evitar emparejar
  /// usuarios offline, en otra partida o atrapados en una cola vieja.
  ///
  /// Retorna matchId si logró crear/reclamar match, o null si no.
  Future<String?> tryFindLiveOpponent({
    required String categoryId,
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 10,
    int winReward = 2,
    String myDisplayName = 'Host',
    bool ranked = false,
  }) async {
    final meRef = _liveSearchRef(uid);
    final meUserRef = _userRef(uid);

    final meSnap = await meRef.get();
    final meData = meSnap.data();
    if (!_isLiveQueueEntryValid(meData)) {
      return null;
    }

    final myTotal = (meData?['totalQuestions'] as int?) ?? totalQuestions;
    final myTime =
        (meData?['timePerQuestionSec'] as int?) ?? timePerQuestionSec;
    final myWinReward = (meData?['winReward'] as int?) ?? winReward;

    final qs = await _db
        .collection('live_search')
        .where('status', isEqualTo: 'searching')
        .where('categoryId', isEqualTo: categoryId)
        .where('difficulty', isEqualTo: difficulty)
        .where('ranked', isEqualTo: ranked)
        .limit(20)
        .get();

    final candidates = qs.docs.where((d) => d.id != uid).toList();
    if (candidates.isEmpty) return null;

    for (final oppDoc in candidates) {
      final oppUid = oppDoc.id;
      final oppRef = _liveSearchRef(oppUid);
      final oppUserRef = _userRef(oppUid);
      final matchId = _db.collection('matches').doc().id;

      final claimed = await _db.runTransaction<bool>((tx) async {
        final meTxSnap = await tx.get(meRef);
        final oppTxSnap = await tx.get(oppRef);
        final meUserSnap = await tx.get(meUserRef);
        final oppUserSnap = await tx.get(oppUserRef);

        final meTx = meTxSnap.data();
        final oppTx = oppTxSnap.data();
        final meUser = meUserSnap.data();
        final oppUser = oppUserSnap.data();

        if (!_isLiveQueueEntryValid(meTx)) return false;
        if (!_isLiveQueueEntryValid(oppTx)) return false;
        if (!_isAvailableForLiveMatch(meUser)) return false;
        if (!_isAvailableForLiveMatch(oppUser)) return false;
        if ((meTx?['ranked'] == true) != ranked) return false;
        if ((oppTx?['ranked'] == true) != ranked) return false;
        if (ranked &&
            !_ratingsAreCompatible(
              myQueue: meTx,
              opponentQueue: oppTx,
            )) {
          return false;
        }

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

        tx.set(
          meUserRef,
          {
            'presence': {
              'status': 'in_match',
              'inMatch': true,
              'lastSeenAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return true;
      });

      if (!claimed) continue;

      final matchRef = _db.collection('matches').doc(matchId);
      final oppName = (oppDoc.data()['displayName'] ?? 'Guest').toString();
      final myAvatarId = (meData?['avatarId'] ?? 'avatar_1').toString();
      final myFrameId = (meData?['equippedFrame'] ?? '').toString();
      final myBestLeagueId = (meData?['bestLeagueId'] ?? '').toString();

      final oppAvatarId = (oppDoc.data()['avatarId'] ?? 'avatar_1').toString();
      final oppFrameId = (oppDoc.data()['equippedFrame'] ?? '').toString();
      final oppBestLeagueId = (oppDoc.data()['bestLeagueId'] ?? '').toString();

      final questions = await _generateFixedQuestions(
        categoryId: categoryId,
        difficulty: difficulty,
        total: myTotal,
      );

      final code = _randomCode(5);

      final myName =
          (meData?['displayName'] ?? myDisplayName).toString().trim();

      final finalMyName = myName.isEmpty ? 'Player' : myName;

      await matchRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'waiting',
        'mode': 'fixed',
        'matchmakingType': ranked ? 'ranked_flexible_mmr' : 'casual_public',
        'ranked': ranked,
        'affectsPvpRating': ranked,
        'hostInitialPvpRating':
            _safeInt(meData?['pvpRating'], _defaultPvpRating),
        'guestInitialPvpRating':
            _safeInt(oppDoc.data()['pvpRating'], _defaultPvpRating),
        'matchmakingRatingGap':
            (_safeInt(meData?['pvpRating'], _defaultPvpRating) -
                    _safeInt(oppDoc.data()['pvpRating'], _defaultPvpRating))
                .abs(),
        'hostPvpLeagueId': PvpLeagueService.instance
            .leagueForRating(_safeInt(meData?['pvpRating'], _defaultPvpRating))
            .id,
        'guestPvpLeagueId': PvpLeagueService.instance
            .leagueForRating(
                _safeInt(oppDoc.data()['pvpRating'], _defaultPvpRating))
            .id,
        'hostPvpLeagueName': PvpLeagueService.instance
            .leagueForRating(_safeInt(meData?['pvpRating'], _defaultPvpRating))
            .name,
        'guestPvpLeagueName': PvpLeagueService.instance
            .leagueForRating(
                _safeInt(oppDoc.data()['pvpRating'], _defaultPvpRating))
            .name,
        'matchmakingWaitSec': max(
          _searchAgeSeconds(meData),
          _searchAgeSeconds(oppDoc.data()),
        ),
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
            'displayName': finalMyName,
            'avatarId': myAvatarId,
            'equippedFrame': myFrameId,
            'bestLeagueId': myBestLeagueId,
            'score': 0,
            'ready': false,
            'finished': false,
          },
          oppUid: {
            'displayName': oppName,
            'avatarId': oppAvatarId,
            'equippedFrame': oppFrameId,
            'bestLeagueId': oppBestLeagueId,
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
    bool ranked = false,
  }) async {
    final matchRef = _db.collection('matches').doc();

    final questions = await _generateFixedQuestions(
      categoryId: categoryId,
      difficulty: difficulty,
      total: totalQuestions,
    );

    final code = _randomCode(5);
    final userSnap = await _userRef(uid).get();
    final userData = userSnap.data() ?? {};

    final avatarId = (userData['avatarId'] ?? 'avatar_1').toString();
    final frameId = (userData['equippedFrame'] ?? '').toString();
    final bestLeagueId = (userData['bestLeagueId'] ?? '').toString();

    await matchRef.set({
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'waiting',
      'mode': 'fixed',
      'matchType': ranked ? 'ranked_private' : 'private',
      'ranked': ranked,
      'affectsPvpRating': ranked,
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
          'avatarId': avatarId,
          'equippedFrame': frameId,
          'bestLeagueId': bestLeagueId,
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

    final userSnap = await _userRef(uid).get();
    final userData = userSnap.data() ?? {};

    final avatarId = (userData['avatarId'] ?? 'avatar_1').toString();
    final frameId = (userData['equippedFrame'] ?? '').toString();
    final bestLeagueId = (userData['bestLeagueId'] ?? '').toString();

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
          'avatarId': avatarId,
          'equippedFrame': frameId,
          'bestLeagueId': bestLeagueId,
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
    final userSnap = await _userRef(uid).get();
    final userData = userSnap.data() ?? {};

    final avatarId = (userData['avatarId'] ?? 'avatar_1').toString();
    final frameId = (userData['equippedFrame'] ?? '').toString();
    final bestLeagueId = (userData['bestLeagueId'] ?? '').toString();

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
          'avatarId': avatarId,
          'equippedFrame': frameId,
          'bestLeagueId': bestLeagueId,
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

      tx.update(ref, {
        'players.$uid.finished': true,
        'players.$uid.finishedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> finalizeMatchIfComplete(String matchId) async {
    // La finalización real la hace Firebase Functions.
    return;
  }

  Future<void> forceFinalizeMatch(String matchId) async {
    // La finalización real la hace Firebase Functions.
    return;
  }

  // ============================================================
  // REMATCH SYSTEM
  // ============================================================

  Future<void> requestRematch(String matchId) async {
    final ref = _db.collection('matches').doc(matchId);

    final snap = await ref.get();
    final data = snap.data();

    if (data == null) {
      throw Exception('Match no encontrado');
    }

    final hostUid = (data['hostUid'] ?? '').toString();
    final guestUid = (data['guestUid'] ?? '').toString();

    final opponentUid = uid == hostUid ? guestUid : hostUid;

    final players = Map<String, dynamic>.from(data['players'] ?? {});
    final myPlayer = Map<String, dynamic>.from(players[uid] ?? {});
    final myName = (myPlayer['displayName'] ?? 'Player').toString();

    final rematchRequests =
        Map<String, dynamic>.from(data['rematchRequests'] ?? {});

    final opponentAlreadyAccepted = rematchRequests[opponentUid] == true;

    await _notificationService.markRematchRequestNotificationsAsRead(
      matchId: matchId,
    );

    await ref.set({
      'rematchRequests': {
        uid: true,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!opponentAlreadyAccepted && opponentUid.isNotEmpty) {
      try {
        await _notificationService.createNotification(
          targetUid: opponentUid,
          type: 'rematch_request',
          title: 'Rematch requested',
          body: '$myName wants a rematch.',
          data: {
            'matchId': matchId,
          },
        );
      } catch (_) {}
    }

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

      final ranked = data['ranked'] == true;
      final affectsPvpRating = data['affectsPvpRating'] == true || ranked;
      final matchmakingType = (data['matchmakingType'] ?? '').toString();

      tx.set(newRef, {
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'playing',
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
            'ready': true,
            'finished': false,
          },
          guestUid: {
            'displayName': guestName,
            'score': 0,
            'ready': true,
            'finished': false,
          },
        },
        'startAt': FieldValue.serverTimestamp(),
        'endedAt': null,
        'winnerUid': null,
        'rewarded': false,
        'matchCode': code,
        'ranked': ranked,
        'affectsPvpRating': affectsPvpRating,
        'matchmakingType': matchmakingType.isEmpty
            ? (ranked ? 'ranked_rematch' : 'casual_rematch')
            : matchmakingType,
        'previousMatchId': matchId,
      });

      // ✅ marca el match viejo
      tx.update(oldRef, {
        'rematchMatchId': newRef.id,
      });

      return newRef.id;
    });
  }

  /// Marks a live match finished when the opponent disconnects. This only
  /// sets match-doc status fields — it does NOT compute or write any
  /// reward/rating itself. Setting both players' `finished:true` here (with
  /// `rewarded` left unset) lets the server-side `finalizePvpMatch` Cloud
  /// Function's trigger guard fire, which then computes and applies the
  /// disconnect bonus/penalty authoritatively.
  Future<void> forceFinishMatchByDisconnect({
    required String matchId,
    required String winnerUid,
  }) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? '').toString();
      if (status == 'finished') return;

      final hostUid = (data['hostUid'] ?? '').toString();
      final guestUid = (data['guestUid'] ?? '').toString();
      if (winnerUid != hostUid && winnerUid != guestUid) return;

      final loserUid = winnerUid == hostUid ? guestUid : hostUid;
      if (loserUid.isEmpty || loserUid == winnerUid) return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      if (!players.containsKey(winnerUid)) return;

      tx.update(ref, {
        'winnerUid': winnerUid,
        'finishReason': 'opponent_disconnected',
        'players.$winnerUid.finished': true,
        'players.$loserUid.finished': true,
      });
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
          'challengerName': challengerDisplayName,
          'categoryId': categoryId,
          'difficulty': difficulty,
          'totalQuestions': totalQuestions,
          'timePerQuestionSec': timePerQuestionSec,
        },
      );
    } catch (_) {}

    return matchRef.id;
  }

  Future<void> declineAsyncMatch({
    required String matchId,
  }) async {
    final ref = _db.collection('async_matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();

      if (data == null) {
        throw Exception('Reto no encontrado');
      }

      final challengerUid = (data['challengerUid'] ?? '').toString();
      final challengedUid = (data['challengedUid'] ?? '').toString();

      if (uid != challengerUid && uid != challengedUid) {
        throw Exception('No perteneces a este reto');
      }

      final status = (data['status'] ?? '').toString();

      if (status == 'completed' || status == 'declined') {
        return;
      }

      tx.set(
          ref,
          {
            'status': 'declined',
            'declinedByUid': uid,
            'declinedAt': FieldValue.serverTimestamp(),
            'lastUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
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

    // Reward computation + "you won/lost" result notifications are now
    // handled server-side by the finalizeAsyncPvpMatch Cloud Function,
    // triggered by the challengerStatus/challengedStatus update above.
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

  static const Duration _questionFetchTimeout = Duration(seconds: 15);

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

    final snap = await col.get().timeout(
          _questionFetchTimeout,
          onTimeout: () => throw Exception(
            'No se pudo conectar. Revisa tu conexión e inténtalo de nuevo.',
          ),
        );
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
        .get()
        .timeout(
          _questionFetchTimeout,
          onTimeout: () => throw Exception(
            'No se pudo conectar. Revisa tu conexión e inténtalo de nuevo.',
          ),
        );

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

      final snap = await col.get().timeout(
            _questionFetchTimeout,
            onTimeout: () => throw Exception(
              'No se pudo conectar. Revisa tu conexión e inténtalo de nuevo.',
            ),
          );
      if (snap.docs.isEmpty) continue;

      final pick = snap.docs[rnd.nextInt(snap.docs.length)].data();
      out.add(pick);
    }

    return out;
  }
}
