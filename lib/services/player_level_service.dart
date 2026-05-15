class PlayerLevelInfo {
  final int level;
  final int currentLevelXp;
  final int xpRequired;
  final double progress;

  const PlayerLevelInfo({
    required this.level,
    required this.currentLevelXp,
    required this.xpRequired,
    required this.progress,
  });
}

class PlayerLevelService {
  PlayerLevelService._();

  static final instance = PlayerLevelService._();

  /// XP requerida para subir cada nivel
  int xpRequiredForLevel(int level) {
    if (level <= 1) return 100;

    return (100 * (1.18 * (level - 1))).round();
  }

  PlayerLevelInfo getLevelInfo(int totalXp) {
    int level = 1;
    int remainingXp = totalXp;

    while (true) {
      final needed = xpRequiredForLevel(level);

      if (remainingXp < needed) {
        return PlayerLevelInfo(
          level: level,
          currentLevelXp: remainingXp,
          xpRequired: needed,
          progress: (remainingXp / needed).clamp(0.0, 1.0),
        );
      }

      remainingXp -= needed;
      level++;
    }
  }
}