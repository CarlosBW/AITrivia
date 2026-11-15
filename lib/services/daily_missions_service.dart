import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'daily_missions.dart';

/// What opening the day's chest paid.
class MissionsChestReward {
  const MissionsChestReward({required this.coins, required this.xp});

  final int coins;
  final int xp;
}

/// Reads a player's missions day and opens its chest.
///
/// Nothing here counts progress: the server adds to the day as it judges
/// each level, Daily Challenge and Weekly Topic round, and this only
/// watches the result.
class DailyMissionsService {
  DailyMissionsService._();

  static final DailyMissionsService instance = DailyMissionsService._();

  /// The signed-in player's missions for [dateId], as they change.
  Stream<MissionsDay> watchDay(String dateId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('daily_missions')
        .doc(dateId)
        .snapshots()
        .map((snap) => MissionsDay.fromDoc(dateId, snap.data()));
  }

  /// Opens today's chest. Throws with the server's reason when it can't:
  /// missions still to do, or the chest already opened.
  Future<MissionsChestReward> claimChest() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          'claimDailyMissionsChest',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call();

    final data = Map<String, dynamic>.from(result.data as Map);
    return MissionsChestReward(
      coins: ((data['coins'] ?? 0) as num).toInt(),
      xp: ((data['xp'] ?? 0) as num).toInt(),
    );
  }
}
