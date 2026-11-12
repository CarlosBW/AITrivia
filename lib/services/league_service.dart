import 'dart:math' as math;

class LeagueInfo {
  final String id;
  final String name;
  final String emoji;
  final int minScore;
  final int colorValue;
  final int top1Reward;
  final int top3Reward;
  final int top10Reward;

  const LeagueInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.minScore,
    required this.colorValue,
    required this.top1Reward,
    required this.top3Reward,
    required this.top10Reward,
  });
}

class LeagueService {
  LeagueService._();

  /// Share of the league score lost at each week's turn. Mirrors
  /// `WEEKLY_LEAGUE_DECAY` in functions/src/weekly_league.ts.
  static const double weeklyDecay = 0.25;

  /// A stored league score as it stands in [currentWeekId].
  ///
  /// The server wears the score down when the player next plays, so the
  /// stored number is from the last week they did. This shows what it is
  /// worth now — the number the server will start from — instead of a
  /// score that drops by surprise on the next Daily Challenge. Mirrors
  /// `decayedLeagueScore` in functions/src/weekly_league.ts.
  static int decayedLeagueScore(
    int score,
    String? scoreWeekId,
    String currentWeekId,
  ) {
    final held = score < 0 ? 0 : score;
    final from = DateTime.tryParse('${scoreWeekId ?? ''}T00:00:00Z');
    final to = DateTime.tryParse('${currentWeekId}T00:00:00Z');
    if (from == null || to == null) return held;

    final weeks = (to.difference(from).inDays / 7).round().clamp(0, 52);
    if (weeks == 0) return held;

    return (held * math.pow(1 - weeklyDecay, weeks)).floor();
  }

  static final instance = LeagueService._();

  static const leagues = [
    LeagueInfo(
      id: 'bronze',
      name: 'Bronze',
      emoji: '🥉',
      minScore: 0,
      colorValue: 0xFFCD7F32,
      top1Reward: 80,
      top3Reward: 50,
      top10Reward: 25,
    ),
    LeagueInfo(
      id: 'silver',
      name: 'Silver',
      emoji: '🥈',
      minScore: 300,
      colorValue: 0xFFC0C0C0,
      top1Reward: 120,
      top3Reward: 75,
      top10Reward: 40,
    ),
    LeagueInfo(
      id: 'gold',
      name: 'Gold',
      emoji: '🥇',
      minScore: 700,
      colorValue: 0xFFFFD700,
      top1Reward: 180,
      top3Reward: 120,
      top10Reward: 70,
    ),
    LeagueInfo(
      id: 'diamond',
      name: 'Diamond',
      emoji: '💎',
      minScore: 1200,
      colorValue: 0xFF6EC6FF,
      top1Reward: 300,
      top3Reward: 200,
      top10Reward: 120,
    ),
    LeagueInfo(
      id: 'master',
      name: 'Master',
      emoji: '👑',
      minScore: 2000,
      colorValue: 0xFF9C27B0,
      top1Reward: 500,
      top3Reward: 350,
      top10Reward: 200,
    ),
  ];

  LeagueInfo getLeagueFromScore(int score) {
    LeagueInfo current = leagues.first;

    for (final league in leagues) {
      if (score >= league.minScore) {
        current = league;
      }
    }

    return current;
  }
}