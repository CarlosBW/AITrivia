import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'firebase_options.dart';
import 'app/app.dart';
import 'services/sfx_service.dart';
import 'services/presence_service.dart';

const AndroidNotificationChannel triviaChannel = AndroidNotificationChannel(
  'triviaia_channel',
  'TriviaIA Notifications',
  description: 'Notifications for TriviaIA daily reminders and rewards',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

class AppLifecyclePresenceObserver extends WidgetsBindingObserver {
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (FirebaseAuth.instance.currentUser == null) return;

    try {
      await PresenceService.instance.setOnline();
    } catch (e) {
      debugPrint('Presence start failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (FirebaseAuth.instance.currentUser == null) return;

    if (state == AppLifecycleState.resumed) {
      PresenceService.instance.setOnline();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      PresenceService.instance.setOffline();
    }
  }
}

final AppLifecyclePresenceObserver presenceObserver =
    AppLifecyclePresenceObserver();

tz.TZDateTime _nextDailyReminderTime({
  int hour = 19,
  int minute = 0,
}) {
  final now = tz.TZDateTime.now(tz.local);

  var scheduled = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );

  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }

  return scheduled;
}

Future<void> _scheduleDailyChallengeReminder() async {
  try {
    await localNotifications.zonedSchedule(
      1001,
      '🔥 Daily Challenge ready!',
      'Play today and keep your streak alive.',
      _nextDailyReminderTime(hour: 19, minute: 0),
      NotificationDetails(
        android: AndroidNotificationDetails(
          triviaChannel.id,
          triviaChannel.name,
          channelDescription: triviaChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  } catch (e) {
    debugPrint('Local daily reminder unavailable: $e');
  }
}

Future<void> _setupNotifications() async {
  try {
    tzdata.initializeTimeZones();
  } catch (e) {
    debugPrint('Timezone init failed: $e');
  }

  try {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await localNotifications.initialize(settings);

    await localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(triviaChannel);
  } catch (e) {
    debugPrint('Local notifications init unavailable: $e');
  }

  try {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      try {
        final notification = message.notification;

        if (notification == null) return;

        await localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              triviaChannel.id,
              triviaChannel.name,
              channelDescription: triviaChannel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      } catch (e) {
        debugPrint('Foreground notification display failed: $e');
      }
    });

    try {
      final token = await messaging.getToken();
      debugPrint('🔥 FCM TOKEN: $token');

      if (token != null) {
        // Más adelante aquí guardaremos el token en Firestore.
      }
    } catch (e) {
      debugPrint('FCM token unavailable: $e');
    }
  } catch (e) {
    debugPrint('Firebase Messaging unavailable: $e');
  }

  await _scheduleDailyChallengeReminder();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  WidgetsBinding.instance.addObserver(presenceObserver);

  if (!kIsWeb) {
    try {
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
    } catch (e) {
      debugPrint('Background messaging registration failed: $e');
    }
  }

  unawaited(_setupNotifications());

  try {
    await SfxService.instance.init();
  } catch (e) {
    debugPrint('SFX init failed: $e');
  }

  unawaited(presenceObserver.start());

  runApp(const TriviaIAApp());
}