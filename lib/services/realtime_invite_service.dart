import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

class RealtimeInviteService {
  RealtimeInviteService._();

  static final RealtimeInviteService instance = RealtimeInviteService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  // Resolved from the acting user's own device locale — correct for
  // exceptions, since they always surface back to whoever called this.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  CollectionReference<Map<String, dynamic>> get _invitesCol {
    return _db.collection('realtime_invites');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyIncomingInvites({
    int limit = 20,
  }) {
    return _invitesCol
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyOutgoingInvites({
    int limit = 20,
  }) {
    return _invitesCol
        .where('fromUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // Creating, accepting and closing an invite all go through Cloud
  // Functions. As client writes, creating one also wrote into the friend's
  // notifications, which the rules refuse — the invite was saved, the
  // sender saw an error, and the friend was never told. The rules also
  // could not stop invites being sent without limit, under any name.

  HttpsCallable _callable(String name, {int timeoutSeconds = 15}) =>
      FirebaseFunctions.instance.httpsCallable(
        name,
        options: HttpsCallableOptions(
          timeout: Duration(seconds: timeoutSeconds),
        ),
      );

  /// Challenges a friend to a live match; the server notifies them. A
  /// pending invite to the same friend is returned instead of a new one.
  Future<String> createInvite({
    required String toUid,
    String categoryId = 'random',
    int difficulty = 1,
    int totalQuestions = 10,
    int timePerQuestionSec = 15,
  }) async {
    if (toUid.trim().isEmpty) {
      throw Exception(_l10n.serviceInvalidUser);
    }
    if (toUid == uid) {
      throw Exception(_l10n.serviceCannotChallengeSelfPeriod);
    }

    final result = await _callable('createRealtimeInvite').call({
      'toUid': toUid,
      'categoryId': categoryId,
      'difficulty': difficulty,
      'totalQuestions': totalQuestions,
      'timePerQuestionSec': timePerQuestionSec,
    });
    return ((result.data as Map)['inviteId'] ?? '').toString();
  }

  /// Accepts an invite; the server creates the match and tells the inviter.
  Future<String> acceptInvite({required String inviteId}) async {
    try {
      final result = await _callable('acceptRealtimeInvite', timeoutSeconds: 30)
          .call({'inviteId': inviteId});
      return ((result.data as Map)['matchId'] ?? '').toString();
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? _l10n.serviceInviteNoLongerAvailable);
    }
  }

  Future<void> declineInvite({required String inviteId}) async {
    await _callable('closeRealtimeInvite').call({'inviteId': inviteId});
  }

  Future<void> cancelInvite({required String inviteId}) async {
    await _callable('closeRealtimeInvite').call({'inviteId': inviteId});
  }
}
