import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/achievement_service.dart';

/// Una recompensa lista para reclamar quedaba donde cayera en la lista,
/// a veces debajo de una pantalla entera de logros sin empezar.
void main() {
  AchievementInfo info(String id) => AchievementInfo(
        id: id,
        title: id,
        description: '',
        target: 10,
        rewardCoins: 10,
        rewardXp: 10,
        icon: '',
      );

  final all = [info('a'), info('b'), info('c'), info('d'), info('e')];

  List<String> order(Map<String, Map<String, dynamic>> progress) =>
      achievementsInDisplayOrder(all, progress).map((a) => a.id).toList();

  test('las recompensas pendientes de reclamar van primero', () {
    expect(
      order({
        'd': {'completed': true, 'claimed': false},
      }),
      ['d', 'a', 'b', 'c', 'e'],
    );
  });

  test('los ya reclamados van al final', () {
    expect(
      order({
        'a': {'completed': true, 'claimed': true},
        'c': {'completed': true, 'claimed': false},
      }),
      ['c', 'b', 'd', 'e', 'a'],
    );
  });

  test('dentro de cada grupo se conserva el orden original', () {
    expect(
      order({
        'e': {'completed': true, 'claimed': false},
        'b': {'completed': true, 'claimed': false},
        'd': {'completed': true, 'claimed': true},
        'a': {'completed': true, 'claimed': true},
      }),
      ['b', 'e', 'c', 'a', 'd'],
    );
  });

  test('sin progreso la lista queda como estaba', () {
    expect(order({}), ['a', 'b', 'c', 'd', 'e']);
  });

  test('no modifica la lista que recibe', () {
    order({
      'e': {'completed': true, 'claimed': false},
    });
    expect(all.map((a) => a.id), ['a', 'b', 'c', 'd', 'e']);
  });
}
