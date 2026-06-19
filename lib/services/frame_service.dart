class ProfileFrameInfo {
  final String id;
  final String name;
  final String emoji;
  final int colorValue;
  final String unlockLabel;

  const ProfileFrameInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    required this.unlockLabel,
  });
}

class FrameService {
  FrameService._();

  static final FrameService instance = FrameService._();

  static const List<ProfileFrameInfo> leagueFrames = [
    ProfileFrameInfo(
      id: 'bronze',
      name: 'Bronze Frame',
      emoji: '🥉',
      colorValue: 0xFFCD7F32,
      unlockLabel: 'Reach Bronze League',
    ),
    ProfileFrameInfo(
      id: 'silver',
      name: 'Silver Frame',
      emoji: '🥈',
      colorValue: 0xFFC0C0C0,
      unlockLabel: 'Reach Silver League',
    ),
    ProfileFrameInfo(
      id: 'gold',
      name: 'Gold Frame',
      emoji: '🥇',
      colorValue: 0xFFFFD700,
      unlockLabel: 'Reach Gold League',
    ),
    ProfileFrameInfo(
      id: 'platinum',
      name: 'Platinum Frame',
      emoji: '🏆',
      colorValue: 0xFF4DB6AC,
      unlockLabel: 'Reach Platinum League',
    ),
    ProfileFrameInfo(
      id: 'diamond',
      name: 'Diamond Frame',
      emoji: '💎',
      colorValue: 0xFF6EC6FF,
      unlockLabel: 'Reach Diamond League',
    ),
    ProfileFrameInfo(
      id: 'master',
      name: 'Master Frame',
      emoji: '👑',
      colorValue: 0xFF9C27B0,
      unlockLabel: 'Reach Master League',
    ),
  ];

  ProfileFrameInfo frameById(String? frameId) {
    if (frameId == null || frameId.trim().isEmpty) {
      return leagueFrames.first;
    }

    return leagueFrames.firstWhere(
      (frame) => frame.id == frameId,
      orElse: () => leagueFrames.first,
    );
  }

  ProfileFrameInfo frameForLeague(String? leagueId) {
    return frameById(leagueId);
  }

  List<ProfileFrameInfo> unlockedLeagueFrames({
    required String bestLeagueId,
  }) {
    final order = leagueFrames.map((frame) => frame.id).toList();
    final bestIndex = order.indexOf(bestLeagueId);

    if (bestIndex < 0) {
      return [leagueFrames.first];
    }

    return leagueFrames.take(bestIndex + 1).toList();
  }

  bool isFrameUnlocked({
    required String frameId,
    required String bestLeagueId,
  }) {
    return unlockedLeagueFrames(bestLeagueId: bestLeagueId)
        .any((frame) => frame.id == frameId);
  }

  String safestEquippedFrame({
    required String? equippedFrame,
    required String bestLeagueId,
  }) {
    final current = equippedFrame ?? 'bronze';

    if (isFrameUnlocked(frameId: current, bestLeagueId: bestLeagueId)) {
      return current;
    }

    return bestLeagueId;
  }
}