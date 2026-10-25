import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/user_facing_error.dart';
import '../l10n/l10n_for.dart';

class FriendService {
  FriendService._();

  static final FriendService instance = FriendService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  // Resolved from the acting user's own device locale — correct for
  // exceptions, since they always surface back to whoever called this.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  DocumentReference<Map<String, dynamic>> _userRef(String userId) {
    return _db.collection('users').doc(userId);
  }

  CollectionReference<Map<String, dynamic>> _friendsCol(String userId) {
    return _userRef(userId).collection('friends');
  }

  CollectionReference<Map<String, dynamic>> _requestsCol(String userId) {
    return _userRef(userId).collection('friend_requests');
  }

  CollectionReference<Map<String, dynamic>> _sentRequestsCol(String userId) {
    return _userRef(userId).collection('sent_friend_requests');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchFriends({
    int limit = 100,
  }) {
    return _friendsCol(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchIncomingRequests({
    int limit = 50,
  }) {
    return _requestsCol(uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOutgoingRequests({
    int limit = 50,
  }) {
    return _sentRequestsCol(uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> searchUsersByUsername({
    required String query,
    int limit = 20,
  }) async {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      throw Exception(_l10n.serviceEnterUsername);
    }

    return _db
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: q)
        .where('usernameLower', isLessThan: '$q\uf8ff')
        .limit(limit)
        .get()
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception(_l10n.serviceConnectionTimeout),
        );
  }

  /// Sends a friend request through the `sendFriendRequest` Cloud
  /// Function, which writes both sides and notifies the other player.
  /// It used to be written here straight into their inbox, which let a
  /// modified client put any name on it or re-open a rejected request.
  Future<void> sendFriendRequest({
    required String targetUid,
  }) async {
    if (targetUid.trim().isEmpty) {
      throw Exception(_l10n.serviceInvalidUser);
    }

    if (targetUid == uid) {
      throw Exception(_l10n.serviceCannotAddSelf);
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'sendFriendRequest',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'targetUid': targetUid});
    } catch (e) {
      throw Exception(userFacingError(_l10n, e));
    }
  }

  // The actual friendship write (both mirror docs) is now Cloud-Function
  // only — see acceptFriendRequest in functions/src/index.ts — since the
  // rule that let either side write `friends/{friendId}` directly (needed
  // for this two-sided write) also let a client fabricate a "friend" doc
  // with no real request ever having been sent or accepted.
  Future<void> acceptFriendRequest({
    required String requesterUid,
  }) async {
    if (requesterUid.trim().isEmpty || requesterUid == uid) {
      throw Exception(_l10n.serviceInvalidRequest);
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'acceptFriendRequest',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'requesterUid': requesterUid});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(userFacingError(_l10n, e, fallback: _l10n.serviceCouldNotAcceptRequest));
    }
  }

  // Cloud-Function-only, same reasoning as acceptFriendRequest — rejecting
  // used to write directly into the requester's own `sent_friend_requests`
  // doc, which required a rule letting the target write into a stranger's
  // collection, letting a client forge entries there too.
  Future<void> rejectFriendRequest({
    required String requesterUid,
  }) async {
    if (requesterUid.trim().isEmpty) {
      throw Exception(_l10n.serviceInvalidRequest);
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'rejectFriendRequest',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'requesterUid': requesterUid});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(userFacingError(_l10n, e, fallback: _l10n.serviceCouldNotRejectRequest));
    }
  }

  Future<void> removeFriend({
    required String friendUid,
  }) async {
    if (friendUid.trim().isEmpty || friendUid == uid) {
      throw Exception(_l10n.serviceInvalidFriend);
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'removeFriend',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'friendUid': friendUid});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(userFacingError(_l10n, e, fallback: _l10n.serviceCouldNotRemoveFriend));
    }
  }
}
