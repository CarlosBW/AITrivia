import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notification_service.dart';

class RealtimeInviteService {
  RealtimeInviteService._();

  static final RealtimeInviteService instance = RealtimeInviteService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService.instance;

  String get uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _invitesCol {
    return _db.collection('realtime_invites');
  }

  CollectionReference<Map<String, dynamic>> get _matchesCol {
    return _db.collection('matches');
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

  Future<String> acceptInvite({
    required String inviteId,
  }) async {
    final inviteRef = _invitesCol.doc(inviteId);
    final matchRef = _matchesCol.doc();

    await _db.runTransaction((tx) async {
      final inviteSnap = await tx.get(inviteRef);
      final invite = inviteSnap.data();

      if (invite == null) {
        throw Exception('La invitación ya no existe.');
      }

      final fromUid = (invite['fromUid'] ?? '').toString();
      final fromName = (invite['fromName'] ?? 'Player 1').toString();
      final toUid = (invite['toUid'] ?? '').toString();
      final toName = (invite['toName'] ?? 'Player 2').toString();
      final status = (invite['status'] ?? '').toString();

      if (toUid != uid) {
        throw Exception('No puedes aceptar esta invitación.');
      }

      if (status == 'accepted') {
        final existingMatchId = (invite['matchId'] ?? '').toString();

        if (existingMatchId.isNotEmpty) {
          return;
        }

        throw Exception('La invitación ya fue aceptada.');
      }

      if (status != 'pending') {
        throw Exception('Esta invitación ya no está disponible.');
      }

      final categoryId = (invite['categoryId'] ?? 'random').toString();
      final difficulty = ((invite['difficulty'] ?? 1) as num).toInt();
      final totalQuestions = ((invite['totalQuestions'] ?? 10) as num).toInt();
      final timePerQuestionSec =
          ((invite['timePerQuestionSec'] ?? 10) as num).toInt();
      final winReward = ((invite['winReward'] ?? 2) as num).toInt();

      final now = FieldValue.serverTimestamp();

      tx.set(matchRef, {
        'createdAt': now,
        'updatedAt': now,
        'status': 'realtime_lobby',
        'mode': 'realtime_friend',
        'source': 'friend_invite',
        'inviteId': inviteId,
        'categoryId': categoryId,
        'difficulty': difficulty,
        'totalQuestions': totalQuestions,
        'timePerQuestionSec': timePerQuestionSec,
        'winReward': winReward,
        'loseReward': 0,
        'hostUid': fromUid,
        'guestUid': toUid,
        'player1Uid': fromUid,
        'player1Name': fromName,
        'player1Ready': false,
        'player2Uid': toUid,
        'player2Name': toName,
        'player2Ready': false,
        'players': {
          fromUid: {
            'displayName': fromName,
            'score': 0,
            'ready': false,
            'finished': false,
          },
          toUid: {
            'displayName': toName,
            'score': 0,
            'ready': false,
            'finished': false,
          },
        },
        'questions': [
          {
            'q': 'What planet is known as the Red Planet?',
            'options': [
              'Earth',
              'Mars',
              'Jupiter',
              'Venus',
            ],
            'answerIndex': 1,
          },
          {
            'q': 'Which ocean is the largest?',
            'options': [
              'Atlantic',
              'Indian',
              'Pacific',
              'Arctic',
            ],
            'answerIndex': 2,
          },
          {
            'q': 'Who wrote Hamlet?',
            'options': [
              'Shakespeare',
              'Cervantes',
              'Homer',
              'Tolstoy',
            ],
            'answerIndex': 0,
          },
          {
            'q': 'What is the capital of Japan?',
            'options': [
              'Tokyo',
              'Seoul',
              'Bangkok',
              'Beijing',
            ],
            'answerIndex': 0,
          },
          {
            'q': 'What gas do humans breathe in?',
            'options': [
              'Hydrogen',
              'Nitrogen',
              'Oxygen',
              'Helium',
            ],
            'answerIndex': 2,
          },
        ],
        'startAt': null,
        'endedAt': null,
        'winnerUid': null,
        'rewarded': false,
      });

      tx.update(inviteRef, {
        'status': 'accepted',
        'matchId': matchRef.id,
        'updatedAt': now,
      });
    });

    try {
      final snap = await inviteRef.get();
      final data = snap.data();

      if (data != null) {
        final fromUid = (data['fromUid'] ?? '').toString();
        final toName = (data['toName'] ?? 'Player').toString();

        await _notificationService.createNotification(
          targetUid: fromUid,
          type: 'realtime_invite_accepted',
          title: 'Realtime invite accepted',
          body: '$toName accepted your realtime challenge.',
          data: {
            'inviteId': inviteId,
            'matchId': matchRef.id,
          },
        );
      }
    } catch (_) {}

    return matchRef.id;
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
