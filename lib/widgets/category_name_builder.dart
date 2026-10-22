import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/category_name_service.dart';

/// Builds [builder] with the display name of [categoryId] — "Aleatorio"
/// for 'random' — instead of the raw id.
class CategoryNameBuilder extends StatefulWidget {
  final String categoryId;
  final Widget Function(BuildContext context, String name) builder;

  const CategoryNameBuilder({
    super.key,
    required this.categoryId,
    required this.builder,
  });

  @override
  State<CategoryNameBuilder> createState() => _CategoryNameBuilderState();
}

class _CategoryNameBuilderState extends State<CategoryNameBuilder> {
  // Held here, not created in build: a new future on every rebuild made
  // the name blink back to its placeholder.
  late Future<String> _name = _lookup();

  Future<String> _lookup() =>
      CategoryNameService.instance.nameFor(widget.categoryId);

  @override
  void didUpdateWidget(CategoryNameBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) _name = _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.categoryId;
    if (id.isEmpty || id == 'random') {
      return widget.builder(
        context,
        AppLocalizations.of(context).friendChallengeCategoryRandom,
      );
    }

    return FutureBuilder<String>(
      future: _name,
      initialData: CategoryNameService.instance.cachedName(id),
      builder: (context, snap) => widget.builder(context, snap.data ?? '…'),
    );
  }
}
