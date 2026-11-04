import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/solo_progress.dart';

/// Lo que Inicio y Solo ofrecen para seguir jugando una categoría: el nivel
/// que se falló, para reintentarlo, o el siguiente sin aprobar.
void main() {
  test('sin progreso se empieza por el nivel 1', () {
    final p = SoloProgress.fromDoc(const {}, 10);
    expect(p.passedCount, 0);
    expect(p.nextLevel, 1);
    expect(p.completedAll, isFalse);
    expect(p.resume, (level: 1, retry: false));
  });

  test('tras aprobar, ofrece el siguiente nivel', () {
    final p = SoloProgress.fromDoc({
      'passedLevels': [1, 2],
      'completedLevels': [1, 2],
      'lastScore': {'levelNumber': 2, 'passed': true, 'correct': 8, 'total': 10},
    }, 10);
    expect(p.passedCount, 2);
    expect(p.resume, (level: 3, retry: false));
  });

  test('tras fallar un nivel nuevo, ofrece reintentarlo', () {
    final p = SoloProgress.fromDoc({
      'passedLevels': [1, 2],
      'completedLevels': [1, 2, 3],
      'lastScore': {'levelNumber': 3, 'passed': false, 'correct': 2, 'total': 10},
    }, 10);
    expect(p.resume, (level: 3, retry: true));
    expect(p.lastCorrect, 2);
    expect(p.lastTotal, 10);
  });

  test('fallar una repetición de un nivel ya aprobado no es un reintento', () {
    final p = SoloProgress.fromDoc({
      'passedLevels': [1, 2, 3],
      'lastScore': {'levelNumber': 1, 'passed': false, 'correct': 1, 'total': 10},
    }, 10);
    expect(p.resume, (level: 4, retry: false));
  });

  test('con todo aprobado no hay nada que retomar', () {
    final p = SoloProgress.fromDoc({
      'passedLevels': [for (var i = 1; i <= 10; i++) i],
    }, 10);
    expect(p.completedAll, isTrue);
    expect(p.nextLevel, 10);
    expect(p.resume, isNull);
  });

  test('tras ampliar un tema completado, ofrece el primer nivel nuevo', () {
    // completedAllLevels lo dejó el servidor cuando el tema tenía 10
    // niveles; con 20, ya no es cierto.
    final p = SoloProgress.fromDoc({
      'passedLevels': [for (var i = 1; i <= 10; i++) i],
      'completedAllLevels': true,
    }, 20);
    expect(p.completedAll, isFalse);
    expect(p.nextLevel, 11);
    expect(p.resume, (level: 11, retry: false));
  });

  test('los documentos viejos sin passedLevels se leen de levelStats', () {
    final p = SoloProgress.fromDoc({
      'levelStats': {
        '1': {'percent': 0.8},
        '2': {'percent': 0.3},
      },
    }, 10);
    expect(p.passedCount, 1);
    expect(p.nextLevel, 2);
  });

  test('ignora niveles fuera de rango y datos mal formados', () {
    final p = SoloProgress.fromDoc({
      'passedLevels': [0, 1, 99],
      'lastScore': 'basura',
    }, 10);
    expect(p.passedCount, 1);
    expect(p.resume, (level: 2, retry: false));
  });
}
