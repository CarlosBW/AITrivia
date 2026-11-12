import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/weekly_topic_service.dart';
import '../daily/daily_challenge_screen.dart';
import '../daily/daily_challenge_result_screen.dart';
import '../leagues/weekly_league_screen.dart';
import '../../services/daily_challenge_service.dart';
import '../../services/weekly_league_service.dart';
import '../../services/life_service.dart';
import '../../services/season_service.dart';
import '../../services/achievement_service.dart';
import '../../services/avatar_service.dart';
import '../../services/sfx_service.dart';
import '../ai_topics/ai_topics_screen.dart';
import '../shop/coin_shop_screen.dart';
import '../solo/level_play_screen.dart';
import '../../services/solo_progress_service.dart';
import '../../l10n/lives_format.dart';
import '../weekly/weekly_topic_screen.dart';
import '../../widgets/guarded_navigation.dart';
import '../../widgets/section_label.dart';
import '../../widgets/category_illustration.dart';
import '../../widgets/hero_card.dart';
import '../../widgets/save_progress_reminder.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  /// Switches the shell to the PvP tab, for the "find a rival" card.
  final VoidCallback? onFindRival;

  const HomeScreen({super.key, this.onFindRival});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // One stream per StreamBuilder, held for the life of the screen. Home
  // rebuilds constantly (life timer, streak/login/achievement popups), and
  // building these inside `build()` re-subscribed all four every time.
  // A Firestore stream feeds one listener, so the user doc has a single
  // StreamBuilder and everything that reads it sits under it.
  late final _userDocForStats = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots();

  /// The "keep going" card's category; replaced on refresh and after
  /// playing from it.
  late Future<RecentSoloCategory?> _recentCategory =
      SoloProgressService.instance.mostRecent();
  late final _achievements =
      AchievementService.instance.watchUserAchievements(uid: uid);

  Map<String, dynamic>? _lifeState;
  bool _loadingLives = true;
  Timer? _lifeTimer;

  /// The life fields of the last user-doc snapshot the card followed.
  String? _lifeDocSignature;

  bool _isNavigating = false;
  final bool _buyingLife = false;

  bool _hasPendingSeasonRewards = false;
  bool _checkingPendingSeasonRewards = false;

  int? _lastSeenStreak;
  bool _showStreakPopup = false;
  bool _streakGlow = false;

  bool _loginPopupHandled = false;
  bool _showLoginPopup = false;
  int _loginStreakForPopup = 0;
  int _loginCoinsForPopup = 0;

  Map<String, bool>? _lastSeenAchievementCompleted;
  bool _showAchievementPopup = false;
  String _achievementPopupIcon = '';
  String _achievementPopupTitle = '';
  int _achievementPopupCoins = 0;
  int _achievementPopupXp = 0;

  bool _livesFailed = false;

  DateTime? _lastSeenAvatarUnlockAt;
  bool _showAvatarUnlockPopup = false;
  String _avatarUnlockEmoji = '';
  String _avatarUnlockName = '';

  late final String uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _initLives();
    _checkPendingSeasonRewards();
    _startLifeTimer();
    SoloProgressService.instance.revision.addListener(_reloadRecentCategory);
  }

  void _reloadRecentCategory() {
    if (!mounted) return;
    setState(() => _recentCategory = SoloProgressService.instance.mostRecent());
  }

  Future<void> _initLives() async {
    if (mounted) {
      setState(() {
        _loadingLives = true;
        _livesFailed = false;
      });
    }

    try {
      final state = await LifeService.instance.refreshLives(uid);

      if (!mounted) return;

      setState(() {
        _lifeState = state;
        _loadingLives = false;
      });
    } catch (_) {
      if (!mounted) return;
      // `_lifeState` stays null here, and the lives card renders on
      // `_loadingLives || _lifeState == null` — so without this explicit
      // failure flag the card would spin forever instead of ever telling
      // the player something went wrong (which is exactly what happened
      // when `refreshUserLives` wasn't deployed).
      setState(() {
        _loadingLives = false;
        _livesFailed = true;
      });
    }
  }

  void _startLifeTimer() {
    _lifeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickLivesLocally();
    });
  }

  void _tickLivesLocally() {
    if (_lifeState == null || !mounted) return;

    setState(() {
      _lifeState = LifeService.instance.calculateLocalLifeState(_lifeState!);
      _loadingLives = false;
    });
  }

  /// Follows the lives the server writes to the user doc.
  ///
  /// The card was loaded once and then only ticked regeneration locally,
  /// which is fine for lives coming back and blind to lives being spent:
  /// Home stays mounted behind the other tabs, so a level played from Solo
  /// left it showing ten full hearts while the play screen said 5.5. The
  /// doc is already being listened to for coins and XP, so this costs no
  /// read — it only has to notice which snapshots moved the lives.
  void _handleLifeChange(Map<String, dynamic> data) {
    final signature = LifeService.lifeFieldsSignature(data);
    if (signature == _lifeDocSignature) return;
    _lifeDocSignature = signature;

    // A doc that carries no life fields yet says nothing about them, and
    // reading it would paint a full bar over whatever the server answered.
    if (data['lifeUnits'] == null) return;

    setState(() {
      _lifeState = LifeService.instance.calculateLocalLifeState(data);
      _loadingLives = false;
      _livesFailed = false;
    });
  }

  Future<void> _syncLivesFromFirestore() async {
    final state = await LifeService.instance.refreshLives(uid);

    if (!mounted) return;

    setState(() {
      _lifeState = state;
      _loadingLives = false;
    });
  }

  Future<void> _checkPendingSeasonRewards() async {
    if (_checkingPendingSeasonRewards) return;

    setState(() => _checkingPendingSeasonRewards = true);

    try {
      final seasonService = SeasonService.instance;

      final hasPending = await seasonService.hasPendingSeasonRewards(
        uid: uid,
      );

      if (hasPending) {
        await seasonService.ensureSeasonRewardNotification(
          uid: uid,
        );
      }

      if (!mounted) return;

      setState(() {
        _hasPendingSeasonRewards = hasPending;
      });
    } catch (_) {
      // No bloquear Home si falla la revisión.
    } finally {
      if (mounted) {
        setState(() => _checkingPendingSeasonRewards = false);
      }
    }
  }

  Future<void> _refreshHome() async {
    setState(() => _recentCategory = SoloProgressService.instance.mostRecent());
    await Future.wait([
      _recentCategory,
      _syncLivesFromFirestore(),
      _checkPendingSeasonRewards(),
    ]);
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;

    final timeoutMessage = AppLocalizations.of(context).homeActionTimeout;

    setState(() => _isNavigating = true);

    try {
      await runGuardedNavigation(
        context,
        action,
        timeoutMessage: timeoutMessage,
      );
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  void _handleStreakChange(int streak) {
    if (_lastSeenStreak == null) {
      _lastSeenStreak = streak;
      return;
    }

    if (streak > _lastSeenStreak!) {
      _lastSeenStreak = streak;

      HapticFeedback.mediumImpact();

      setState(() {
        _showStreakPopup = true;
        _streakGlow = true;
      });

      Future.delayed(const Duration(milliseconds: 1300), () {
        if (!mounted) return;

        setState(() {
          _showStreakPopup = false;
          _streakGlow = false;
        });
      });
    } else {
      _lastSeenStreak = streak;
    }
  }

  void _showLoginStreakCelebration(int streak, int coins) {
    if (_loginPopupHandled) return;
    _loginPopupHandled = true;

    HapticFeedback.mediumImpact();

    setState(() {
      _showLoginPopup = true;
      _loginStreakForPopup = streak;
      _loginCoinsForPopup = coins;
    });

    FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'loginStreakCelebrationPending': false},
      SetOptions(merge: true),
    );

    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;

      setState(() => _showLoginPopup = false);
    });
  }

  // Only the notification/user-doc fields report an achievement completing
  // — there's no client-side "moment" tied to it (it can complete as a side
  // effect of any server-side function), so this compares each snapshot's
  // completed flags against the previous one to catch the transition.
  void _handleAchievementsSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final current = <String, bool>{
      for (final doc in snap.docs) doc.id: doc.data()['completed'] == true,
    };

    final previous = _lastSeenAchievementCompleted;
    _lastSeenAchievementCompleted = current;

    if (previous == null) return;

    for (final entry in current.entries) {
      final wasCompleted = previous[entry.key] == true;
      if (entry.value && !wasCompleted) {
        _showAchievementCelebration(entry.key);
        return;
      }
    }
  }

  void _showAchievementCelebration(String achievementId) {
    final info = AchievementService.instance.getAchievementById(
      achievementId,
    );
    if (info == null) return;

    HapticFeedback.mediumImpact();
    SfxService.instance.playReward();

    setState(() {
      _showAchievementPopup = true;
      _achievementPopupIcon = info.icon;
      _achievementPopupTitle = info.title;
      _achievementPopupCoins = info.rewardCoins;
      _achievementPopupXp = info.rewardXp;
    });

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;

      setState(() => _showAchievementPopup = false);
    });
  }

  // Mirrors _handleAchievementsSnapshot's approach: lastUnlockedAvatarAt is
  // written server-side whenever a new avatar unlocks (see
  // user_bootstrap.dart's field comment), but nothing ever read it — this
  // just detects it moving forward to celebrate the unlock once.
  void _handleAvatarUnlockChange(Map<String, dynamic> data) {
    final rawAt = data['lastUnlockedAvatarAt'];
    final unlockedAt = rawAt is Timestamp ? rawAt.toDate() : null;
    if (unlockedAt == null) return;

    final previous = _lastSeenAvatarUnlockAt;
    _lastSeenAvatarUnlockAt = unlockedAt;

    if (previous == null) return;
    if (!unlockedAt.isAfter(previous)) return;

    final avatarId = data['lastUnlockedAvatarId']?.toString();
    if (avatarId == null || avatarId.isEmpty) return;

    final info = AvatarService.instance.avatarById(avatarId);

    HapticFeedback.mediumImpact();
    SfxService.instance.playReward();

    setState(() {
      _showAvatarUnlockPopup = true;
      _avatarUnlockEmoji = info.emoji;
      _avatarUnlockName = info.name;
    });

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;

      setState(() => _showAvatarUnlockPopup = false);
    });
  }

  @override
  void dispose() {
    _lifeTimer?.cancel();
    SoloProgressService.instance.revision
        .removeListener(_reloadRecentCategory);
    super.dispose();
  }

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildLivesChip(AppLocalizations l10n) {
    const heart = Color(0xFFFF4D5E);
    final state = _lifeState;

    if (_livesFailed) {
      return _ResourceChip(
        icon: Icons.favorite_rounded,
        color: heart,
        value: '–',
        label: l10n.commonRetry,
        onTap: _initLives,
      );
    }

    if (_loadingLives || state == null) {
      return _ResourceChip(
        icon: Icons.favorite_rounded,
        color: heart,
        value: '–',
        label: l10n.homeLivesLabel,
      );
    }

    final units = state['lifeUnits'] as int;
    final isFull = units >= (state['maxLifeUnits'] as int);

    return _ResourceChip(
      icon: Icons.favorite_rounded,
      color: heart,
      value: l10n.lives(units),
      label: isFull
          ? l10n.levelPlayLivesMax
          : _formatCountdown(state['secondsToNextHalfLife']),
    );
  }

  Future<void> _openDailyChallenge() async {
    final l10n = AppLocalizations.of(context);

    await _safeNavigate(() async {
      final alreadyPlayed =
          await DailyChallengeService.instance.hasPlayedToday(uid);

      if (!mounted) return;

      if (alreadyPlayed) {
        final todayResult =
            await DailyChallengeService.instance.getTodayResult(uid);

        if (!mounted) return;

        if (todayResult != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DailyChallengeResultScreen(result: todayResult),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.homeAlreadyPlayedDaily)),
          );
        }
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DailyChallengeScreen(uid: uid)),
      );

      if (!mounted) return;
      await _refreshHome();
    });
  }

  /// Opens the level the "keep going" card offers. The level screen runs
  /// its own lives check, so there's none here, and saving the level
  /// reloads the card through [SoloProgressService.revision].
  Future<void> _playRecent(RecentSoloCategory recent) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LevelPlayScreen(
          categoryId: recent.categoryId,
          categoryName: recent.name,
          levelNumber: recent.resume.level,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Text on the welcome-back and avatar-unlock popups, which sit on
    // primaryContainer: a pale wash in the light themes, where the white
    // these used was unreadable.
    final onPopup = Theme.of(context).colorScheme.onPrimaryContainer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TriviaIA'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refreshHome,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const SaveProgressReminder(),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _userDocForStats,
                  builder: (context, snap) {
                    final data = snap.data?.data() ?? {};
                    final loaded = snap.hasData;
                    final coins = data['coins'] ?? 0;
                    final passes = ((data['freeTopicPasses'] ?? 0) as num).toInt();
                    final xp = data['xp'] ?? 0;
                    final streak = ((data['dailyStreak'] ?? 0) as num).toInt();

                    final loginStreak =
                        ((data['loginStreak'] ?? 0) as num).toInt();
                    final loginCelebrationPending =
                        data['loginStreakCelebrationPending'] == true;
                    final loginCelebrationCoins =
                        ((data['loginStreakCelebrationCoins'] ?? 0) as num)
                            .toInt();

                    if (loaded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;

                        _handleStreakChange(streak);
                        _handleAvatarUnlockChange(data);
                        _handleLifeChange(data);

                        if (loginCelebrationPending) {
                          _showLoginStreakCelebration(
                            loginStreak,
                            loginCelebrationCoins,
                          );
                        }
                      });
                    }

                    final busy = _isNavigating || _buyingLife;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (snap.hasError)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              l10n.homeStatsErrorLoading(userFacingError(
                                AppLocalizations.of(context),
                                snap.error!,
                              )),
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: context.appColors.danger),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(child: _buildLivesChip(l10n)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ResourceChip(
                                icon: Icons.monetization_on_rounded,
                                color: context.appColors.reward,
                                value: loaded ? '$coins' : '–',
                                label: l10n.homeCoins,
                                onTap: busy
                                    ? null
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const CoinShopScreen(),
                                          ),
                                        ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ResourceChip(
                                icon: Icons.auto_awesome_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                value: loaded ? '$xp' : '–',
                                label: l10n.homeXp,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FutureBuilder<RecentSoloCategory?>(
                          future: _recentCategory,
                          builder: (context, recentSnap) {
                            final recent = recentSnap.data;
                            if (recent == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _ResumeCard(
                                recent: recent,
                                onPlay: busy
                                    ? null
                                    : () => _safeNavigate(
                                          () => _playRecent(recent),
                                        ),
                              ),
                            );
                          },
                        ),
                        AnimatedScale(
                          scale: _streakGlow ? 1.03 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: HeroCard(
                            // Darkened only as far as the white text needs:
                            // the dark themes lighten danger, and the card
                            // went pale.
                            gradientStart: readableInk(
                              Color.lerp(
                                context.appColors.reward,
                                context.appColors.danger,
                                0.45,
                              )!,
                              context.appColors.onAccent,
                              minContrast: 3,
                            ),
                            gradientEnd: readableInk(
                              context.appColors.danger,
                              context.appColors.onAccent,
                              minContrast: 3,
                            ),
                            illustration: 'assets/illustrations/daily.png',
                            badge: streak > 0
                                ? l10n.homeDailyChallengeStreak(streak)
                                : null,
                            title: l10n.homeDailyChallengeTitle,
                            subtitle: l10n.homeDailySubtitle,
                            actionLabel: l10n.homePlayAction,
                            onTap: busy ? null : _openDailyChallenge,
                          ),
                        ),
                        const SizedBox(height: 14),
                        HeroCard(
                          gradientStart: context.appColors.brandGradientStart,
                          gradientEnd: context.appColors.brandGradientEnd,
                          illustration: 'assets/illustrations/pvp.png',
                          title: l10n.homeFindRivalTitle,
                          subtitle: l10n.homeFindRivalSubtitle,
                          actionLabel: l10n.homePlayAction,
                          onTap: busy ? null : widget.onFindRival,
                        ),
                        const SizedBox(height: 14),
                        HeroCard(
                          gradientStart: context.appColors.heroGradientStart,
                          gradientEnd: context.appColors.heroGradientEnd,
                          illustration: 'assets/illustrations/ai_topic.png',
                          badge: passes > 0
                              ? l10n.homeFreeTopicPasses(passes)
                              : null,
                          title: l10n.homeAiTopicTitle,
                          subtitle: l10n.homeAiTopicSubtitle,
                          onTap: busy
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const AiTopicsScreen(),
                                    ),
                                  );
                                },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                SectionLabel(l10n.homeMoreWaysToPlay),
                const SizedBox(height: 10),
                _WeeklyTopicCard(
                  isBusy: _isNavigating || _buyingLife,
                  onOpen: (topicData) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WeeklyTopicScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isNavigating || _buyingLife
                        ? null
                        : () {
                            _safeNavigate(() async {
                              if (!context.mounted) return;

                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const WeeklyLeagueScreen(),
                                ),
                              );

                              if (!mounted) return;
                              await _checkPendingSeasonRewards();
                            });
                          },
                    icon: _WeeklyButtonIcon(
                      hasPendingRewards: _hasPendingSeasonRewards,
                      checking: _checkingPendingSeasonRewards,
                    ),
                    label: Text(
                      _hasPendingSeasonRewards
                          ? l10n.homeWeeklyChallengeReward
                          : l10n.homeWeeklyChallenge,
                    ),
                  ),
                ),
                if (!_hasPendingSeasonRewards) ...[
                  const SizedBox(height: 6),
                  const _WeeklyCountdownLabel(),
                ],
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(context.radii.md),
                    boxShadow: context.surfaces.shadowsOr(null),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    l10n.homeTabsHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (_isNavigating || _buyingLife)
            Container(
              color: Theme.of(context)
                  .colorScheme
                  .scrim
                  .withValues(alpha: 0.4),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      l10n.commonLoading,
                      style: TextStyle(color: context.appColors.onScrim),
                    ),
                  ],
                ),
              ),
            ),
          if (_showStreakPopup)
            Center(
              child: AnimatedScale(
                scale: _showStreakPopup ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.danger,
                    borderRadius: BorderRadius.circular(context.radii.lg),
                    border: context.surfaces.borderOr(null),
                    boxShadow: context.surfaces.shadowsOr([
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeStreakUpTitle,
                        style: context.heading(26, color: context.appColors.onAccent),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeStreakUpSubtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: context.appColors.onAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showLoginPopup)
            Center(
              child: AnimatedScale(
                scale: _showLoginPopup ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(context.radii.lg),
                    border: context.surfaces.borderOr(null),
                    boxShadow: context.surfaces.shadowsOr([
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeWelcomeBackTitle,
                        style: context.heading(26, color: onPopup),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeLoginStreakLabel(_loginStreakForPopup),
                        style: TextStyle(
                          fontSize: 14,
                          color: onPopup,
                        ),
                      ),
                      if (_loginCoinsForPopup > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.homeLoginStreakCoins(_loginCoinsForPopup),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: readableInk(
                              context.appColors.reward,
                              Theme.of(context).colorScheme.primaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _achievements,
            builder: (context, snap) {
              final data = snap.data;
              if (data != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _handleAchievementsSnapshot(data);
                });
              }
              return const SizedBox.shrink();
            },
          ),
          if (_showAchievementPopup)
            Center(
              child: AnimatedScale(
                scale: _showAchievementPopup ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.reward,
                    borderRadius: BorderRadius.circular(context.radii.lg),
                    border: context.surfaces.borderOr(null),
                    boxShadow: context.surfaces.shadowsOr([
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeAchievementUnlockedTitle,
                        style: context.heading(24, color: Color(0xFF412402)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeAchievementUnlockedSubtitle(
                          _achievementPopupIcon,
                          _achievementPopupTitle,
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF412402),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.homeAchievementUnlockedRewards(
                          _achievementPopupCoins,
                          _achievementPopupXp,
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF412402),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showAvatarUnlockPopup)
            Center(
              child: AnimatedScale(
                scale: _showAvatarUnlockPopup ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(context.radii.lg),
                    border: context.surfaces.borderOr(null),
                    boxShadow: context.surfaces.shadowsOr([
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeAvatarUnlockedTitle,
                        style: context.heading(24, color: onPopup),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeAvatarUnlockedSubtitle(
                          _avatarUnlockEmoji,
                          _avatarUnlockName,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: onPopup,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Gives the weekly reset a visible anticipation cue on Home itself instead
// of only inside weekly_league_screen.dart — previously a player only saw
// anything about the weekly reset after it already happened (the pending-
// reward dot), with no "come back before the timer runs out" pull while a
// week is still active.
class _WeeklyCountdownLabel extends StatefulWidget {
  const _WeeklyCountdownLabel();

  @override
  State<_WeeklyCountdownLabel> createState() => _WeeklyCountdownLabelState();
}

class _WeeklyCountdownLabelState extends State<_WeeklyCountdownLabel> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _timeLeft = WeeklyLeagueService.instance.timeUntilReset();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      setState(() {
        _timeLeft = WeeklyLeagueService.instance.timeUntilReset();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    return '${days}d ${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Text(
        l10n.homeWeeklyResetsIn(_formatDuration(_timeLeft)),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// The AI-topic flow is the game's differentiator and the main sink for
// coins earned elsewhere, so this CTA gets its own glowing pulse to draw
// the eye — the only element on Home that animates on a loop.
class _WeeklyTopicCard extends StatefulWidget {
  final bool isBusy;
  final void Function(Map<String, dynamic> topicData) onOpen;

  const _WeeklyTopicCard({
    required this.isBusy,
    required this.onOpen,
  });

  @override
  State<_WeeklyTopicCard> createState() => _WeeklyTopicCardState();
}

// Stateful only to keep its topic stream across Home's rebuilds.
class _WeeklyTopicCardState extends State<_WeeklyTopicCard> {
  late final _weeklyTopic = WeeklyTopicService.instance.watchCurrentTopic();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _weeklyTopic,
      builder: (context, snap) {
        if (snap.hasError) {
          return _WeeklyTopicUnavailableCard(
            message: l10n.homeWeeklyTopicUnavailable,
            detail: userFacingError(AppLocalizations.of(context), snap.error!),
          );
        }

        if (!snap.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appColors.rewardBg,
              borderRadius: BorderRadius.circular(context.radii.sm),
              border: context.surfaces.borderOr(null),
              boxShadow: context.surfaces.shadowsOr(null),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.homeWeeklyTopicLoading,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        }

        final data = snap.data!.data();

        if (data == null || data['active'] != true) {
          return _WeeklyTopicUnavailableCard(
            message: l10n.homeWeeklyTopicNoneAvailable,
            detail: l10n.homeWeeklyTopicCheckBack,
          );
        }

        // `description` and `title` (no language suffix) are the legacy
        // single-language fields older weekly-topic docs were seeded with —
        // kept as a fallback so those don't regress to the generic text.
        final languageCode = Localizations.localeOf(context).languageCode;
        final title = (data['title_$languageCode'] ??
                data['title'] ??
                l10n.weeklyTopicScreenTitle)
            .toString();
        final description = (data['description_$languageCode'] ??
                data['description'] ??
                l10n.homeWeeklyTopicDefaultDescription)
            .toString();
        final rewardCoins = ((data['rewardCoins'] ?? 0) as num).toInt();
        // White text on the light end of the gradient was barely legible;
        // darkened until it reads against the lightest color.
        final ink = readableInk(
          context.appColors.onAccent,
          const Color(0xFFFFC94D),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFC94D), Color(0xFFF2994A)],
            ),
            borderRadius: BorderRadius.circular(context.radii.md),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr(null),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: context.appColors.onAccent.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star_rounded,
                      color: ink,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: context.heading(16, color: ink),
                    ),
                  ),
                  if (rewardCoins > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.onAccent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(context.radii.pill),
                      ),
                      child: Text(
                        l10n.homeWeeklyTopicRewardCoins(rewardCoins),
                        style: TextStyle(
                          color: ink,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.appColors.onAccent,
                    foregroundColor: const Color(0xFFB35C1E),
                  ),
                  onPressed:
                      widget.isBusy ? null : () => widget.onOpen(data),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(l10n.homeOpenWeeklyTopic),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeeklyTopicUnavailableCard extends StatelessWidget {
  final String message;
  final String detail;

  const _WeeklyTopicUnavailableCard({
    required this.message,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_busy_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyButtonIcon extends StatelessWidget {
  final bool hasPendingRewards;
  final bool checking;

  const _WeeklyButtonIcon({
    required this.hasPendingRewards,
    required this.checking,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.workspace_premium_outlined),
        if (checking)
          const Positioned(
            right: -5,
            top: -5,
            child: SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          )
        else if (hasPendingRewards)
          Positioned(
            right: -5,
            top: -5,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: context.appColors.danger,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

// Daily Challenge + streak used to be two separate cards, but the streak
// only exists because of the Daily Challenge, so the count now lives
// inline in this card's subtitle instead of its own block below it.
/// One of the three counters at the top of Home: lives, coins, XP.
class _ResourceChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _ResourceChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(context.radii.md);

    // The shadow on a box around the Material, as in BuyCoinsButton.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: context.surfaces.borderOr(null),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: context.heading(17)),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks up the fixed category played last: the level just failed, or the
/// next one to play.
class _ResumeCard extends StatelessWidget {
  final RecentSoloCategory recent;
  final VoidCallback? onPlay;

  const _ResumeCard({required this.recent, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final retry = recent.resume.retry;
    final level = recent.resume.level;
    // The button writes onAccent on this, so it's darkened until that
    // reads; the dark themes' danger is too pale for white text.
    final accent = readableInk(
      retry ? context.appColors.danger : colorScheme.primary,
      context.appColors.onAccent,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: context.surfaces.borderOr(
          Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
        ),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Row(
        children: [
          CategoryIllustration(
            categoryId: recent.categoryId,
            name: recent.name,
            size: 72,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  retry
                      ? l10n.homeRetryTitle
                      : l10n.homeResumeTitle(recent.name),
                  style: context.heading(17),
                ),
                const SizedBox(height: 2),
                Text(
                  retry
                      ? l10n.homeRetrySubtitle(
                          recent.name,
                          level,
                          recent.progress.lastCorrect,
                          recent.progress.lastTotal,
                        )
                      : l10n.homeResumeSubtitle(level),
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: context.appColors.onAccent,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onPlay,
                  icon: Icon(retry ? Icons.replay : Icons.play_arrow),
                  label: Text(
                    retry ? l10n.commonRetry : l10n.homeResumeAction(level),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
