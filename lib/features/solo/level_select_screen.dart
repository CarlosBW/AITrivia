import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/life_service.dart';
import 'level_play_screen.dart';
import '../../widgets/no_lives_dialog.dart';

class LevelSelectScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  final bool isAiTopic;
  final String? aiTopicId;

  final bool isWeeklyTopic;
  final String? weeklyTopicWeekId;

  const LevelSelectScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.isAiTopic = false,
    this.aiTopicId,
    this.isWeeklyTopic = false,
    this.weeklyTopicWeekId,
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen>
    with WidgetsBindingObserver {
  bool _isNavigating = false;
  bool _buyingLife = false;

  bool _loading = true;
  bool _refreshing = false;
  String? _loadError;

  Map<String, dynamic> _categoryData = {};
  Map<String, dynamic> _progressData = {};

  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadScreenData();
  }

  @override
  void didUpdateWidget(covariant LevelSelectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.categoryId != widget.categoryId) {
      _loadScreenData();
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
        } else {
          _refreshing = true;
        }
        _loadError = null;
      });
    }

    try {
      late final DocumentReference<Map<String, dynamic>> categoryRef;
      late final DocumentReference<Map<String, dynamic>> progressRef;

      if (widget.isAiTopic) {
        categoryRef = db
            .collection('users')
            .doc(uid)
            .collection('ai_topics')
            .doc(widget.aiTopicId);

        progressRef = db
            .collection('users')
            .doc(uid)
            .collection('progress_ai')
            .doc(widget.aiTopicId);
      } else {
        categoryRef = db.collection('fixed_categories').doc(widget.categoryId);

        progressRef = db
            .collection('users')
            .doc(uid)
            .collection('progress_fixed')
            .doc(widget.categoryId);
      }

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
        _refreshing = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || loadId != _loadVersion) return;

      setState(() {
        _loading = false;
        _refreshing = false;
        _loadError = e.toString();
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

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❤️ Vida recuperada')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No tienes suficientes monedas'),
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
            levelNumber: level,
            isAiTopic: widget.isAiTopic,
            aiTopicId: widget.aiTopicId,
            isWeeklyTopic: widget.isWeeklyTopic,
            weeklyTopicWeekId: widget.weeklyTopicWeekId,
          ),
        ),
      );

      // After returning from gameplay, reload progress once so the level map
      // never shows stale completion, stars, or next-level state.
      await _loadScreenData(showLoading: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_loadError != null)
            _LoadErrorView(
              error: _loadError!,
              onRetry: () => _loadScreenData(),
            )
          else
            _buildContent(context: context, uid: uid),
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
        ],
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required String uid,
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

    final completedAll = _progressData['completedAllLevels'] == true ||
        (levelCount > 0 && completedCount >= levelCount);

    final recommendedLevel = completedAll ? levelCount : maxUnlocked;

    if (levelCount <= 0) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.info_outline, size: 42),
          SizedBox(height: 12),
          Text(
            'Esta categoría aún no tiene niveles disponibles.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Selecciona un nivel',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                completedAll
                    ? widget.isAiTopic
                        ? 'Tema IA aprobado'
                        : 'Categoría aprobada'
                    : widget.isAiTopic
                        ? 'Tu progreso aprobado en este tema IA'
                        : 'Tu progreso aprobado en esta categoría',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aprobados: $completedCount / $levelCount',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isNavigating || _buyingLife
                      ? null
                      : () => _openLevel(
                            context: context,
                            uid: uid,
                            level: recommendedLevel,
                          ),
                  icon: Icon(
                    completedAll ? Icons.replay : Icons.play_arrow,
                  ),
                  label: Text(
                    completedAll
                        ? 'Jugar último nivel'
                        : 'Continuar en nivel $recommendedLevel',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: levelCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.92,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final level = index + 1;
            final isCompleted = passedLevels.contains(level);
            final isPlayed = playedLevels.contains(level);
            final isUnlocked = level <= maxUnlocked;

            final stars = _starsForLevel(
              level: level,
              isCompleted: isCompleted,
              levelStats: levelStats,
            );

            Color tileColor;
            IconData icon;
            String subtitle;

            if (isCompleted) {
              tileColor = Colors.green.withOpacity(0.15);
              icon = Icons.check_circle;
              subtitle = 'Completado';
            } else if (isUnlocked) {
              tileColor = isPlayed
                  ? Colors.orange.withOpacity(0.12)
                  : Colors.blue.withOpacity(0.12);
              icon = isPlayed ? Icons.refresh : Icons.play_circle_fill;
              subtitle = isPlayed ? 'Reintentar' : 'Disponible';
            } else {
              tileColor = Colors.black12;
              icon = Icons.lock;
              subtitle = 'Bloqueado';
            }

            final showRecommended = level == recommendedLevel && !completedAll;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: showRecommended ? Colors.blueAccent : Colors.black12,
                  width: showRecommended ? 2 : 1,
                ),
                boxShadow: showRecommended
                    ? [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: (!isUnlocked || _isNavigating || _buyingLife)
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
                      Icon(icon, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Nivel $level',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      _StarsRow(count: stars),
                      if (showRecommended) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Siguiente',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
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

class _LoadErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _LoadErrorView({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar la categoría.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarsRow extends StatelessWidget {
  final int count;

  const _StarsRow({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final filled = i < count;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 18,
          ),
        );
      }),
    );
  }
}
