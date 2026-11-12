import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> _notificationsCol(String userId) {
    return _db.collection('users').doc(userId).collection('notifications');
  }

  /// Stores this device's FCM token in a subcollection only its owner can
  /// read.
  ///
  /// It used to live on the user doc, which any signed-in player may read
  /// — that read is what the friends list, leaderboards and profile views
  /// need, so the whole document was effectively public and the push token
  /// rode along with it. The old field is cleared on the same write so a
  /// device that upgrades stops leaving a copy behind.
  StreamSubscription<String>? _tokenRefresh;

  /// Saves this device's push token for [userId] and keeps it current.
  ///
  /// Called once the player is signed in. It used to run only at startup,
  /// and only if someone was already signed in — which a brand-new install
  /// never is at that point — so a new player got no pushes until their
  /// next cold start, and a rotated token was never saved at all.
  Future<void> registerPushToken(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      // Asked here, once the player is in, rather than at startup: on a
      // first launch that put the system prompt over the language picker
      // before the player had seen anything of the game.
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) await saveFcmToken(userId, token);

      await _tokenRefresh?.cancel();
      _tokenRefresh = messaging.onTokenRefresh.listen((fresh) {
        saveFcmToken(userId, fresh).catchError((Object e) {
          debugPrint('FCM token refresh not saved: $e');
        });
      });
    } catch (e) {
      debugPrint('FCM token unavailable: $e');
    }
  }

  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  bool _tapsWired = false;

  /// Fires with a notification's data when the player taps it: the push
  /// that launched the app, any tapped while it runs in the background,
  /// and the ones shown while it is open (see [localNotificationTapped]).
  /// Tapping one used to just open the app wherever it was.
  Stream<Map<String, dynamic>> pushTaps() {
    if (!_tapsWired) {
      _tapsWired = true;
      FirebaseMessaging.instance.getInitialMessage().then((initial) {
        if (initial != null) _taps.add(initial.data);
      }).catchError((Object _) {});
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _taps.add(message.data),
        onError: (Object _) {},
      );
    }
    return _taps.stream;
  }

  /// A notification this app displayed itself was tapped.
  ///
  /// A push that arrives while the app is open isn't shown by the system:
  /// the app shows it as a local notification, and those had no tap
  /// handler at all — tapping one did nothing. [payload] is the push's
  /// data as [pushPayload] encoded it.
  void localNotificationTapped(String? payload) {
    final data = pushDataFromPayload(payload);
    if (data != null) _taps.add(data);
  }

  Future<void> saveFcmToken(String userId, String token) async {
    final userRef = _db.collection('users').doc(userId);

    await userRef.collection('private').doc('push').set(
      {'fcmToken': token, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    await userRef.set(
      {'fcmToken': FieldValue.delete()},
      SetOptions(merge: true),
    );
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

  Future<void> markMatchNotificationsAsRead({
    required String matchId,
    List<String> types = const ['match_invite', 'match_turn'],
  }) async {
    if (matchId.trim().isEmpty) return;

    final batch = _db.batch();
    int count = 0;

    for (final type in types) {
      final snap = await _notificationsCol(uid)
          .where('read', isEqualTo: false)
          .where('type', isEqualTo: type)
          .where('data.matchId', isEqualTo: matchId)
          .limit(20)
          .get();

      for (final doc in snap.docs) {
        batch.set(
          doc.reference,
          {
            'read': true,
            'readAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        count++;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
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

  /// Writes a notification into **this player's own** inbox.
  ///
  /// Only self-notifications are written directly: creating a notification
  /// doc fires `sendPushOnNotificationCreated`, so a client able to write
  /// into someone else's inbox could push arbitrary text to them. For
  /// anything aimed at another player use [notifyUser], which goes through
  /// a Cloud Function that checks the sender earned the right to notify and
  /// composes the wording server-side. firestore.rules enforces this split.
  Future<void> createSelfNotification({
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await _notificationsCol(uid).add({
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? {},
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Asks the server to notify another player.
  ///
  /// The caller picks *which* notification is sent, never its wording: the
  /// function derives title/body from [type], the recipient's language and
  /// the sender's stored display name, and refuses types the caller can't
  /// back with a real friend request, match or invite.
  ///
  /// Best-effort like the direct write it replaces — a failure here must
  /// not undo the friend request or match turn that triggered it.
  Future<void> notifyUser({
    required String targetUid,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    if (targetUid.trim().isEmpty) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'sendUserNotification',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({
        'targetUid': targetUid,
        'type': type,
        'data': data ?? {},
      });
    } on FirebaseFunctionsException {
      // Swallowed on purpose: the notification is a courtesy on top of an
      // action that already succeeded.
    }
  }

  Future<void> markAsRead({
    required String notificationId,
  }) async {
    await _notificationsCol(uid).doc(notificationId).set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks a notification read and records how the player answered it
  /// from the list (a friend request accepted or rejected), so its buttons
  /// don't come back.
  Future<void> resolveNotification({
    required String notificationId,
    required String resolution,
  }) async {
    await _notificationsCol(uid).doc(notificationId).set({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
      'data': {'resolution': resolution},
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

/// Where tapping a push should take the player.
///
/// Tapping a challenge used to open the notifications list, then the
/// invites screen, and only there could it be accepted. The push now
/// carries the invite or match id, so it can go straight to it.
@immutable
class PushTapTarget {
  final String kind;
  final String? id;

  const PushTapTarget._(this.kind, this.id);

  /// Accept this live challenge and open its lobby.
  const PushTapTarget.acceptLiveInvite(String inviteId)
      : this._('acceptLiveInvite', inviteId);

  /// Open this turn-based match.
  const PushTapTarget.asyncMatch(String matchId)
      : this._('asyncMatch', matchId);

  /// Open the lobby of a live match a friend accepted.
  const PushTapTarget.liveLobby(String matchId) : this._('liveLobby', matchId);

  /// Anything else: the notifications list, as before.
  const PushTapTarget.notifications() : this._('notifications', null);

  @override
  bool operator ==(Object other) =>
      other is PushTapTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'PushTapTarget($kind, $id)';
}

/// [PushTapTarget] for a push's data. Pushes sent before the ids were
/// added carry only the type, and fall back to the list.
PushTapTarget pushTapTarget(Map<String, dynamic> data) {
  final type = (data['type'] ?? '').toString();
  final inviteId = (data['inviteId'] ?? '').toString();
  final matchId = (data['matchId'] ?? '').toString();

  switch (type) {
    case 'realtime_invite':
      if (inviteId.isNotEmpty) return PushTapTarget.acceptLiveInvite(inviteId);
    case 'match_invite':
    case 'match_turn':
    case 'match_result':
      if (matchId.isNotEmpty) return PushTapTarget.asyncMatch(matchId);
    case 'realtime_invite_accepted':
      if (matchId.isNotEmpty) return PushTapTarget.liveLobby(matchId);
  }
  return const PushTapTarget.notifications();
}

/// A push's data as the payload of the local notification that shows it
/// while the app is open.
String pushPayload(Map<String, dynamic> data) => jsonEncode(data);

/// The push data a tapped local notification carries, or null if it has
/// none — the Daily Challenge reminder, for one, is not about a push.
Map<String, dynamic>? pushDataFromPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// How long a tap that couldn't be acted on is still worth acting on.
const Duration pendingPushTapLifetime = Duration(minutes: 2);

/// Whether a notification tapped while another screen was on top should
/// still be opened once the player is back on the tabs.
///
/// A tap is not opened over a level or a match in progress; it waits. But
/// only briefly: opening a challenge twenty minutes after it was tapped,
/// when a long match finally ends, is no longer what the player asked for.
bool pendingPushTapIsFresh(DateTime tappedAt, DateTime now) {
  return now.difference(tappedAt) <= pendingPushTapLifetime;
}
