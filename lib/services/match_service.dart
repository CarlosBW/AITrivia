import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'economy_service.dart';
import 'locale_controller.dart';
import 'match_rules.dart' as rules;
import 'notification_service.dart';
import 'pvp_league_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/user_facing_error.dart';
import '../l10n/l10n_for.dart';

/// Where the server says a player stands in a PvP match, async or live.
///
/// [remainingMs] is a duration rather than a deadline on purpose: the
/// countdown runs off it directly, so a wrong device clock can't buy time.
class AsyncPvpTurn {
  const AsyncPvpTurn({
    required this.index,
    required this.finished,
    required this.remainingMs,
    required this.answers,
    this.verdicts = const {},
  });

  /// Question to show; equals the question count once [finished].
  final int index;
  final bool finished;
  final int remainingMs;

  /// Everything banked so far, keyed by question index.
  final Map<int, int> answers;

  /// Whether each banked answer was right, keyed by question index. The
  /// answer key itself never reaches the client during a match.
  final Map<int, bool> verdicts;

  int get correctCount => verdicts.values.where((v) => v).length;
}

/// What the server banked for one answer, plus the next question's clock.
class AsyncPvpAnswer {
  const AsyncPvpAnswer({
    required this.storedIndex,
    required this.correctIndex,
    required this.timedOut,
    required this.nextIndex,
    required this.nextRemainingMs,
    required this.finished,
  });

  /// The option actually recorded — -1 when the answer arrived too late,
  /// whatever the client sent.
  final int storedIndex;

  /// The right option, revealed only once this question is answered.
  final int correctIndex;

  bool get correct => storedIndex >= 0 && storedIndex == correctIndex;
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

  // Every write to a live match goes through a Cloud Function now. The
  // client used to create the match with its own questions and write its
  // own answers, readiness and rematches; the rules could check the shape
  // of those writes but not their contents. These calls mirror the async
  // ones: the server stamps each question's deadline, judges each answer
  // against a key the client can't read, and writes the scores.

  HttpsCallable _callable(String name, {int timeoutSeconds = 15}) =>
      FirebaseFunctions.instance.httpsCallable(
        name,
        options: HttpsCallableOptions(
          timeout: Duration(seconds: timeoutSeconds),
        ),
      );

  /// Creates a private room; the other player joins with its code.
  Future<String> createFixedMatch({
    required String categoryId,
    int totalQuestions = 10,
    int timePerQuestionSec = 15,
    int difficulty = 1,
    bool ranked = false,
  }) async {
    final result =
        await _callable('createPrivateLiveMatch', timeoutSeconds: 30).call({
      'categoryId': categoryId,
      'difficulty': difficulty,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
      'ranked': ranked,
    });
    return ((result.data as Map)['matchId'] ?? '').toString();
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
      throw Exception(userFacingError(_l10n, e, fallback: _l10n.serviceRoomNotFound));
    }
  }

  /// Marks me ready (or not) in the lobby; the server starts the match
  /// once both players are.
  Future<void> setReady(String matchId, bool ready) async {
    await _callable('setLiveMatchReady').call({
      'matchId': matchId,
      'ready': ready,
    });
  }

  /// Cancels a room still in the lobby, so the player left behind when the
  /// other one goes isn't stuck there.
  Future<void> cancelWaitingMatch(String matchId) async {
    await _callable('cancelLiveMatch').call({'matchId': matchId});
  }

  /// Opens (or resumes) my run through a live match. Same contract as
  /// [openAsyncTurn].
  Future<AsyncPvpTurn> openLiveTurn({required String matchId}) async {
    final result =
        await _callable('openLiveMatchTurn').call({'matchId': matchId});
    return _turnFrom(result.data);
  }

  /// Banks one live answer and returns the verdict and the next clock. Same
  /// contract as [submitAsyncAnswer].
  Future<AsyncPvpAnswer> submitLiveAnswer({
    required String matchId,
    required int questionIndex,
    required int selectedAnswerIndex,
  }) async {
    final result = await _callable('submitLiveMatchAnswer').call({
      'matchId': matchId,
      'questionIndex': questionIndex,
      'selectedIndex': selectedAnswerIndex,
    });
    return _answerFrom(result.data);
  }

  /// Closes my run; once both players have, the server settles the match.
  Future<void> setFinished(String matchId) async {
    await _callable('finishLiveMatch').call({'matchId': matchId});
  }

  // ============================================================
  // REMATCH SYSTEM
  // ============================================================

  /// Asks for a rematch. The server notifies the opponent on the first ask
  /// and creates the new match once both have asked, returning its id.
  Future<String?> requestRematch(String matchId) async {
    await _notificationService.markRematchRequestNotificationsAsRead(
      matchId: matchId,
    );
    final result = await _callable('requestLiveRematch', timeoutSeconds: 30)
        .call({'matchId': matchId});
    return (result.data as Map)['rematchMatchId']?.toString();
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

    return _turnFrom(result.data);
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

    return _answerFrom(result.data);
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

  AsyncPvpTurn _turnFrom(Object? raw) {
    final data = Map<String, dynamic>.from(raw as Map);
    final verdicts = <int, bool>{};
    final rawVerdicts = data['verdicts'];
    if (rawVerdicts is Map) {
      rawVerdicts.forEach((k, v) {
        final i = int.tryParse(k.toString());
        if (i != null) verdicts[i] = v == true;
      });
    }
    return AsyncPvpTurn(
      index: ((data['index'] ?? 0) as num).toInt(),
      finished: data['finished'] == true,
      remainingMs: ((data['remainingMs'] ?? 0) as num).toInt(),
      answers: _parseAnswerMap(data['answers']),
      verdicts: verdicts,
    );
  }

  AsyncPvpAnswer _answerFrom(Object? raw) {
    final data = Map<String, dynamic>.from(raw as Map);
    return AsyncPvpAnswer(
      storedIndex: ((data['storedIndex'] ?? -1) as num).toInt(),
      correctIndex: ((data['correctIndex'] ?? -1) as num).toInt(),
      timedOut: data['timedOut'] == true,
      nextIndex: ((data['nextIndex'] ?? 0) as num).toInt(),
      nextRemainingMs: ((data['nextRemainingMs'] ?? 0) as num).toInt(),
      finished: data['finished'] == true,
    );
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
}
