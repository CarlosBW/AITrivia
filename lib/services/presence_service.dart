import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Resolved from the acting user's own device locale — correct here since
  // presenceLabel always describes presence to the user currently viewing
  // the screen (friends list, etc.), not the presence subject.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  Timer? _heartbeatTimer;
  bool _ready = false;

  // Last presence this client wrote. The heartbeat used to re-read the user
  // doc on every beat just to learn what it had written itself fifteen
  // seconds earlier — one billed read per beat per active player, for data
  // this object already had. Nobody else writes this user's presence, so
  // remembering it is as accurate as the round-trip was.
  String _lastStatus = 'online';
  bool _lastInMatch = false;

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

    _lastStatus = status;
    _lastInMatch = inMatch;

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
          await _setPresence(
            status: _lastStatus,
            inMatch: _lastInMatch,
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
      await _setPresence(
        status: _lastStatus,
        inMatch: _lastInMatch,
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
        return _l10n.presenceStatusOnline;
      case 'in_match':
        return _l10n.presenceStatusInMatch;
      case 'searching_match':
        return _l10n.presenceStatusSearching;
      default:
        return _l10n.friendsOfflineLabel;
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
