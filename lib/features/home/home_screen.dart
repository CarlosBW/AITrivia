import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../daily/daily_challenge_screen.dart';
import '../daily/daily_leaderboard_screen.dart';
import '../leagues/weekly_league_screen.dart';
import '../profile/profile_screen.dart';
import '../solo/level_play_screen.dart';
import '../solo/level_select_screen.dart';
import '../versus/versus_menu_screen.dart';
import '../../services/daily_challenge_service.dart';
import '../../services/life_service.dart';
import '../../services/season_service.dart';

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

  bool _loadingCategories = true;
  String? _categoriesError;
  List<_HomeCategoryItem> _categories = [];

  int? _lastSeenStreak;
  bool _showStreakPopup = false;
  bool _streakGlow = false;

  static const int _buyLifeCost = 10;

  late final String uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _initLives();
    _checkPendingSeasonRewards();
    _loadCategoriesAndProgress();
    _startLifeTimer();
  }

  Future<void> _initLives() async {
    await LifeService.instance.ensureUserLifeDoc(uid);

    // One Firestore sync when Home opens. After this, the countdown is local.
    final state = await LifeService.instance.refreshLives(uid);

    if (!mounted) return;

    setState(() {
      _lifeState = state;
      _loadingLives = false;
    });
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
      final hasPending = await SeasonService.instance.hasPendingSeasonRewards(
        uid: uid,
      );

      if (!mounted) return;

      setState(() {
        _hasPendingSeasonRewards = hasPending;
      });
    } catch (_) {
      // Do not block Home if reward check fails.
    } finally {
      if (mounted) {
        setState(() => _checkingPendingSeasonRewards = false);
      }
    }
  }

  Future<void> _loadCategoriesAndProgress() async {
    if (!mounted) return;

    setState(() {
      _loadingCategories = true;
      _categoriesError = null;
    });

    try {
      final db = FirebaseFirestore.instance;

      final categoriesSnap = await db
          .collection('fixed_categories')
          .where('isActive', isEqualTo: true)
          .get();

      final docs = categoriesSnap.docs.toList()
        ..sort((a, b) {
          final ao = ((a.data()['order'] ?? 999) as num).toInt();
          final bo = ((b.data()['order'] ?? 999) as num).toInt();
          return ao.compareTo(bo);
        });

      final items = await Future.wait(
        docs.map((doc) async {
          final data = doc.data();
          final categoryId = doc.id;
          final name = (data['name'] ?? categoryId).toString();
          final levelCount = ((data['levelCount'] ?? 10) as num).toInt();

          final progressSnap = await db
              .collection('users')
              .doc(uid)
              .collection('progress_fixed')
              .doc(categoryId)
              .get();

          final progressData = progressSnap.data() ?? {};

          final completedLevels =
              (progressData['completedLevels'] as List<dynamic>? ?? [])
                  .map((e) => (e as num).toInt())
                  .toSet();

          final completedCount = completedLevels.length;
          final progress = levelCount == 0
              ? 0.0
              : (completedCount / levelCount).clamp(0.0, 1.0);

          int nextLevel = 1;
          if (completedLevels.isNotEmpty) {
            final highestCompleted = completedLevels.reduce(
              (a, b) => a > b ? a : b,
            );
            nextLevel = highestCompleted + 1;
          }
          if (nextLevel > levelCount) {
            nextLevel = levelCount;
          }

          final completedAll = progressData['completedAllLevels'] == true ||
              completedCount >= levelCount;

          String statusText;
          Color statusColor;

          if (completedAll) {
            statusText = 'Completado';
            statusColor = Colors.green;
          } else if (completedCount > 0) {
            statusText = 'En curso';
            statusColor = Colors.orange;
          } else {
            statusText = 'Nuevo';
            statusColor = Colors.blue;
          }

          return _HomeCategoryItem(
            categoryId: categoryId,
            name: name,
            levelCount: levelCount,
            completedCount: completedCount,
            progress: progress,
            nextLevel: nextLevel,
            completedAll: completedAll,
            statusText: statusText,
            statusColor: statusColor,
          );
        }),
      );

      if (!mounted) return;

      setState(() {
        _categories = items;
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _categoriesError = e.toString();
        _loadingCategories = false;
      });
    }
  }

  Future<void> _refreshHomeAfterGameplay() async {
    await Future.wait([
      _syncLivesFromFirestore(),
      _checkPendingSeasonRewards(),
      _loadCategoriesAndProgress(),
    ]);
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;

    setState(() => _isNavigating = true);

    try {
      await action();
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

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❤️ Vida recuperada')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ No tienes suficientes monedas')),
        );
      }
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
      builder: (dialogContext) => _NoLivesDialog(
        currentLivesText: currentLivesText,
        nextHalfLifeText: nextHalfLifeText,
        nextFullLifeText: nextFullLifeText,
        cost: _buyLifeCost,
        onBuyLife: _buyingLife ? null : () => _buyLifeFromDialog(dialogContext),
      ),
    );
  }

  Future<bool> _ensureHasLives(BuildContext context, String uid) async {
    await LifeService.instance.ensureUserLifeDoc(uid);
    final lifeState = await LifeService.instance.refreshLives(uid);

    if (mounted) {
      setState(() {
        _lifeState = lifeState;
        _loadingLives = false;
      });
    }

    final lifeUnits = (lifeState['lifeUnits'] ?? 0) as int;
    final maxLifeUnits = (lifeState['maxLifeUnits'] ?? 10) as int;
    final secondsToNextHalfLife = lifeState['secondsToNextHalfLife'] as int?;

    if (lifeUnits < 2) {
      if (!context.mounted) return false;

      await _showNoLivesDialog(
        context: context,
        lifeUnits: lifeUnits,
        maxLifeUnits: maxLifeUnits,
        secondsToNextHalfLife: secondsToNextHalfLife,
      );

      return false;
    }
    return true;
  }

  Future<void> _openLevelSelect(_HomeCategoryItem item) async {
    final canPlay = await _ensureHasLives(context, uid);
    if (!canPlay) return;

    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LevelSelectScreen(
          categoryId: item.categoryId,
          categoryName: item.name,
        ),
      ),
    );

    if (!mounted) return;
    await _refreshHomeAfterGameplay();
  }

  Future<void> _continueLevel(_HomeCategoryItem item) async {
    final canPlay = await _ensureHasLives(context, uid);
    if (!canPlay) return;

    if (!context.mounted) return;

    if (item.completedAll) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LevelSelectScreen(
            categoryId: item.categoryId,
            categoryName: item.name,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LevelPlayScreen(
            categoryId: item.categoryId,
            levelNumber: item.nextLevel,
          ),
        ),
      );
    }

    if (!mounted) return;
    await _refreshHomeAfterGameplay();
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TriviaIA'),
        centerTitle: true,
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userRef.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? {};
              final avatarId = (data['avatarId'] ?? 'avatar_1').toString();
              final username = (data['username'] ?? 'Player').toString();

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileScreen(),
                      ),
                    );

                    if (!mounted) return;
                    await _checkPendingSeasonRewards();
                  },
                  child: CircleAvatar(
                    radius: 19,
                    backgroundColor: Colors.deepPurple.withOpacity(0.15),
                    child: Text(
                      _avatarEmoji(avatarId, fallbackName: username),
                      style: const TextStyle(fontSize: 19),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
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

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _handleStreakChange(streak);
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
                                          child: _StatCard(
                                            icon: Icons.favorite,
                                            label: 'Vidas',
                                            value:
                                                '${LifeService.instance.formatLives(_lifeState!['lifeUnits'])} / ${LifeService.instance.formatLives(_lifeState!['maxLifeUnits'])}',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _StatCard(
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
                                child: _StatCard(
                                  icon: Icons.monetization_on,
                                  label: 'Monedas',
                                  value: '$coins',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.auto_awesome,
                                  label: 'XP',
                                  value: '$xp',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _StatCard(
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isNavigating || _buyingLife
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
                              await _refreshHomeAfterGameplay();
                            });
                          },
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Daily Challenge'),
                  ),
                ),
                const SizedBox(height: 12),
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
                                  builder: (_) =>
                                      const DailyLeaderboardScreen(),
                                ),
                              );
                            });
                          },
                    icon: const Icon(Icons.emoji_events),
                    label: const Text('Leaderboard'),
                  ),
                ),
                const SizedBox(height: 12),
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

                              await _checkPendingSeasonRewards();
                            });
                          },
                    icon: _WeeklyButtonIcon(
                      hasPendingRewards: _hasPendingSeasonRewards,
                      checking: _checkingPendingSeasonRewards,
                    ),
                    label: Text(
                      _hasPendingSeasonRewards
                          ? 'Weekly League • Reward!'
                          : 'Weekly League',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isNavigating || _buyingLife
                            ? null
                            : () {
                                _safeNavigate(() async {
                                  if (!context.mounted) return;
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const VersusMenuScreen(),
                                    ),
                                  );
                                });
                              },
                        icon: const Icon(Icons.sports_esports),
                        label: const Text('1 vs 1'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isNavigating || _buyingLife
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Próximamente: Tema libre con IA (consumirá pases o monedas).',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Tema libre (IA)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Temas fijos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _buildCategoriesList(),
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
        ],
      ),
    );
  }

  Widget _buildCategoriesList() {
    if (_loadingCategories) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categoriesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Error al cargar categorías:\n$_categoriesError',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadCategoriesAndProgress,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_categories.isEmpty) {
      return const Center(
        child: Text('No hay categorías activas en Firestore.'),
      );
    }

    return ListView.separated(
      itemCount: _categories.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = _categories[i];
        return _CategoryCard(
          item: item,
          disabled: _isNavigating || _buyingLife,
          onOpenLevels: () {
            _safeNavigate(() => _openLevelSelect(item));
          },
          onContinue: () {
            _safeNavigate(() => _continueLevel(item));
          },
        );
      },
    );
  }
}

