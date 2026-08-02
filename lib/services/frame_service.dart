import 'locale_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_for.dart';

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

  // Resolved from the acting user's own device locale — mirrors
  // AvatarService's _l10n, for instance methods without a BuildContext.
  AppLocalizations get _l10n =>
      l10nFor(LocaleController.instance.locale.value.languageCode);

  static List<ProfileFrameInfo> leagueFramesFor(AppLocalizations l10n) => [
        ProfileFrameInfo(
          id: 'bronze',
          name: l10n.frameNameBronze,
          emoji: '🥉',
          colorValue: 0xFFCD7F32,
          unlockLabel: l10n.avatarUnlockReachBronze,
        ),
        ProfileFrameInfo(
          id: 'silver',
          name: l10n.frameNameSilver,
          emoji: '🥈',
          colorValue: 0xFFC0C0C0,
          unlockLabel: l10n.avatarUnlockReachSilver,
        ),
        ProfileFrameInfo(
          id: 'gold',
          name: l10n.frameNameGold,
          emoji: '🥇',
          colorValue: 0xFFFFD700,
          unlockLabel: l10n.avatarUnlockReachGold,
        ),
        ProfileFrameInfo(
          id: 'platinum',
          name: l10n.frameNamePlatinum,
          emoji: '🏆',
          colorValue: 0xFF4DB6AC,
          unlockLabel: l10n.avatarUnlockReachPlatinum,
        ),
        ProfileFrameInfo(
          id: 'diamond',
          name: l10n.frameNameDiamond,
          emoji: '💎',
          colorValue: 0xFF6EC6FF,
          unlockLabel: l10n.avatarUnlockReachDiamond,
        ),
        ProfileFrameInfo(
          id: 'master',
          name: l10n.frameNameMaster,
          emoji: '👑',
          colorValue: 0xFF9C27B0,
          unlockLabel: l10n.avatarUnlockReachMaster,
        ),
      ];

  List<ProfileFrameInfo> get leagueFrames => leagueFramesFor(_l10n);

  ProfileFrameInfo frameById(String? frameId) {
    if (frameId == null || frameId.trim().isEmpty) {
      return leagueFramesFor(_l10n).first;
    }

    return leagueFramesFor(_l10n).firstWhere(
      (frame) => frame.id == frameId,
      orElse: () => leagueFramesFor(_l10n).first,
    );
  }

  ProfileFrameInfo frameForLeague(String? leagueId) {
    return frameById(leagueId);
  }

  List<ProfileFrameInfo> unlockedLeagueFrames({
    required String bestLeagueId,
  }) {
    final frames = leagueFramesFor(_l10n);
    final order = frames.map((frame) => frame.id).toList();
    final bestIndex = order.indexOf(bestLeagueId);

    if (bestIndex < 0) {
      return [frames.first];
    }

    return frames.take(bestIndex + 1).toList();
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
