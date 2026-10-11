import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sign-in the player can attach their game to.
enum AccountProvider { google, apple }

/// Why attaching a sign-in to the current account did not go through.
enum LinkFailure {
  /// That sign-in already owns a saved game — the way *to* that game, not
  /// an error to show and drop.
  alreadyInUse,

  /// The player backed out of the provider's own screen.
  cancelled,

  other,
}

/// Sorts a [FirebaseAuthException.code] from a link attempt.
LinkFailure classifyLinkError(String code) {
  switch (code) {
    case 'credential-already-in-use':
    case 'email-already-in-use':
    case 'account-exists-with-different-credential':
      return LinkFailure.alreadyInUse;
    case 'canceled':
    case 'web-context-canceled':
    case 'web-context-cancelled':
      return LinkFailure.cancelled;
    default:
      return LinkFailure.other;
  }
}

/// XP below which a guest has nothing worth a reminder yet — roughly a
/// first sitting. Asking any earlier is asking a stranger to sign in.
const int kSaveProgressReminderMinXp = 100;

/// How long "not now" keeps the reminder away.
const Duration kSaveProgressReminderSnooze = Duration(days: 3);

/// Whether to nudge the player to save their progress.
bool shouldRemindToSaveProgress({
  required bool isGuest,
  required int xp,
  required DateTime? dismissedAt,
  required DateTime now,
}) {
  if (!isGuest || xp < kSaveProgressReminderMinXp) return false;
  if (dismissedAt == null || dismissedAt.isAfter(now)) return true;
  return now.difference(dismissedAt) >= kSaveProgressReminderSnooze;
}

/// How an attempt to save the current game under a sign-in ended.
sealed class LinkOutcome {
  const LinkOutcome();
}

/// The game is now tied to the sign-in and can be recovered with it.
class LinkSaved extends LinkOutcome {
  const LinkSaved();
}

class LinkCancelled extends LinkOutcome {
  const LinkCancelled();
}

/// The sign-in already has a saved game. [credential] signs into it; doing
/// so means leaving the current one — see
/// [AccountLinkService.switchToSavedAccount].
class LinkFoundSavedGame extends LinkOutcome {
  const LinkFoundSavedGame(this.credential);

  final AuthCredential credential;
}

/// Ties the anonymous account every player starts with to a Google or Apple
/// sign-in, so the game survives a reinstall or a new phone.
///
/// Linking keeps the same uid, so nothing is migrated: every document the
/// player owns is already under it.
class AccountLinkService {
  AccountLinkService._();

  static final AccountLinkService instance = AccountLinkService._();

  static const _dismissedAtKey = 'saveProgressReminderDismissedAt';

  Future<void>? _googleReady;

  User? get _user => FirebaseAuth.instance.currentUser;

  /// True while the game exists only on this device.
  bool get isGuest => _user?.isAnonymous ?? true;

  /// False only in the gap [switchToSavedAccount] can leave behind: the
  /// guest already deleted, the saved account not signed in.
  bool get hasSession => _user != null;

  /// What this platform can offer. Apple is limited to its own devices:
  /// there it is native, and App Store review requires it wherever another
  /// sign-in is offered.
  List<AccountProvider> get availableProviders {
    final onApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return [
      AccountProvider.google,
      if (onApple) AccountProvider.apple,
    ];
  }

  /// The sign-in this game is saved under, or null for a guest.
  AccountProvider? get linkedProvider {
    final ids = _user?.providerData.map((info) => info.providerId).toSet() ??
        const <String>{};

    if (ids.contains('google.com')) return AccountProvider.google;
    if (ids.contains('apple.com')) return AccountProvider.apple;
    return null;
  }

  /// The address shown to the player so they know which account holds
  /// their game. Apple may hide it, hence nullable.
  String? get linkedEmail {
    final user = _user;
    if (user == null) return null;

    for (final info in user.providerData) {
      final email = info.email;
      if (email != null && email.isNotEmpty) return email;
    }
    return user.email;
  }

  /// Saves the current game under [provider].
  ///
  /// Throws for real failures (no network, provider not configured); the
  /// expected ways of not succeeding come back as a [LinkOutcome].
  Future<LinkOutcome> link(AccountProvider provider) async {
    final user = _user;
    if (user == null) {
      throw StateError('No signed-in user to link.');
    }

    AuthCredential? attempted;

    try {
      switch (provider) {
        case AccountProvider.google:
          attempted = await _googleCredential();
          if (attempted == null) return const LinkCancelled();
          await user.linkWithCredential(attempted);
        case AccountProvider.apple:
          await user.linkWithProvider(AppleAuthProvider());
      }
      return const LinkSaved();
    } on FirebaseAuthException catch (e) {
      switch (classifyLinkError(e.code)) {
        case LinkFailure.cancelled:
          return const LinkCancelled();
        case LinkFailure.alreadyInUse:
          // Firebase hands back a credential good for signing in to the
          // account that owns it. Apple's is single-use, so the one from
          // the failed attempt cannot stand in for it; Google's can.
          final existing = e.credential ?? attempted;
          if (existing == null) rethrow;
          return LinkFoundSavedGame(existing);
        case LinkFailure.other:
          rethrow;
      }
    }
  }

  /// Leaves the current guest game for the saved one [credential] owns.
  ///
  /// The guest account is deleted first, through the same callable as
  /// "delete my account", because only its own session can do that: once
  /// signed in elsewhere, nothing could free its username or take it off
  /// the leaderboards. The cost of that order is that a sign-in failing
  /// right after leaves the player signed out — the app then starts a fresh
  /// guest, from which they can sign in again.
  Future<void> switchToSavedAccount(AuthCredential credential) async {
    await FirebaseFunctions.instance
        .httpsCallable(
          'deleteMyAccount',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call();

    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  /// When the player last waved the save-progress reminder away.
  Future<DateTime?> reminderDismissedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_dismissedAtKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> dismissReminder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Runs Google's account picker. Null when the player closes it.
  Future<AuthCredential?> _googleCredential() async {
    // The SDK must be initialised exactly once before anything else.
    await (_googleReady ??= GoogleSignIn.instance.initialize());

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google sign-in returned no ID token.');
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}
