import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_bootstrap.dart';
import '../onboarding/onboarding_screen.dart';
import '../navigation/main_navigation_screen.dart';
import '../../services/presence_service.dart';
import '../../services/match_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  bool _hasSeenOnboarding = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _signInAndBootstrap();
  }

  Future<void> _signInAndBootstrap() async {
    try {
      final auth = FirebaseAuth.instance;

      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }

      final uid = auth.currentUser!.uid;

      final hasSeenOnboarding = await _runWithFirestoreRetry(
        () => bootstrapUserDoc(uid),
      );

      await MatchService().recoverMyRealtimeStateOnAppStart();
      await PresenceService.instance.setOnline();

      if (!mounted) return;

      setState(() {
        _hasSeenOnboarding = hasSeenOnboarding;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
      return Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Error: $_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_hasSeenOnboarding) {
      return const OnboardingScreen();
    }

    return const MainNavigationScreen();
  }
}