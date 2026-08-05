import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'economy_service.dart';
import 'locale_controller.dart';
import 'notification_service.dart';
import 'pvp_league_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

class MatchService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _notificationService = NotificationService.instance;

  String get uid => _auth.currentUser!.uid;

  // Resolved from the acting user's own device locale — correct for
  // exceptions, since they always surface back to whoever called this.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

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
    int timePerQuestionSec = 15,
    int winReward = EconomyService.defaultPvpWinReward,
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
          _l10n.serviceRankedCooldown(_formatCooldownRemaining(cooldownUntil)),
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

  /// Finds and pairs with a live opponent — entirely server-side
  /// (tryFindLiveOpponent Cloud Function), since the candidate scan and
  /// claim used to write directly to *other* players' `live_search` docs
  /// from the client. firestore.rules could narrow that down but never
  /// fully close it (a client could still plant a fake "matched" claim on
  /// an actively-searching victim's queue entry); Admin SDK bypasses that
  /// problem entirely. Every match parameter (category, difficulty,
  /// ranked, reward, etc.) is read server-side from the caller's own
  /// queue doc, already written by `startLiveSearch` — this call takes no
  /// arguments. Returns matchId if paired, null if no opponent yet.
  Future<String?> tryFindLiveOpponent() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'tryFindLiveOpponent',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call();

      return (result.data as Map)['matchId'] as String?;
    } on FirebaseFunctionsException {
      return null;
    }
  }

  // ============================================================
  // LIVE 1 vs 1 (matches) - lo que ya tenías
  // ============================================================

  Future<String> createFixedMatch({
    required String categoryId,
    int totalQuestions = 10,
    int timePerQuestionSec = 15,
    int winReward = EconomyService.defaultPvpWinReward,
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

  /// Looks up a private room by its shared code and claims the guest slot
  /// — entirely server-side (joinMatchByCode Cloud Function), since the
  /// old client-side two-step (resolveMatchIdByCode + joinMatch) could
  /// never actually work: joinMatch's own read of the match doc needs
  /// firestore.rules' host/guest check to pass, but the joiner isn't
  /// either yet at that point, so it was always rejected with
  /// permission-denied.
  Future<String> joinMatchByCode(String code) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'joinMatchByCode',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'code': code});

      return (result.data as Map)['matchId'].toString();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceRoomNotFound);
    }
  }

  Future<void> setReady(String matchId, bool ready) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception(_l10n.serviceRoomNotFound);

      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'waiting').toString();
      if (status != 'waiting') return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      if (!players.containsKey(uid)) {
        throw Exception(_l10n.serviceNotInRoom);
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

  /// Cancels a match still in the lobby (`status == 'waiting'`, nothing of
  /// economic consequence has happened yet) — used when the other player
  /// goes stale before both are ready, so the remaining player isn't stuck
  /// on match_lobby_screen.dart forever with no way out. `status` isn't
  /// locked in firestore.rules (tryStartMatchIfReady already transitions
  /// it client-side), so no rules change is needed for this.
  Future<void> cancelWaitingMatch(String matchId) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final status = (data['status'] ?? 'waiting').toString();
      if (status != 'waiting') return;

      tx.update(ref, {'status': 'cancelled'});
    });
  }

  // `score` here is still an optimistic, client-computed value used only
  // for this player's own live in-match display — finalizePvpMatch ignores
  // it entirely and recomputes the authoritative score itself from
  // `players.$uid.answers` (this player's actual selected option per
  // question) against the match's own stored `questions`, so a modified
  // client reporting an inflated deltaScore can no longer affect the real
  // result. The per-question `answers` map (keyed by questionIndex) also
  // makes this a one-shot write per question, same as `score` was before.
  Future<void> submitAnswer({
    required String matchId,
    required int questionIndex,
    required int selectedAnswerIndex,
    required int deltaScore,
  }) async {
    final ref = _db.collection('matches').doc(matchId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final players = Map<String, dynamic>.from(data['players'] ?? {});
      if (!players.containsKey(uid)) {
        throw Exception(_l10n.serviceNotInRoom);
      }

      final me = Map<String, dynamic>.from(players[uid] ?? {});
      final answers = Map<String, dynamic>.from(me['answers'] ?? {});

      final key = questionIndex.toString();
      if (answers.containsKey(key)) return;

      tx.update(ref, {
        'players.$uid.answers.$key': selectedAnswerIndex,
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
      throw Exception(_l10n.serviceMatchNotFound);
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
        final recipientL10n =
            await _notificationService.l10nForRecipient(opponentUid);

        await _notificationService.createNotification(
          targetUid: opponentUid,
          type: 'rematch_request',
          title: recipientL10n.serviceRematchRequestedTitle,
          body: recipientL10n.serviceRematchRequestedBody(myName),
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
          ((data['timePerQuestionSec'] ?? 15) as num).toInt();

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

  /// Claims that the opponent in a live match has disconnected, ending it
  /// in the caller's favor — server-verified (claimOpponentDisconnected
  /// Cloud Function independently re-reads the opponent's own presence
  /// doc before honoring this), since firestore.rules no longer lets a
  /// client write `winnerUid`/`finishReason` directly. Throws if the
  /// server disagrees (opponent still looks active).
  Future<void> claimOpponentDisconnected(String matchId) async {
    await FirebaseFunctions.instance
        .httpsCallable(
          'claimOpponentDisconnected',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({'matchId': matchId});
  }
  // ============================================================
  // ASYNC (diferido) 1 vs 1 (async_matches) - existente
  // ============================================================

  Future<String> createAsyncFixedMatch({
    required String challengedUid,
    required String categoryId,
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 15,
    int winReward = EconomyService.defaultPvpWinReward,
    String challengerDisplayName = 'Player',
    String challengedDisplayName = 'Player',
  }) async {
    if (challengedUid.trim().isEmpty) {
      throw Exception(_l10n.serviceChallengedUidEmpty);
    }
    if (challengedUid == uid) {
      throw Exception(_l10n.serviceCannotChallengeSelfNoPeriod);
    }

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
      final recipientL10n =
          await _notificationService.l10nForRecipient(challengedUid);

      await _notificationService.createNotification(
        targetUid: challengedUid,
        type: 'match_invite',
        title: recipientL10n.serviceNewAsyncChallengeTitle,
        body: recipientL10n.serviceNewAsyncChallengeBody(
          challengerDisplayName,
        ),
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
        throw Exception(_l10n.serviceChallengeNotFound);
      }

      final challengerUid = (data['challengerUid'] ?? '').toString();
      final challengedUid = (data['challengedUid'] ?? '').toString();

      if (uid != challengerUid && uid != challengedUid) {
        throw Exception(_l10n.serviceNotYourChallenge);
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

  // `score` is still stored for this player's own live/result display
  // (e.g. active_matches_screen.dart, result screens) but
  // finalizeAsyncPvpMatch ignores it and recomputes the authoritative
  // score itself from `answers` (this player's actual selected option per
  // question, keyed by questionIndex) against the match's own stored
  // `questions` — a modified client reporting an inflated score can no
  // longer affect the real result.
  Future<void> submitAsyncResult({
    required String matchId,
    required int score,
    required Map<int, int> answers,
  }) async {
    final ref = _db.collection('async_matches').doc(matchId);
    final answersMap = answers.map((k, v) => MapEntry(k.toString(), v));

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) throw Exception(_l10n.serviceAsyncMatchNotFound);

      final challengerUid = (data['challengerUid'] ?? '').toString();
      final challengedUid = (data['challengedUid'] ?? '').toString();

      if (uid != challengerUid && uid != challengedUid) {
        throw Exception(_l10n.serviceNotYourMatch);
      }

      if (uid == challengerUid) {
        final st = (data['challengerStatus'] ?? 'pending').toString();
        if (st == 'finished') return;

        tx.update(ref, {
          'challengerStatus': 'finished',
          'challenger.score': score,
          'challenger.answers': answersMap,
          'challenger.finishedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final st = (data['challengedStatus'] ?? 'pending').toString();
        if (st == 'finished') return;

        tx.update(ref, {
          'challengedStatus': 'finished',
          'challenged.score': score,
          'challenged.answers': answersMap,
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
          final recipientL10n =
              await _notificationService.l10nForRecipient(opponentUid);

          await _notificationService.createNotification(
            targetUid: opponentUid,
            type: 'match_turn',
            title: recipientL10n.serviceYourTurnTitle,
            body: recipientL10n.serviceYourTurnBody(myName),
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

  final _secureRandom = Random.secure();

  String _randomCode(int len) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final b = StringBuffer();
    for (int i = 0; i < len; i++) {
      b.write(chars[_secureRandom.nextInt(chars.length)]);
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
          onTimeout: () => throw Exception(_l10n.serviceConnectionTimeout),
        );
    final docs = snap.docs;
    if (docs.isEmpty) {
      throw Exception(_l10n.servicePoolEmptyForCategory(categoryId));
    }

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
          onTimeout: () => throw Exception(_l10n.serviceConnectionTimeout),
        );

    final categories = catsSnap.docs.map((d) => d.id).toList();
    if (categories.isEmpty) {
      throw Exception(_l10n.serviceNoActiveCategories);
    }

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
            onTimeout: () => throw Exception(_l10n.serviceConnectionTimeout),
          );
      if (snap.docs.isEmpty) continue;

      final pick = snap.docs[rnd.nextInt(snap.docs.length)].data();
      out.add(pick);
    }

    return out;
  }
}
