import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/economy_service.dart';
import '../../services/life_service.dart';
import '../daily/daily_challenge_screen.dart';
import '../versus/pvp_screen.dart';
import 'level_play_screen.dart';
import 'level_select_screen.dart';
import '../../widgets/no_lives_dialog.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

class SoloScreen extends StatefulWidget {
  const SoloScreen({super.key});

  @override
  State<SoloScreen> createState() => _SoloScreenState();
}

class _SoloScreenState extends State<SoloScreen> {
  bool _loading = true;
  bool _isNavigating = false;
  bool _buyingLife = false;
  String? _error;

  List<_SoloCategoryItem> _categories = [];

  static const int _buyLifeCost = EconomyService.buyFullLifeCost;

  late final String uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _loadCategoriesAndProgress();
  }

  Future<void> _loadCategoriesAndProgress() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
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

          // Same passedLevels-or-migrate-from-levelStats fallback as
          // level_select_screen.dart, for progress docs saved before the
          // passedLevels field existed.
          final levelStats = Map<String, dynamic>.from(
            progressData['levelStats'] as Map? ?? {},
          );

          final migratedPassedLevels = <int>{};
          for (final entry in levelStats.entries) {
            final level = int.tryParse(entry.key);
            final stat = Map<String, dynamic>.from(entry.value as Map? ?? {});
            final percent = ((stat['percent'] ?? 0.0) as num).toDouble();

            if (level != null && percent >= 0.4) {
              migratedPassedLevels.add(level);
            }
          }

          final passedLevels = (progressData['passedLevels'] as List<dynamic>?)
                  ?.map((e) => (e as num).toInt())
                  .toSet() ??
              migratedPassedLevels;

          final completedCount = completedLevels.length;
          final progress = levelCount == 0
              ? 0.0
              : (completedCount / levelCount).clamp(0.0, 1.0);

          // Uses passedLevels (actually passed >=40%), not completedLevels
          // (attempted, pass or fail), so Continue can't drop a player past
          // a level they failed — matching level_select_screen.dart's
          // lock/unlock logic, which also keys off passedLevels.
          int nextLevel = 1;
          if (passedLevels.isNotEmpty) {
            final highestPassed = passedLevels.reduce(
              (a, b) => a > b ? a : b,
            );
            nextLevel = highestPassed + 1;
          }

          if (nextLevel > levelCount) {
            nextLevel = levelCount;
          }

          final completedAll = progressData['completedAllLevels'] == true ||
              completedCount >= levelCount;

          _SoloCategoryStatus status;

          if (completedAll) {
            status = _SoloCategoryStatus.completed;
          } else if (completedCount > 0) {
            status = _SoloCategoryStatus.inProgress;
          } else {
            status = _SoloCategoryStatus.fresh;
          }

          return _SoloCategoryItem(
            categoryId: categoryId,
            name: name,
            levelCount: levelCount,
            completedCount: completedCount,
            progress: progress,
            nextLevel: nextLevel,
            completedAll: completedAll,
            status: status,
          );
        }),
      );

      if (!mounted) return;

      setState(() {
        _categories = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating || _buyingLife) return;

    setState(() => _isNavigating = true);

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? l10n.soloLifeRecovered : l10n.soloNotEnoughCoins,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _buyingLife = false);
      }
    }
  }

  Future<void> _showNoLivesDialog({
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

  Future<bool> _ensureHasLives() async {
    await LifeService.instance.ensureUserLifeDoc(uid);
    final lifeState = await LifeService.instance.refreshLives(uid);

    final lifeUnits = (lifeState['lifeUnits'] ?? 0) as int;
    final maxLifeUnits = (lifeState['maxLifeUnits'] ?? 10) as int;
    final secondsToNextHalfLife = lifeState['secondsToNextHalfLife'] as int?;

    if (lifeUnits < 2) {
      if (!mounted) return false;

      await _showNoLivesDialog(
        lifeUnits: lifeUnits,
        maxLifeUnits: maxLifeUnits,
        secondsToNextHalfLife: secondsToNextHalfLife,
      );

      return false;
    }

    return true;
  }

  Future<void> _openLevelSelect(_SoloCategoryItem item) async {
    final canPlay = await _ensureHasLives();
    if (!canPlay) return;

    if (!mounted) return;

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
    await _loadCategoriesAndProgress();
  }

  Future<void> _continueLevel(_SoloCategoryItem item) async {
    final canPlay = await _ensureHasLives();
    if (!canPlay) return;

    if (!mounted) return;

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
    await _loadCategoriesAndProgress();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.soloTabTitle),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadCategoriesAndProgress,
            child: _buildContent(l10n),
          ),
          if (_isNavigating || _buyingLife)
            Container(
              color: Theme.of(context)
                  .colorScheme
                  .scrim
                  .withValues(alpha: 0.35),
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
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            l10n.soloErrorLoadingCategories(_error!),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadCategoriesAndProgress,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.commonRetry),
          ),
        ],
      );
    }

    if (_categories.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.info_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            l10n.soloNoCategoriesAvailable,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final allCompleted = _categories.isNotEmpty &&
        _categories.every((c) => c.status == _SoloCategoryStatus.completed);
    final bannerOffset = allCompleted ? 1 : 0;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _categories.length + 1 + bannerOffset,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l10n.soloFixedTopics,
              style: context.heading(22),
            ),
          );
        }

        if (allCompleted && i == 1) {
          return _AllCategoriesCompletedBanner(l10n: l10n);
        }

        final item = _categories[i - 1 - bannerOffset];

        return _CategoryCard(
          item: item,
          accent: CategoryAccent.forIndex(i - 1 - bannerOffset),
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

// Shown once every fixed category is finished — Solo's 90 levels each only
// pay out once, so without this a completionist player would just see 9
// checkmarks and no indication of where to keep earning coins/XP.
class _AllCategoriesCompletedBanner extends StatelessWidget {
  final AppLocalizations l10n;

  const _AllCategoriesCompletedBanner({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.soloAllCompletedTitle,
                  style: context.heading(16, color: colorScheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.soloAllCompletedBody,
            style: TextStyle(color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DailyChallengeScreen(
                          uid: FirebaseAuth.instance.currentUser!.uid,
                        ),
                      ),
                    );
                  },
                  child: Text(l10n.soloAllCompletedDailyButton),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PvPScreen()),
                    );
                  },
                  child: Text(l10n.soloAllCompletedPvpButton),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _SoloCategoryStatus { completed, inProgress, fresh }

