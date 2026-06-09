import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notification_service.dart';

class RealtimeInviteService {
  RealtimeInviteService._();

  static final RealtimeInviteService instance = RealtimeInviteService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final NotificationService _notificationService = NotificationService.instance;

  final Random _random = Random();

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
        .orderBy(
          'createdAt',
          descending: true,
        )
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyOutgoingInvites({
    int limit = 20,
  }) {
    return _invitesCol
        .where('fromUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy(
          'createdAt',
          descending: true,
        )
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
      throw Exception(
        'No puedes retarte a ti mismo.',
      );
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

    final inviteSnap = await inviteRef.get();

    final invite = inviteSnap.data();

    if (invite == null) {
      throw Exception(
        'La invitación ya no existe.',
      );
    }

    final fromUid = (invite['fromUid'] ?? '').toString();

    final fromName = (invite['fromName'] ?? 'Player 1').toString();

    final toUid = (invite['toUid'] ?? '').toString();

    final toName = (invite['toName'] ?? 'Player 2').toString();

    final status = (invite['status'] ?? '').toString();

    if (toUid != uid) {
      throw Exception(
        'No puedes aceptar esta invitación.',
      );
    }

    if (status != 'pending') {
      throw Exception(
        'Esta invitación ya no está disponible.',
      );
    }

    final categoryId = (invite['categoryId'] ?? 'random').toString();

    final difficulty = ((invite['difficulty'] ?? 1) as num).toInt();

    final totalQuestions = ((invite['totalQuestions'] ?? 10) as num).toInt();

    final timePerQuestionSec =
        ((invite['timePerQuestionSec'] ?? 10) as num).toInt();

    final winReward = ((invite['winReward'] ?? 2) as num).toInt();

    final resolvedCategoryId = await _resolveCategoryId(categoryId);

    final questions = await _generateQuestions(
      categoryId: resolvedCategoryId,
      difficulty: difficulty,
      totalQuestions: totalQuestions,
    );

    if (questions.isEmpty) {
      throw Exception(
        'No hay preguntas disponibles para esta categoría.',
      );
    }

    final now = FieldValue.serverTimestamp();

    await matchRef.set({
      'createdAt': now,
      'updatedAt': now,
      'status': 'realtime_lobby',
      'mode': 'realtime_friend',
      'source': 'friend_invite',
      'inviteId': inviteId,
      'categoryId': resolvedCategoryId,
      'requestedCategoryId': categoryId,
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
      'questions': questions,
      'startAt': null,
      'endedAt': null,
      'winnerUid': null,
      'rewarded': false,
    });

    await inviteRef.update({
      'status': 'accepted',
      'matchId': matchRef.id,
      'updatedAt': now,
    });

    try {
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
    } catch (_) {}

    return matchRef.id;
  }

  Future<String> _resolveCategoryId(String categoryId) async {
    if (categoryId != 'random') return categoryId;

    final snap = await _db
        .collection('fixed_categories')
        .where('isActive', isEqualTo: true)
        .get();

    final ids = snap.docs.map((d) => d.id).toList();

    if (ids.isEmpty) {
      throw Exception('No hay categorías activas disponibles.');
    }

    ids.shuffle(_random);
    return ids.first;
  }

  Future<List<Map<String, dynamic>>> _generateQuestions({
    required String categoryId,
    required int difficulty,
    required int totalQuestions,
  }) async {
    final questions = <Map<String, dynamic>>[];

    final difficulties = <int>[
      difficulty,
      1,
      2,
      3,
    ].toSet().toList();

    QuerySnapshot<Map<String, dynamic>>? poolSnap;

    for (final diff in difficulties) {
      final snap = await _db
          .collection('fixed_pools')
          .doc(categoryId)
          .collection('difficulty_$diff')
          .doc('pool')
          .collection('questions')
          .get();

      if (snap.docs.isNotEmpty) {
        poolSnap = snap;
        break;
      }
    }

    if (poolSnap == null || poolSnap.docs.isEmpty) {
      return questions;
    }

    final allQuestions = poolSnap.docs.map((d) => d.data()).toList();
    allQuestions.shuffle(_random);

    final selected = allQuestions.take(totalQuestions).toList();

    for (final q in selected) {
      final existingQuestionText = (q['q'] ?? q['question'] ?? '').toString();

      final existingOptions =
          (q['options'] as List<dynamic>?)?.map((e) => e.toString()).toList();

      final existingAnswerIndex = q['answerIndex'];

      if (existingQuestionText.isNotEmpty &&
          existingOptions != null &&
          existingOptions.length >= 2 &&
          existingAnswerIndex is num) {
        questions.add({
          'q': existingQuestionText,
          'options': existingOptions,
          'answerIndex': existingAnswerIndex.toInt(),
        });
        continue;
      }

      final correct = (q['correctAnswer'] ?? '').toString().trim();

      final incorrect = (q['incorrectAnswers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList() ??
          [];

      if (existingQuestionText.isEmpty ||
          correct.isEmpty ||
          incorrect.isEmpty) {
        continue;
      }

      final options = [
        correct,
        ...incorrect,
      ];

      options.shuffle(_random);

      questions.add({
        'q': existingQuestionText,
        'options': options,
        'answerIndex': options.indexOf(correct),
      });
    }

    return questions;
  }

  Future<void> declineInvite({
    required String inviteId,
  }) async {
    final ref = _invitesCol.doc(inviteId);

    await ref.update({
      'status': 'declined',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelInvite({
    required String inviteId,
  }) async {
    final ref = _invitesCol.doc(inviteId);

    await ref.update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markExpiredInvites() async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(
        const Duration(minutes: 5),
      ),
    );

    final snap = await _invitesCol
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .where(
          'createdAt',
          isLessThan: cutoff,
        )
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
