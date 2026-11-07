import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_themes.dart';
import '../../theme/starfield_backdrop.dart';
import '../../widgets/nav_glyphs.dart';
import '../../widgets/question_answer_card.dart';

/// A game screen dressed in [spec], so a player can see a theme before
/// buying it. Nothing is equipped: the theme only applies inside this
/// screen.
///
/// Pops `true` when the player taps the price, and the store takes it
/// from there with its usual confirmation.
class ThemePreviewScreen extends StatelessWidget {
  const ThemePreviewScreen({
    super.key,
    required this.spec,
    required this.name,
    required this.owned,
    this.themeFor = buildAppTheme,
  });

  final AppThemeSpec spec;
  final String name;
  final bool owned;

  /// Builds the theme to preview. Tests swap it: [buildAppTheme] loads its
  /// fonts through google_fonts, which a test can't.
  final ThemeData Function(AppThemeSpec spec) themeFor;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: themeFor(spec),
      child: Builder(builder: (context) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final pageColor = context.decor.pageColor;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: themeBackdrop(
        spec.backdrop,
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              l10n.themePreviewIntro,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.themePreviewLevel,
              style: context.heading(20, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            // A wrong pick next to the right answer, so both verdicts show.
            QuestionAnswerCard(
              qText: l10n.themePreviewQuestion,
              options: [
                l10n.themePreviewAnswerVenus,
                l10n.themePreviewAnswerMars,
                l10n.themePreviewAnswerJupiter,
                l10n.themePreviewAnswerSaturn,
              ],
              answerIndex: 1,
              selectedIndex: 0,
              locked: true,
              onTapAnswer: (_) {},
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {},
              child: Text(l10n.themePreviewNext),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PreviewNavBar(icons: spec.navIcons),
          Container(
            color: pageColor,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(l10n.themePreviewClose),
                      ),
                    ),
                    if (!owned) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Text(
                            '🪙',
                            style: TextStyle(fontSize: 14),
                          ),
                          label: Text(l10n.themeShopPriceButton(spec.price)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom bar's glyphs in the previewed theme, the first one selected.
/// Only a picture: the real bar lives in the navigation shell.
class _PreviewNavBar extends StatelessWidget {
  const _PreviewNavBar({required this.icons});

  final AppNavIcons icons;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaces = context.surfaces;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: surfaces.hasBorder
              ? BorderSide(
                  color: surfaces.borderColor,
                  width: surfaces.borderWidth,
                )
              : BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 4; i++)
            SizedBox.square(
              dimension: 26,
              child: CustomPaint(
                painter: navGlyphPainters(
                  icons,
                  i == 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                )[i],
              ),
            ),
        ],
      ),
    );
  }
}
