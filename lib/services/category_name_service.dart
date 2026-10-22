import 'package:cloud_firestore/cloud_firestore.dart';

/// Display names of the fixed categories, for screens that only hold an id.
///
/// Matches, invites and notifications store the category id ('cine'), and
/// those screens printed it as it came. One read of `fixed_categories`
/// per session covers every lookup after it.
class CategoryNameService {
  CategoryNameService._();

  static final CategoryNameService instance = CategoryNameService._();

  Future<Map<String, String>>? _names;
  Map<String, String>? _loaded;

  /// The name if the categories are already loaded; null otherwise.
  String? cachedName(String categoryId) => _loaded?[categoryId];

  /// The display name of [categoryId], or the id itself if it has none.
  Future<String> nameFor(String categoryId) async {
    final names = await (_names ??= _load());
    return names[categoryId] ?? categoryId;
  }

  Future<Map<String, String>> _load() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('fixed_categories').get();
      final names = <String, String>{
        for (final doc in snap.docs)
          if (doc.data()['name'] is String &&
              (doc.data()['name'] as String).isNotEmpty)
            doc.id: doc.data()['name'] as String,
      };
      return _loaded = names;
    } catch (_) {
      // Try again on the next lookup rather than keeping the failure.
      _names = null;
      return const {};
    }
  }
}
