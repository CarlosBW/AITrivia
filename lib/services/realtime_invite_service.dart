import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notification_service.dart';

class RealtimeInviteService {
  RealtimeInviteService._();

  static final RealtimeInviteService instance = RealtimeInviteService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService =
      NotificationService.instance;

  String get uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _invitesCol {
    return _db.collection('realtime_invites');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyIncomingInvites({
    int limit = 20,
  }) {
    return _invitesCol
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyOutgoingInvites({
    int limit = 20,
  }) {
    return _invitesCol
        .where('fromUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<String> createInvite({
    required String toUid,
    required String toName,
    required String fromName,
    String categoryId = 'random',
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 10,
    int winReward = 2,
  }) async {
    if (toUid.trim().isEmpty) {
      throw Exception('Usuario inválido.');
    }

    if (toUid == uid) {
      throw Exception('No puedes retarte a ti mismo.');
    }

    final now = FieldValue.serverTimestamp();
    final inviteRef = _invitesCol.doc();

    await inviteRef.set({
      'fromUid': uid,
      'fromName': fromName,
      'toUid': toUid,
      'toName': toName,
      'status': 'pending',
      'categoryId': categoryId,
      'difficulty': difficulty,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
      'winReward': winReward,
      'matchId': null,
      'createdAt': now,
      'updatedAt': now,
    });

    try {
      await _notificationService.createNotification(
        targetUid: toUid,
        type: 'realtime_invite',
        title: 'Realtime challenge',
        body: '$fromName invited you to a realtime 1 vs 1 match.',
        data: {
          'inviteId': inviteRef.id,
          'fromUid': uid,
        },
      );
    } catch (_) {}

    return inviteRef.id;
  }

  Future<void> declineInvite({
    required String inviteId,
  }) async {
    final ref = _invitesCol.doc(inviteId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();

      if (data == null) {
        throw Exception('La invitación ya no existe.');
      }

      final toUid = (data['toUid'] ?? '').toString();
      final status = (data['status'] ?? '').toString();

      if (toUid != uid) {
        throw Exception('No puedes rechazar esta invitación.');
      }

      if (status != 'pending') return;

      tx.update(ref, {
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> cancelInvite({
    required String inviteId,
  }) async {
    final ref = _invitesCol.doc(inviteId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();

      if (data == null) {
        throw Exception('La invitación ya no existe.');
      }

      final fromUid = (data['fromUid'] ?? '').toString();
      final status = (data['status'] ?? '').toString();

      if (fromUid != uid) {
        throw Exception('No puedes cancelar esta invitación.');
      }

      if (status != 'pending') return;

      tx.update(ref, {
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markExpiredInvites() async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );

    final snap = await _invitesCol
        .where('status', isEqualTo: 'pending')
        .where('createdAt', isLessThan: cutoff)
        .limit(20)
        .get();

    final batch = _db.batch();

    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'status': 'expired',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
}