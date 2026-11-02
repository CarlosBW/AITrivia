import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/economy_service.dart';
import '../../services/life_service.dart';
import '../daily/daily_challenge_screen.dart';
import '../versus/pvp_screen.dart';
import 'level_select_screen.dart';
import '../../widgets/no_lives_dialog.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/locale_controller.dart';
import '../../l10n/localized_content.dart';
import '../../l10n/user_facing_error.dart';
import '../../services/solo_progress.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_illustration.dart';
import '../../l10n/lives_format.dart';

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

  /// [showLoading] swaps the grid for a spinner; refreshes that already
  /// have something on screen update it in place instead.
  Future<void> _loadCategoriesAndProgress({bool showLoading = true}) async {
    if (!mounted) return;

    setState(() {
      if (showLoading) _loading = true;
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
          final name =
              localizedCategoryName(data, LocaleController.instance.locale.value.languageCode) ?? categoryId;
          final levelCount = ((data['levelCount'] ?? 10) as num).toInt();

          final progressSnap = await db
              .collection('users')
              .doc(uid)
              .collection('progress_fixed')
              .doc(categoryId)
              .get();

          final progressData = progressSnap.data() ?? {};

          final attempted =
              (progressData['completedLevels'] as List<dynamic>? ?? [])
                  .isNotEmpty;

          // Passed levels, as the level list counts them: a level that was
          // only attempted doesn't move the bar.
          final soloProgress = SoloProgress.fromDoc(progressData, levelCount);
          final completedCount = soloProgress.passedCount;
          final progress = levelCount == 0
              ? 0.0
              : (completedCount / levelCount).clamp(0.0, 1.0);
          final completedAll = soloProgress.completedAll;

          _SoloCategoryStatus status;

          if (completedAll) {
            status = _SoloCategoryStatus.completed;
          } else if (attempted) {
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
        _error = userFacingError(AppLocalizations.of(context), e);
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
        '${AppLocalizations.of(context).lives(lifeUnits)} / ${AppLocalizations.of(context).lives(maxLifeUnits)}';

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
    // Not awaited and without the full-screen spinner: awaiting kept the
    // navigation overlay's spinner up on top of the grid's own, two
    // spinners stacked out of line every time the player came back.
    unawaited(_loadCategoriesAndProgress(showLoading: false));
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
            onRefresh: () => _loadCategoriesAndProgress(showLoading: false),
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

    final busy = _isNavigating || _buyingLife;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.soloFixedTopics, style: context.heading(22)),
        const SizedBox(height: 12),
        if (allCompleted) ...[
          _AllCategoriesCompletedBanner(l10n: l10n),
          const SizedBox(height: 12),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: _categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.9,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, i) {
            final item = _categories[i];
            return _CategoryCard(
              item: item,
              accent: CategoryAccent.forIndex(i),
              disabled: busy,
              onOpenLevels: () {
                _safeNavigate(() => _openLevelSelect(item));
              },
            );
          },
        ),
      ],
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
  final _SoloCategoryStatus status;

  const _SoloCategoryItem({
    required this.categoryId,
    required this.name,
    required this.levelCount,
    required this.completedCount,
    required this.progress,
    required this.status,
  });
}

class _CategoryCard extends StatelessWidget {
  final _SoloCategoryItem item;
  final CategoryAccent accent;
  final bool disabled;
  final VoidCallback onOpenLevels;

  const _CategoryCard({
    required this.item,
    required this.accent,
    required this.disabled,
    required this.onOpenLevels,
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
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context);
    final radius = BorderRadius.circular(context.radii.md);

    // The shadow sits on a box around the Material: Ink paints onto the
    // Material, which clips it, and the blur came out as a grey wash.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: context.surfaces.shadowsOr([
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ]),
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: disabled ? null : onOpenLevels,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: context.surfaces.borderOr(null),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    decoration: BoxDecoration(
                      color: context.tintOf(accent.progress, accent.background),
                      borderRadius: BorderRadius.circular(context.radii.sm),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: CategoryIllustration(
                            categoryId: item.categoryId,
                            name: item.name,
                            size: 92,
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius:
                                  BorderRadius.circular(context.radii.pill),
                            ),
                            child: Text(
                              _statusLabel(l10n),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: readableInk(
                                  statusColor,
                                  colorScheme.surface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.heading(16),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(context.radii.pill),
                        child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(accent.progress),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.soloCategoryLevels(
                          item.completedCount,
                          item.levelCount,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
