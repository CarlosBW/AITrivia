import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'economy_service.dart';
import 'locale_controller.dart';
import 'match_rules.dart' as rules;
import 'notification_service.dart';
import 'pvp_league_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

/// Where the server says a player stands in an async match.
///
/// [remainingMs] is a duration rather than a deadline on purpose: the
/// countdown runs off it directly, so a wrong device clock can't buy time.
class AsyncPvpTurn {
  const AsyncPvpTurn({
    required this.index,
    required this.finished,
    required this.remainingMs,
    required this.answers,
  });

  /// Question to show; equals the question count once [finished].
  final int index;
  final bool finished;
  final int remainingMs;

  /// Everything banked so far, keyed by question index.
  final Map<int, int> answers;
}

/// What the server banked for one answer, plus the next question's clock.
class AsyncPvpAnswer {
  const AsyncPvpAnswer({
    required this.storedIndex,
    required this.timedOut,
    required this.nextIndex,
    required this.nextRemainingMs,
    required this.finished,
  });

  /// The option actually recorded — -1 when the answer arrived too late,
  /// whatever the client sent.
  final int storedIndex;
  final bool timedOut;
  final int nextIndex;

  /// Clock for [nextIndex], counted from the moment this call returned.
  /// Covers the play screen's reveal pause, so it is a question's full time
  /// plus that pause.
  final int nextRemainingMs;
  final bool finished;
}

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

  // Las reglas viven en match_rules.dart; aqui solo se traduce de los
  // tipos de Firestore a valores planos. Esa frontera es lo que las hace
  // testeables sin Firestore ni reloj.
  Timestamp? _activePvpCooldownUntil(Map<String, dynamic>? userData) {
    final raw = userData?['pvpCooldownUntil'];
    if (raw is! Timestamp) return null;

    final active = rules.activeCooldownUntil(raw.toDate(), DateTime.now());
    return active == null ? null : raw;
  }

  String _formatCooldownRemaining(Timestamp cooldownUntil) {
    return rules.formatCooldownRemaining(
      cooldownUntil.toDate().difference(DateTime.now()),
    );
  }

  Future<Timestamp?> getActivePvpCooldownUntil() async {
    final snap = await _userRef(uid).get();
    return _activePvpCooldownUntil(snap.data());
  }

  DocumentReference<Map<String, dynamic>> _userRef(String userId) =>
      _db.collection('users').doc(userId);

  int _safeInt(dynamic value, int fallback) =>
      rules.safeInt(value, fallback);

  bool _isLiveQueueEntryValid(Map<String, dynamic>? data) {
    if (data == null) return false;

    final heartbeat = data['lastHeartbeatAt'] ?? data['updatedAt'];

    return rules.isLiveQueueEntryValid(
      status: (data['status'] ?? '').toString(),
      matchId: data['matchId'],
      lastSeenAt: heartbeat is Timestamp ? heartbeat.toDate() : null,
      now: DateTime.now(),
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
      await _notificationService.notifyUser(
        targetUid: opponentUid,
        type: 'rematch_request',
        data: {'matchId': matchId},
      );
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

  /// Creates an async challenge. Server-side (createAsyncPvpMatch), because
  /// firestore.rules can check the shape of a document but not where its
  /// contents came from — so the client used to pick the `questions`
  /// itself. A modified client could write its own questions, with its own
  /// `answerIndex`, into a match the opponent then had to play, and could
  /// set any `timePerQuestionSec` it liked — the field every server-anchored
  /// deadline is now measured from.
  ///
  /// The reward is the server's constant, and both display names are read
  /// from the two user docs, so nothing shown to the other player travels
  /// from here. The "you've been challenged" notification is sent by the
  /// same call.
  Future<String> createAsyncFixedMatch({
    required String challengedUid,
    required String categoryId,
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 15,
  }) async {
    if (challengedUid.trim().isEmpty) {
      throw Exception(_l10n.serviceChallengedUidEmpty);
    }
    if (challengedUid == uid) {
      throw Exception(_l10n.serviceCannotChallengeSelfNoPeriod);
    }

    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'createAsyncPvpMatch',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call({
      'challengedUid': challengedUid,
      'categoryId': categoryId,
      'difficulty': difficulty,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
    });

    return ((result.data as Map)['matchId'] ?? '').toString();
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

  /// Opens (or resumes) my turn in an async match — the only way to learn
  /// which question to show and how long is left on it.
  ///
  /// Playing an async match used to be a direct client write, which left
  /// two holes firestore.rules could not close: the rule had to allow "this
  /// player edits their own answers map", so a modified client could go
  /// back and fix its wrong answers any time before the match finalized,
  /// and the per-question countdown only ever existed in the play screen,
  /// so a modified client could simply not run it. The server now stamps
  /// each question's deadline and judges every answer against it.
  ///
  /// A deadline is stamped once per question and never refreshed: leave
  /// mid-question and come back after it passed and that question is banked
  /// as a timeout, which is what makes leaving to look an answer up
  /// expensive.
  Future<AsyncPvpTurn> openAsyncTurn({required String matchId}) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'openAsyncPvpTurn',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({'matchId': matchId});

    final data = Map<String, dynamic>.from(result.data as Map);

    return AsyncPvpTurn(
      index: (data['index'] as num).toInt(),
      finished: data['finished'] == true,
      remainingMs: ((data['remainingMs'] ?? 0) as num).toInt(),
      answers: _parseAnswerMap(data['answers']),
    );
  }

  /// Banks one answer and returns the clock for the question after it.
  ///
  /// [selectedAnswerIndex] is -1 when the local countdown ran out. The
  /// server banks -1 too for anything that arrives past its deadline, and
  /// -1 never matches a valid `answerIndex`, so a timeout scores as wrong
  /// exactly like a wrong tap.
  ///
  /// Throws when the server can't line the call up with the turn it expects
  /// (already answered, out of order, never opened) — the caller's answer
  /// to all of those is the same: call [openAsyncTurn] again and take the
  /// server's word for where the run is.
  Future<AsyncPvpAnswer> submitAsyncAnswer({
    required String matchId,
    required int questionIndex,
    required int selectedAnswerIndex,
  }) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'submitAsyncPvpAnswer',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({
      'matchId': matchId,
      'questionIndex': questionIndex,
      'selectedIndex': selectedAnswerIndex,
    });

    final data = Map<String, dynamic>.from(result.data as Map);

    return AsyncPvpAnswer(
      storedIndex: ((data['storedIndex'] ?? -1) as num).toInt(),
      timedOut: data['timedOut'] == true,
      nextIndex: ((data['nextIndex'] ?? 0) as num).toInt(),
      nextRemainingMs: ((data['nextRemainingMs'] ?? 0) as num).toInt(),
      finished: data['finished'] == true,
    );
  }

  /// Closes my round and returns the score the server computed from the
  /// answers it banked — the same one finalizeAsyncPvpMatch settles the
  /// match on, so the result screen can't show a number that disagrees
  /// with the outcome.
  Future<int> finishAsyncMatch({required String matchId}) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'finishAsyncPvpMatch',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({'matchId': matchId});

    final score = ((result.data as Map)['score'] ?? 0) as num;

    // =========================================================
// TURN / RESULT NOTIFICATIONS
// =========================================================

    final ref = _db.collection('async_matches').doc(matchId);

    try {
      final snap = await ref.get();
      final data = snap.data();

      if (data != null) {
        final challengerUid = (data['challengerUid'] ?? '').toString();
        final challengedUid = (data['challengedUid'] ?? '').toString();

        final challengerStatus =
            (data['challengerStatus'] ?? 'pending').toString();
        final challengedStatus =
            (data['challengedStatus'] ?? 'pending').toString();

        final opponentUid =
            uid == challengerUid ? challengedUid : challengerUid;

        if (challengerStatus != 'finished' || challengedStatus != 'finished') {
          await _notificationService.notifyUser(
            targetUid: opponentUid,
            type: 'match_turn',
            data: {'matchId': matchId},
          );
        }
      }
    } catch (_) {}

    // Reward computation + "you won/lost" result notifications are now
    // handled server-side by the finalizeAsyncPvpMatch Cloud Function,
    // triggered by the challengerStatus/challengedStatus update above.

    return score.toInt();
  }

  /// An answers map as the callables return it, keyed by question index.
  Map<int, int> _parseAnswerMap(Object? raw) => rules.parseAnswerMap(raw);

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
