class CoinPack {
  final String id;
  final int coins;
  final double usd;

  const CoinPack({required this.id, required this.coins, required this.usd});
}

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
  // PVP
  // ============================================================

  static const int defaultPvpWinReward = 2;

  // ============================================================
  // IAP COIN PACKS
  // ============================================================
  //
  // `id` must exactly match the product id configured for this pack in
  // both the Google Play Console and App Store Connect once those are
  // set up — PurchaseService looks products up by this id, and the
  // verifyCoinPurchase Cloud Function maps id -> coins server-side (the
  // client-reported coin amount is never trusted).

  static const List<CoinPack> coinPacks = [
    CoinPack(id: 'coins_pack_small', coins: 100, usd: 0.99),
    CoinPack(id: 'coins_pack_ai_topic', coins: 600, usd: 4.99),
    CoinPack(id: 'coins_pack_medium', coins: 1500, usd: 9.99),
    CoinPack(id: 'coins_pack_large', coins: 4000, usd: 19.99),
  ];

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
