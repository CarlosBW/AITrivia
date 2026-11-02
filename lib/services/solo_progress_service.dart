import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../l10n/localized_content.dart';
import 'locale_controller.dart';
import 'solo_progress.dart';

/// The fixed category the player touched last, with what to offer next.
class RecentSoloCategory {
  final String categoryId;
  final String name;
  final SoloProgress progress;

  /// Never null: a category with nothing left to play isn't returned.
  final ({int level, bool retry}) resume;

  const RecentSoloCategory({
    required this.categoryId,
    required this.name,
    required this.progress,
    required this.resume,
  });
}

class SoloProgressService {
  SoloProgressService._();

  static final SoloProgressService instance = SoloProgressService._();

  /// Bumped when a fixed-category level is saved, so Home's card catches
  /// up with a level played from the Solo tab while Home sat in the
  /// background.
  final ValueNotifier<int> revision = ValueNotifier(0);

  void notifyLevelSaved() => revision.value++;

  /// The most recently played fixed category, for Home's "keep going" /
  /// "try again" card. Two reads: the latest progress doc and its category.
  Future<RecentSoloCategory?> mostRecent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final db = FirebaseFirestore.instance;
    final latest = await db
        .collection('users')
        .doc(uid)
        .collection('progress_fixed')
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .get();
    if (latest.docs.isEmpty) return null;

    final progressDoc = latest.docs.first;
    final category =
        await db.collection('fixed_categories').doc(progressDoc.id).get();
    final categoryData = category.data();
    if (categoryData == null || categoryData['isActive'] == false) return null;

    final levelCount = ((categoryData['levelCount'] ?? 10) as num).toInt();
    final progress = SoloProgress.fromDoc(progressDoc.data(), levelCount);
    final resume = progress.resume;
    if (resume == null) return null;

    return RecentSoloCategory(
      categoryId: progressDoc.id,
      name: localizedCategoryName(
            categoryData,
            LocaleController.instance.locale.value.languageCode,
          ) ??
          progressDoc.id,
      progress: progress,
      resume: resume,
    );
  }
}
