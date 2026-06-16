class EconomyService {
  EconomyService._();

  static final EconomyService instance = EconomyService._();

  // ============================================================
  // LIVES
  // ============================================================

  static const int buyFullLifeCost = 10;

  // ============================================================
  // AI TOPICS - future economy
  // ============================================================

  static const int firstAiTopicFreePasses = 1;
  static const int createAiTopicCost = 600;
  static const int regenerateAiQuestionsCost = 150;
  static const int expandAiTopicCost = 300;

  // ============================================================
  // SOLO REWARDS
  // ============================================================

  static const int soloPerfectLevelCoins = 8;
  static const int soloGreatLevelCoins = 5;
  static const int soloGoodLevelCoins = 3;
  static const int completeFixedCategoryCoins = 10;

  // ============================================================
  // DAILY CHALLENGE
  // ============================================================

  static const int dailyCoinsPerBlock = 5;
  static const int dailyCorrectPerCoinBlock = 10;

  static const int dailyStreak3DaysCoins = 5;
  static const int dailyStreak7DaysCoins = 15;
  static const int dailyStreak14DaysCoins = 30;

  static const int dailyLevelUpCoins = 15;

  // ============================================================
  // PVP
  // ============================================================

  static const int defaultPvpWinReward = 2;

  String formatCoins(int coins) {
    return '$coins coins';
  }

  bool canAfford({
    required int currentCoins,
    required int cost,
  }) {
    return currentCoins >= cost;
  }
}