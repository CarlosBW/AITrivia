import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'achievement_service.dart';
import 'notification_service.dart';

class FriendService {
  FriendService._();

  static final FriendService instance = FriendService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _achievementService = AchievementService.instance;
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
        .get();
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

  Future<void> acceptFriendRequest({
    required String requesterUid,
  }) async {
    if (requesterUid.trim().isEmpty) {
      throw Exception('Solicitud inválida.');
    }

    if (requesterUid == uid) {
      throw Exception('Solicitud inválida.');
    }

    final myRef = _userRef(uid);
    final requesterRef = _userRef(requesterUid);

    final requestRef = _requestsCol(uid).doc(requesterUid);

    final myFriendRef = _friendsCol(uid).doc(requesterUid);
    final requesterFriendRef = _friendsCol(requesterUid).doc(uid);

    final requesterSentRequestRef = _sentRequestsCol(requesterUid).doc(uid);

    await _db.runTransaction((tx) async {
      final mySnap = await tx.get(myRef);
      final requesterSnap = await tx.get(requesterRef);
      final requestSnap = await tx.get(requestRef);

      if (!requestSnap.exists) {
        throw Exception('La solicitud ya no existe.');
      }

      final requestStatus =
          (requestSnap.data()?['status'] ?? 'pending').toString();

      if (requestStatus != 'pending') {
        throw Exception('La solicitud ya fue procesada.');
      }

      final myData = mySnap.data() ?? {};
      final requesterData = requesterSnap.data() ?? {};

      final myDisplayName = (myData['displayName'] ??
              myData['username'] ??
              'Player${uid.substring(0, 4)}')
          .toString();

      final requesterDisplayName = (requesterData['displayName'] ??
              requesterData['username'] ??
              'Player${requesterUid.substring(0, 4)}')
          .toString();

      final now = FieldValue.serverTimestamp();

      tx.set(
        myFriendRef,
        {
          'uid': requesterUid,
          'displayName': requesterDisplayName,
          'username':
              (requesterData['username'] ?? requesterDisplayName).toString(),
          'avatarId': (requesterData['avatarId'] ?? 'avatar_1').toString(),
          'equippedFrame': requesterData['equippedFrame'] ?? 'bronze',

          'bestLeagueId': requesterData['bestLeagueId'] ?? 'bronze',
          // PvP snapshot for future efficient friend leaderboards.
          'pvpRating': requesterData['pvpRating'] ?? 1000,
          'pvpLeagueId': requesterData['pvpLeagueId'] ?? 'bronze',
          'pvpLeagueName': requesterData['pvpLeagueName'] ?? 'Bronze',
          'pvpLeagueEmoji': requesterData['pvpLeagueEmoji'] ?? '🥉',

          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      tx.set(
        requesterFriendRef,
        {
          'uid': uid,
          'displayName': myDisplayName,
          'username': (myData['username'] ?? myDisplayName).toString(),
          'avatarId': (myData['avatarId'] ?? 'avatar_1').toString(),
          'equippedFrame': myData['equippedFrame'] ?? 'bronze',

          'bestLeagueId': myData['bestLeagueId'] ?? 'bronze',
          // PvP snapshot for future efficient friend leaderboards.
          'pvpRating': myData['pvpRating'] ?? 1000,
          'pvpLeagueId': myData['pvpLeagueId'] ?? 'bronze',
          'pvpLeagueName': myData['pvpLeagueName'] ?? 'Bronze',
          'pvpLeagueEmoji': myData['pvpLeagueEmoji'] ?? '🥉',

          'createdAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      tx.update(requestRef, {
        'status': 'accepted',
        'updatedAt': now,
      });

      tx.set(
        requesterSentRequestRef,
        {
          'status': 'accepted',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    });

    Future.microtask(() async {
      try {
        final myFriendsSnap = await _friendsCol(uid).get();
        final requesterFriendsSnap = await _friendsCol(requesterUid).get();

        await Future.wait([
          _achievementService.syncFriendsAchievements(
            uid: uid,
            friendCount: myFriendsSnap.docs.length,
          ),
          _achievementService.syncFriendsAchievements(
            uid: requesterUid,
            friendCount: requesterFriendsSnap.docs.length,
          ),
        ]);
      } catch (_) {}
    });
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
    if (friendUid.trim().isEmpty) {
      throw Exception('Amigo inválido.');
    }

    if (friendUid == uid) {
      throw Exception('No puedes eliminarte a ti mismo.');
    }

    final myFriendRef = _friendsCol(uid).doc(friendUid);
    final theirFriendRef = _friendsCol(friendUid).doc(uid);

    await _db.runTransaction((tx) async {
      tx.delete(myFriendRef);
      tx.delete(theirFriendRef);
    });
  }
}
