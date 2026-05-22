import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _heartbeatTimer;

  String get uid => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _userRef(String userId) {
    return _db.collection('users').doc(userId);
  }

  Future<void> setOnline() async {
    await _setPresence(
      status: 'online',
      inMatch: false,
    );

    _startHeartbeat();
  }

  Future<void> setOffline() async {
    _stopHeartbeat();

    await _setPresence(
      status: 'offline',
      inMatch: false,
    );
  }

  Future<void> setSearchingMatch() async {
    await _setPresence(
      status: 'searching_match',
      inMatch: false,
    );
  }

  Future<void> setInMatch() async {
    await _setPresence(
      status: 'in_match',
      inMatch: true,
    );
  }

  Future<void> setAvailable() async {
    await _setPresence(
      status: 'online',
      inMatch: false,
    );
  }

  Future<void> _setPresence({
    required String status,
    required bool inMatch,
  }) async {
    final ref = _userRef(uid);

    await ref.set({
      'presence': {
        'status': status,
        'inMatch': inMatch,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) async {
        try {
          await _setPresence(
            status: 'online',
            inMatch: false,
          );
        } catch (_) {}
      },
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserPresence({
    required String userId,
  }) {
    return _userRef(userId).snapshots();
  }

  String presenceLabel(Map<String, dynamic>? presence) {
    final status = (presence?['status'] ?? 'offline').toString();

    switch (status) {
      case 'online':
        return 'Online';
      case 'in_match':
        return 'In match';
      case 'searching_match':
        return 'Searching match';
      default:
        return 'Offline';
    }
  }

  bool isProbablyOnline(Map<String, dynamic>? presence) {
    final status = (presence?['status'] ?? 'offline').toString();
    final updatedAt = presence?['updatedAt'];

    if (status == 'offline') return false;

    if (updatedAt is! Timestamp) {
      return status == 'online' ||
          status == 'in_match' ||
          status == 'searching_match';
    }

    final last = updatedAt.toDate();
    final diff = DateTime.now().difference(last);

    return diff.inMinutes <= 5;
  }
}