import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notification_service.dart';

class FriendService {
  FriendService._();

  static final FriendService instance = FriendService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _notificationService = NotificationService.instance;

  String get uid => _auth.currentUser!.uid;

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
      throw Exception('Escribe un nombre de usuario.');
    }

    return _db
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: q)
        .where('usernameLower', isLessThan: '$q\uf8ff')
        .limit(limit)
        .get()
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception(
            'No se pudo conectar. Revisa tu conexi\u00f3n e int\u00e9ntalo de nuevo.',
          ),
        );
  }

  Future<void> sendFriendRequest({
    required String targetUid,
  }) async {
    if (targetUid.trim().isEmpty) {
      throw Exception('Usuario inválido.');
    }

    if (targetUid == uid) {
      throw Exception('No puedes agregarte a ti mismo.');
    }

    final myRef = _userRef(uid);
    final targetRef = _userRef(targetUid);

    final myFriendRef = _friendsCol(uid).doc(targetUid);
    final targetFriendRef = _friendsCol(targetUid).doc(uid);

    final requestRef = _requestsCol(targetUid).doc(uid);
    final sentRequestRef = _sentRequestsCol(uid).doc(targetUid);

    String notificationDisplayName = 'Player${uid.substring(0, 4)}';

    await _db.runTransaction((tx) async {
      final mySnap = await tx.get(myRef);
      final targetSnap = await tx.get(targetRef);
      final myFriendSnap = await tx.get(myFriendRef);
      final targetFriendSnap = await tx.get(targetFriendRef);
      final requestSnap = await tx.get(requestRef);

      if (!targetSnap.exists) {
        throw Exception('El usuario no existe.');
      }

      if (myFriendSnap.exists || targetFriendSnap.exists) {
        throw Exception('Ya son amigos.');
      }

      if (requestSnap.exists &&
          (requestSnap.data()?['status'] ?? 'pending') == 'pending') {
        throw Exception('Solicitud ya enviada.');
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
      await _notificationService.createNotification(
        targetUid: targetUid,
        type: 'friend_request',
        title: 'New friend request',
        body: '$notificationDisplayName wants to add you as a friend.',
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
      throw Exception('Solicitud inválida.');
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('acceptFriendRequest')
          .call({'requesterUid': requesterUid});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo aceptar la solicitud.');
    }
  }

  Future<void> rejectFriendRequest({
    required String requesterUid,
  }) async {
    if (requesterUid.trim().isEmpty) {
      throw Exception('Solicitud inválida.');
    }

    final requestRef = _requestsCol(uid).doc(requesterUid);
    final requesterSentRequestRef = _sentRequestsCol(requesterUid).doc(uid);

    await _db.runTransaction((tx) async {
      final now = FieldValue.serverTimestamp();

      tx.set(
        requestRef,
        {
          'status': 'rejected',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      tx.set(
        requesterSentRequestRef,
        {
          'status': 'rejected',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> removeFriend({
    required String friendUid,
  }) async {
    if (friendUid.trim().isEmpty || friendUid == uid) {
      throw Exception('Amigo inválido.');
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('removeFriend')
          .call({'friendUid': friendUid});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'No se pudo eliminar al amigo.');
    }
  }
}
