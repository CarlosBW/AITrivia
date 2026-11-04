import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/ai_topic_service.dart';
import '../../services/economy_service.dart';
import '../../services/life_service.dart';
import 'level_play_screen.dart';
import '../../widgets/no_lives_dialog.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/category_illustration.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../l10n/lives_format.dart';

class LevelSelectScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  final bool isAiTopic;
  final String? aiTopicId;

  const LevelSelectScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.isAiTopic = false,
    this.aiTopicId,
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen>
    with WidgetsBindingObserver {
  bool _isNavigating = false;
  bool _buyingLife = false;
  bool _expanding = false;

  bool _loading = true;
  String? _loadError;

  Map<String, dynamic> _categoryData = {};
  Map<String, dynamic> _progressData = {};

  int _loadVersion = 0;

  /// Live view of this category's progress.
  ///
  /// Reloading once on return from gameplay isn't enough: the level screen
  /// submits its result without waiting for it, so a player who backs out
  /// immediately gets here before the write lands and sees the level they
  /// just finished still marked unplayed. Watching the document means the
  /// map corrects itself whenever the result actually arrives, whether
  /// that's before or after they come back.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _progressSub;

  /// The progress document backing this screen — `progress_ai` for AI
  /// topics, `progress_fixed` for the built-in categories.
  DocumentReference<Map<String, dynamic>> _progressRef() {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return widget.isAiTopic
        ? db
            .collection('users')
            .doc(uid)
            .collection('progress_ai')
            .doc(widget.aiTopicId)
        : db
            .collection('users')
            .doc(uid)
            .collection('progress_fixed')
            .doc(widget.categoryId);
  }

  void _watchProgress() {
    _progressSub?.cancel();
    _progressSub = _progressRef().snapshots().listen((snap) {
      if (!mounted) return;
      setState(() => _progressData = snap.data() ?? {});
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadScreenData();
    _watchProgress();
  }

  @override
  void didUpdateWidget(covariant LevelSelectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.categoryId != widget.categoryId) {
      _loadScreenData();
      _watchProgress();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadScreenData(showLoading: false);
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadScreenData({bool showLoading = true}) async {
    final loadId = ++_loadVersion;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;

    if (mounted) {
      setState(() {
        if (showLoading) {
          _loading = true;
        }
        _loadError = null;
      });
    }

    try {
      late final DocumentReference<Map<String, dynamic>> categoryRef;

      if (widget.isAiTopic) {
        categoryRef = db
            .collection('users')
            .doc(uid)
            .collection('ai_topics')
            .doc(widget.aiTopicId);
      } else {
        categoryRef = db.collection('fixed_categories').doc(widget.categoryId);
      }

      final progressRef = _progressRef();

      final snaps = await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
        categoryRef.get(),
        progressRef.get(),
      ]);

      if (!mounted || loadId != _loadVersion) return;

      final categorySnap = snaps[0];
      final progressSnap = snaps[1];

      setState(() {
        _categoryData = categorySnap.data() ?? {};
        _progressData = progressSnap.data() ?? {};
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || loadId != _loadVersion) return;

      setState(() {
        _loading = false;
        _loadError = userFacingError(AppLocalizations.of(context), e);
      });
    }
  }

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _buyLifeFromDialog({
    required BuildContext dialogContext,
    required String uid,
  }) async {
    if (_buyingLife) return;

    Navigator.pop(dialogContext);

    setState(() => _buyingLife = true);

    try {
      final success = await LifeService.instance.buyFullLife(
        uid: uid,
        cost: 10,
      );

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.soloLifeRecovered)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.soloNotEnoughCoins),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _buyingLife = false);
      }
    }
  }

  Future<void> _showNoLivesDialog({
    required BuildContext context,
    required String uid,
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
        cost: 10,
        onBuyLife: _buyingLife
            ? null
            : () => _buyLifeFromDialog(
                  dialogContext: dialogContext,
                  uid: uid,
                ),
      ),
    );
  }

  Future<bool> _ensureHasLives(BuildContext context, String uid) async {
    await LifeService.instance.ensureUserLifeDoc(uid);
    final lifeState = await LifeService.instance.refreshLives(uid);

    final lifeUnits = (lifeState['lifeUnits'] ?? 0) as int;
    final maxLifeUnits = (lifeState['maxLifeUnits'] ?? 10) as int;
    final secondsToNextHalfLife = lifeState['secondsToNextHalfLife'] as int?;

    if (lifeUnits < 2) {
      if (!context.mounted) return false;

      await _showNoLivesDialog(
        context: context,
        uid: uid,
        lifeUnits: lifeUnits,
        maxLifeUnits: maxLifeUnits,
        secondsToNextHalfLife: secondsToNextHalfLife,
      );

      return false;
    }

    return true;
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

  Future<void> _openLevel({
    required BuildContext context,
    required String uid,
    required int level,
  }) async {
    await _safeNavigate(() async {
      final canPlay = await _ensureHasLives(context, uid);
      if (!canPlay) return;

      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LevelPlayScreen(
            categoryId: widget.categoryId,
            categoryName: widget.categoryName,
            levelNumber: level,
            isAiTopic: widget.isAiTopic,
            aiTopicId: widget.aiTopicId,
          ),
        ),
      );

      // After returning from gameplay, reload progress once so the level map
      // never shows stale completion, stars, or next-level state.
      await _loadScreenData(showLoading: false);
    });
  }

  /// Adds another batch of levels to this AI topic, the same purchase as
  /// the topic list's menu — which is where it used to be the only way in.
  Future<void> _expandTopic(BuildContext context, String uid) async {
    final topicId = widget.aiTopicId;
    if (topicId == null || _expanding || _isNavigating || _buyingLife) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final coins = ((userSnap.data()?['coins'] ?? 0) as num).toInt();

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiTopicsExpandDialogTitle),
        content: Text(
          l10n.aiTopicsExpandDialogBody(
            widget.categoryName,
            EconomyService.expandAiTopicCost,
            coins,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.aiTopicsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiTopicsConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    setState(() => _expanding = true);

    try {
      await AiTopicService.instance.expandTopic(topicId: topicId);
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.aiTopicsExpandSuccess)),
      );
      // The new levels come from the topic doc, which this screen reads
      // once rather than watches.
      await _loadScreenData(showLoading: false);
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingError(AppLocalizations.of(context), e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _expanding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: AppBarTitle(widget.categoryName),
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_loadError != null)
            LoadErrorView(
              title: l10n.levelSelectLoadFailedTitle,
              message: _loadError!,
              onRetry: () => _loadScreenData(),
            )
          else
            _buildContent(context: context, uid: uid, l10n: l10n),
          if (_isNavigating || _buyingLife || _expanding)
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
        ],
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required String uid,
    required AppLocalizations l10n,
  }) {
    final levelCount = ((_categoryData['levelCount'] ?? 10) as num).toInt();

    final playedLevels =
        (_progressData['completedLevels'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .where((level) => level >= 1 && level <= levelCount)
            .toSet();

    final levelStats = Map<String, dynamic>.from(
      _progressData['levelStats'] as Map? ?? {},
    );

    final migratedPassedLevels = <int>{};
    for (final entry in levelStats.entries) {
      final level = int.tryParse(entry.key);
      final stat = Map<String, dynamic>.from(entry.value as Map? ?? {});
      final percent = ((stat['percent'] ?? 0.0) as num).toDouble();

      if (level != null &&
          level >= 1 &&
          level <= levelCount &&
          percent >= 0.4) {
        migratedPassedLevels.add(level);
      }
    }

    final passedLevels = (_progressData['passedLevels'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .where((level) => level >= 1 && level <= levelCount)
            .toSet() ??
        migratedPassedLevels;

    int maxUnlocked = 1;
    if (passedLevels.isNotEmpty) {
      final highestPassed = passedLevels.reduce(
        (a, b) => a > b ? a : b,
      );
      maxUnlocked = highestPassed + 1;
    }

    if (maxUnlocked > levelCount) {
      maxUnlocked = levelCount;
    }

    final completedCount = passedLevels.length;
    final progress =
        levelCount == 0 ? 0.0 : (completedCount / levelCount).clamp(0.0, 1.0);

    // Counted, not read from `completedAllLevels`: that flag is never
    // cleared, so after expanding an AI topic it kept offering to replay
    // the last level instead of the first new one.
    final completedAll = levelCount > 0 && completedCount >= levelCount;

    final recommendedLevel = completedAll ? levelCount : maxUnlocked;

    if (levelCount <= 0) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.info_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            l10n.levelSelectNoLevelsYet,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      );
    }

    final earnedStars = passedLevels.fold<int>(
      0,
      (total, level) =>
          total +
          _starsForLevel(
            level: level,
            isCompleted: true,
            levelStats: levelStats,
          ),
    );

    final busy = _isNavigating || _buyingLife || _expanding;
    final canExpand = widget.isAiTopic &&
        widget.aiTopicId != null &&
        _categoryData['status'] == 'ready';
    final colorScheme = Theme.of(context).colorScheme;
    final onHero = context.appColors.onAccent;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                context.appColors.heroGradientStart,
                context.appColors.heroGradientEnd,
              ],
            ),
            borderRadius: BorderRadius.circular(context.radii.lg),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr(null),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.levelSelectPathTitle(widget.categoryName),
                      style: context.heading(22, color: onHero),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.levelSelectPassedOfTotal(completedCount, levelCount),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: onHero.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(context.radii.pill),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: onHero.withValues(alpha: 0.25),
                        valueColor: AlwaysStoppedAnimation(onHero),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: onHero.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(context.radii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: context.appColors.reward,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.levelSelectStarsOfTotal(
                              earnedStars,
                              levelCount * 3,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: onHero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              CategoryIllustration(
                categoryId: widget.categoryId,
                name: widget.categoryName,
                isAiTopic: widget.isAiTopic,
                size: 112,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(context.radii.md),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr(null),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _LevelBadge(
                    level: recommendedLevel,
                    color: completedAll
                        ? context.appColors.success
                        : colorScheme.primary,
                    size: 48,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.levelSelectNextChallenge,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          completedAll
                              ? l10n.levelSelectAllDone
                              : l10n.levelSelectLevelNumber(recommendedLevel),
                          style: context.heading(19),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => _openLevel(
                          context: context,
                          uid: uid,
                          level: recommendedLevel,
                        ),
                icon: Icon(completedAll ? Icons.replay : Icons.play_arrow),
                label: Text(
                  completedAll
                      ? l10n.levelSelectPlayLastLevel
                      : l10n.levelSelectContinueAtLevel(recommendedLevel),
                ),
              ),
              if (canExpand) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _expandTopic(context, uid),
                  icon: const Icon(Icons.add_circle_outline),
                  // The price the way the store shows one: coin, then amount.
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(l10n.aiTopicsExpandMenuItem)),
                      const SizedBox(width: 10),
                      const Text('🪙', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        '${EconomyService.expandAiTopicCost}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: levelCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final level = index + 1;
            final isCompleted = passedLevels.contains(level);
            final isPlayed = playedLevels.contains(level);
            final isUnlocked = level <= maxUnlocked;
            final isNext = level == recommendedLevel && !completedAll;

            final stars = _starsForLevel(
              level: level,
              isCompleted: isCompleted,
              levelStats: levelStats,
            );

            final accent = isCompleted
                ? context.appColors.success
                : isUnlocked
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant;

            final String subtitle;
            if (isCompleted) {
              subtitle = l10n.soloStatusCompleted;
            } else if (isNext) {
              subtitle = l10n.levelSelectNextBadge;
            } else if (isUnlocked) {
              subtitle = isPlayed ? l10n.commonRetry : l10n.levelSelectAvailable;
            } else {
              subtitle = l10n.levelSelectLocked;
            }

            final radius = BorderRadius.circular(context.radii.md);

            return Opacity(
              opacity: isUnlocked ? 1 : 0.6,
              child: Container(
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? colorScheme.surface
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: radius,
                  border: context.surfaces.borderOr(Border.all(
                    color: isNext
                        ? colorScheme.primary
                        : isCompleted
                            ? context.appColors.success.withValues(alpha: 0.5)
                            : Colors.transparent,
                    width: isNext ? 2 : 1.5,
                  )),
                  boxShadow: context.surfaces.shadowsOr(isUnlocked
                      ? [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : []),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: (!isUnlocked || busy)
                        ? null
                        : () => _openLevel(
                              context: context,
                              uid: uid,
                              level: level,
                            ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          isUnlocked
                              ? _LevelBadge(
                                  level: level,
                                  color: accent,
                                  size: 44,
                                )
                              : Icon(
                                  Icons.lock_rounded,
                                  size: 36,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.levelSelectLevelNumber(level),
                            style: context.heading(16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          _StarsRow(count: stars),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.readableOnOwnTint(
                                accent,
                                wash: 0,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_open_rounded,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.levelSelectUnlockHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  int _starsForLevel({
    required int level,
    required bool isCompleted,
    required Map<String, dynamic> levelStats,
  }) {
    if (!isCompleted) return 0;

    final stat = Map<String, dynamic>.from(
      levelStats[level.toString()] as Map? ?? {},
    );

    final percent = ((stat['percent'] ?? 0.0) as num).toDouble();

    if (percent >= 0.9) return 3;
    if (percent >= 0.7) return 2;
    return 1;
  }
}

class _StarsRow extends StatelessWidget {
  final int count;

  const _StarsRow({required this.count});

  @override
  Widget build(BuildContext context) {
    // Same gradient used by level_play_screen.dart's _BigStarsRow on the
    // level-complete result screen, so a level's star color here matches
    // what the player just saw when they earned it.
    final gradientStart = context.appColors.heroGradientStart;
    final gradientEnd = context.appColors.heroGradientEnd;
    final unfilledColor =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.35);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final filled = i < count;
        final color = filled
            ? Color.lerp(gradientStart, gradientEnd, i / 2)!
            : unfilledColor;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 18,
            color: color,
          ),
        );
      }),
    );
  }
}

/// A level's number in a filled circle of [color].
class _LevelBadge extends StatelessWidget {
  final int level;
  final Color color;
  final double size;

  const _LevelBadge({
    required this.level,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        '$level',
        style: context.heading(size * 0.42, color: context.appColors.onAccent),
      ),
    );
  }
}
