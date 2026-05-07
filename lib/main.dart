import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';
import 'app/app.dart';
import 'services/sfx_service.dart';

/// 🔔 Canal Android
const AndroidNotificationChannel triviaChannel = AndroidNotificationChannel(
  'triviaia_channel',
  'TriviaIA Notifications',
  description: 'Notifications for TriviaIA daily reminders and rewards',
  importance: Importance.high,
);

/// 🔔 Local notifications plugin
final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

/// 🌙 Background handler
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> _setupNotifications() async {
  /// Android initialization
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  /// iOS initialization
  const iosInit = DarwinInitializationSettings();

  const settings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await localNotifications.initialize(settings);

  /// Crear canal Android
  await localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(triviaChannel);

  /// Solicitar permisos
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  /// Foreground notifications
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
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
      ),
    );
  });

  /// Obtener token FCM
  final token = await messaging.getToken();

  debugPrint('🔥 FCM TOKEN: $token');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  /// Background notifications
  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  /// 🔔 Setup notifications
  await _setupNotifications();

  /// 🔊 Sonidos
  await SfxService.instance.init();

  runApp(const TriviaIAApp());
}