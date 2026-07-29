import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _heartbeatTimer;
  bool _ready = false;

  static const Duration heartbeatInterval = Duration(seconds: 15);
  static const Duration onlineMaxAge = Duration(seconds: 45);

  // Guards against writing presence before bootstrapUserDoc has created the
  // users/{uid} doc — a merge-set on a not-yet-existing doc is evaluated as
  // a Firestore `create`, which firestore.rules rejects (it requires
  // coins/xp fields presence writes don't send), surfacing as
  // PERMISSION_DENIED if a lifecycle-triggered setOnline() races ahead of
  // bootstrap on a slow/cold app start.
  void markReady() {
    _ready = true;
  }

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

    _startHeartbeat();
  }

  Future<void> setInMatch() async {
    await _setPresence(
      status: 'in_match',
      inMatch: true,
    );

    _startHeartbeat();
  }

  Future<void> setAvailable() async {
    await _setPresence(
      status: 'online',
      inMatch: false,
    );

    _startHeartbeat();
  }

  static const Duration _presenceWriteTimeout = Duration(seconds: 8);

  Future<void> _setPresence({
    required String status,
    required bool inMatch,
  }) async {
    if (!_ready) return;

    final ref = _userRef(uid);

    await ref.set({
      'presence': {
        'status': status,
        'inMatch': inMatch,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(_presenceWriteTimeout);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(
      heartbeatInterval,
      (_) async {
        try {
          final snap = await _userRef(uid).get();
          final presence = snap.data()?['presence'] as Map<String, dynamic>?;

          final status = (presence?['status'] ?? 'online').toString();
          final inMatch = presence?['inMatch'] == true;

          await _setPresence(
            status: status,
            inMatch: inMatch,
          );
        } catch (_) {}
      },
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }



  Future<Map<String, dynamic>?> getMyPresence() async {
    final snap = await _userRef(uid).get().timeout(_presenceWriteTimeout);
    final data = snap.data();
    final presence = data?['presence'];

    if (presence is Map) {
      return Map<String, dynamic>.from(presence);
    }

    return null;
  }

  Future<void> refreshHeartbeatNow() async {
    try {
      final presence = await getMyPresence();
      final status = (presence?['status'] ?? 'online').toString();
      final inMatch = presence?['inMatch'] == true;

      await _setPresence(
        status: status,
        inMatch: inMatch,
      );
    } catch (_) {}
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

    return diff <= onlineMaxAge;
  }
}
