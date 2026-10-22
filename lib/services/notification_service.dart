import 'dart:async';

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

  /// Fires when the player opens the app by tapping a push: the one that
  /// launched it, then any tapped while it runs in the background. Tapping
  /// one used to just open the app wherever it was.
  Stream<RemoteMessage> pushTaps() async* {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) yield initial;
    yield* FirebaseMessaging.onMessageOpenedApp;
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
