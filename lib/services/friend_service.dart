import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'locale_controller.dart';
import 'notification_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

class FriendService {
  FriendService._();

  static final FriendService instance = FriendService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _notificationService = NotificationService.instance;

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

  Future<void> sendFriendRequest({
    required String targetUid,
  }) async {
    if (targetUid.trim().isEmpty) {
      throw Exception(_l10n.serviceInvalidUser);
    }

    if (targetUid == uid) {
      throw Exception(_l10n.serviceCannotAddSelf);
    }

    final myRef = _userRef(uid);
    final targetRef = _userRef(targetUid);

    final myFriendRef = _friendsCol(uid).doc(targetUid);
    final targetFriendRef = _friendsCol(targetUid).doc(uid);

    final requestRef = _requestsCol(targetUid).doc(uid);
    final sentRequestRef = _sentRequestsCol(uid).doc(targetUid);
    // The other direction — did they already request me? Search results
    // are a point-in-time snapshot, so it's possible for their request to
    // land in the window between rendering the "Add" button and tapping
    // it; without this check that would create a second, opposite-facing
    // pending request instead of surfacing the one already waiting.
    final reverseRequestRef = _requestsCol(uid).doc(targetUid);

    String notificationDisplayName = 'Player${uid.substring(0, 4)}';

    await _db.runTransaction((tx) async {
      final mySnap = await tx.get(myRef);
      final targetSnap = await tx.get(targetRef);
      final myFriendSnap = await tx.get(myFriendRef);
      final targetFriendSnap = await tx.get(targetFriendRef);
      final requestSnap = await tx.get(requestRef);
      final reverseRequestSnap = await tx.get(reverseRequestRef);

      if (!targetSnap.exists) {
        throw Exception(_l10n.serviceUserNotFound);
      }

      if (myFriendSnap.exists || targetFriendSnap.exists) {
        throw Exception(_l10n.serviceAlreadyFriends);
      }

      if (requestSnap.exists &&
          (requestSnap.data()?['status'] ?? 'pending') == 'pending') {
        throw Exception(_l10n.serviceRequestAlreadySent);
      }

      if (reverseRequestSnap.exists &&
          (reverseRequestSnap.data()?['status'] ?? 'pending') == 'pending') {
        throw Exception(_l10n.serviceRequestAlreadyReceived);
      }

      final myData = mySnap.data() ?? {};
      final targetData = targetSnap.data() ?? {};

      final displayName = (myData['displayName'] ??
              myData['username'] ??
              'Player${uid.substring(0, 4)}')
          .toString();

      notificationDisplayName = displayName;

      final username = (myData['username'] ?? displayName).toString();
      final avatarId = (myData['avatarId'] ?? 'avatar_1').toString();
      final equippedFrame = (myData['equippedFrame'] ?? 'bronze').toString();

      final bestLeagueId = (myData['bestLeagueId'] ?? 'bronze').toString();

      final targetDisplayName = (targetData['displayName'] ??
              targetData['username'] ??
              'Player${targetUid.substring(0, 4)}')
          .toString();

      final targetUsername =
          (targetData['username'] ?? targetDisplayName).toString();

      final targetAvatarId = (targetData['avatarId'] ?? 'avatar_1').toString();
      final targetEquippedFrame =
          (targetData['equippedFrame'] ?? 'bronze').toString();

      final targetBestLeagueId =
          (targetData['bestLeagueId'] ?? 'bronze').toString();

      final now = FieldValue.serverTimestamp();

      tx.set(
        requestRef,
        {
          'requesterUid': uid,
          'requesterDisplayName': displayName,
          'requesterUsername': username,
          'requesterAvatarId': avatarId,
          'requesterEquippedFrame': equippedFrame,
          'requesterBestLeagueId': bestLeagueId,
          'status': 'pending',
          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      tx.set(
        sentRequestRef,
        {
          'targetUid': targetUid,
          'targetDisplayName': targetDisplayName,
          'targetUsername': targetUsername,
          'targetAvatarId': targetAvatarId,
          'targetEquippedFrame': targetEquippedFrame,
          'targetBestLeagueId': targetBestLeagueId,
          'status': 'pending',
          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    });

    try {
      final recipientL10n =
          await _notificationService.l10nForRecipient(targetUid);

      await _notificationService.createNotification(
        targetUid: targetUid,
        type: 'friend_request',
        title: recipientL10n.serviceFriendRequestNotifTitle,
        body: recipientL10n.serviceFriendRequestNotifBody(
          notificationDisplayName,
        ),
        data: {
          'requesterUid': uid,
        },
      );
    } catch (_) {}
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
      throw Exception(e.message ?? _l10n.serviceCouldNotAcceptRequest);
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
      throw Exception(e.message ?? _l10n.serviceCouldNotRejectRequest);
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
      throw Exception(e.message ?? _l10n.serviceCouldNotRemoveFriend);
    }
  }
}
