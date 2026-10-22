import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/localized_content.dart';
import 'locale_controller.dart';

/// Display names of the fixed categories, for screens that only hold an id.
///
/// Matches, invites and notifications store the category id ('cine'), and
/// those screens printed it as it came. One read of `fixed_categories`
/// per session covers every lookup after it.
class CategoryNameService {
  CategoryNameService._();

  static final CategoryNameService instance = CategoryNameService._();

  // Whole docs, not names: the name depends on the player's language,
  // which can change after they load.
  Future<Map<String, Map<String, dynamic>>>? _categories;
  Map<String, Map<String, dynamic>>? _loaded;

  String? _nameIn(Map<String, Map<String, dynamic>>? docs, String id) =>
      localizedCategoryName(
        docs?[id],
        LocaleController.instance.locale.value.languageCode,
      );

  /// The name if the categories are already loaded; null otherwise.
  String? cachedName(String categoryId) => _nameIn(_loaded, categoryId);

  /// The display name of [categoryId], or the id itself if it has none.
  Future<String> nameFor(String categoryId) async {
    final docs = await (_categories ??= _load());
    return _nameIn(docs, categoryId) ?? categoryId;
  }

  Future<Map<String, Map<String, dynamic>>> _load() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('fixed_categories').get();
      final docs = {for (final doc in snap.docs) doc.id: doc.data()};
      return _loaded = docs;
    } catch (_) {
      // Try again on the next lookup rather than keeping the failure.
      _categories = null;
      return const {};
    }
  }
}
