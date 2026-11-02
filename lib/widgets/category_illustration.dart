import 'package:flutter/material.dart';

/// The built-in categories with an illustration of their own, by id.
const List<String> categoryIllustrationIds = [
  'arte',
  'ciencia',
  'cine',
  'deportes',
  'geografia',
  'historia',
  'libros',
  'musica',
  'videojuegos',
];

/// Whole words only: "art" inside "Cartas" is not Arte.
final Map<String, RegExp> _namePatterns = {
  'cine': RegExp(r'\b(cine|movies?|films?)\b'),
  'historia': RegExp(r'\b(historia|history)\b'),
  'ciencia': RegExp(r'\b(ciencias?|science)\b'),
  'geografia': RegExp(r'\b(geografia|geography)\b'),
  'musica': RegExp(r'\b(musica|music)\b'),
  'arte': RegExp(r'\b(arte|art)\b'),
  'libros': RegExp(r'\b(libros?|books?|literatura|literature)\b'),
  'videojuegos': RegExp(r'\b(videojuegos?|video ?games?)\b'),
  'deportes': RegExp(r'\b(deportes?|sports?)\b'),
};

String _withoutAccents(String s) => s
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

/// The 3D illustration for a category: its own when the id or the name is
/// one of the built-in ones, the AI one for an AI topic, and a generic one
/// for anything else.
String categoryIllustrationAsset(
  String categoryId,
  String name, {
  bool isAiTopic = false,
}) {
  if (isAiTopic) return 'assets/illustrations/ai_topic.png';

  if (categoryIllustrationIds.contains(categoryId)) {
    return 'assets/illustrations/$categoryId.png';
  }

  final key = _withoutAccents('$categoryId $name'.toLowerCase());
  for (final entry in _namePatterns.entries) {
    if (entry.value.hasMatch(key)) {
      return 'assets/illustrations/${entry.key}.png';
    }
  }
  return 'assets/illustrations/random.png';
}

/// A category's illustration at [size], see [categoryIllustrationAsset].
class CategoryIllustration extends StatelessWidget {
  final String categoryId;
  final String name;
  final bool isAiTopic;
  final double size;

  const CategoryIllustration({
    super.key,
    required this.categoryId,
    required this.name,
    this.isAiTopic = false,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      categoryIllustrationAsset(categoryId, name, isAiTopic: isAiTopic),
      width: size,
      height: size,
      // The files are 512px; decode near the size shown instead.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
    );
  }
}
