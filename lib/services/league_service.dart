class LeagueInfo {
  final String id;
  final String name;
  final String emoji;
  final int minScore;
  final int colorValue;

  const LeagueInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.minScore,
    required this.colorValue,
  });
}

class LeagueService {
  LeagueService._();

  static final instance = LeagueService._();

  static const leagues = [
    LeagueInfo(
      id: 'bronze',
      name: 'Bronze',
      emoji: '🥉',
      minScore: 0,
      colorValue: 0xFFCD7F32,
    ),
    LeagueInfo(
      id: 'silver',
      name: 'Silver',
      emoji: '🥈',
      minScore: 300,
      colorValue: 0xFFC0C0C0,
    ),
    LeagueInfo(
      id: 'gold',
      name: 'Gold',
      emoji: '🥇',
      minScore: 700,
      colorValue: 0xFFFFD700,
    ),
    LeagueInfo(
      id: 'diamond',
      name: 'Diamond',
      emoji: '💎',
      minScore: 1200,
      colorValue: 0xFF6EC6FF,
    ),
    LeagueInfo(
      id: 'master',
      name: 'Master',
      emoji: '👑',
      minScore: 2000,
      colorValue: 0xFF9C27B0,
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