import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_bootstrap.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/username_picker_screen.dart';
import '../navigation/main_navigation_screen.dart';
import '../../services/presence_service.dart';
import '../../services/match_service.dart';
import '../../services/purchase_service.dart';
import '../../services/theme_service.dart';
import '../../services/notification_service.dart';
import '../../l10n/generated/app_localizations.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _needsUsername = false;
  bool _hasSeenOnboarding = true;
  String? _uid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = FirebaseAuth.instance;

      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }

      final uid = auth.currentUser!.uid;

      final exists = await _runWithFirestoreRetry(() => userDocExists(uid));

      if (!mounted) return;

      if (!exists) {
        // Brand-new account — gate on picking a permanent, unique
        // username before creating the Firestore user doc at all.
        setState(() {
          _uid = uid;
          _needsUsername = true;
          _loading = false;
        });
        return;
      }

      await _finishBootstrap(uid);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _finishBootstrap(String uid, {String? username}) async {
    final hasSeenOnboarding = await _runWithFirestoreRetry(
      () => bootstrapUserDoc(uid, requestedUsername: username),
    );

    PresenceService.instance.markReady();

    // Starts following the equipped theme once there is a user doc to
    // follow. Not awaited: the app paints in the default theme and swaps
    // as soon as the first snapshot lands, which beats holding the whole
    // launch on a read that only decides how things look.
    ThemeService.instance.watch(uid);

    // Listens for purchases from launch, not from the first visit to the
    // shop. A paid purchase whose crediting failed is left pending so the
    // store hands it back on the next launch — but it only hands it to
    // someone listening, and a player who paid and got nothing is the one
    // least likely to open the shop again. Here rather than in main():
    // crediting is a callable, and that needs the signed-in user.
    PurchaseService.instance.start();

    // Nice to have, never a reason not to open the app: these used to be
    // awaited bare, so a failure in either stopped the launch.
    try {
      await MatchService().recoverMyRealtimeStateOnAppStart();
      await PresenceService.instance.setOnline();
    } catch (_) {}

    unawaited(NotificationService.instance.registerPushToken(uid));

    if (!mounted) return;

    setState(() {
      _needsUsername = false;
      _hasSeenOnboarding = hasSeenOnboarding;
      _loading = false;
      _error = null;
    });
  }

  Future<T> _runWithFirestoreRetry<T>(
    Future<T> Function() action,
  ) async {
    const maxAttempts = 4;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on FirebaseException catch (e) {
        final canRetry = e.code == 'aborted' || e.code == 'unavailable';

        if (!canRetry || attempt == maxAttempts) {
          rethrow;
        }

        await Future.delayed(
          Duration(milliseconds: 250 * attempt),
        );
      }
    }

    throw StateError('Unreachable');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      // Shown when the first launch can't reach the server. It used to
      // print the raw exception and offer nothing but killing the app.
      final l10n = AppLocalizations.of(context);
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.authGateConnectionError, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _start, child: Text(l10n.commonRetry)),
              ],
            ),
          ),
        ),
      );
    }

    if (_needsUsername) {
      return UsernamePickerScreen(
        onSubmit: (username) => _finishBootstrap(_uid!, username: username),
      );
    }

    if (!_hasSeenOnboarding) {
      return const OnboardingScreen();
    }

    return const MainNavigationScreen();
  }
}