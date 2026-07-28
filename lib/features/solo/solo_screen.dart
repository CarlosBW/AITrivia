import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/life_service.dart';
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

  static const int _buyLifeCost = 10;

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

          _SoloCategoryStatus status;
          Color statusColor;

          if (completedAll) {
            status = _SoloCategoryStatus.completed;
            statusColor = AppColors.success;
          } else if (completedCount > 0) {
            status = _SoloCategoryStatus.inProgress;
            statusColor = AppColors.reward;
          } else {
            status = _SoloCategoryStatus.fresh;
            statusColor = const Color(0xFF85B7EB);
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
            statusColor: statusColor,
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
              color: Colors.black.withValues(alpha: 0.35),
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

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _categories.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l10n.soloFixedTopics,
              style: GoogleFonts.baloo2(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        final item = _categories[i - 1];

        return _CategoryCard(
          item: item,
          accent: CategoryAccent.forIndex(i - 1),
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
  final Color statusColor;

  const _SoloCategoryItem({
    required this.categoryId,
    required this.name,
    required this.levelCount,
    required this.completedCount,
    required this.progress,
    required this.nextLevel,
    required this.completedAll,
    required this.status,
    required this.statusColor,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                      borderRadius: BorderRadius.circular(AppRadius.sm),
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
                      style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: item.statusColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel(l10n),
                      style: TextStyle(
                        color: item.statusColor,
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
                borderRadius: BorderRadius.circular(8),
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
