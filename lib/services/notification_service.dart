import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _notificationsCol(String userId) {
    return _db.collection('users').doc(userId).collection('notifications');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyNotifications({
    int limit = 50,
  }) {
    return _notificationsCol(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyUnreadNotifications({
    int limit = 20,
  }) {
    return _notificationsCol(uid)
        .where('read', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<void> markRematchRequestNotificationsAsRead({
    required String matchId,
  }) async {
    final snap = await _notificationsCol(uid)
        .where('read', isEqualTo: false)
        .where('type', isEqualTo: 'rematch_request')
        .where('data.matchId', isEqualTo: matchId)
        .limit(20)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();

    for (final doc in snap.docs) {
      batch.set(
        doc.reference,
        {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> createOrBumpNotificationById({
    required String targetUid,
    required String notificationId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (targetUid.trim().isEmpty) return;

    final ref = _notificationsCol(targetUid).doc(notificationId);

    await ref.set({
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? {},
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'bumpedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createNotification({
    required String targetUid,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (targetUid.trim().isEmpty) return;

    await _notificationsCol(targetUid).add({
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? {},
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createOrBumpUniqueUnreadNotification({
    required String targetUid,
    required String type,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    required List<String> uniqueDataKeys,
  }) async {
    if (targetUid.trim().isEmpty) return;

    Query<Map<String, dynamic>> query = _notificationsCol(targetUid)
        .where('read', isEqualTo: false)
        .where('type', isEqualTo: type);

    for (final key in uniqueDataKeys) {
      if (!data.containsKey(key)) continue;
      query = query.where('data.$key', isEqualTo: data[key]);
    }

    final snap = await query.limit(1).get();

    if (snap.docs.isNotEmpty) {
      await snap.docs.first.reference.set({
        'title': title,
        'body': body,
        'data': data,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'bumpedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    await _notificationsCol(targetUid).add({
      'type': type,
      'title': title,
      'body': body,
      'data': data,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAsRead({
    required String notificationId,
  }) async {
    await _notificationsCol(uid).doc(notificationId).set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markAllAsRead() async {
    final snap = await _notificationsCol(uid)
        .where('read', isEqualTo: false)
        .limit(50)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();

    for (final doc in snap.docs) {
      batch.set(
        doc.reference,
        {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> deleteNotification({
    required String notificationId,
  }) async {
    await _notificationsCol(uid).doc(notificationId).delete();
  }
}
