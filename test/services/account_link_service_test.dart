import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/account_link_service.dart';

void main() {
  group('classifyLinkError', () {
    // The whole point of linking is recovering a game, so "this sign-in
    // already owns one" must be told apart from a real failure: it is the
    // case that leads to the saved game, not an error to show and drop.
    test('recognises a sign-in that already owns a saved game', () {
      expect(
        classifyLinkError('credential-already-in-use'),
        LinkFailure.alreadyInUse,
      );
      expect(
        classifyLinkError('email-already-in-use'),
        LinkFailure.alreadyInUse,
      );
      expect(
        classifyLinkError('account-exists-with-different-credential'),
        LinkFailure.alreadyInUse,
      );
    });

    test('treats the player backing out as a cancel, not an error', () {
      expect(classifyLinkError('canceled'), LinkFailure.cancelled);
      expect(classifyLinkError('web-context-canceled'), LinkFailure.cancelled);
      expect(classifyLinkError('web-context-cancelled'), LinkFailure.cancelled);
    });

    test('leaves everything else as a real failure', () {
      expect(classifyLinkError('network-request-failed'), LinkFailure.other);
      expect(classifyLinkError('operation-not-allowed'), LinkFailure.other);
      expect(classifyLinkError(''), LinkFailure.other);
    });
  });

  group('shouldRemindToSaveProgress', () {
    final now = DateTime(2026, 10, 10, 12);

    test('reminds a guest who has progress worth keeping', () {
      expect(
        shouldRemindToSaveProgress(
          isGuest: true,
          xp: kSaveProgressReminderMinXp,
          dismissedAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('never reminds an account that is already saved', () {
      expect(
        shouldRemindToSaveProgress(
          isGuest: false,
          xp: 99999,
          dismissedAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('stays quiet until there is something to lose', () {
      expect(
        shouldRemindToSaveProgress(
          isGuest: true,
          xp: kSaveProgressReminderMinXp - 1,
          dismissedAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('respects a dismissal for the snooze period, then comes back', () {
      final justDismissed = now.subtract(const Duration(hours: 1));
      final longAgo = now.subtract(
        kSaveProgressReminderSnooze + const Duration(minutes: 1),
      );

      expect(
        shouldRemindToSaveProgress(
          isGuest: true,
          xp: 5000,
          dismissedAt: justDismissed,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldRemindToSaveProgress(
          isGuest: true,
          xp: 5000,
          dismissedAt: longAgo,
          now: now,
        ),
        isTrue,
      );
    });

    // A clock set back after dismissing would otherwise hide the reminder
    // until the clock caught up again, which could be never.
    test('ignores a dismissal dated in the future', () {
      expect(
        shouldRemindToSaveProgress(
          isGuest: true,
          xp: 5000,
          dismissedAt: now.add(const Duration(days: 30)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
