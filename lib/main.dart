import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'firebase_options.dart';
import 'app/app.dart';
import 'l10n/generated/app_localizations.dart';
import 'services/sfx_service.dart';
import 'services/presence_service.dart';
import 'services/locale_controller.dart';
import 'services/daily_challenge_service.dart';

/// The app's notification channel, named in the player's language — it is
/// what Android shows under the app's notification settings, and it was
/// English-only. Re-creating it under the same id updates the name.
AndroidNotificationChannel get triviaChannel {
  final l10n = lookupAppLocalizations(LocaleController.instance.locale.value);
  return AndroidNotificationChannel(
    'triviaia_channel',
    l10n.notificationChannelName,
    description: l10n.notificationChannelDescription,
    importance: Importance.high,
  );
}

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

// Called from native code in its own isolate, so a release build's tree
// shaking can't see it's used: without the pragma it's stripped, and a
// push arriving with the app closed hits "must be annotated".
@pragma('vm:entry-point')
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
  bool skipToday = false,
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

  if (skipToday || scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }

  return scheduled;
}

/// Schedules the evening Daily Challenge reminder: today at 19:00, or
/// tomorrow if today's challenge was already played on this device.
///
/// One-off rather than repeating, and re-scheduled on every launch and
/// after each Daily Challenge: a repeating one fired every evening, also
/// for players who had already played that day.
Future<void> _scheduleDailyChallengeReminder() async {
  // No BuildContext this early, so the strings are looked up for the
  // player's locale directly. Scheduling under the same id replaces the
  // previous reminder, which is how a language change takes effect.
  final l10n = lookupAppLocalizations(LocaleController.instance.locale.value);
  final playedToday =
      await DailyChallengeService.instance.playedTodayOnThisDevice();

  try {
    await localNotifications.zonedSchedule(
      1001,
      l10n.dailyReminderTitle,
      l10n.dailyReminderBody,
      _nextDailyReminderTime(hour: 19, minute: 0, skipToday: playedToday),
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
    );
  } catch (e) {
    debugPrint('Local daily reminder unavailable: $e');
  }
}

Future<void> _renameNotificationChannel() async {
  try {
    await localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(triviaChannel);
  } catch (_) {}
}

Future<void> _setupNotifications() async {
  try {
    tzdata.initializeTimeZones();
  } catch (e) {
    debugPrint('Timezone init failed: $e');
  }

  try {
    const androidInit = AndroidInitializationSettings('ic_stat_triviaia');
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
    // Permission is asked after sign-in — see
    // NotificationService.registerPushToken.
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

    // The token itself is saved once there is a signed-in player — see
    // NotificationService.registerPushToken, called from AuthGate.
  } catch (e) {
    debugPrint('Firebase Messaging unavailable: $e');
  }

  await _scheduleDailyChallengeReminder();
  DailyChallengeService.instance.onPlayedToday =
      () => unawaited(_scheduleDailyChallengeReminder());

  // The reminder's text is fixed when it is scheduled, and it repeats
  // daily — without this it would keep the language the app started in
  // long after the player switched.
  LocaleController.instance.locale.addListener(() {
    unawaited(_scheduleDailyChallengeReminder());
    unawaited(_renameNotificationChannel());
  });
}

// Play Integrity (Android) / App Attest (iOS) in release builds, debug
// tokens in debug builds. Enforcement itself is a separate, later step —
// this only activates the client SDK so it starts minting tokens; nothing
// rejects requests until App Check is registered for this app in the
// Firebase Console and enforcement is turned on for Firestore/Functions
// (see the launch checklist — turning enforcement on before that
// registration exists would lock every real user out).
Future<void> _setupAppCheck() async {
  if (kIsWeb) {
    // No reCAPTCHA site key registered yet for the web app — skip until
    // App Check is set up for the web target in the Firebase Console.
    return;
  }

  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  } catch (e) {
    debugPrint('App Check activation failed: $e');
  }
}

// No web support in firebase_crashlytics — Crashlytics is Android/iOS/
// desktop-native only. Disabled in debug builds so local dev crashes don't
// pollute the production crash-free-rate metric.
Future<void> _setupCrashlytics() async {
  if (kIsWeb) return;

  try {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Crashlytics setup failed: $e');
  }
}

/// The licenses of the bundled fonts (SIL OFL, and Apache 2.0 for
/// Mountains of Christmas), which they require shipping alongside them;
/// they show in the app's license page.
void _registerFontLicenses() {
  const families = {
    'Baloo 2': 'OFL-baloo2.txt',
    'Black Ops One': 'OFL-blackopsone.txt',
    'Chakra Petch': 'OFL-chakrapetch.txt',
    'Cinzel': 'OFL-cinzel.txt',
    'Manrope': 'OFL-manrope.txt',
    'Mountains of Christmas': 'LICENSE-mountainsofchristmas.txt',
    'Playfair Display': 'OFL-playfairdisplay.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in families.entries) {
      final text =
          await rootBundle.loadString('assets/google_fonts/${entry.value}');
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The fonts ship inside the app (assets/google_fonts/). Fetched on first
  // launch, an offline first run showed the system font, and each fetch
  // was a request to Google the privacy policy didn't mention.
  GoogleFonts.config.allowRuntimeFetching = false;
  _registerFontLicenses();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _setupAppCheck();
  await _setupCrashlytics();

  WidgetsBinding.instance.addObserver(presenceObserver);

  await LocaleController.instance.load();

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