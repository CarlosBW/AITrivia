class AvatarInfo {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final String unlockLabel;

  /// Para avatares futuros con imagen generada por IA o asset propio.
  /// Por ahora puede quedar null.
  final String? imageUrl;

  /// Permite marcar avatares dinámicos que no están en la lista estática,
  /// como avatares únicos generados por temas IA.
  final bool isDynamic;

  const AvatarInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.unlockLabel,
    this.imageUrl,
    this.isDynamic = false,
  });
}

class AvatarService {
  AvatarService._();

  static final AvatarService instance = AvatarService._();

  // ============================================================
  // BASE AVATARS
  // ============================================================

  static const List<AvatarInfo> baseAvatars = [
    AvatarInfo(
      id: 'avatar_1',
      name: 'Brain',
      emoji: '🧠',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
    AvatarInfo(
      id: 'avatar_2',
      name: 'Rocket',
      emoji: '🚀',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
    AvatarInfo(
      id: 'avatar_3',
      name: 'Gamer',
      emoji: '🎮',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
    AvatarInfo(
      id: 'avatar_4',
      name: 'Fire',
      emoji: '🔥',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
    AvatarInfo(
      id: 'avatar_5',
      name: 'Star',
      emoji: '⭐',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
    AvatarInfo(
      id: 'avatar_6',
      name: 'Cat',
      emoji: '🐱',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
    AvatarInfo(
      id: 'avatar_7',
      name: 'Robot',
      emoji: '🤖',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
    AvatarInfo(
      id: 'avatar_8',
      name: 'Trophy',
      emoji: '🏆',
      category: 'base',
      unlockLabel: 'Default avatar',
    ),
  ];

  // ============================================================
  // PVP AVATARS
  // ============================================================

  static const List<AvatarInfo> pvpAvatars = [
    AvatarInfo(
      id: 'pvp_bronze',
      name: 'Bronze Challenger',
      emoji: '🥉',
      category: 'pvp',
      unlockLabel: 'Reach Bronze League',
    ),
    AvatarInfo(
      id: 'pvp_silver',
      name: 'Silver Challenger',
      emoji: '🥈',
      category: 'pvp',
      unlockLabel: 'Reach Silver League',
    ),
    AvatarInfo(
      id: 'pvp_gold',
      name: 'Gold Champion',
      emoji: '🥇',
      category: 'pvp',
      unlockLabel: 'Reach Gold League',
    ),
    AvatarInfo(
      id: 'pvp_platinum',
      name: 'Platinum Elite',
      emoji: '💎',
      category: 'pvp',
      unlockLabel: 'Reach Platinum League',
    ),
    AvatarInfo(
      id: 'pvp_diamond',
      name: 'Diamond Elite',
      emoji: '🔷',
      category: 'pvp',
      unlockLabel: 'Reach Diamond League',
    ),
    AvatarInfo(
      id: 'pvp_master',
      name: 'Master Champion',
      emoji: '👑',
      category: 'pvp',
      unlockLabel: 'Reach Master League',
    ),
  ];

  // ============================================================
  // WEEKLY TOPIC AVATARS
  // ============================================================

  static const List<AvatarInfo> weeklyAvatars = [
    AvatarInfo(
      id: 'weekly_cine',
      name: 'Cinema Expert',
      emoji: '🎬',
      category: 'weekly',
      unlockLabel: 'Complete a Cinema Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_history',
      name: 'History Scholar',
      emoji: '🏛️',
      category: 'weekly',
      unlockLabel: 'Complete a History Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_science',
      name: 'Science Mind',
      emoji: '🔬',
      category: 'weekly',
      unlockLabel: 'Complete a Science Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_sports',
      name: 'Sports Champion',
      emoji: '🏟️',
      category: 'weekly',
      unlockLabel: 'Complete a Sports Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_music',
      name: 'Music Maestro',
      emoji: '🎵',
      category: 'weekly',
      unlockLabel: 'Complete a Music Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_art',
      name: 'Art Connoisseur',
      emoji: '🎨',
      category: 'weekly',
      unlockLabel: 'Complete an Art Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_geography',
      name: 'Globe Trotter',
      emoji: '🌍',
      category: 'weekly',
      unlockLabel: 'Complete a Geography Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_videogames',
      name: 'Game Master',
      emoji: '🎮',
      category: 'weekly',
      unlockLabel: 'Complete a Gaming Weekly Topic',
    ),
    AvatarInfo(
      id: 'weekly_books',
      name: 'Bookworm',
      emoji: '📚',
      category: 'weekly',
      unlockLabel: 'Complete a Books Weekly Topic',
    ),
  ];

  // ============================================================
  // ACHIEVEMENT AVATARS
  // ============================================================

  static const List<AvatarInfo> achievementAvatars = [
    AvatarInfo(
      id: 'achievement_100_questions',
      name: '100 Answers',
      emoji: '🎯',
      category: 'achievement',
      unlockLabel: 'Answer 100 questions',
    ),
    AvatarInfo(
      id: 'achievement_1000_questions',
      name: 'Trivia Legend',
      emoji: '🌟',
      category: 'achievement',
      unlockLabel: 'Answer 1000 questions',
    ),
  ];

  // ============================================================
  // AI AVATAR PLACEHOLDERS
  // ============================================================

  static const List<AvatarInfo> aiAvatars = [
    AvatarInfo(
      id: 'ai_topic_completed',
      name: 'AI Topic Master',
      emoji: '✨',
      category: 'ai',
      unlockLabel: 'Complete an AI-generated topic',
    ),
  ];

  List<AvatarInfo> get staticAvatars => [
        ...baseAvatars,
        ...pvpAvatars,
        ...weeklyAvatars,
        ...achievementAvatars,
        ...aiAvatars,
      ];

  /// Lista usada por el selector actual.
  ///
  /// Más adelante, cuando agreguemos avatares dinámicos generados por IA,
  /// el ProfileScreen podrá combinar esta lista con los dynamicAvatars del usuario.
  List<AvatarInfo> get allAvatars => staticAvatars;

  AvatarInfo avatarById(String? avatarId) {
    if (avatarId == null || avatarId.trim().isEmpty) {
      return baseAvatars.first;
    }

    return staticAvatars.firstWhere(
      (avatar) => avatar.id == avatarId,
      orElse: () => baseAvatars.first,
    );
  }

  AvatarInfo dynamicAvatarInfo({
    required String avatarId,
    required String name,
    required String imageUrl,
    String emoji = '✨',
    String category = 'ai_dynamic',
    String unlockLabel = 'Complete an AI topic',
  }) {
    return AvatarInfo(
      id: avatarId,
      name: name,
      emoji: emoji,
      category: category,
      unlockLabel: unlockLabel,
      imageUrl: imageUrl,
      isDynamic: true,
    );
  }

  String aiTopicAvatarId(String topicId) {
    return 'ai_topic_$topicId';
  }

  List<String> defaultUnlockedAvatarIds() {
    return baseAvatars.map((avatar) => avatar.id).toList();
  }

  // ============================================================
  // AVAILABILITY
  // ============================================================
  //
  // Note: unlockedAvatars/dynamicAvatars are locked against direct client
  // writes in firestore.rules — avatar unlocks are granted server-side
  // (see submitDailyChallengeResult for the question-count achievements).

  List<String> unlockedAvatarIdsForBestLeague({
    required String bestLeagueId,
    List<dynamic>? storedUnlockedAvatars,
  }) {
    final unlocked = <String>{
      ...defaultUnlockedAvatarIds(),
      ...?storedUnlockedAvatars?.map((e) => e.toString()),
    };

    switch (bestLeagueId) {
      case 'master':
        unlocked.add('pvp_master');
        unlocked.add('pvp_diamond');
        unlocked.add('pvp_platinum');
        unlocked.add('pvp_gold');
        unlocked.add('pvp_silver');
        unlocked.add('pvp_bronze');
        break;
      case 'diamond':
        unlocked.add('pvp_diamond');
        unlocked.add('pvp_platinum');
        unlocked.add('pvp_gold');
        unlocked.add('pvp_silver');
        unlocked.add('pvp_bronze');
        break;
      case 'platinum':
        unlocked.add('pvp_platinum');
        unlocked.add('pvp_gold');
        unlocked.add('pvp_silver');
        unlocked.add('pvp_bronze');
        break;
      case 'gold':
        unlocked.add('pvp_gold');
        unlocked.add('pvp_silver');
        unlocked.add('pvp_bronze');
        break;
      case 'silver':
        unlocked.add('pvp_silver');
        unlocked.add('pvp_bronze');
        break;
      case 'bronze':
      default:
        unlocked.add('pvp_bronze');
        break;
    }

    return unlocked.toList();
  }

  bool isAvatarUnlocked({
    required String avatarId,
    required String bestLeagueId,
    List<dynamic>? storedUnlockedAvatars,
  }) {
    return unlockedAvatarIdsForBestLeague(
      bestLeagueId: bestLeagueId,
      storedUnlockedAvatars: storedUnlockedAvatars,
    ).contains(avatarId);
  }

  String safestEquippedAvatar({
    required String? avatarId,
    required String bestLeagueId,
    List<dynamic>? storedUnlockedAvatars,
  }) {
    final current = avatarId ?? baseAvatars.first.id;

    if (isAvatarUnlocked(
      avatarId: current,
      bestLeagueId: bestLeagueId,
      storedUnlockedAvatars: storedUnlockedAvatars,
    )) {
      return current;
    }

    return baseAvatars.first.id;
  }
}