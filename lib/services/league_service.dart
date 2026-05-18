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