class _SoloCategoryItem {
  final String categoryId;
  final String name;
  final int levelCount;
  final int completedCount;
  final double progress;
  final int nextLevel;
  final bool completedAll;
  final _SoloCategoryStatus status;

  const _SoloCategoryItem({
    required this.categoryId,
    required this.name,
    required this.levelCount,
    required this.completedCount,
    required this.progress,
    required this.nextLevel,
    required this.completedAll,
    required this.status,
  });
}

/// Best-effort icon per known category name/id, falling back to a generic
/// quiz icon for AI-generated or unrecognized categories.
IconData _iconForCategory(String categoryId, String name) {
  final key = '$categoryId $name'.toLowerCase();

  if (key.contains('cine') || key.contains('movie')) {
    return Icons.movie_outlined;
  }
  if (key.contains('historia') || key.contains('history')) {
    return Icons.account_balance_outlined;
  }
  if (key.contains('ciencia') || key.contains('science')) {
    return Icons.science_outlined;
  }
  if (key.contains('geografia') ||
      key.contains('geografía') ||
      key.contains('geography')) {
    return Icons.public_outlined;
  }
  if (key.contains('musica') || key.contains('música') || key.contains('music')) {
    return Icons.music_note_outlined;
  }
  if (key.contains('arte') || key.contains('art')) {
    return Icons.palette_outlined;
  }
  if (key.contains('libro') || key.contains('book')) {
    return Icons.menu_book_outlined;
  }
  if (key.contains('videojuego') || key.contains('video game')) {
    return Icons.sports_esports_outlined;
  }
  if (key.contains('deporte') || key.contains('sport')) {
    return Icons.sports_soccer_outlined;
  }

  return Icons.quiz_outlined;
}

class _CategoryCard extends StatelessWidget {
  final _SoloCategoryItem item;
  final CategoryAccent accent;
  final bool disabled;
  final VoidCallback onOpenLevels;
  final VoidCallback onContinue;

  const _CategoryCard({
    required this.item,
    required this.accent,
    required this.disabled,
    required this.onOpenLevels,
    required this.onContinue,
  });

  String _statusLabel(AppLocalizations l10n) {
    switch (item.status) {
      case _SoloCategoryStatus.completed:
        return l10n.soloStatusCompleted;
      case _SoloCategoryStatus.inProgress:
        return l10n.soloStatusInProgress;
      case _SoloCategoryStatus.fresh:
        return l10n.soloStatusNew;
    }
  }

  /// Derived here rather than carried on [_SoloCategoryItem]: the colour is
  /// presentation, and having the loader resolve it meant reading the theme
  /// from a method `initState` calls — which throws, and left this screen
  /// stuck on its spinner.
  Color _statusColor(BuildContext context) {
    switch (item.status) {
      case _SoloCategoryStatus.completed:
        return context.appColors.success;
      case _SoloCategoryStatus.inProgress:
        return context.appColors.reward;
      case _SoloCategoryStatus.fresh:
        return const Color(0xFF85B7EB);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(context.radii.md),
        onTap: disabled ? null : onOpenLevels,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.background,
                      borderRadius: BorderRadius.circular(context.radii.sm),
                      border: context.surfaces.borderOr(null),
                      boxShadow: context.surfaces.shadowsOr(null),
                    ),
                    child: Icon(
                      _iconForCategory(item.categoryId, item.name),
                      color: accent.foreground,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.name,
                      style: context.heading(18),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(context).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(context.radii.pill),
                    ),
                    child: Text(
                      _statusLabel(l10n),
                      style: TextStyle(
                        color: _statusColor(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.soloProgressLevels(item.completedCount, item.levelCount),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(context.radii.xs),
                child: LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 8,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(accent.progress),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: disabled ? null : onOpenLevels,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(l10n.soloViewLevels),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: disabled ? null : onContinue,
                      icon: Icon(
                        item.completedAll
                            ? Icons.check_circle_outline
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        item.completedAll
                            ? l10n.soloStatusCompleted
                            : l10n.soloContinueLevel(item.nextLevel),
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
