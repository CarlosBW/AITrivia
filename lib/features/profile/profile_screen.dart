import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app.dart';

import '../../services/daily_challenge_service.dart';
import '../../services/player_level_service.dart';
import '../../services/league_service.dart';
import '../../services/weekly_league_service.dart';
import '../../services/pvp_league_service.dart';
import '../../services/frame_service.dart';
import '../../services/avatar_service.dart';
import '../achievements/achievements_screen.dart';
import '../../widgets/buy_coins_button.dart';
import '../../widgets/stat_chip.dart';
import '../../widgets/spotlight_hint.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

const _kPrivacyPolicyUrl = 'https://trivia-ia-app.web.app/privacy.html';
const _kTermsOfServiceUrl = 'https://trivia-ia-app.web.app/terms.html';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  late final String uid;
  late final DocumentReference<Map<String, dynamic>> userRef;

  Map<String, dynamic>? _userData;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    uid = FirebaseAuth.instance.currentUser!.uid;
    userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfile(showLoading: false);
    }
  }

  Future<void> _loadProfile({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final snap = await userRef.get();
      if (!mounted) return;

      setState(() {
        _userData = snap.data() ?? {};
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).profileLinkOpenFailed)),
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.profileDeleteAccountConfirmTitle),
        content: Text(l10n.profileDeleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.profileDeleteAccountConfirmAction,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);

    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'deleteMyAccount',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Full app restart: AuthGate signs back in anonymously as a brand
      // new account, matching what a fresh install would see.
      runApp(const TriviaIAApp());
    } catch (e) {
      if (!mounted) return;

      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _syncTodayLeaderboardProfile({
    required String uid,
    String? username,
    String? avatarId,
    String? equippedFrame,
  }) async {
    final dateId = DailyChallengeService.instance.todayDateId();

    final leaderboardRef = FirebaseFirestore.instance
        .collection('daily_leaderboards')
        .doc(dateId)
        .collection('players')
        .doc(uid);

    final leaderboardSnap = await leaderboardRef.get();
    if (!leaderboardSnap.exists) return;

    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (username != null) {
      update['username'] = username;
      update['displayName'] = username;
    }

    if (avatarId != null) {
      update['avatarId'] = avatarId;
    }

    if (equippedFrame != null) {
      update['equippedFrame'] = equippedFrame;
    }

    await leaderboardRef.set(update, SetOptions(merge: true));
  }

  Future<void> _syncCurrentWeeklyLeaderboardProfile({
    required String uid,
    required Map<String, dynamic> latestUserData,
    String? username,
    String? avatarId,
    String? equippedFrame,
  }) async {
    final leagueScore = ((latestUserData['leagueScore'] ?? 0) as num).toInt();
    final league = LeagueService.instance.getLeagueFromScore(leagueScore);
    final weekId = WeeklyLeagueService.instance.currentWeekId();

    final weeklyRef = WeeklyLeagueService.instance.weeklyPlayerRef(
      uid: uid,
      weekId: weekId,
      leagueId: league.id,
    );

    final weeklySnap = await weeklyRef.get();
    if (!weeklySnap.exists) return;

    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (username != null) {
      update['username'] = username;
      update['displayName'] = username;
    }

    if (avatarId != null) {
      update['avatarId'] = avatarId;
    }

    if (equippedFrame != null) {
      update['equippedFrame'] = equippedFrame;
    }

    await weeklyRef.set(update, SetOptions(merge: true));
  }

  Future<void> _syncLeaderboardProfiles({
    String? username,
    String? avatarId,
    String? equippedFrame,
  }) async {
    final latestUserSnap = await userRef.get();
    final latestUserData = latestUserSnap.data() ?? {};

    await Future.wait([
      _syncTodayLeaderboardProfile(
        uid: uid,
        username: username,
        avatarId: avatarId,
        equippedFrame: equippedFrame,
      ),
      _syncCurrentWeeklyLeaderboardProfile(
        uid: uid,
        latestUserData: latestUserData,
        username: username,
        avatarId: avatarId,
        equippedFrame: equippedFrame,
      ),
    ]);
  }

  Future<void> _chooseAvatar({
    required BuildContext context,
    required String currentAvatarId,
    required String bestLeagueId,
    required List<dynamic>? storedUnlockedAvatars,
  }) async {
    if (_saving) return;

    final l10n = AppLocalizations.of(context);

    final unlockedIds = AvatarService.instance.unlockedAvatarIdsForBestLeague(
      bestLeagueId: bestLeagueId,
      storedUnlockedAvatars: storedUnlockedAvatars,
    );

    final avatars = AvatarService.instance.allAvatarsFor(l10n);
    final currentAvatar = AvatarService.instance.avatarById(currentAvatarId);
    final unlockedCount =
        avatars.where((avatar) => unlockedIds.contains(avatar.id)).length;

    final selectedAvatarId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text(
                  l10n.profileAvatarCollection,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.profileUnlockedCount(unlockedCount, avatars.length),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Text(
                          currentAvatar.emoji,
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.profileCurrentlyEquipped,
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentAvatar.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _AvatarCategoryBadge(
                              category: currentAvatar.category,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: avatars.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final avatar = avatars[index];
                    final isSelected = avatar.id == currentAvatarId;
                    final isUnlocked = unlockedIds.contains(avatar.id);

                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        if (!isUnlocked) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(avatar.unlockLabel),
                            ),
                          );
                          return;
                        }

                        Navigator.pop(sheetContext, avatar.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                              : isUnlocked
                                  ? Theme.of(context).colorScheme.surface
                                  : Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Opacity(
                                  opacity: isUnlocked ? 1.0 : 0.35,
                                  child: Text(
                                    avatar.emoji,
                                    style: const TextStyle(fontSize: 34),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  avatar.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isUnlocked
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (isUnlocked)
                                  _AvatarCategoryBadge(
                                    category: avatar.category,
                                  )
                                else
                                  Text(
                                    avatar.unlockLabel,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            if (!isUnlocked)
                              Positioned(
                                right: 2,
                                top: 2,
                                child: Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (isSelected)
                              Positioned(
                                right: 2,
                                top: 2,
                                child: Icon(
                                  Icons.check_circle,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedAvatarId == null || selectedAvatarId == currentAvatarId) return;

    setState(() => _saving = true);

    try {
      await userRef.set({
        'avatarId': selectedAvatarId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _syncLeaderboardProfiles(avatarId: selectedAvatarId);
      await _loadProfile(showLoading: false);

      if (!context.mounted) return;
      final selectedAvatar =
          AvatarService.instance.avatarById(selectedAvatarId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.profileEquippedNotice(
              selectedAvatar.emoji,
              selectedAvatar.name,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileAvatarUpdateError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseFrame({
    required BuildContext context,
    required String equippedFrame,
    required String bestLeagueId,
  }) async {
    if (_saving) return;

    final l10n = AppLocalizations.of(context);

    final unlockedFrames = FrameService.instance.unlockedLeagueFrames(
      bestLeagueId: bestLeagueId,
    );

    final selectedFrameId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l10n.profileChooseFrame,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            ...unlockedFrames.map(
              (frame) => ListTile(
                leading: Text(
                  frame.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(frame.name),
                subtitle: Text(frame.unlockLabel),
                trailing: frame.id == equippedFrame
                    ? const Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(
                    sheetContext,
                    frame.id,
                  );
                },
              ),
            ),
          ],
        );
      },
    );

    if (selectedFrameId == null || selectedFrameId == equippedFrame) {
      return;
    }

    setState(() => _saving = true);

    try {
      await userRef.set(
        {
          'equippedFrame': selectedFrameId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await _syncLeaderboardProfiles(equippedFrame: selectedFrameId);
      await _loadProfile(showLoading: false);

      if (!context.mounted) return;

      final frame = FrameService.instance.frameById(
        selectedFrameId,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.profileEquippedNotice(frame.emoji, frame.name),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return const Scaffold(
        appBar: _ProfileAppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: const _ProfileAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                Text(
                  l10n.profileErrorLoading(_error!),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _loadProfile(),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _userData ?? {};

    final username = (data['username'] ??
            data['displayName'] ??
            'Player${uid.substring(0, 4)}')
        .toString();

    final xp = ((data['xp'] ?? 0) as num).toInt();
    final coins = ((data['coins'] ?? 0) as num).toInt();
    final freeTopicPasses = ((data['freeTopicPasses'] ?? 0) as num).toInt();

    final gamesPlayed = ((data['gamesPlayed'] ?? 0) as num).toInt();
    final correctAnswers = ((data['correctAnswers'] ?? 0) as num).toInt();
    final wrongAnswers = ((data['wrongAnswers'] ?? 0) as num).toInt();

    final totalAnswers = correctAnswers + wrongAnswers;
    final accuracy =
        totalAnswers == 0 ? 0 : ((correctAnswers / totalAnswers) * 100).round();

    final dailyStreak = ((data['dailyStreak'] ?? 0) as num).toInt();
    final maxDailyStreak =
        ((data['maxDailyStreak'] ?? dailyStreak) as num).toInt();
    final bestDailyScore = ((data['bestDailyScore'] ?? 0) as num).toInt();
    final pvpRating = ((data['pvpRating'] ?? 1000) as num).toInt();
    final pvpRatingDelta = ((data['pvpRatingDelta'] ?? 0) as num).toInt();
    final pvpLeague = PvpLeagueService.instance.leagueForRating(pvpRating);
    final pvpLeagueProgress = pvpLeague.progressFor(pvpRating);

    final bestLeagueId = (data['bestLeagueId'] ?? pvpLeague.id).toString();

    final equippedFrame = (data['equippedFrame'] ?? bestLeagueId).toString();

    final frame = FrameService.instance.frameById(
      FrameService.instance.safestEquippedFrame(
        equippedFrame: equippedFrame,
        bestLeagueId: bestLeagueId,
      ),
    );

    final storedUnlockedAvatars = data['unlockedAvatars'] as List<dynamic>?;

    final safeAvatarId = AvatarService.instance.safestEquippedAvatar(
      avatarId: (data['avatarId'] ?? 'avatar_1').toString(),
      bestLeagueId: bestLeagueId,
      storedUnlockedAvatars: storedUnlockedAvatars,
    );

    final avatarInfo = AvatarService.instance.avatarById(safeAvatarId);
    final avatar = avatarInfo.emoji;

    final wins1v1 = ((data['wins1v1'] ?? 0) as num).toInt();
    final losses1v1 = ((data['losses1v1'] ?? 0) as num).toInt();
    final draws1v1 = ((data['draws1v1'] ?? 0) as num).toInt();
    final matches1v1 = ((data['matches1v1'] ?? 0) as num).toInt();

    final currentWinStreak1v1 =
        ((data['currentWinStreak1v1'] ?? 0) as num).toInt();

    final bestWinStreak1v1 = ((data['bestWinStreak1v1'] ?? 0) as num).toInt();

    final winrate1v1 =
        matches1v1 == 0 ? 0 : ((wins1v1 / matches1v1) * 100).round();

    final levelInfo = PlayerLevelService.instance.getLevelInfo(xp);
    final level = levelInfo.level;
    final leagueScore = ((data['leagueScore'] ?? 0) as num).toInt();

    final levelXp = levelInfo.currentLevelXp;
    final xpRequired = levelInfo.xpRequired;
    final progress = levelInfo.progress;

    return Scaffold(
      appBar: const _ProfileAppBar(),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _saving
                          ? null
                          : () => _chooseAvatar(
                                context: context,
                                currentAvatarId: safeAvatarId,
                                bestLeagueId: bestLeagueId,
                                storedUnlockedAvatars: storedUnlockedAvatars,
                              ),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(frame.colorValue),
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(frame.colorValue).withValues(alpha: 0.30),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Text(
                            avatar,
                            style: const TextStyle(fontSize: 44),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.profileLevel(level),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SpotlightHint(
                      id: 'profile_frame_chip',
                      title: l10n.spotlightFramesTitle,
                      description: l10n.spotlightFramesBody,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _saving
                            ? null
                            : () => _chooseFrame(
                                  context: context,
                                  equippedFrame: equippedFrame,
                                  bestLeagueId: bestLeagueId,
                                ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                Color(frame.colorValue).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Color(frame.colorValue)
                                  .withValues(alpha: 0.40),
                            ),
                          ),
                          child: Text(
                            '${frame.emoji} ${frame.name}',
                            style: TextStyle(
                              color: Color(frame.colorValue),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.profileWeeklyScore(leagueScore),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(l10n.profileXpToNextLevel(levelXp, xpRequired)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AchievementsScreen(),
                      ),
                    );
                  },
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFC94D), Color(0xFFF2994A)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.emoji_events,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.profileAchievements,
                                style: GoogleFonts.baloo2(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.profileAchievementsSubtitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: StatChip(
                      icon: Icons.monetization_on_outlined,
                      label: l10n.profileCoins,
                      accent: AppColors.reward,
                      background: AppColors.rewardBg,
                      value: '$coins',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatChip(
                      icon: Icons.style_outlined,
                      label: l10n.profileFreeTopics,
                      accent: Theme.of(context).colorScheme.primary,
                      background: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      value: '$freeTopicPasses',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const BuyCoinsButton(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatChip(
                      icon: Icons.local_fire_department_outlined,
                      label: l10n.profileStreak,
                      accent: const Color(0xFFFF6B5B),
                      background: AppColors.dangerBg,
                      value: '$dailyStreak',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatChip(
                      icon: Icons.whatshot_outlined,
                      label: l10n.profileBestStreak,
                      accent: AppColors.reward,
                      background: AppColors.rewardBg,
                      value: '$maxDailyStreak',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                l10n.profileStats,
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _WideStatTile(
                icon: Icons.sports_esports_outlined,
                label: l10n.profileGamesPlayed,
                value: '$gamesPlayed',
              ),
              _WideStatTile(
                icon: Icons.check_circle_outline,
                label: l10n.profileCorrectAnswers,
                value: '$correctAnswers',
              ),
              _WideStatTile(
                icon: Icons.cancel_outlined,
                label: l10n.profileWrongAnswers,
                value: '$wrongAnswers',
              ),
              _WideStatTile(
                icon: Icons.percent,
                label: l10n.profileAccuracy,
                value: '$accuracy%',
              ),
              _WideStatTile(
                icon: Icons.emoji_events_outlined,
                label: l10n.profileBestDailyScore,
                value: '$bestDailyScore',
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(pvpLeague.colorValue).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Color(pvpLeague.colorValue).withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pvpLeague.emoji,
                          style: const TextStyle(fontSize: 30),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.profilePvpLeague(pvpLeague.name),
                                style: TextStyle(
                                  color: Color(pvpLeague.colorValue),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                pvpRatingDelta == 0
                                    ? '$pvpRating MMR'
                                    : '$pvpRating MMR (${pvpRatingDelta > 0 ? '+' : ''}$pvpRatingDelta)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: pvpLeagueProgress,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.profileRankedHint,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.profile1v1Stats,
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _WideStatTile(
                icon: Icons.leaderboard_outlined,
                label: l10n.profileRankedMmr,
                value: pvpRatingDelta == 0
                    ? '$pvpRating'
                    : '$pvpRating (${pvpRatingDelta > 0 ? '+' : ''}$pvpRatingDelta)',
              ),
              _WideStatTile(
                icon: Icons.emoji_events_outlined,
                label: l10n.profileVictories,
                value: '$wins1v1',
              ),
              _WideStatTile(
                icon: Icons.close,
                label: l10n.profileDefeats,
                value: '$losses1v1',
              ),
              _WideStatTile(
                icon: Icons.handshake,
                label: l10n.profileDraws,
                value: '$draws1v1',
              ),
              _WideStatTile(
                icon: Icons.sports_martial_arts,
                label: l10n.profileMatchesPlayed,
                value: '$matches1v1',
              ),
              _WideStatTile(
                icon: Icons.percent,
                label: l10n.profileWinrate,
                value: '$winrate1v1%',
              ),
              _WideStatTile(
                icon: Icons.local_fire_department_outlined,
                label: l10n.profileCurrentStreak,
                value: '$currentWinStreak1v1',
              ),
              _WideStatTile(
                icon: Icons.whatshot_outlined,
                label: l10n.profileBestStreak,
                value: '$bestWinStreak1v1',
              ),
              const SizedBox(height: 20),
              Text(
                l10n.profileRecentMatches,
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _RecentMatchHistory(uid: uid),
              const SizedBox(height: 24),
              Text(
                l10n.profileLegalSectionTitle,
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _LegalLinkTile(
                icon: Icons.privacy_tip_outlined,
                label: l10n.profilePrivacyPolicy,
                onTap: () => _openLegalUrl(_kPrivacyPolicyUrl),
              ),
              _LegalLinkTile(
                icon: Icons.description_outlined,
                label: l10n.profileTermsOfService,
                onTap: () => _openLegalUrl(_kTermsOfServiceUrl),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.profileDangerZoneTitle,
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 10),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Colors.red),
                ),
                child: ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(
                    l10n.profileDeleteAccount,
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: _saving ? null : _confirmDeleteAccount,
                ),
              ),
            ],
          ),
          if (_saving)
            Container(
              color: Colors.black.withValues(alpha: 0.35),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      l10n.commonSaving,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarCategoryBadge extends StatelessWidget {
  final String category;

  const _AvatarCategoryBadge({required this.category});

  String _label(AppLocalizations l10n) {
    switch (category) {
      case 'base':
        return l10n.avatarCategoryBase;
      case 'pvp':
        return l10n.avatarCategoryPvp;
      case 'weekly':
        return l10n.avatarCategoryWeekly;
      case 'achievement':
        return l10n.avatarCategoryAchievement;
      case 'ai':
        return l10n.avatarCategoryAi;
      case 'ai_dynamic':
        return l10n.avatarCategoryAiUnique;
      default:
        return category.toUpperCase();
    }
  }

  Color _color(BuildContext context) {
    switch (category) {
      case 'base':
        return Colors.blueGrey;
      case 'pvp':
        return Colors.deepPurple;
      case 'weekly':
        return Colors.amber.shade800;
      case 'achievement':
        return Colors.green;
      case 'ai':
      case 'ai_dynamic':
        return Colors.pinkAccent;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        _label(AppLocalizations.of(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _RecentMatchHistory extends StatelessWidget {
  final String uid;

  const _RecentMatchHistory({required this.uid});

  String _resultText(AppLocalizations l10n, String result) {
    switch (result) {
      case 'victory':
        return l10n.matchResultVictory;
      case 'defeat':
        return l10n.matchResultDefeat;
      case 'draw':
        return l10n.matchResultDraw;
      default:
        return l10n.matchResultMatch;
    }
  }

  IconData _resultIcon(String result) {
    switch (result) {
      case 'victory':
        return Icons.emoji_events;
      case 'defeat':
        return Icons.close;
      case 'draw':
        return Icons.handshake;
      default:
        return Icons.sports_esports;
    }
  }

  Color _resultColor(BuildContext context, String result) {
    switch (result) {
      case 'victory':
        return AppColors.success;
      case 'defeat':
        return AppColors.danger;
      case 'draw':
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _deltaText(dynamic value) {
    final delta =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    if (delta == null) return '';
    if (delta > 0) return '+$delta MMR';
    return '$delta MMR';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('match_history')
        .orderBy('createdAt', descending: true)
        .limit(10);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            l10n.profileErrorLoadingMatchHistory(snap.error.toString()),
            textAlign: TextAlign.center,
          );
        }

        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              l10n.profileNoMatches,
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            final result = (data['result'] ?? 'match').toString();
            final opponent = (data['opponentName'] ?? 'Rival').toString();
            final myScore = ((data['myScore'] ?? 0) as num).toInt();
            final opponentScore = ((data['opponentScore'] ?? 0) as num).toInt();
            final ranked = data['ranked'] == true;
            final deltaText = ranked ? _deltaText(data['ratingDelta']) : '';
            final color = _resultColor(context, result);
            final resultLabel = _resultText(l10n, result);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _resultIcon(result),
                        color: color,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          resultLabel.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (deltaText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            deltaText,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.profileVsOpponent(opponent),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Text(
                                l10n.profileScore,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$myScore - $opponentScore',
                                style: GoogleFonts.baloo2(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          ranked ? l10n.profileRanked : l10n.profileCasual,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ProfileAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(AppLocalizations.of(context).profileTitle),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _LegalLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LegalLinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _WideStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WideStatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
