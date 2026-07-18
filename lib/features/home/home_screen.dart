import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/weekly_topic_service.dart';
import '../daily/daily_challenge_screen.dart';
import '../leagues/weekly_league_screen.dart';
import '../../services/daily_challenge_service.dart';
import '../../services/life_service.dart';
import '../../services/season_service.dart';
import '../../widgets/no_lives_dialog.dart';
import '../ai_topics/ai_topics_screen.dart';
import '../weekly/weekly_topic_screen.dart';
import '../../widgets/stat_chip.dart';
import '../../widgets/section_label.dart';

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
  bool _buyingLife = false;

  bool _hasPendingSeasonRewards = false;
  bool _checkingPendingSeasonRewards = false;

  int? _lastSeenStreak;
  bool _showStreakPopup = false;
  bool _streakGlow = false;

  bool _loginPopupHandled = false;
  bool _showLoginPopup = false;
  int _loginStreakForPopup = 0;
  int _loginCoinsForPopup = 0;

  static const int _buyLifeCost = 10;

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

    setState(() => _isNavigating = true);

    try {
      await action().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw TimeoutException('La acción tardó demasiado.');
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

  Future<void> _buyLifeFromDialog(BuildContext dialogContext) async {
    if (_buyingLife) return;

    Navigator.pop(dialogContext);

    setState(() => _buyingLife = true);

    try {
      final success = await LifeService.instance.buyFullLife(
        uid: uid,
        cost: _buyLifeCost,
      );

      await _syncLivesFromFirestore();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '❤️ Vida recuperada' : '❌ No tienes suficientes monedas',
          ),
        ),
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
        setState(() => _buyingLife = false);
      }
    }
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

  Future<void> _showNoLivesDialog({
    required BuildContext context,
    required int lifeUnits,
    required int maxLifeUnits,
    required int? secondsToNextHalfLife,
  }) async {
    final currentLivesText =
        '${LifeService.instance.formatLives(lifeUnits)} / ${LifeService.instance.formatLives(maxLifeUnits)}';

    final nextHalfLifeText = secondsToNextHalfLife == null
        ? '--:--'
        : _formatCountdown(secondsToNextHalfLife);

    final needOneMoreHalf = lifeUnits == 1;
    final secondsToFullLife = secondsToNextHalfLife == null
        ? null
        : needOneMoreHalf
            ? secondsToNextHalfLife
            : secondsToNextHalfLife + 150;

    final nextFullLifeText = secondsToFullLife == null
        ? '--:--'
        : _formatCountdown(secondsToFullLife);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => NoLivesDialog(
        currentLivesText: currentLivesText,
        nextHalfLifeText: nextHalfLifeText,
        nextFullLifeText: nextFullLifeText,
        cost: _buyLifeCost,
        onBuyLife: _buyingLife ? null : () => _buyLifeFromDialog(dialogContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TriviaIA'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refreshHome,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
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
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _loadingLives || _lifeState == null
                              ? const LinearProgressIndicator()
                              : Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: StatChip(
                                            icon: Icons.favorite,
                                            label: 'Vidas',
                                            value:
                                                '${LifeService.instance.formatLives(_lifeState!['lifeUnits'])} / ${LifeService.instance.formatLives(_lifeState!['maxLifeUnits'])}',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: StatChip(
                                            icon: Icons.timer,
                                            label: 'Próx. media vida',
                                            value: _lifeState!['lifeUnits'] >=
                                                    _lifeState!['maxLifeUnits']
                                                ? 'MAX'
                                                : _formatCountdown(
                                                    _lifeState![
                                                        'secondsToNextHalfLife'],
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                          Row(
                            children: [
                              Expanded(
                                child: StatChip(
                                  icon: Icons.monetization_on,
                                  label: 'Monedas',
                                  value: '$coins',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: StatChip(
                                  icon: Icons.auto_awesome,
                                  label: 'XP',
                                  value: '$xp',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          StatChip(
                            icon: Icons.style,
                            label: 'Tema libre',
                            value: '$passes',
                            fullWidth: true,
                          ),
                          const SizedBox(height: 14),
                          _StreakCard(
                            streak: streak,
                            glow: _streakGlow,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Material(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _isNavigating || _buyingLife
                        ? null
                        : () {
                            _safeNavigate(() async {
                              final alreadyPlayed = await DailyChallengeService
                                  .instance
                                  .hasPlayedToday(uid);

                              if (!context.mounted) return;

                              if (alreadyPlayed) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Ya jugaste el Daily Challenge de hoy.',
                                    ),
                                  ),
                                );
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.calendar_today,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Daily Challenge',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Juega hoy y mantén tu racha',
                                  style: TextStyle(
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
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const SectionLabel('Más formas de jugar'),
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
                          ? 'Weekly Challenge • Reward!'
                          : 'Weekly Challenge',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isNavigating || _buyingLife
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AiTopicsScreen(),
                              ),
                            );
                          },
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Tema libre (IA)'),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
                    ),
                  ),
                  child: const Text(
                    'Usa las pestañas inferiores para jugar SOLO, competir en PvP, retar amigos y ver tu perfil.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (_isNavigating || _buyingLife)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.white),
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
                    color: Colors.deepOrange.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🔥 STREAK UP!',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Keep coming back daily',
                        style: TextStyle(
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
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '📅 ¡Volviste!',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Racha de sesión: $_loginStreakForPopup días',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      if (_loginCoinsForPopup > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '+$_loginCoinsForPopup monedas',
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
        ],
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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: WeeklyTopicService.instance.watchCurrentTopic(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _WeeklyTopicUnavailableCard(
            message: 'Weekly Topic unavailable',
            detail: snap.error.toString(),
          );
        }

        if (!snap.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.amber.withOpacity(0.30),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Loading Weekly Topic...',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        }

        final data = snap.data!.data();

        if (data == null || data['active'] != true) {
          return const _WeeklyTopicUnavailableCard(
            message: 'No Weekly Topic available',
            detail: 'Check back soon for a featured challenge.',
          );
        }

        final title = (data['title'] ?? 'Weekly Topic').toString();
        final description =
            (data['description'] ?? 'Complete levels and earn rewards.')
                .toString();
        final rewardCoins = ((data['rewardCoins'] ?? 0) as num).toInt();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.amber.withOpacity(0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
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
                        color: Colors.amber.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '+$rewardCoins coins',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : () => onOpen(data),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Open Weekly Topic'),
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
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_busy),
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
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
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
        const Icon(Icons.workspace_premium),
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
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int streak;
  final bool glow;

  const _StreakCard({
    required this.streak,
    required this.glow,
  });

  Color _color() {
    if (streak >= 7) return Colors.red;
    if (streak >= 3) return Colors.orange;
    return Colors.grey;
  }

  String _subtitle() {
    if (streak >= 14) return 'Legendary streak!';
    if (streak >= 7) return 'On fire!';
    if (streak >= 3) return 'Keep it going!';
    return 'Start your streak today';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(glow ? 0.30 : 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(glow ? 0.9 : 0.35),
          width: glow ? 2 : 1,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withOpacity(0.45),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          AnimatedScale(
            scale: glow ? 1.25 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              Icons.local_fire_department,
              color: color,
              size: 30,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Streak: $streak días',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (streak > 0 && streak % 3 == 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Reward!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
