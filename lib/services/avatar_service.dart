class AvatarInfo {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final String unlockLabel;

  const AvatarInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.unlockLabel,
  });
}

class AvatarService {
  AvatarService._();

  static final AvatarService instance = AvatarService._();

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

  List<AvatarInfo> get allAvatars => [
        ...baseAvatars,
        ...pvpAvatars,
      ];

  AvatarInfo avatarById(String? avatarId) {
    if (avatarId == null || avatarId.trim().isEmpty) {
      return baseAvatars.first;
    }

    return allAvatars.firstWhere(
      (avatar) => avatar.id == avatarId,
      orElse: () => baseAvatars.first,
    );
  }

  List<String> defaultUnlockedAvatarIds() {
    return baseAvatars.map((avatar) => avatar.id).toList();
  }

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