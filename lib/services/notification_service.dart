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