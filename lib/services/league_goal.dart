/// One row of a league board, as far as a goal needs it.
typedef LeagueRow = ({String uid, String name, int score});

/// Where a player stands on their league board and what the next step up
/// is: the rival just ahead and the points it takes to pass them.
class LeagueGoal {
  const LeagueGoal({
    required this.rank,
    this.rivalName,
    this.pointsToPass = 0,
    this.lead,
  });

  /// The player's place, from 1.
  final int rank;

  /// Who is just ahead; null when the player is first.
  final String? rivalName;

  /// Points that would put the player ahead of that rival.
  final int pointsToPass;

  /// When first: how far ahead of second place, or null when alone.
  final int? lead;

  bool get isFirst => rank == 1;
}

/// The goal for [myUid] on [board], which is ordered best score first, as
/// the leaderboard query returns it. Null when the player isn't on it: the
/// board shows only the top of a league.
LeagueGoal? leagueGoal(List<LeagueRow> board, String myUid) {
  final index = board.indexWhere((row) => row.uid == myUid);
  if (index < 0) return null;

  final mine = board[index].score;
  if (index == 0) {
    return LeagueGoal(
      rank: 1,
      lead: board.length > 1 ? mine - board[1].score : null,
    );
  }

  final rival = board[index - 1];
  return LeagueGoal(
    rank: index + 1,
    rivalName: rival.name,
    // One more than the gap: level on points isn't ahead.
    pointsToPass: rival.score - mine + 1,
  );
}
