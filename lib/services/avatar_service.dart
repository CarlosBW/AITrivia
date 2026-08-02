import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

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

  // Resolved from the acting user's own device locale — correct for
  // instance methods below (avatarById, safestEquippedAvatar, etc.) that
  // don't have a BuildContext handy. Widgets that already have one (e.g.
  // the avatar picker listing every avatar) should call the *For(l10n)
  // variants directly instead, mirroring AchievementService's pattern.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  // Doc ids only — kept separate from baseAvatarsFor() so id-only lookups
  // (defaultUnlockedAvatarIds) don't need an AppLocalizations instance.
  static const List<String> _baseAvatarIds = [
    'avatar_1', 'avatar_2', 'avatar_3', 'avatar_4',
    'avatar_5', 'avatar_6', 'avatar_7', 'avatar_8',
  ];

  // ============================================================
  // BASE AVATARS
  // ============================================================

  static List<AvatarInfo> baseAvatarsFor(AppLocalizations l10n) => [
        AvatarInfo(
          id: 'avatar_1',
          name: l10n.avatarNameBrain,
          emoji: '🧠',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
        AvatarInfo(
          id: 'avatar_2',
          name: l10n.avatarNameRocket,
          emoji: '🚀',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
        AvatarInfo(
          id: 'avatar_3',
          name: l10n.avatarNameGamer,
          emoji: '🎮',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
        AvatarInfo(
          id: 'avatar_4',
          name: l10n.avatarNameFire,
          emoji: '🔥',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
        AvatarInfo(
          id: 'avatar_5',
          name: l10n.avatarNameStar,
          emoji: '⭐',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
        AvatarInfo(
          id: 'avatar_6',
          name: l10n.avatarNameCat,
          emoji: '🐱',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
        AvatarInfo(
          id: 'avatar_7',
          name: l10n.avatarNameRobot,
          emoji: '🤖',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
        AvatarInfo(
          id: 'avatar_8',
          name: l10n.avatarNameTrophy,
          emoji: '🏆',
          category: 'base',
          unlockLabel: l10n.avatarUnlockDefault,
        ),
      ];

  // ============================================================
  // PVP AVATARS
  // ============================================================

  static List<AvatarInfo> pvpAvatarsFor(AppLocalizations l10n) => [
        AvatarInfo(
          id: 'pvp_bronze',
          name: l10n.avatarNamePvpBronze,
          emoji: '🥉',
          category: 'pvp',
          unlockLabel: l10n.avatarUnlockReachBronze,
        ),
        AvatarInfo(
          id: 'pvp_silver',
          name: l10n.avatarNamePvpSilver,
          emoji: '🥈',
          category: 'pvp',
          unlockLabel: l10n.avatarUnlockReachSilver,
        ),
        AvatarInfo(
          id: 'pvp_gold',
          name: l10n.avatarNamePvpGold,
          emoji: '🥇',
          category: 'pvp',
          unlockLabel: l10n.avatarUnlockReachGold,
        ),
        AvatarInfo(
          id: 'pvp_platinum',
          name: l10n.avatarNamePvpPlatinum,
          emoji: '💎',
          category: 'pvp',
          unlockLabel: l10n.avatarUnlockReachPlatinum,
        ),
        AvatarInfo(
          id: 'pvp_diamond',
          name: l10n.avatarNamePvpDiamond,
          emoji: '🔷',
          category: 'pvp',
          unlockLabel: l10n.avatarUnlockReachDiamond,
        ),
        AvatarInfo(
          id: 'pvp_master',
          name: l10n.avatarNamePvpMaster,
          emoji: '👑',
          category: 'pvp',
          unlockLabel: l10n.avatarUnlockReachMaster,
        ),
      ];

  // ============================================================
  // WEEKLY TOPIC AVATARS
  // ============================================================

  static List<AvatarInfo> weeklyAvatarsFor(AppLocalizations l10n) => [
        AvatarInfo(
          id: 'weekly_cine',
          name: l10n.avatarNameWeeklyCine,
          emoji: '🎬',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyCine,
        ),
        AvatarInfo(
          id: 'weekly_history',
          name: l10n.avatarNameWeeklyHistory,
          emoji: '🏛️',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyHistory,
        ),
        AvatarInfo(
          id: 'weekly_science',
          name: l10n.avatarNameWeeklyScience,
          emoji: '🔬',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyScience,
        ),
        AvatarInfo(
          id: 'weekly_sports',
          name: l10n.avatarNameWeeklySports,
          emoji: '🏟️',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklySports,
        ),
        AvatarInfo(
          id: 'weekly_music',
          name: l10n.avatarNameWeeklyMusic,
          emoji: '🎵',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyMusic,
        ),
        AvatarInfo(
          id: 'weekly_art',
          name: l10n.avatarNameWeeklyArt,
          emoji: '🎨',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyArt,
        ),
        AvatarInfo(
          id: 'weekly_geography',
          name: l10n.avatarNameWeeklyGeography,
          emoji: '🌍',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyGeography,
        ),
        AvatarInfo(
          id: 'weekly_videogames',
          name: l10n.avatarNameWeeklyVideogames,
          emoji: '🎮',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyVideogames,
        ),
        AvatarInfo(
          id: 'weekly_books',
          name: l10n.avatarNameWeeklyBooks,
          emoji: '📚',
          category: 'weekly',
          unlockLabel: l10n.avatarUnlockWeeklyBooks,
        ),
      ];

  // ============================================================
  // ACHIEVEMENT AVATARS
  // ============================================================

  static List<AvatarInfo> achievementAvatarsFor(AppLocalizations l10n) => [
        AvatarInfo(
          id: 'achievement_100_questions',
          name: l10n.avatarName100Questions,
          emoji: '🎯',
          category: 'achievement',
          unlockLabel: l10n.avatarUnlock100Questions,
        ),
        AvatarInfo(
          id: 'achievement_1000_questions',
          name: l10n.avatarName1000Questions,
          emoji: '🌟',
          category: 'achievement',
          unlockLabel: l10n.avatarUnlock1000Questions,
        ),
      ];

  // ============================================================
  // AI AVATAR PLACEHOLDERS
  // ============================================================

  static List<AvatarInfo> aiAvatarsFor(AppLocalizations l10n) => [
        AvatarInfo(
          id: 'ai_topic_completed',
          name: l10n.avatarNameAiTopicMaster,
          emoji: '✨',
          category: 'ai',
          unlockLabel: l10n.avatarUnlockAiTopicMaster,
        ),
      ];

  static List<AvatarInfo> staticAvatarsFor(AppLocalizations l10n) => [
        ...baseAvatarsFor(l10n),
        ...pvpAvatarsFor(l10n),
        ...weeklyAvatarsFor(l10n),
        ...achievementAvatarsFor(l10n),
        ...aiAvatarsFor(l10n),
      ];

  List<AvatarInfo> get staticAvatars => staticAvatarsFor(_l10n);

  /// Lista usada por el selector actual.
  ///
  /// Más adelante, cuando agreguemos avatares dinámicos generados por IA,
  /// el ProfileScreen podrá combinar esta lista con los dynamicAvatars del usuario.
  List<AvatarInfo> allAvatarsFor(AppLocalizations l10n) => staticAvatarsFor(l10n);

  AvatarInfo avatarById(String? avatarId) {
    if (avatarId == null || avatarId.trim().isEmpty) {
      return baseAvatarsFor(_l10n).first;
    }

    return staticAvatarsFor(_l10n).firstWhere(
      (avatar) => avatar.id == avatarId,
      orElse: () => baseAvatarsFor(_l10n).first,
    );
  }

  AvatarInfo dynamicAvatarInfo({
    required String avatarId,
    required String name,
    required String imageUrl,
    String emoji = '✨',
    String category = 'ai_dynamic',
    String? unlockLabel,
  }) {
    return AvatarInfo(
      id: avatarId,
      name: name,
      emoji: emoji,
      category: category,
      unlockLabel: unlockLabel ?? _l10n.avatarUnlockAiTopicMaster,
      imageUrl: imageUrl,
      isDynamic: true,
    );
  }

  String aiTopicAvatarId(String topicId) {
    return 'ai_topic_$topicId';
  }

  List<String> defaultUnlockedAvatarIds() {
    return List<String>.from(_baseAvatarIds);
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
    final current = avatarId ?? _baseAvatarIds.first;

    if (isAvatarUnlocked(
      avatarId: current,
      bestLeagueId: bestLeagueId,
      storedUnlockedAvatars: storedUnlockedAvatars,
    )) {
      return current;
    }

    return _baseAvatarIds.first;
  }
}
