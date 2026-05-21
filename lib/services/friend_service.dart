import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendService {
  FriendService._();

  static final FriendService instance = FriendService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

      final displayName = (myData['displayName'] ??
              myData['username'] ??
              'Player${uid.substring(0, 4)}')
          .toString();

      final username = (myData['username'] ?? displayName).toString();
      final avatarId = (myData['avatarId'] ?? 'avatar_1').toString();

      tx.set(
        requestRef,
        {
          'requesterUid': uid,
          'requesterDisplayName': displayName,
          'requesterUsername': username,
          'requesterAvatarId': avatarId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
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

      final requesterDisplayName =
          (requesterData['displayName'] ??
                  requesterData['username'] ??
                  'Player${requesterUid.substring(0, 4)}')
              .toString();

      tx.set(
        myFriendRef,
        {
          'uid': requesterUid,
          'displayName': requesterDisplayName,
          'username':
              (requesterData['username'] ?? requesterDisplayName).toString(),
          'avatarId': (requesterData['avatarId'] ?? 'avatar_1').toString(),
          'createdAt': FieldValue.serverTimestamp(),
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
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.update(requestRef, {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectFriendRequest({
    required String requesterUid,
  }) async {
    if (requesterUid.trim().isEmpty) {
      throw Exception('Solicitud inválida.');
    }

    final requestRef = _requestsCol(uid).doc(requesterUid);

    await requestRef.set(
      {
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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