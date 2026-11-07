import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/widgets/category_illustration.dart';

/// Cada categoría fija tiene su ilustración 3D; un tema IA lleva la suya y
/// lo que no se reconoce cae en la genérica, nunca en un asset inexistente.
void main() {
  test('las categorías fijas usan su propia ilustración', () {
    for (final id in const [
      'arte',
      'astronomia',
      'ciencia',
      'cine',
      'deportes',
      'geografia',
      'historia',
      'libros',
      'musica',
      'videojuegos',
    ]) {
      expect(
        categoryIllustrationAsset(id, ''),
        'assets/illustrations/$id.png',
        reason: id,
      );
    }
  });

  test('se reconoce por el nombre, en español o inglés', () {
    expect(categoryIllustrationAsset('x', 'Movies'),
        'assets/illustrations/cine.png');
    expect(categoryIllustrationAsset('x', 'Música'),
        'assets/illustrations/musica.png');
    expect(categoryIllustrationAsset('x', 'Geography'),
        'assets/illustrations/geografia.png');
    expect(categoryIllustrationAsset('x', 'Video games'),
        'assets/illustrations/videojuegos.png');
    expect(categoryIllustrationAsset('x', 'Astronomía'),
        'assets/illustrations/astronomia.png');
    expect(categoryIllustrationAsset('x', 'Astronomy'),
        'assets/illustrations/astronomia.png');
  });

  test('un tema IA usa la ilustración de IA aunque su nombre coincida', () {
    expect(categoryIllustrationAsset('t1', 'Cine de terror', isAiTopic: true),
        'assets/illustrations/ai_topic.png');
  });

  test('lo desconocido cae en la ilustración genérica', () {
    expect(categoryIllustrationAsset('cocina', 'Cocina'),
        'assets/illustrations/random.png');
    // "art" dentro de otra palabra no es Arte.
    expect(categoryIllustrationAsset('cartas', 'Cartas'),
        'assets/illustrations/random.png');
  });

  test('todas las rutas devueltas existen', () {
    for (final path in [
      for (final id in categoryIllustrationIds) 'assets/illustrations/$id.png',
      categoryIllustrationAsset('t', 't', isAiTopic: true),
      categoryIllustrationAsset('zzz', 'zzz'),
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