class _HomeCategoryItem {
  final String categoryId;
  final String name;
  final int levelCount;
  final int completedCount;
  final double progress;
  final int nextLevel;
  final bool completedAll;
  final String statusText;
  final Color statusColor;

  const _HomeCategoryItem({
    required this.categoryId,
    required this.name,
    required this.levelCount,
    required this.completedCount,
    required this.progress,
    required this.nextLevel,
    required this.completedAll,
    required this.statusText,
    required this.statusColor,
  });
}

class _CategoryCard extends StatelessWidget {
  final _HomeCategoryItem item;
  final bool disabled;
  final VoidCallback onOpenLevels;
  final VoidCallback onContinue;

  const _CategoryCard({
    required this.item,
    required this.disabled,
    required this.onOpenLevels,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: disabled ? null : onOpenLevels,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: item.statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.statusText,
                      style: TextStyle(
                        color: item.statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Progreso: ${item.completedCount} / ${item.levelCount} niveles',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: disabled ? null : onOpenLevels,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Ver niveles'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: disabled ? null : onContinue,
                      icon: Icon(
                        item.completedAll ? Icons.check_circle : Icons.play_arrow,
                      ),
                      label: Text(
                        item.completedAll
                            ? 'Completado'
                            : 'Continuar N${item.nextLevel}',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _avatarEmoji(String avatarId, {String fallbackName = 'Player'}) {
  const avatars = {
    'avatar_1': '🧠',
    'avatar_2': '🚀',
    'avatar_3': '🎮',
    'avatar_4': '🔥',
    'avatar_5': '⭐',
    'avatar_6': '🐱',
    'avatar_7': '🤖',
    'avatar_8': '🏆',
  };

  if (avatars.containsKey(avatarId)) return avatars[avatarId]!;

  final trimmed = fallbackName.trim();
  if (trimmed.isEmpty) return '🙂';
  return trimmed.characters.first.toUpperCase();
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool fullWidth;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment:
            fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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

class _NoLivesDialog extends StatelessWidget {
  final String currentLivesText;
  final String nextHalfLifeText;
  final String nextFullLifeText;
  final VoidCallback? onBuyLife;
  final int cost;

  const _NoLivesDialog({
    required this.currentLivesText,
    required this.nextHalfLifeText,
    required this.nextFullLifeText,
    this.onBuyLife,
    this.cost = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border,
                size: 38,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sin vidas suficientes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Necesitas al menos 1 vida completa para entrar a un nivel.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _DialogInfoRow(
                    icon: Icons.favorite,
                    label: 'Tus vidas',
                    value: currentLivesText,
                  ),
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.timer,
                    label: 'Próx. media vida',
                    value: nextHalfLifeText,
                  ),
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.hourglass_bottom,
                    label: 'Para 1 vida completa',
                    value: nextFullLifeText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Volver'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Esperar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBuyLife,
                icon: const Icon(Icons.favorite),
                label: Text('Recuperar 1 vida ($cost monedas)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DialogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
