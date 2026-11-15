import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/league_goal.dart';

void main() {
  const board = <LeagueRow>[
    (uid: 'a', name: 'Ana', score: 900),
    (uid: 'b', name: 'Beto', score: 640),
    (uid: 'me', name: 'Yo', score: 600),
    (uid: 'c', name: 'Caro', score: 200),
  ];

  test('dice a quién tienes delante y cuánto falta para pasarlo', () {
    final goal = leagueGoal(board, 'me')!;

    expect(goal.rank, 3);
    expect(goal.isFirst, isFalse);
    expect(goal.rivalName, 'Beto');
    // Empatar no es pasar: hace falta un punto más que la diferencia.
    expect(goal.pointsToPass, 41);
  });

  test('empatado con el de delante falta un solo punto', () {
    final goal = leagueGoal(const [
      (uid: 'a', name: 'Ana', score: 600),
      (uid: 'me', name: 'Yo', score: 600),
    ], 'me')!;

    expect(goal.pointsToPass, 1);
  });

  test('en primer lugar dice la ventaja sobre el segundo', () {
    final goal = leagueGoal(board, 'a')!;

    expect(goal.isFirst, isTrue);
    expect(goal.rivalName, isNull);
    expect(goal.lead, 260);
  });

  test('primero y solo no hay ventaja que medir', () {
    final goal = leagueGoal(const [(uid: 'me', name: 'Yo', score: 90)], 'me')!;

    expect(goal.isFirst, isTrue);
    expect(goal.lead, isNull);
  });

  // La tabla muestra solo lo más alto de la liga.
  test('quien no aparece en la tabla no tiene meta', () {
    expect(leagueGoal(board, 'otro'), isNull);
    expect(leagueGoal(const [], 'me'), isNull);
  });
}
