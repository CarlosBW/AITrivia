import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'my_profile_service.dart';

/// Why a player is being reported; the server accepts exactly these.
enum PlayerReportReason {
  offensiveName('offensive_name'),
  cheating('cheating'),
  spamOrHarassment('spam_or_harassment'),
  other('other');

  const PlayerReportReason(this.id);

  final String id;
}

/// Reporting and blocking other players, and checking a username before
/// it's taken. All of it goes through Cloud Functions (reportPlayer,
/// blockPlayer, unblockPlayer, checkUsername); the app only reads its own
/// block list.
class PlayerSafetyService {
  PlayerSafetyService._();

  static final PlayerSafetyService instance = PlayerSafetyService._();

  static const Duration _timeout = Duration(seconds: 15);

  Stream<Set<String>>? _blocked;
  String? _blockedUid;
  Set<String>? _latestBlocked;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(name, options: HttpsCallableOptions(timeout: _timeout))
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// The uids this player blocked, as they change. One shared listener,
  /// like [MyProfileService.watchMe]: several screens filter on it.
  Stream<Set<String>> watchBlocked() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const {});

    if (_blocked == null || _blockedUid != uid) {
      _blockedUid = uid;
      _latestBlocked = null;
      _blocked = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('blocked')
          .snapshots()
          .map((snap) => _latestBlocked = {for (final d in snap.docs) d.id})
          // Unreadable (offline, or rules not deployed yet) means nothing
          // is filtered out, not that the screens using it fail.
          // The listener ends after an error, so the next caller starts
          // a fresh one.
          .handleError((Object _) => _blocked = null)
          .asBroadcastStream();
    }
    return withLatest(_blocked!, _latestBlocked);
  }

  /// The blocked players with the name they had when blocked, newest
  /// first, for the list in Profile.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchBlockedPlayers() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('blocked')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> report({
    required String targetUid,
    required PlayerReportReason reason,
    String details = '',
    String? matchId,
  }) async {
    await _call('reportPlayer', {
      'targetUid': targetUid,
      'reason': reason.id,
      'details': details,
      if (matchId != null) 'matchId': matchId,
    });
  }

  Future<void> block(String targetUid) async {
    await _call('blockPlayer', {'targetUid': targetUid});
  }

  Future<void> unblock(String targetUid) async {
    await _call('unblockPlayer', {'targetUid': targetUid});
  }

  /// Whether [username] may be taken. The server also takes back a
  /// refused name after the fact, so this is for telling the player
  /// before they commit to it.
  Future<bool> isUsernameAllowed(String username) async {
    final data = await _call('checkUsername', {'username': username});
    return data['allowed'] == true;
  }
}
