import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';

/// One package (or font) and the licenses it ships under.
class PackageLicenses {
  PackageLicenses(this.name);

  final String name;
  final List<LicenseEntry> entries = [];
}

/// The registered licenses, one group per package, sorted by name whatever
/// its capitals. An entry naming several packages appears under each.
List<PackageLicenses> groupLicensesByPackage(Iterable<LicenseEntry> entries) {
  final byName = <String, PackageLicenses>{};
  for (final entry in entries) {
    for (final package in entry.packages) {
      final group = byName.putIfAbsent(package, () => PackageLicenses(package));
      if (!group.entries.contains(entry)) group.entries.add(entry);
    }
  }
  return byName.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// The open-source software and fonts the app is built with, and their
/// licenses. Reached from Profile.
///
/// Those licenses ask for their text to travel with the app, and this is
/// where it does. Flutter's own `showLicensePage` shows the same registry;
/// this one wears the app's theme.
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key, this.licenses});

  /// The licenses to show; the app's registry when left out.
  final Stream<LicenseEntry>? licenses;

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  late final Future<List<PackageLicenses>> _packages =
      (widget.licenses ?? LicenseRegistry.licenses)
          .toList()
          .then(groupLicensesByPackage);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l10n.profileLicenses)),
      body: FutureBuilder<List<PackageLicenses>>(
        future: _packages,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final packages = snap.data!;

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: packages.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.heroGradientStart,
                        colors.heroGradientEnd,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(context.radii.lg),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.favorite_rounded,
                          color: colors.onAccent, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          l10n.licensesIntro,
                          style: TextStyle(
                            color: colors.onAccent,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final package = packages[i - 1];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Text(
                      package.name.characters.first.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(
                    package.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(l10n.licensesCount(package.entries.length)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PackageLicensesScreen(package: package),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The full text of one package's licenses.
class _PackageLicensesScreen extends StatelessWidget {
  const _PackageLicensesScreen({required this.package});

  final PackageLicenses package;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(package.name)),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: package.entries.length,
        itemBuilder: (context, i) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(context.radii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final paragraph in package.entries[i].paragraphs)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      bottom: 10,
                      start: paragraph.indent > 0
                          ? 16.0 * paragraph.indent
                          : 0,
                    ),
                    child: Text(
                      paragraph.text,
                      textAlign:
                          paragraph.indent == LicenseParagraph.centeredIndent
                              ? TextAlign.center
                              : TextAlign.start,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                        fontWeight:
                            paragraph.indent == LicenseParagraph.centeredIndent
                                ? FontWeight.w700
                                : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
