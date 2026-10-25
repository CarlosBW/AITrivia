import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The signed-in player's own user document, as a single shared stream.
///
/// The profile avatar sits in the app bar of every screen, so without this
/// each screen would open its own `users/{uid}` subscription and a tab
/// switch would tear one down and build another. One broadcast stream,
/// created on first use and kept for the session, means the number of
/// listeners no longer has anything to do with the number of reads.
class MyProfileService {
  MyProfileService._();

  static final MyProfileService instance = MyProfileService._();

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;
  String? _streamUid;

  /// The last document seen. A broadcast stream doesn't replay it, so
  /// without this a screen opened after the first snapshot showed an empty
  /// avatar until the document next changed.
  DocumentSnapshot<Map<String, dynamic>>? _latest;

  /// Emits the current user's document as it changes. Returns an empty
  /// stream when nobody is signed in — callers render their placeholder
  /// rather than having to null-check auth themselves.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMe() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    // Rebuilt when the account changes: the cached stream belongs to the
    // previous uid and would keep serving their avatar after a sign-out.
    if (_stream == null || _streamUid != uid) {
      _streamUid = uid;
      _latest = null;
      _stream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .map((snap) => _latest = snap)
          .asBroadcastStream();
    }

    return withLatest(_stream!, _latest);
  }

  /// Drops the cached stream — call on sign-out so the next reader starts
  /// a fresh subscription for whoever signs in next.
  void reset() {
    _stream = null;
    _streamUid = null;
    _latest = null;
  }
}

/// Listens to [shared], first handing the new listener [latest] when there
/// is one — what a broadcast stream alone doesn't do for late subscribers.
Stream<T> withLatest<T>(Stream<T> shared, T? latest) {
  return Stream.multi((controller) {
    if (latest != null) controller.add(latest);
    final sub = shared.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });
}
