import 'package:flutter/material.dart';

/// Small-caps section header, formalizing the style already used ad hoc
/// for Home's "Más formas de jugar" label.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.black54,
        letterSpacing: 0.3,
      ),
    );
  }
}
