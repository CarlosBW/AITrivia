import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/presence_service.dart';

void main() {
  // Regression: pulling the notification shade down while searching for an
  // opponent marked the player offline, and they could no longer be paired.
  test('the app losing focus without leaving the screen is not away', () {
    expect(lifecycleMeansAway(AppLifecycleState.inactive), isFalse);
  });

  test('the app going to the background is away', () {
    expect(lifecycleMeansAway(AppLifecycleState.paused), isTrue);
    expect(lifecycleMeansAway(AppLifecycleState.detached), isTrue);
  });

  test('coming back is not away', () {
    expect(lifecycleMeansAway(AppLifecycleState.resumed), isFalse);
  });
}
