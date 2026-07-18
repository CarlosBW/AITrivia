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
  // AI TOPICS CONFIG
  // ============================================================

  static const int maxAiTopicsPerUser = 20;

  static const int aiLevelsPerTopic = 10;
  static const int aiQuestionsPerLevel = 10;
  static const int aiGenerationBufferLevels = 2;

  static const int aiInitialGeneratedLevels = 2;

  // ============================================================
  // SOLO REWARDS
  // ============================================================

  static const int soloPerfectLevelCoins = 3;
  static const int soloGreatLevelCoins = 2;
  static const int soloGoodLevelCoins = 1;
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
  // LOGIN STREAK (separate from the Daily Challenge streak)
  // ============================================================

  static const int loginStreak3DaysCoins = 3;
  static const int loginStreak7DaysCoins = 8;
  static const int loginStreak14DaysCoins = 15;

  // ============================================================
  // PVP
  // ============================================================

  static const int defaultPvpWinReward = 2;

  // ============================================================
  // IAP COIN PACKS - planned
  // ============================================================

  static const int coinPackSmallCoins = 100;
  static const double coinPackSmallUsd = 0.99;

  static const int coinPackAiTopicCoins = 600;
  static const double coinPackAiTopicUsd = 4.99;

  static const int coinPackMediumCoins = 1500;
  static const double coinPackMediumUsd = 9.99;

  static const int coinPackLargeCoins = 4000;
  static const double coinPackLargeUsd = 19.99;

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
