import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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
import '../weekly/weekly_topic_screen.dart';
import '../../widgets/stat_chip.dart';
import '../../widgets/section_label.dart';
import '../../widgets/buy_coins_button.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _lifeState;
  bool _loadingLives = true;
  Timer? _lifeTimer;

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
  }

  Future<void> _initLives() async {
    try {
      await LifeService.instance.ensureUserLifeDoc(uid);
      final state = await LifeService.instance.refreshLives(uid);

      if (!mounted) return;

      setState(() {
        _lifeState = state;
        _loadingLives = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLives = false);
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
    await Future.wait([
      _syncLivesFromFirestore(),
      _checkPendingSeasonRewards(),
    ]);
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;

    final timeoutMessage = AppLocalizations.of(context).homeActionTimeout;

    setState(() => _isNavigating = true);

    try {
      await action().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw TimeoutException(timeoutMessage);
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
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
    super.dispose();
  }

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final l10n = AppLocalizations.of(context);

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
                _AiTopicCta(
                  onTap: _isNavigating || _buyingLife
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
                const SizedBox(height: 18),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userRef.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const LinearProgressIndicator();
                    }

                    final data = snap.data!.data() ?? {};
                    final coins = data['coins'] ?? 0;
                    final passes = data['freeTopicPasses'] ?? 0;
                    final xp = data['xp'] ?? 0;
                    final streak = ((data['dailyStreak'] ?? 0) as num).toInt();

                    final loginStreak =
                        ((data['loginStreak'] ?? 0) as num).toInt();
                    final loginCelebrationPending =
                        data['loginStreakCelebrationPending'] == true;
                    final loginCelebrationCoins =
                        ((data['loginStreakCelebrationCoins'] ?? 0) as num)
                            .toInt();

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;

                      _handleStreakChange(streak);
                      _handleAvatarUnlockChange(data);

                      if (loginCelebrationPending) {
                        _showLoginStreakCelebration(
                          loginStreak,
                          loginCelebrationCoins,
                        );
                      }
                    });

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        children: [
                          _loadingLives || _lifeState == null
                              ? const LinearProgressIndicator()
                              : Column(
                                  children: [
                                    _LivesCard(
                                      livesText:
                                          '${LifeService.instance.formatLives(_lifeState!['lifeUnits'])}/${LifeService.instance.formatLives(_lifeState!['maxLifeUnits'])}',
                                      isFull: _lifeState!['lifeUnits'] >=
                                          _lifeState!['maxLifeUnits'],
                                      countdownText: _formatCountdown(
                                        _lifeState!['secondsToNextHalfLife'],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                          Row(
                            children: [
                              Expanded(
                                child: StatChip(
                                  icon: Icons.monetization_on_outlined,
                                  label: l10n.homeCoins,
                                  accent: AppColors.reward,
                                  background: AppColors.rewardBg,
                                  value: '$coins',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatChip(
                                  icon: Icons.auto_awesome_outlined,
                                  label: l10n.homeXp,
                                  accent: Theme.of(context).colorScheme.primary,
                                  background: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  value: '$xp',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          StatChip(
                            icon: Icons.style_outlined,
                            label: l10n.homeFreeTopic,
                            accent: Theme.of(context).colorScheme.primary,
                            background: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            value: '$passes',
                            fullWidth: true,
                          ),
                          const SizedBox(height: 14),
                          const BuyCoinsButton(),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userRef.snapshots(),
                  builder: (context, snap) {
                    final streak = ((snap.data?.data()?['dailyStreak'] ?? 0)
                            as num)
                        .toInt();

                    return _DailyChallengeCard(
                      streak: streak,
                      glow: _streakGlow,
                      onTap: _isNavigating || _buyingLife
                          ? null
                          : () {
                              _safeNavigate(() async {
                                final alreadyPlayed =
                                    await DailyChallengeService.instance
                                        .hasPlayedToday(uid);

                                if (!context.mounted) return;

                                if (alreadyPlayed) {
                                  final todayResult =
                                      await DailyChallengeService.instance
                                          .getTodayResult(uid);

                                  if (!context.mounted) return;

                                  if (todayResult != null) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            DailyChallengeResultScreen(
                                          result: todayResult,
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          l10n.homeAlreadyPlayedDaily,
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }

                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DailyChallengeScreen(uid: uid),
                                  ),
                                );

                                if (!mounted) return;
                                await _refreshHome();
                              });
                            },
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
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
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
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      l10n.commonLoading,
                      style: const TextStyle(color: Colors.white),
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
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeStreakUpTitle,
                        style: GoogleFonts.baloo2(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeStreakUpSubtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
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
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeWelcomeBackTitle,
                        style: GoogleFonts.baloo2(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeLoginStreakLabel(_loginStreakForPopup),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      if (_loginCoinsForPopup > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.homeLoginStreakCoins(_loginCoinsForPopup),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.amberAccent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: AchievementService.instance.watchUserAchievements(
              uid: uid,
            ),
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
                    color: AppColors.reward,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeAchievementUnlockedTitle,
                        style: GoogleFonts.baloo2(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF412402),
                        ),
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
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.homeAvatarUnlockedTitle,
                        style: GoogleFonts.baloo2(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.homeAvatarUnlockedSubtitle(
                          _avatarUnlockEmoji,
                          _avatarUnlockName,
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
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

// Vidas + tiempo de regeneración are one system, so they read as one card
// instead of two separate stat chips.
class _LivesCard extends StatelessWidget {
  final String livesText;
  final bool isFull;
  final String countdownText;

  const _LivesCard({
    required this.livesText,
    required this.isFull,
    required this.countdownText,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const iconColor = Color(0xFFFF6B5B);
    const valueColor = Color(0xFFB23A2C);
    const labelColor = Color(0xFFD9695B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite_border, size: 22, color: iconColor),
          const SizedBox(width: 10),
          Text(
            l10n.homeLivesSuffix(livesText),
            style: GoogleFonts.baloo2(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const Spacer(),
          Icon(
            isFull ? Icons.check_circle_outline : Icons.timer_outlined,
            size: 16,
            color: labelColor,
          ),
          const SizedBox(width: 4),
          Text(
            isFull ? l10n.homeLivesFull : countdownText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

// The AI-topic flow is the game's differentiator and the main sink for
// coins earned elsewhere, so this CTA gets its own glowing pulse to draw
// the eye — the only element on Home that animates on a loop.
class _AiTopicCta extends StatefulWidget {
  final VoidCallback? onTap;

  const _AiTopicCta({required this.onTap});

  @override
  State<_AiTopicCta> createState() => _AiTopicCtaState();
}

class _AiTopicCtaState extends State<_AiTopicCta>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = reduceMotion ? 0.0 : _controller.value;

            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8A6BFF), Color(0xFFFF5C93)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.reward.withValues(
                      alpha: 0.25 + t * 0.30,
                    ),
                    blurRadius: 14 + t * 12,
                    spreadRadius: t * 2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Transform.scale(
                    scale: 1.0 + t * 0.10,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.reward,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFF412402),
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.homeAiTopicTitle,
                          style: GoogleFonts.baloo2(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.homeAiTopicSubtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeeklyTopicCard extends StatelessWidget {
  final bool isBusy;
  final void Function(Map<String, dynamic> topicData) onOpen;

  const _WeeklyTopicCard({
    required this.isBusy,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: WeeklyTopicService.instance.watchCurrentTopic(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _WeeklyTopicUnavailableCard(
            message: l10n.homeWeeklyTopicUnavailable,
            detail: snap.error.toString(),
          );
        }

        if (!snap.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.rewardBg,
              borderRadius: BorderRadius.circular(14),
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
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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

        final title = (data['title'] ?? 'Weekly Topic').toString();

        // `description` (no language suffix) is the legacy single-language
        // field older weekly-topic docs were seeded with — kept as a
        // fallback so those don't regress to the generic default text.
        final languageCode = Localizations.localeOf(context).languageCode;
        final description = (data['description_$languageCode'] ??
                data['description'] ??
                l10n.homeWeeklyTopicDefaultDescription)
            .toString();
        final rewardCoins = ((data['rewardCoins'] ?? 0) as num).toInt();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFC94D), Color(0xFFF2994A)],
            ),
            borderRadius: BorderRadius.circular(18),
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
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.baloo2(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (rewardCoins > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.homeWeeklyTopicRewardCoins(rewardCoins),
                        style: const TextStyle(
                          color: Colors.white,
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB35C1E),
                  ),
                  onPressed: isBusy ? null : () => onOpen(data),
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
        borderRadius: BorderRadius.circular(18),
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
              decoration: const BoxDecoration(
                color: AppColors.danger,
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
class _DailyChallengeCard extends StatelessWidget {
  final int streak;
  final bool glow;
  final VoidCallback? onTap;

  const _DailyChallengeCard({
    required this.streak,
    required this.glow,
    required this.onTap,
  });

  Color _streakColor(BuildContext context) {
    if (streak >= 7) return AppColors.danger;
    return const Color(0xFFE5622C);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final streakColor = _streakColor(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: streakColor.withValues(alpha: glow ? 0.8 : 0.25),
          width: glow ? 1.6 : 1,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: streakColor.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            child: Row(
              children: [
                AnimatedScale(
                  scale: glow ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: streakColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.local_fire_department,
                      color: streakColor,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.homeDailyChallengeTitle,
                        style: GoogleFonts.baloo2(
                          color: colorScheme.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              l10n.homeDailyChallengeStreak(streak),
                              style: TextStyle(
                                color: streakColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (streak > 0 && streak % 3 == 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.reward,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                l10n.homeReward,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: colorScheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
