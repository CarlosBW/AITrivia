import 'package:flutter/material.dart';

/// An app-bar title that shrinks to fit before it lets itself be cut.
///
/// Nearly every screen carries the player's name and avatar in its bar,
/// which on a phone leaves the title about half the width. A plain `Text`
/// answered that with an ellipsis — "Temporada…", "Weekly Chall…" — on
/// titles that would have fitted a few points smaller.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  /// How far the title may shrink. Past this it is cut after all: a title
  /// nobody can read is worse than one that is incomplete.
  static const double minScale = 0.7;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final fontSize = style.fontSize;

    return LayoutBuilder(
      builder: (context, constraints) {
        var scale = 1.0;

        if (fontSize != null && constraints.maxWidth.isFinite) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();

          final natural = painter.width;
          painter.dispose();

          if (natural > constraints.maxWidth) {
            // A hair under the exact ratio: glyph widths don't scale
            // perfectly linearly, and landing a pixel over brings the
            // ellipsis straight back.
            scale = (constraints.maxWidth / natural * 0.98)
                .clamp(minScale, 1.0);
          }
        }

        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: fontSize == null
              ? style
              : style.copyWith(fontSize: fontSize * scale),
        );
      },
    );
  }
}
