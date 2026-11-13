import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A section header: a short bar in the theme's colour and the title in
/// the theme's heading face.
///
/// It was a line of small grey text, which read as a caption left over
/// between two cards rather than the start of a section.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: context.heading(18, color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}
